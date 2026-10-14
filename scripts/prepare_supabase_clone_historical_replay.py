#!/usr/bin/env python3
"""Prepare a schema-only staging-clone prehistory fixture for a disposable replay of 12 archived migrations.

This script reconstructs the clone's prehistory from audited catalog metadata and shared DDL. The
12 archived migration bodies are materialized separately and are never rewritten. Output is only
for a temporary local Supabase runner; this script must never target an existing hosted project.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "supabase/reconciliation/reconstructed/staging-baseline"
CLONE_FINGERPRINT = ROOT / "supabase/reconciliation/staging-clone-catalog-fingerprint-2026-10-14.json"
CLONE_ACL = ROOT / "supabase/reconciliation/historical-replay-bootstrap/staging_clone_effective_acl_snapshot.sql"
OUTPUT_NAME = "20260929000000_clone_prehistory_schema.sql"

CLONE_ONLY_ROUTINES = {
    "private.create_test_tenant(p_name text)",
    "private.test_tenant_b_fixture_has_data(p_tenant_b uuid)",
    "public.test_tenant_isolation()",
    "public.validate_journal_consistency()",
}
CLONE_ONLY_POLICIES_CREATED_BY_TAIL = {
    "pos_memberships_owner_manage",
    "pos_pin_audit_owner_read",
}
CLONE_ABSENT_TRIGGERS = {
    "accounting_transaction_customer_receivable_guard",
    "accounting_transaction_extended_withholding_guard",
    "trg_app_config_audit",
    "trg_devices_updated_at",
    "trg_plans_updated_at",
    "trg_subscriptions_updated_at",
    "tax_documents_guard",
    "tax_rate_brackets_guard",
}


def count(pattern: str, text: str) -> int:
    return len(re.findall(pattern, text, flags=re.MULTILINE | re.IGNORECASE))


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ValueError(f"cannot read {path.relative_to(ROOT)}: {exc}") from exc


def load_clone_fingerprint() -> dict:
    try:
        value = json.loads(CLONE_FINGERPRINT.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"clone catalog fingerprint is invalid: {exc}") from exc
    if value.get("source_project_id") != "txwzhesvcjftybrlhnzs":
        raise ValueError("catalog fingerprint does not identify the inspected staging-clone")
    if value.get("source_environment") != "staging-clone":
        raise ValueError("catalog fingerprint is not labelled staging-clone")
    observed = tuple(len(value.get(key, [])) for key in ("relations", "functions", "policies", "triggers"))
    if observed != (71, 134, 42, 41):
        raise ValueError(f"clone fingerprint counts changed unexpectedly: {observed}")
    return value


def filter_routine_ddl(source: str, wanted_ids: set[str], label: str) -> tuple[str, set[str]]:
    marker = re.compile(r"(?m)^-- ([^\r\n]+)\r?\n(?=CREATE OR REPLACE FUNCTION\b)")
    matches = list(marker.finditer(source))
    create_count = count(r"^CREATE OR REPLACE FUNCTION\b", source)
    if len(matches) != create_count:
        raise ValueError(
            f"{label}: function headings={len(matches)} differs from function definitions={create_count}"
        )
    if not matches:
        raise ValueError(f"{label}: no routine DDL headings found")

    chunks = [source[:matches[0].start()]]
    seen: set[str] = set()
    kept: set[str] = set()
    for index, match in enumerate(matches):
        routine_id = match.group(1).strip()
        if routine_id in seen:
            raise ValueError(f"{label}: duplicate routine heading {routine_id}")
        seen.add(routine_id)
        end = matches[index + 1].start() if index + 1 < len(matches) else len(source)
        if routine_id in wanted_ids:
            body = source[match.start():end]
            if not re.search(r"\$function\$;\s*$", body):
                raise ValueError(f"{label}: function block has no terminating $function$; — {routine_id}")
            chunks.append(body)
            kept.add(routine_id)
    return "".join(chunks), kept


def filter_security_ddl(source: str) -> tuple[str, int, int]:
    # Split at policy statement boundaries. Remove only the two staging-only owner policies from
    # the prehistory so that the clone's own recorded policy migrations form the final clone set.
    parts = re.split(r"(?m)(?=^CREATE POLICY\b)", source)
    kept_parts: list[str] = []
    removed_policies: set[str] = set()
    for part in parts:
        match = re.match(r'\s*CREATE POLICY\s+"?([^"\s]+)"?', part)
        if match and match.group(1) in CLONE_ONLY_POLICIES_CREATED_BY_TAIL:
            removed_policies.add(match.group(1))
            continue
        kept_parts.append(part)
    if removed_policies != CLONE_ONLY_POLICIES_CREATED_BY_TAIL:
        raise ValueError(f"could not remove exactly the two clone-absent policies: {sorted(removed_policies)}")
    security = "".join(kept_parts)

    original_trigger_count = count(r"^CREATE (?:CONSTRAINT\s+)?TRIGGER\b", security)
    output_lines: list[str] = []
    removed_triggers: set[str] = set()
    for line in security.splitlines(keepends=True):
        match = re.match(r"\s*CREATE (?:CONSTRAINT\s+)?TRIGGER\s+([^\s]+)", line, re.IGNORECASE)
        if match and match.group(1).strip('"') in CLONE_ABSENT_TRIGGERS:
            removed_triggers.add(match.group(1).strip('"'))
            continue
        output_lines.append(line)
    if removed_triggers != CLONE_ABSENT_TRIGGERS:
        raise ValueError(f"could not remove exactly the eight clone-absent triggers: {sorted(removed_triggers)}")
    security = "".join(output_lines)
    policies = count(r"^CREATE POLICY\b", security)
    triggers = count(r"^CREATE (?:CONSTRAINT\s+)?TRIGGER\b", security)
    if original_trigger_count != 49 or (policies, triggers) != (40, 41):
        raise ValueError(
            f"clone prehistory security counts unexpected: source_triggers={original_trigger_count}, "
            f"prehistory_policies={policies}, prehistory_triggers={triggers}"
        )
    return security, policies, triggers


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-migrations-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        fingerprint = load_clone_fingerprint()
        clone_ids = {str(routine.get("id")) for routine in fingerprint["functions"]}
        if not CLONE_ONLY_ROUTINES.issubset(clone_ids):
            raise ValueError("clone fingerprint no longer includes all four documented clone-only routines")
        wanted_ids = clone_ids - CLONE_ONLY_ROUTINES
        if len(wanted_ids) != 130:
            raise ValueError(f"expected 130 shared routines in prehistory, got {len(wanted_ids)}")

        table_sql = read_text(BASELINE / "010_tables_and_sequences.sql")
        constraint_sql = read_text(BASELINE / "020_constraints_and_indexes.sql")
        security_sql = read_text(BASELINE / "040_rls_policies_and_triggers.sql")
        acl_sql = read_text(CLONE_ACL)

        if count(r"^CREATE TABLE\b", table_sql) != 67:
            raise ValueError("expected 67 shared base table definitions")
        if count(r"^ALTER TABLE ONLY .* ADD CONSTRAINT\b", constraint_sql) != 613:
            raise ValueError("expected 613 shared base constraint statements before clone tail")
        if count(r"^CREATE (?:UNIQUE )?INDEX\b", constraint_sql) != 49:
            raise ValueError("expected 49 source indexes before clone-only delta reconciliation")

        # The clone is missing this staging-only index at the captured endpoint.
        constraint_sql, removed_indexes = re.subn(
            r"(?ms)^-- public\.config_history\.idx_config_history_changed_at\r?\n"
            r"CREATE INDEX idx_config_history_changed_at\b.*?;\s*",
            "",
            constraint_sql,
        )
        if removed_indexes != 1:
            raise ValueError(f"expected exactly one staging-only config_history index; removed={removed_indexes}")

        # The catalog reports this logically equivalent check constraint with clone's original
        # expression. Keep the actual clone's textual definition for fingerprint parity.
        constraint_sql, replaced = re.subn(
            r"(ALTER TABLE ONLY public\.extended_withholding_liabilities ADD CONSTRAINT "
            r"extended_withholding_liabilities_original_amount_check CHECK \()original_amount > 0(\);)",
            r"\1NOT (original_amount <= 0)\2",
            constraint_sql,
        )
        if replaced != 1:
            raise ValueError(f"expected one extended-withholding constraint replacement; found {replaced}")
        if "chk_balance" in constraint_sql:
            raise ValueError("chk_balance must be introduced by archived stress migration, not prehistory")
        if "accounting_transaction_evidence_journal_tenant_fkey" in constraint_sql:
            raise ValueError("composite evidence FK must be introduced by archived atomic-posting migration, not prehistory")
        if count(r"^CREATE (?:UNIQUE )?INDEX\b", constraint_sql) != 48:
            raise ValueError("expected 48 indexes after removing the one staging-only index")

        routine_fragments: list[str] = []
        observed_ids: set[str] = set()
        routine_files = sorted(BASELINE.glob("030_plpgsql_*.sql")) + [BASELINE / "031_sql_functions.sql"]
        for routine_file in routine_files:
            filtered, kept = filter_routine_ddl(read_text(routine_file), wanted_ids, routine_file.name)
            routine_fragments.append(filtered)
            overlap = observed_ids.intersection(kept)
            if overlap:
                raise ValueError(f"duplicate routine definitions across fragments: {sorted(overlap)}")
            observed_ids.update(kept)
        if observed_ids != wanted_ids:
            raise ValueError(
                f"prehistory routine set mismatch: missing={sorted(wanted_ids-observed_ids)[:10]}, "
                f"unexpected={sorted(observed_ids-wanted_ids)[:10]}"
            )

        security_sql, policy_count, trigger_count = filter_security_ddl(security_sql)
        if count(r"^\s*(?:INSERT INTO|COPY)\b", table_sql + "\n" + constraint_sql):
            raise ValueError("schema-only clone prehistory cannot contain INSERT/COPY data statements")
        if not acl_sql.startswith("-- DISPOSABLE CLONE HISTORICAL REPLAY ONLY"):
            raise ValueError("clone effective ACL snapshot lacks its mandatory disposable-only safety label")
        if "private.pos_outbox" in table_sql or "public.transaction_type_map" in table_sql:
            raise ValueError("clone-only relations must be created by the recorded outbox migration bodies")

        args.output_migrations_dir.mkdir(parents=True, exist_ok=True)
        target = args.output_migrations_dir / OUTPUT_NAME
        if target.exists():
            raise FileExistsError(f"refusing to overwrite existing {target.name}")
        header = """-- DISPOSABLE CLONE PRE-HISTORY SCHEMA FIXTURE — NOT RECOVERED HISTORICAL MIGRATION SOURCE.
-- Built from audited shared DDL + clone-specific catalog fingerprint/ACL evidence.
-- All 12 recorded clone migration SQL bodies follow unchanged in their own versioned files.
-- Never apply this schema-only fixture to an existing or hosted Supabase project.
"""
        sections = [header, table_sql, constraint_sql, "\n".join(routine_fragments), security_sql, acl_sql]
        combined = "\n\n".join(section.rstrip() for section in sections if section.strip()) + "\n"
        target.write_text(combined, encoding="utf-8")
        print("PASS: clone prehistory assembled in the isolated runner migrations directory.")
        print("PASS: 67 shared tables, 613 shared constraints, 48 shared indexes, 130 routines, 40 policies, 41 triggers.")
        print("PASS: clone-only relations/helpers and two tail-added constraints are absent before recorded clone replay.")
        print("PASS: clone effective ACL snapshot has the required replay-only label; no business rows were seeded.")
        print(f"FIXTURE: {target.name} bytes={target.stat().st_size}")
        print("NOTICE: this is a schema-only prehistory reconstruction, not a claim that a missing original bootstrap migration was recovered.")
        return 0
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print(f"FAIL: clone replay preparation: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
