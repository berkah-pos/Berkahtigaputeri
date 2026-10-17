# Owner Source-of-Record Confirmation — 2026-10-17

> **Historical decision notice — 2026-10-17:** This report records the owner's earlier source designation at that time. The later same-day owner ADR `docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` supersedes it for current project operations. It must not be used to authorize connecting to either Supabase project, including read-only access, or to initiate inventory, export, migration, mutation, or cutover. This historical record is retained so the decision history is transparent.

**Decision status:** OWNER-CONFIRMED SOURCE DESIGNATION  
**Repository:** berkah-pos/Berkahtigaputeri  
**Date/time context:** 2026-10-17, Asia/Jakarta  
**Related authority:** docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md §4  
**Related audit:** docs/reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md

## 1. Explicit owner decision

The owner explicitly designated the following Supabase project as the authoritative source-of-record resource for migration and production/source-of-record purposes:

| Field | Decision |
|---|---|
| Project ID | **cztlmwzfrhyafgawphgw** |
| Display name observed in prior catalog evidence | **berkahtigaputeri-pos-staging** |
| Authority | **Selected source-of-record resource** by explicit owner decision |
| Existing resource label | **staging** — retained as metadata; it does not override this owner designation |
| Other observed project | **txwzhesvcjftybrlhnzs** (berkahtigaputeri-pos-staging-clone) — comparison/reconciliation evidence, not the selected source-of-record baseline |

This decision supersedes the earlier unresolved source-identity question in the owner ADR and the pre-decision audit snapshot. It is a resource designation, not a claim that the target Laravel/PostgreSQL architecture is deployed.

## 2. What this decision resolves—and what it does not

**Resolved:** which existing Supabase project must be treated as the owner-designated authoritative source resource for the next source-reconciliation step.

**Not established by designation alone:** whether that project is currently serving live production traffic; whether all production/source-of-record data and objects are present; whether its migration history is complete; whether an export or backup is complete, restorable, or current; or whether the staging clone matches it. The previously recorded metadata differs materially: 139 migration-history records on **cztlmwzfrhyafgawphgw** versus 12 on **txwzhesvcjftybrlhnzs**, with differing catalog footprints. Those differences must be reconciled and explained, not ignored.

The accepted target remains Laravel Central API on KVM2/Coolify with PostgreSQL 17, central database plus a separate tenant database and restricted runtime role per tenant. The source designation does not alter the target architecture.

## 3. Required next actions

1. Use the exact project ID **cztlmwzfrhyafgawphgw**, not name-based guessing, for an authorized **read-only** catalog/export reconciliation.
2. Record the approved read-only access scope and inventory sanitized metadata for schemas/relations, migration history, functions/RPCs and security attributes, triggers, RLS/policies, extensions, indexes/constraints, roles/attributes/grants/default privileges, identity mappings, Storage/object metadata, Realtime/publication use, Edge Functions and secret references (never secret values), known consumers, counts and checksums.
3. Verify export/backup scope and integrity; record restore evidence where available. Do not put credentials, connection URLs/tokens, unredacted production rows or secret values in Git.
4. Reconcile the 139-versus-12 migration-history records and other catalog differences, classify the clone's drift, and attach evidence with dates and exact resource IDs.
5. Keep migration/import, schema/grant mutation, migration-history repair, reset, pause/deletion, cutover and hosted-resource retirement blocked until the inventory is reviewed, backup/restore and parity/security/rollback gates pass, and separate explicit cutover/retirement authorization is recorded.

The owner designation must not be construed as authorization to write to either live project or to execute the mutation-capable scripts/sync_excel_to_supabase.py.

## 4. Status following this decision

| Gate | Status |
|---|---|
| Target architecture choice | **ACCEPTED** — Laravel Central API + PostgreSQL 17 |
| Source-of-record identity | **OWNER-CONFIRMED** — cztlmwzfrhyafgawphgw |
| Authorized read-only inventory/export | **PENDING / NOT VERIFIED** |
| Source-vs-clone catalog/history reconciliation | **PENDING / NOT VERIFIED** |
| Export/backup integrity and restore | **PENDING / NOT VERIFIED** |
| PostgreSQL provisioning and tenant A/B isolation | **NOT VERIFIED** |
| Workbook/config/API/Flutter parity | **NOT VERIFIED** |
| Load/capacity and backup/restore acceptance | **NOT VERIFIED** |
| Migration, cutover, production release and hosted resource retirement | **BLOCKED** |

**Next accountable role:** Database/Schema Forensics Lead, with the Principal Architect / Decision Owner handling any access or decision gap. The next deliverable is a sanitized, dated, read-only inventory/export reconciliation for the owner-designated project—not a live mutation or migration.
