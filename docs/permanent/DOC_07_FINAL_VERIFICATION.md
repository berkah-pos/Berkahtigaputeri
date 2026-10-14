# DOC_07 — Historical Final Pos Verification Snapshot

**Status: HISTORICAL / SUPERSEDED as a current runtime or release certification.**
**Original snapshot:** 2026-10-13, former shared PostgreSQL/Supabase implementation.

This file preserves the provenance of former Final Pos source/CI checks. It is not evidence that the current Laravel/KVM2 implementation boots, deploys, isolates tenant databases, syncs sales, or is production-ready.

## Contracts retained

- `GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE`.
- Canonical workbook inventory: 352 keys (1 global, 3 templates, 100 tenants, 140 service rows, 108 devices).
- Sorted keyset MD5: `1fd3d64219ecc7c333453c20da80e295`.
- FEFO physical allocation and FIFO financial costing are intentionally different.
- Inventory COA `1-1040`; COGS COA `5-5010`.

## Current verification authority

Use `AGENTS.md`, `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`, `docs/permanent/DOC_00_MASTER_ROADMAP.md` and `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`.

Current acceptance must be established from the migration branch's present CI, clean MariaDB migration and tenant-provisioning tests, mobile analyzer/tests/AAB, a deployed staging environment and a Tenant A/B attack matrix. The former current-head commit and any old hosted RLS query are not a pass for the new architecture.

**No production KVM2 deploy, transaction migration, backup/restore drill, signing-certificate match or cutover is certified by this historical snapshot.**
