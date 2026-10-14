# FASE 2 — ARCHITECTURE ALIGNMENT

**Status: GREEN for the reviewed source-contract and Admin CI gates.**  
**Overall program:** NOT GREEN — remote migration reconciliation, hostile Tenant A/B tests, and production gates remain blocked.  
**Date:** 2026-10-14  
**Branch:** `chore/consolidate-single-main-repo`

## 1. Canonical source contract

Reviewed root `AGENTS.md`, `.cursor/rules/berkah-pos.mdc`, `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`, the master roadmap, Admin/runtime docs, active Supabase migrations, the workbook sync scripts, and targeted Admin/Flutter files.

The contract remains:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
app_config(key PRIMARY KEY, value JSONB, updated_at)
1 global + 3 templates + 100 tenants + 140 services + 108 devices = 352 keys
```

For an effective-config request, only the requested tenant-service layer is selected (`pos` or `akuntansi`), and later JSON objects overwrite earlier **top-level** properties. A device ID supplied by a caller is not authority: RPC source checks authentication, device-to-tenant membership, and caller/device authorization. `SECURITY DEFINER` functions have explicit empty search paths and reviewed source-level grants in the active hardening migration.

## 2. Corrective changes made on this branch

| Area | Before | Change and expected invariant |
|---|---|---|
| `btp-admin/editor-core.js` | Saves built replacement JSON only from visible form fields; metadata saves could remove unrendered tenant/template fields. | Atomic writes now merge the existing row with the submitted patch before calling `update_app_config_atomic`, preserving unedited canonical fields and keeping expected-version compare-and-swap. |
| Tenant metadata save | The Admin called the atomic RPC then issued a second direct `tenants` update, creating a separate projection-write path. | Tenant metadata and an intentional feature override are submitted once through the versioned tenant `app_config` write; the existing RPC owns its relational projection update. |
| `btp-admin/feature-flags.js` | Read and directly wrote deprecated `tenants.features`; those edits could disagree with canonical configuration used by Flutter. | Flags are read from the Admin's effective config. When a user changes the flags, the resulting `features` object is included in the same atomic tenant patch. An unchanged inherited value causes no tenant override. |
| `btp-admin/clients.html` | “Add Tenant” inserted only a relational tenant row, bypassing the workbook's fixed canonical key inventory. | Direct creation is disabled with an explicit workbook/352-key onboarding notice. A dynamic onboarding flow requires a separately reviewed provisioning design. |
| `.github/workflows/canonical-workbook-validate.yml` | Admin JavaScript changes were not included in its path filters or syntax checks. | The workflow now watches `btp-admin/**`, checks the Admin JavaScript syntax, and runs the Admin config contract tests alongside the existing workbook tests. |
| `scripts/tests/test_admin_config_contract.py` | No regression checks guarded these Admin integration invariants. | Added six tests for patch preservation, one atomic tenant write, effective feature resolution, five-layer/service separation, removal of relational-only creation, and canonical sync/inventory guards. |

The feature override flow reads inherited flags through `BTP_EDITOR.getEffectiveConfig()`. It adds a tenant-level `features` object only when an admin actually changes one or both flags, avoiding an unnecessary copy of template defaults into every tenant. If effective config lacks supported flags, Admin initialization fails closed instead of inventing default entitlements.

## 3. Source-level checks completed

- `pos-app/lib/core/config/config_service.dart`: requires an authenticated Supabase session for cloud reads; calls only `get_effective_config` with explicit tenant, device and service parameters; caches only the previous effective result for the same tenant/device/service tuple; and documents top-level overwrite semantics in `mergeLayers()`.
- Active SQL sources: `get_effective_config` selects GLOBAL, resolves TEMPLATE via the tenant row, selects one requested SERVICE layer, and applies DEVICE last. The atomic update source validates a positive expected version, locks the current row, rejects version conflicts, increments the version, and updates tenant/device projections in the same transaction.
- Admin service selection accepts only `pos` and `akuntansi`, and the write handlers keep their service-specific keys separate.
- `scripts/sync_excel_to_supabase.py` retains its compare-and-swap call and fail-closed version conflict behavior. Its delegated workbook parser retains the seven-sheet contract and validates exactly 352 canonical keys and the three template IDs.
- Targeted repository search found no active tracked-source match for the forbidden `app_config(device_id, key, value)` form or a three-layer inheritance sequence. Search evidence is scoped evidence, not a substitute for full historical repository archaeology.

## 4. CI evidence on the consolidation branch

Successful hosted run: [Canonical Workbook Validation — run 38583997667](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38583997667), on consolidation-branch SHA `ffa18ca106c32debe6384c50893f48ce95a6b5a1`.

The successful job verified:
- `node --check` for `btp-admin/editor-core.js`, `btp-admin/feature-flags.js`, and `btp-admin/admin-fields.js`;
- **10 Python tests passed** across the existing workbook tests and new Admin contract tests;
- workbook inventory: `1 global + 3 template + 100 tenant + 140 service + 108 device = 352`;
- `EXPECTED KEY COUNT VERIFIED: 352`;
- `DRY-RUN OK`, with no Supabase credentials and no network writes.

Two preceding CI attempts failed only on a new static-test assertion that expected the wrong variable name in the service key; that assertion was corrected, and the linked later run on the updated source completed successfully. The earlier failure is not represented as a passing run.

## 5. Boundaries and remaining blockers

This phase is **GREEN for source alignment and its declared static CI acceptance checks**, not a production certification. Still outstanding:

1. Full SHA-256 repository diff/merge report and review of any future branch divergence.
2. Approved Supabase DEV target and full staging / staging-clone schema, migration, extension, policy, routine, trigger, and effective-privilege reconciliation.
3. Independent hostile Tenant A/B runtime checks through the real authentication/enrollment path, RPC/API and other enabled surfaces.
4. Restore evidence, disposable load/resilience gates, independent release review, and explicit production approval.
5. Browser-level Admin interaction tests and cross-service integration tests are not executed by the new static contract suite.
6. The canonical reference repository `berkah-ajb-dev/Berkahtigaputeri` still returns 404 from the connected GitHub API, and this session has no local git shell to perform the requested local commands/SHA-256 repository script.

No remote Supabase schema, row, privilege, migration, or production resource was changed in Phase 2.

**Phase conclusion: GREEN for the source and CI gates above; program completion remains BLOCKED until the remaining phases meet their own acceptance criteria.**
