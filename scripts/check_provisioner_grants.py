#!/usr/bin/env python3
"""Secret-safe checks of actual MariaDB SHOW GRANTS for privileged DB accounts."""
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
        # Do not emit stderr/stdout; connector errors can expose implementation detail.
        raise RuntimeError("SHOW GRANTS failed for a disposable database principal")
    return [
        line.strip().replace("\\\\", "\\").replace(chr(96), "").replace("\\_", "_").replace("\\%", "%")
        for line in result.stdout.splitlines()
        if line.strip()
    ]


def fail(message: str) -> int:
    print("FAIL: " + message)
    return 1


def main() -> int:
    try:
        provisioner = show_grants("berkahpos_provisioner")
        migrator = show_grants("berkahpos_migrator")
    except RuntimeError as error:
        return fail(str(error))

    tenant_pattern = "berkahpos_tenant_%.*"

    # The only allowed global provisioner grants are USAGE and CREATE USER.
    for grant in provisioner:
        if re.search(r"\bON\s+\*\.\*", grant, re.IGNORECASE):
            if re.search(r"^GRANT\s+USAGE\s+ON\s+\*\.\*", grant, re.IGNORECASE):
                continue
            if re.search(r"^GRANT\s+CREATE USER\s+ON\s+\*\.\*", grant, re.IGNORECASE):
                continue
            return fail("provisioner has an unexpected global privilege grant")

        if re.search(r"\bWITH GRANT OPTION\b", grant, re.IGNORECASE):
            if not re.search(r"^GRANT SELECT, INSERT, UPDATE, DELETE ON " + re.escape(tenant_pattern), grant, re.IGNORECASE):
                return fail("provisioner GRANT OPTION is not confined to the tenant database pattern")

        if re.search(r"^GRANT CREATE ON ", grant, re.IGNORECASE):
            if not re.search(r"^GRANT CREATE ON " + re.escape(tenant_pattern), grant, re.IGNORECASE):
                return fail("provisioner CREATE privilege is not confined to tenant-prefixed databases")

        if re.search(r"^GRANT (?:CREATE|ALTER|DROP|SELECT|INSERT|UPDATE|DELETE)(?:,| ON)", grant, re.IGNORECASE):
            if not re.search(r"\bON\s+" + re.escape(tenant_pattern), grant, re.IGNORECASE):
                return fail("provisioner has DDL/DML outside the tenant database pattern")

        if re.search(r"\bDROP\b|\bALTER\b", grant, re.IGNORECASE):
            return fail("provisioner must not have DROP or ALTER privileges")

    # Migrator may run DDL/DML only on the tenant DB wildcard and never delegates grants.
    meaningful_migrator_grants = [
        grant for grant in migrator
        if not re.search(r"^GRANT USAGE ON \*\.\*", grant, re.IGNORECASE)
    ]
    if len(meaningful_migrator_grants) != 1:
        return fail("migrator must have exactly one tenant-pattern-scoped privilege grant")

    migration_grant = meaningful_migrator_grants[0]
    expected = r"^GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES ON " + re.escape(tenant_pattern)
    if not re.search(expected, migration_grant, re.IGNORECASE):
        return fail("migrator grant set or tenant database pattern differs from the reviewed contract")
    if re.search(r"\bDROP\b|\bGRANT OPTION\b|\bON\s+\*\.\*", migration_grant, re.IGNORECASE):
        return fail("migrator must not have DROP, GRANT OPTION, or global privileges")

    print("PASS: actual SHOW GRANTS limits provisioner global privileges to CREATE USER; schema creation/CRUD grants are tenant-pattern scoped; migrator DDL is tenant-pattern scoped without DROP or GRANT OPTION.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
