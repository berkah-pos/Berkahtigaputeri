> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.** This retained document records a legacy Supabase-era workflow, retired implementation contract, or dated verification snapshot. Its commands, SQL, project identifiers, identity claims and “green/certified/current” labels are historical evidence only. Do not follow them against any hosted environment or connect to a Supabase project. Current platform authority: [ADR-2026-10-17 no-Supabase decision](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md). Current target and acceptance: [DOC_14](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md). Current configuration semantics only: [DOC_00](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md). See the [authority/supersession map](../reports/ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md) and [dated audit snapshot](../reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md).

---

# HISTORICAL / SUPERSEDED — DOC_05 Feature Flags Pilot

Status: **HISTORICAL / SUPERSEDED** — this document describes the pre-Final-Pos two-service pilot and is not current runtime authority.

## Why this document is retained

The former contract stored feature entitlements in `tenants.features` and included demo tenants `clientA` / `clientB`. The current canonical architecture supersedes that contract. The document remains to preserve historical context, but its prior "LIVE / P4" status and SQL seed must not be treated as current verification.

## Former contract — superseded for runtime/storage

For current work, use these authorities instead:

1. `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — the active five-layer/workbook semantics.
2. `ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` — accepted platform and prohibition on Supabase use/access.
3. `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` — Laravel Central API, normalized central configuration storage, separate PostgreSQL 17 tenant databases/roles and target acceptance gates.
4. The workbook remains the 352-entry source/export contract; the Laravel importer/API must map it to the normalized target model. The legacy Supabase sync script is prohibited and is not a validator or current import command.

For Final Pos, application entitlement flags are resolved from canonical `app_config` values through the authorized effective-config path. A client must not read `tenants.features` as its authoritative source or write that compatibility column as the feature setting. Feature-entitlement resolution is separate from effective service configuration: one request must never combine the POS and Akuntansi service configuration rows.

The canonical template rows are the source of template-level feature flags. In the read-only staging check on 2026-10-13, the 100 workbook-owned tenants assigned to BASIC (60), PRO (35), and ENTERPRISE (5) had template feature flags aligned with the presence of their service-config keys; no service/feature mismatch was observed. This is staging evidence, not production certification.

## Historical implementation follow-up (must be re-verified)

The staging observation below was recorded on 2026-10-13 under the old Supabase architecture. It is retained for historical analysis only and is not current implementation or deployment evidence.

## Known implementation follow-up

The current `main` revision still has a legacy Admin widget at `btp-admin/feature-flags.js` which directly reads and updates `tenants.features` (lines 4-5). This is a known Admin/runtime-parity defect for the later Phase 3 work. Do not treat that widget as proof of canonical feature-flag behavior. Correct it through a reviewed branch/PR after Phase 2's data-source ownership gate is resolved.

## Historical examples — not canonical

The old pilot's `clientA` / `clientB` values, MDR examples, and service keys are historical only. Do not seed them into the canonical workbook-managed inventory, and do not manually execute `DOC_05_FEATURE_FLAGS.sql`.

## Security invariant

A feature flag controls UI availability only; it does not replace authentication, tenant/device ownership checks, or Row-Level Security. Configuration writes must use the documented atomic expected-version RPC.
