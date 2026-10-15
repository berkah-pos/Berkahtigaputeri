#!/usr/bin/env python3
"""Inspect SHOW GRANTS for the central app account without revealing DB secrets."""
import os
import re
import subprocess
import sys


def main() -> int:
    password = os.environ.get("MARIADB_ROOT_PASSWORD", "")
    if not password:
        print("FAIL: required disposable DB admin credential is unavailable.")
        return 1

    command = [
        "mariadb", "--host=127.0.0.1", "--port=3306", "--user=root",
        "--password=" + password, "--batch", "--skip-column-names",
        "--execute=SHOW GRANTS FOR 'berkahpos_app'@'%';",
    ]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode:
        print("FAIL: SHOW GRANTS query failed; database credential values are not logged.")
        return 1

    grants = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    scoped = [
        grant for grant in grants
        if not re.match(r"^GRANT USAGE ON \*\.\* TO\b", grant, re.IGNORECASE)
    ]
    if len(scoped) != 1:
        print("FAIL: central app account must have exactly one non-USAGE grant.")
        return 1

    grant = scoped[0].upper()
    if not re.search(r"GRANT SELECT, INSERT, UPDATE, DELETE ON .+CENTRAL.+\.\* TO", grant):
        print("FAIL: central app account does not have the exact central CRUD grant.")
        return 1
    if any(token in grant for token in ("CREATE", "ALTER", "DROP", "INDEX", "REFERENCES", "GRANT OPTION")):
        print("FAIL: central app account includes DDL or grant delegation.")
        return 1
    if "TENANT" in grant or re.search(r"\bON\s+\*\.\*", grant):
        print("FAIL: central app account has tenant-scope or global privileges.")
        return 1

    print("PASS: SHOW GRANTS confirms the central app account has CRUD on central only.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
