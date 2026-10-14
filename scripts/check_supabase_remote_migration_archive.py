#!/usr/bin/env python3
"""Verify SQL bodies recovered from the hosted Supabase migration registries."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE_PATH = ROOT / "supabase/reconciliation/recovered-remote-migration-statements-2026-10-14.json"
MANIFEST_PATH = ROOT / "supabase/reconciliation/source-recovery-manifest-2026-10-14.json"
EXPECTED_COUNTS = {"staging": 139, "staging-clone": 12}
VERSION_RE = re.compile(r"^\d{14}$")
NAME_RE = re.compile(r"^[a-z0-9_]+$")
HIGH_CONFIDENCE_SECRET_PATTERNS = {
    "private-key PEM": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", re.I),
    "compact JWT": re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"),
    "Supabase secret key": re.compile(r"\bsb_secret_[A-Za-z0-9_-]{16,}", re.I),
    "AWS access key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "GitHub token": re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{30,}\b"),
    "Stripe secret": re.compile(r"\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}\b", re.I),
    "credential-bearing database URI": re.compile(r"\b(?:postgres(?:ql)?|mysql)://[^/\s:@]+:[^@\s/]+@", re.I),
    "hard-coded credential assignment": re.compile(
        r"(?:password|passwd|secret(?:[_-]?key)?|api[_-]?key|service[_-]?role[_-]?key|jwt[_-]?secret|access[_-]?token)\s*(?:=|:)\s*['\"][^'\"\r\n]{16,}['\"]",
        re.I,
    ),
}

def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot load {path.relative_to(ROOT)}: {exc}") from exc

def main() -> int:
    errors: list[str] = []
    try:
        archive = load_json(ARCHIVE_PATH)
        manifest = load_json(MANIFEST_PATH)
    except ValueError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    if archive.get("schema_version") != 1:
        errors.append("unsupported archive schema_version")
    bootstrap_path = ROOT / "supabase/reconciliation/historical-replay-bootstrap/20260929000000_legacy_licences.sql"
    if not bootstrap_path.is_file():
        errors.append("documented pre-history licences bootstrap is missing")
    else:
        bootstrap_sql = bootstrap_path.read_text(encoding="utf-8")
        for required in ("CREATE TABLE public.licences", "toko_address text", "licences_pkey", "licences_package_id_check"):
            if required not in bootstrap_sql:
                errors.append(f"pre-history bootstrap is missing schema marker: {required}")
        bootstrap_lines = [line.strip().lower() for line in bootstrap_sql.splitlines() if line.strip() and not line.strip().startswith("--")]
        if any(re.match(r"^(?:insert into|copy\\s|update\\s|delete from)\\b", line) for line in bootstrap_lines):
            errors.append("pre-history bootstrap must not seed or modify data rows")
        if any(re.match(r"^tenant_id\\s+", line) for line in bootstrap_lines):
            errors.append("pre-history bootstrap must not pre-create tenant_id; an archived migration adds it")

    entries = archive.get("entries", [])
    if len(entries) != sum(EXPECTED_COUNTS.values()):
        errors.append(f"archive entry count {len(entries)} != 151")

    archive_maps: dict[str, dict[str, dict[str, Any]]] = {k: {} for k in EXPECTED_COUNTS}
    observed_counts = {k: 0 for k in EXPECTED_COUNTS}
    observed_bytes = 0
    for entry in entries:
        env = entry.get("environment")
        version = str(entry.get("version", ""))
        name = str(entry.get("name", ""))
        sql = entry.get("sql")
        if env not in EXPECTED_COUNTS:
            errors.append(f"unexpected archive environment on {version or '<missing version>'}")
            continue
        observed_counts[env] += 1
        if not VERSION_RE.fullmatch(version):
            errors.append(f"malformed version in {env}: {version!r}")
        if not NAME_RE.fullmatch(name):
            errors.append(f"unsafe migration name in {env}/{version}: {name!r}")
        if version in archive_maps[env]:
            errors.append(f"duplicate archived version in {env}: {version}")
        if not isinstance(sql, str) or not sql:
            errors.append(f"missing SQL body in {env}/{version}")
            continue
        raw = sql.encode("utf-8")
        sql_bytes = len(raw)
        actual_sha = hashlib.sha256(raw).hexdigest()
        observed_bytes += sql_bytes
        if sql_bytes != entry.get("sql_bytes"):
            errors.append(f"SQL byte-count mismatch in {env}/{version}")
        if actual_sha != entry.get("sql_sha256"):
            errors.append(f"SQL SHA-256 mismatch in {env}/{version}")
        if entry.get("statement_count") != 1:
            errors.append(f"expected exactly one recorded statement string in {env}/{version}")
        for label, pattern in HIGH_CONFIDENCE_SECRET_PATTERNS.items():
            if pattern.search(sql):
                errors.append(f"secret-pattern scan hit ({label}) in {env}/{version}; do not publish unreviewed body")
        archive_maps[env][version] = entry

    for env, expected in EXPECTED_COUNTS.items():
        if observed_counts[env] != expected:
            errors.append(f"{env}: archived {observed_counts[env]} bodies, expected {expected}")
        env_entries = [e for e in entries if e.get("environment") == env]
        versions = [str(e.get("version")) for e in env_entries]
        if versions != sorted(versions):
            errors.append(f"{env}: archive entries are not sorted by version")
        remote = next((x for x in manifest.get("remote_environments", []) if x.get("environment") == env), None)
        if remote is None:
            errors.append(f"{env}: source recovery manifest is missing its remote registry")
            continue
        registry = remote.get("entries", [])
        if len(registry) != expected or remote.get("registry_count") != expected:
            errors.append(f"{env}: source recovery manifest registry count drift")
        registry_map = {str(r.get("version")): r for r in registry}
        if set(registry_map) != set(archive_maps[env]):
            errors.append(f"{env}: archive versions do not match the captured registry")
        for version, entry in archive_maps[env].items():
            row = registry_map.get(version)
            if row is None:
                continue
            if row.get("name") != entry.get("name"):
                errors.append(f"{env}/{version}: archived name differs from captured registry")
            if row.get("remote_body_status") != "RECOVERED_FROM_SUPABASE_MIGRATION_LEDGER":
                errors.append(f"{env}/{version}: manifest does not record remote body recovery")
            if row.get("sql_sha256") != entry.get("sql_sha256") or row.get("sql_bytes") != entry.get("sql_bytes"):
                errors.append(f"{env}/{version}: source-recovery manifest body fingerprint mismatch")

    counts = archive.get("counts", {})
    if counts.get("total_records") != 151 or counts.get("total_sql_bytes") != observed_bytes:
        errors.append("archive summary counts do not match validated records")

    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: 151 SQL migration bodies recovered from the two hosted migration ledgers; registry versions/names match.")
    print("PASS: all 151 UTF-8 byte counts and SHA-256 body checksums match; no duplicate/missing version.")
    print("PASS: no high-confidence credential pattern found in the archived SQL bodies.")
    print(f"COUNTS: staging=139 staging-clone=12 bytes={observed_bytes}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
