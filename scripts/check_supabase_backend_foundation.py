#!/usr/bin/env python3
"""Static repository guardrails for the Supabase backend foundation.

This script does not connect to Supabase and does not certify staging or production.
It verifies the local config, canonical contracts, migration naming, and security test presence.
"""
from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "supabase" / "config.toml"
MIGRATIONS = ROOT / "supabase" / "migrations"
TENANT_TEST = ROOT / "supabase" / "tests" / "tenant_isolation.test.sql"
CANONICAL = ROOT / "docs" / "permanent" / "DOC_00_CANONICAL_ARCHITECTURE_DECISION.md"
ROADMAP = ROOT / "docs" / "permanent" / "DOC_00_MASTER_ROADMAP.md"
ARCHITECTURE = ROOT / "docs" / "permanent" / "DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md"
FOUNDATION = ROOT / "docs" / "permanent" / "DOC_14_SUPABASE_IDCLOUDHOST_BACKEND_FOUNDATION.md"
RUNBOOK = ROOT / "docs" / "permanent" / "DOC_15_PRODUCTION_BACKEND_DEPLOYMENT_RUNBOOK.md"
MIGRATION_NAME = re.compile(r"^(\d{14})_[a-z0-9_]+\.sql$")


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)


def main() -> int:
    failures: list[str] = []

    if not CONFIG.is_file():
        failures.append("supabase/config.toml is missing")
        config: dict = {}
    else:
        try:
            config = tomllib.loads(CONFIG.read_text(encoding="utf-8"))
        except (tomllib.TOMLDecodeError, OSError) as exc:
            failures.append(f"supabase/config.toml is invalid: {exc}")
            config = {}

    project_id = config.get("project_id")
    if project_id != "berkah-pos-local":
        failures.append("config.toml must use the non-production local project_id 'berkah-pos-local'")
    if config.get("db", {}).get("major_version") != 17:
        failures.append("local Postgres major version must remain aligned with the inspected staging projects (17)")
    if config.get("experimental", {}).get("pgdelta", {}).get("enabled", False) is not False:
        failures.append("pg-delta must remain disabled until the remote schema/migration baseline is reconciled")

    migration_files = sorted(MIGRATIONS.glob("*.sql")) if MIGRATIONS.is_dir() else []
    versions: list[str] = []
    for migration in migration_files:
        match = MIGRATION_NAME.fullmatch(migration.name)
        if not match:
            failures.append(f"migration filename does not follow <14-digit-timestamp>_<snake_case>.sql: {migration}")
            continue
        versions.append(match.group(1))
    if len(versions) != len(set(versions)):
        failures.append("migration timestamps must be unique")
    if not migration_files:
        failures.append("no Supabase migration files found")
    if not any("phase5_tenant_isolation_hardening" in path.name for path in migration_files):
        failures.append("Phase 5 tenant-isolation migration is missing")
    if not TENANT_TEST.is_file():
        failures.append("tenant-isolation SQL test file is missing")

    for path in (CANONICAL, ROADMAP, ARCHITECTURE, FOUNDATION, RUNBOOK):
        if not path.is_file():
            failures.append(f"required architecture/evidence document is missing: {path.relative_to(ROOT)}")

    if CANONICAL.is_file():
        canonical_text = CANONICAL.read_text(encoding="utf-8")
        if "GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE" not in canonical_text:
            failures.append("canonical five-layer configuration inheritance contract is missing")
        if "352" not in canonical_text:
            failures.append("canonical 352-key configuration inventory contract is missing")

    # Never permit local-only credential files to be checked in at the paths
    # that commonly carry Supabase CLI configuration/secrets.
    for secret_path in (ROOT / ".env", ROOT / "supabase" / ".env", ROOT / "supabase" / ".env.local"):
        if secret_path.exists():
            failures.append(f"local secret file must not exist in the repository checkout: {secret_path.relative_to(ROOT)}")

    if failures:
        for message in failures:
            fail(message)
        return 1

    print(f"PASS: Supabase config TOML parses; local-only project_id and Postgres {config['db']['major_version']} are set.")
    print(f"PASS: {len(migration_files)} tracked SQL migration(s) use unique timestamped filenames.")
    print("PASS: canonical inheritance, 352-key inventory, Phase 5 migration and tenant-isolation test are present.")
    print("NOTICE: this is a static repository check, not a live database or production certification.")
    print("NOTICE: keep pg-delta disabled until repository migrations and the staging schema/history are reconciled.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
