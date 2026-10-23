#!/usr/bin/env python3
"""Fail-closed exact set comparison for expected, catalog and verified backups."""
from __future__ import annotations
import argparse
import hashlib
import re
import sys
from pathlib import Path

DB_NAME = re.compile(r"^[a-z][a-z0-9_]{0,62}$")

def read_names(path: Path) -> list[str]:
    names = [line.strip() for line in path.read_text(encoding="utf-8").splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    if any(not DB_NAME.fullmatch(name) for name in names):
        raise ValueError(f"{path.name}: invalid PostgreSQL database identifier")
    if len(names) != len(set(names)):
        raise ValueError(f"{path.name}: duplicate database identifier")
    return names

def fingerprint(name: str) -> str:
    return hashlib.sha256(name.encode()).hexdigest()[:12]

def compare(expected: list[str], catalog: list[str], backups: list[str], central: str) -> list[str]:
    issues: list[str] = []
    for label, names in (("expected", expected), ("catalog", catalog), ("verified-backup", backups)):
        if central not in names:
            issues.append(f"central database absent from {label} inventory")
    for label, names in (("catalog", catalog), ("verified-backup", backups)):
        missing = sorted(set(expected) - set(names))
        extra = sorted(set(names) - set(expected))
        if missing:
            issues.append(f"{label}: {len(missing)} expected DB(s) missing; SHA256 prefixes=" +
                          ",".join(fingerprint(n) for n in missing))
        if extra:
            issues.append(f"{label}: {len(extra)} unexpected DB(s); SHA256 prefixes=" +
                          ",".join(fingerprint(n) for n in extra))
    return issues

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", required=True, type=Path, help="reviewed registry plus central DB")
    parser.add_argument("--catalog", required=True, type=Path, help="non-template database names from pg_database")
    parser.add_argument("--backed-up", required=True, type=Path, help="only checksum-verified remote backup objects")
    parser.add_argument("--central-db", required=True, help="canonical central database identifier")
    args = parser.parse_args(argv)
    if not DB_NAME.fullmatch(args.central_db):
        parser.error("--central-db must be a lowercase PostgreSQL identifier")
    try:
        expected = read_names(args.expected)
        catalog = read_names(args.catalog)
        backups = read_names(args.backed_up)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"FAIL: inventory input invalid: {error}", file=sys.stderr)
        return 2
    issues = compare(expected, catalog, backups, args.central_db)
    if issues:
        print("FAIL: backup coverage mismatch")
        for issue in issues:
            print(f"- {issue}")
        return 1
    print(f"PASS: exact DB coverage; expected={len(expected)}, catalog={len(catalog)}, checksum-verified-backups={len(backups)}; central included")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
