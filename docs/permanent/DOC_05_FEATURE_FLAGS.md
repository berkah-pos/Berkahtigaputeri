> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> This Supabase-era guide, tenant-isolation certificate or versioning report is preserved as a record of its original revision only. Its “GREEN/CERTIFIED/current” claims, identities, SQL and test results are not present-day acceptance and do not prove PostgreSQL 17 database-per-tenant security. Do not access a Supabase project (including read-only), and never run `scripts/sync_excel_to_supabase.py`, even with `--dry-run`.
>
> Current authority: [DOC_00](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](DOC_00_MASTER_ROADMAP.md), [authority map](AUTHORITY_AND_SUPERSESSION_MAP.md). The initial backend scaffold smoke pass is limited to commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149); PG17 real-grant/A-B denial, name confidentiality, API parity, restore and production readiness remain NOT VERIFIED.
>
> ---
>
# DOC_05 — Historical Feature Flags Pilot (Superseded)

Status: **HISTORICAL / SUPERSEDED** — this document describes the pre-Final-Pos two-service pilot and is not current runtime authority.

## Why this document is retained

The former contract stored feature entitlements in `tenants.features` and included demo tenants `clientA` / `clientB`. The current canonical architecture supersedes that contract. The document remains to preserve historical context, but its prior "LIVE / P4" status and SQL seed must not be treated as current verification.

## Current Final Pos contract

The authorities are:

1. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — only supported inheritance is `GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE`.
2. `docs/permanent/DOC_02_FINAL_POS_RELATIONAL_OWNERSHIP.sql` — the workbook owns the relational projections and `app_config`; `tenants.features` is a deprecated compatibility projection.
3. `scripts/sync_excel_to_supabase.py` — validates the canonical workbook's 352-key contract.

For Final Pos, application entitlement flags are resolved from canonical `app_config` values through the authorized effective-config path. A client must not read `tenants.features` as its authoritative source or write that compatibility column as the feature setting. Feature-entitlement resolution is separate from effective service configuration: one request must never combine the POS and Akuntansi service configuration rows.

The canonical template rows are the source of template-level feature flags. In the read-only staging check on 2026-10-13, the 100 workbook-owned tenants assigned to BASIC (60), PRO (35), and ENTERPRISE (5) had template feature flags aligned with the presence of their service-config keys; no service/feature mismatch was observed. This is staging evidence, not production certification.

## Known implementation follow-up

The current `main` revision still has a legacy Admin widget at `btp-admin/feature-flags.js` which directly reads and updates `tenants.features` (lines 4-5). This is a known Admin/runtime-parity defect for the later Phase 3 work. Do not treat that widget as proof of canonical feature-flag behavior. Correct it through a reviewed branch/PR after Phase 2's data-source ownership gate is resolved.

## Historical examples — not canonical

The old pilot's `clientA` / `clientB` values, MDR examples, and service keys are historical only. Do not seed them into the canonical workbook-managed inventory, and do not manually execute `DOC_05_FEATURE_FLAGS.sql`.

## Security invariant

A feature flag controls UI availability only; it does not replace authentication, tenant/device ownership checks, or Row-Level Security. Configuration writes must use the documented atomic expected-version RPC.
