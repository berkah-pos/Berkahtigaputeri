# FASE 1 — INVENTORY VALIDATION (352 KEYS)

**Status: GREEN for canonical workbook/static inventory validation.**  
**Overall consolidation status:** still blocked by Phase 0 access/execution limitations and Phase 4/6 Supabase reconciliation/security gates.  
**Date:** 2026-10-14  
**Branch:** `chore/consolidate-single-main-repo`

## 1. Evidence and tested revision

The successful [Canonical Workbook Validation run 38568280597](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38568280597) executed against PR #39 head `185bfef085abeba479bc94f2df4b6fe7811363cf` on a GitHub-hosted Ubuntu runner. The following artifacts have identical Git blob IDs on current `main`, PR #39's head, and this consolidation branch:

| Artifact | Git blob ID | Result |
|---|---|---|
| Canonical workbook | `cb8775f498487eece091c32b2774f45daa183afd` | Identical |
| `scripts/sync_excel_to_supabase.py` | `c7fedf73fc1f431ad2f28bf097f2b1cf344331e6` | Identical |
| `scripts/sync_excel_to_supabase_legacy.py` | `9273b6626acc612aec2e34a669aadefacb9bd720` | Identical |
| `scripts/tests/test_sync_inventory.py` | `a780a1f8304c31928d5953580a58044de8c8eb49` | Identical |
| `.github/workflows/canonical-workbook-validate.yml` | `cf6c5d276b3869f1291d78eae0caedadfd09d4b9` | Identical |

This is source-equality evidence from Git object IDs. It is not a substitute for the requested local SHA-256 repo comparison, which is unavailable in this session. The workflow run is suitable evidence for the workbook, parser, inventory tests, and sync script because those exact blobs were unchanged.

## 2. Workbook dry-run and regression output

From the successful job log for workflow run `38568280597`, job `115866474986`:

- Inventory regression tests: **4 tests passed**.
- Script command: `scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352`.
- Output: `Inventory: 1 global + 3 template + 100 tenant + 140 service + 108 device = 352`.
- Output: `352 keys validated`.
- Output: `EXPECTED KEY COUNT VERIFIED: 352`.
- Output: `DRY-RUN OK: no Supabase credentials required; no network writes performed`.

The authoritative workbook is `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`; its canonical sheet contract is `README_PRODUCTION`, `TEMPLATES`, `GLOBAL`, `TENANTS_MASTER`, `DEVICES`, `SERVICES`, and `APP_CONFIG_EXPORT`. No workbook edits were required or made.

## 3. Read-only inventory checks against both connected staging projects

A read-only SQL aggregate was executed directly in each connected staging database.

| Check | `berkahtigaputeri-pos-staging` | `berkahtigaputeri-pos-staging-clone` |
|---|---:|---:|
| Total `app_config` rows | 352 | 352 |
| `global` keys | 1 | 1 |
| `template:<id>` keys | 3 | 3 |
| `tenant:<id>` keys | 100 | 100 |
| `tenant:<id>:service:<service>` keys | 140 | 140 |
| `device:<id>` keys | 108 | 108 |
| Unexpected key forms | 0 | 0 |
| Values not JSON objects | 0 | 0 |
| Missing/nonpositive integer versions | 0 | 0 |
| Template keys | BASIC, ENTERPRISE, PRO | BASIC, ENTERPRISE, PRO |

Additional observed fingerprints:
- Ordered keyset MD5 on both projects: `1fd3d64219ecc7c333453c20da80e295`.
- Ordered concatenated key/value payload MD5 on both projects: `fc4c054a80a0f59871f1edc0bb03e268`.
- Version range on each project: 95–108 across 14 distinct version values.

The matching keyset and payload fingerprints show that the two connected staging projects currently have matching `app_config` key/value snapshots. They do not prove that every live value has been compared with the actual workbook rows, nor do they certify the RPC's compare-and-swap semantics.

## 4. Safety decision

**No apply/sync operation was run.** The workbook workflow was explicitly dry-run-only, and the database aggregate queries were read-only. No Supabase credentials were read, no rows were written, and no migrations/permissions were changed.

The two projects remain different outside `app_config`: the primary staging project reports 139 recorded migrations and 63 public tables; the staging clone reports 12 migrations and 64 public tables. Their schema/routine/policy/trigger/extension drift is tracked in the open draft [PR #39](https://github.com/berkah-pos/Berkahtigaputeri/pull/39). This phase must not be interpreted as approval to sync or overwrite either project.

## 5. Acceptance

- [x] Canonical workbook dry-run reported exactly 352 keys on a successful hosted CI run.
- [x] Category counts matched `1 + 3 + 100 + 140 + 108 = 352`.
- [x] Inventory regression tests passed.
- [x] Database `app_config` keys follow the canonical forms and have 352 rows in both staging projects.
- [x] Template identities are BASIC, PRO, ENTERPRISE.
- [x] No database writes or workbook changes.
- [ ] Live project-vs-workbook key/value parity has not been directly demonstrated.
- [ ] The approved destination for a future `--apply` remains unresolved; do not sync until the owner/environment gate is established.

**Phase conclusion:** GREEN for the 352-key workbook and key-inventory acceptance criteria. The entire program is not GREEN; staging-clone drift, tenant isolation proof, RPC privilege review, and release gates remain blocked.
