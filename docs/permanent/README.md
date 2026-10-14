# DOCS PERMANENT — FINAL POS ARCHITECTURE AUTHORITY

This folder contains the durable architecture, security, schema, operational, and verification record for Berkah POS.

## Mandatory read order

1. Root `AGENTS.md` — mandatory preflight, scoped work, and evidence-reporting rules.
2. `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — sole authority for Final Pos configuration inheritance.
3. `DOC_00_MASTER_ROADMAP.md` — correction phases and acceptance gates in order.
4. `DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md` — scoped execution and evidence protocol.
5. `DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` — implementation evidence and unresolved gates.
6. `DOC_01_3_LAYER_CONFIG.md` — legacy filename; canonical Final Pos contract.
7. `DOC_02_SUPABASE_SCHEMA_V1.sql` and `DOC_02_FINAL_POS_RELATIONAL_OWNERSHIP.sql` — schema and workbook ownership.
8. `DOC_03_RLS_AUTH.sql` and `DOC_03_RLS_AUTH_FIXED.sql` — authenticated tenant-isolation contract.
9. `DOC_04_ADMIN_ARCHITECTURE.md` — Admin architecture.
10. `scripts/sync_excel_to_supabase.py` — workbook validator and 352-key inventory.
11. `DOC_05_FEATURE_FLAGS.md`, `DOC_05_FEATURE_FLAGS.sql` — service/feature configuration.
12. `DOC_06_AUDIT_VERSIONING.md`, `DOC_06_ATOMIC_VERSIONING_RPC.sql` — atomic version integrity.
13. `CERTIFICATION_CURRENT_HEAD.md` — scoped Phase 1 canonical source audit; **not** a Phase 7 product/runtime certification.
14. `DOC_07_FINAL_VERIFICATION_CURRENT_HEAD.md` — historical snapshot dated 2026-10-04; its legacy filename does **not** make it current.
15. `DOC_07_FINAL_VERIFICATION_HISTORICAL_a19cb3f.md` — historical old 3-layer snapshot; **not current authority**.
16. `DOC_08_RPC_EFFECTIVE_CONFIG.sql` — authenticated effective-config RPC reference.
17. `DOC_09_APK_VERIFICATION.md` — APK/config verification and release-surface boundary.
18. `DOC_14_SUPABASE_IDCLOUDHOST_BACKEND_FOUNDATION.md` — Supabase-managed + IDCloudHost architecture, backend rollout gates, and explicit source/staging/production evidence; required for backend/operations/deployment changes.
19. `DOC_15_PRODUCTION_BACKEND_DEPLOYMENT_RUNBOOK.md` — Ubuntu 24.04 VM selection, secure host hardening, managed Supabase feature rollout, CI/CD, monitoring, backup/restore, and production acceptance checklist.

When any document conflicts with `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`, the canonical decision wins. Historical reports do not prove current CI, staging, or production status.

## Canonical model

```text
GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE
```

Canonical workbook:

`config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`

Canonical inventory:

```text
1 global + 3 templates + 100 tenants + 140 services + 108 devices = 352 keys
```

Canonical key forms:

```text
global
template:<TEMPLATE_ID>
tenant:<tenant_id>
tenant:<tenant_id>:service:<service>
device:<device_id>
```

POS and Akuntansi service rows are service-specific and are not merged together.

## Security boundary

Anonymous direct reads of Final Pos backing tables are not allowed. Anonymous execution of `get_effective_config(...)` is also revoked. Runtime cloud config requires authentication, and normal authenticated callers are scoped by `devices.user_id = auth.uid()` plus device-to-tenant validation.

## Repository operating rule

- Work on branches and merge through review/PR.
- Do not push Final Pos implementation directly to `main`.
- Do not restore inheritance that omits TEMPLATE.
- Do not re-enable anonymous Final Pos table/RPC reads.
- Keep `btp-admin/` as the published Admin path.
- Treat `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` as the architecture authority; use current test/runtime evidence for implementation certification.
- Keep historical verification clearly labelled historical.

## Live Admin

https://berkah-ajb-dev.github.io/Berkahtigaputeri/btp-admin/

20. `DOC_16_SUPABASE_MIGRATION_RECONCILIATION.md` — current staging/clone migration-history and schema fingerprint comparison; mandatory before remote migration work.
21. `DOC_17_SUPABASE_SOURCE_RECOVERY_AND_CLEAN_REPLAY.md` — two-repository migration source recovery, reconstructed staging schema snapshot, and isolated clean-replay protocol.
22. `DOC_07_FINAL_VERIFICATION.md` — current consolidation-branch verification evidence and explicit outstanding release blockers; not production certification.
