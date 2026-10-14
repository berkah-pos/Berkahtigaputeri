#!/usr/bin/env python3
"""Materialize recorded migration SQL bodies in a disposable local Supabase project only."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

VERSION_RE = re.compile(r"^\d{14}$")
NAME_RE = re.compile(r"^[a-z0-9_]+$")

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("output_migrations_dir", type=Path)
    parser.add_argument("--environment", choices=("staging", "staging-clone"), required=True)
    args = parser.parse_args()
    try:
        archive = json.loads(args.archive.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FAIL: cannot load migration archive: {exc}", file=sys.stderr)
        return 1

    entries = [e for e in archive.get("entries", []) if e.get("environment") == args.environment]
    expected = {"staging": 139, "staging-clone": 12}[args.environment]
    if len(entries) != expected:
        print(f"FAIL: {args.environment} has {len(entries)} archived entries; expected {expected}", file=sys.stderr)
        return 1
    args.output_migrations_dir.mkdir(parents=True, exist_ok=True)
    versions: set[str] = set()
    total_bytes = 0
    for entry in entries:
        version = str(entry.get("version", ""))
        name = str(entry.get("name", ""))
        sql = entry.get("sql")
        if not VERSION_RE.fullmatch(version) or not NAME_RE.fullmatch(name) or not isinstance(sql, str) or not sql:
            print(f"FAIL: malformed migration archive entry {args.environment}/{version}", file=sys.stderr)
            return 1
        if version in versions:
            print(f"FAIL: duplicate version {args.environment}/{version}", file=sys.stderr)
            return 1
        versions.add(version)
        raw = sql.encode("utf-8")
        if len(raw) != entry.get("sql_bytes") or hashlib.sha256(raw).hexdigest() != entry.get("sql_sha256"):
            print(f"FAIL: SQL body integrity check failed for {args.environment}/{version}", file=sys.stderr)
            return 1
        path = args.output_migrations_dir / f"{version}_{name}.sql"
        if path.exists():
            print(f"FAIL: refusing to overwrite pre-existing migration file {path.name}", file=sys.stderr)
            return 1
        path.write_bytes(raw)
        total_bytes += len(raw)

    names = sorted(p.name for p in args.output_migrations_dir.glob("*.sql"))
    if len(names) != expected:
        print(f"FAIL: wrote {len(names)} migration files; expected {expected}", file=sys.stderr)
        return 1
    print(f"PASS: materialized {expected} recorded {args.environment} migration bodies to the disposable work directory.")
    print(f"PASS: each body passed its archived byte-count and SHA-256 check; bytes={total_bytes}.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
