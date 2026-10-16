#!/usr/bin/env python3
"""Fail closed on cross-tenant provisioning/migration grants.

This checks real SHOW GRANTS output using a separate disposable admin credential.
It is a policy gate, not a replacement for adversarial two-tenant SQL tests.
"""
import os
import re
import subprocess


def show_grants(username: str) -> list[str]:
    env = os.environ.copy()
    password = env.pop("MARIADB_ROOT_PASSWORD", "")
    if not password:
        raise RuntimeError("disposable database inspection credential unavailable")
    env["MYSQL_PWD"] = password
    result = subprocess.run(
        [
            "mariadb", "--host=127.0.0.1", "--port=3306", "--user=root",
            "--batch", "--skip-column-names",
            "--execute=SHOW GRANTS FOR '" + username + "'@'%';",
        ],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode:
        # Do not emit connector stdout/stderr; it can include implementation details.
        raise RuntimeError("SHOW GRANTS failed for a disposable database principal")
    return [
        line.strip().replace("\\\\", "\\").replace(chr(96), "").replace("\\_", "_").replace("\\%", "%")
        for line in result.stdout.splitlines()
        if line.strip()
    ]


def main() -> int:
    try:
        provisioner = show_grants("berkahpos_provisioner")
        migrator = show_grants("berkahpos_migrator")
    except RuntimeError as error:
        print("FAIL: " + str(error))
        return 1

    violations: list[str] = []
    tenant_pattern = re.compile(r"\bON\s+berkahpos_t_%\s*\.\*", re.IGNORECASE)

    for grant in provisioner:
        if re.search(r"^GRANT\s+USAGE\s+ON\s+\*\.\*", grant, re.IGNORECASE):
            continue
        if re.search(r"\bCREATE\s+USER\b", grant, re.IGNORECASE):
            violations.append("provisioner has global CREATE USER; a compromised worker can create arbitrary database principals")
        if re.search(r"\bWITH\s+GRANT\s+OPTION\b", grant, re.IGNORECASE):
            violations.append("provisioner can delegate privileges; wildcard delegation is not accepted as tenant isolation")
        if tenant_pattern.search(grant) and re.search(
            r"\b(CREATE|SELECT|INSERT|UPDATE|DELETE|ALTER|DROP|INDEX|REFERENCES)\b",
            grant,
            re.IGNORECASE,
        ):
            violations.append("provisioner has direct privileges across the tenant database-name pattern")
        if re.search(r"\bON\s+\*\.\*", grant, re.IGNORECASE) and not re.search(
            r"^GRANT\s+USAGE\s+ON\s+\*\.\*",
            grant,
            re.IGNORECASE,
        ):
            violations.append("provisioner has a global privilege other than USAGE")

    for grant in migrator:
        if re.search(r"^GRANT\s+USAGE\s+ON\s+\*\.\*", grant, re.IGNORECASE):
            continue
        if tenant_pattern.search(grant):
            violations.append("migrator has direct DDL/DML privileges across all tenant databases")
        if re.search(r"\bWITH\s+GRANT\s+OPTION\b|\bON\s+\*\.\*", grant, re.IGNORECASE):
            violations.append("migrator can delegate privileges or has a global privilege")

    if violations:
        for violation in dict.fromkeys(violations):
            print("FAIL: " + violation + ".")
        print("SECURITY GATE: FAIL — obtain a narrower, tested broker/definer design or explicit owner-approved service-compromise blast-radius acceptance.")
        return 1

    print("PASS: provisioner and migrator privileges are outside the cross-tenant wildcard and no global delegation privilege remains.")
    print("Note: this policy result still requires real two-tenant negative tests and independent SHOW GRANTS review.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
