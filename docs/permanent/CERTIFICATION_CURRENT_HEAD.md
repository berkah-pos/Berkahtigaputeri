# Phase 1 — Canonical Architecture and Current-Head Source Audit

**Status: PARTIAL — source/document audit only.** This is not Phase 7 product certification and does not prove the current Android build, live Supabase data, tenant isolation, deployment, signing, or production readiness.

**Repository:** `berkah-pos/Berkahtigaputeri` (the requested `berkah-ajb-dev/Berkahtigaputeri` path did not resolve directly through the connected GitHub API)  
**Audited base:** `main` at `fb460b7415d546ce6ff8a23430a56c683f6ffb5a`  
**Fix branch:** `audit/phase-1-canonical-architecture-20261013`  
**Pull request:** [#24 — Phase 1 canonical architecture and audit evidence](https://github.com/berkah-pos/Berkahtigaputeri/pull/24)  
**Audit date:** 2026-10-13

## 1. Canonical contract — SOURCE-VERIFIED

The controlling decision in `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md:12,39-48,89-98` requires the only supported inheritance order:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

The workbook is `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`. The canonical inventory is exactly 352 keys: 1 global + 3 templates + 100 tenants + 140 service rows + 108 devices. The canonical schema is `app_config(key PRIMARY KEY, value JSONB, updated_at)`. A resolver must merge only the requested service row; POS and Akuntansi cannot be combined into one effective configuration result.

The source validator `scripts/sync_excel_to_supabase_legacy.py:21-28,122-162` defines the expected sheets and row-type counts, rejects an `APP_CONFIG_EXPORT` whose row count is not 352, checks type counts and key validity, and rejects missing required template keys. The wrapper `scripts/sync_excel_to_supabase.py:317-355` previously did not accept the explicitly requested `--expect-keys` CLI argument; this branch adds that optional assertion while preserving the fixed canonical 352-key validation.

The roadmap's Phase 1 acceptance criteria are documented in `docs/permanent/DOC_00_MASTER_ROADMAP.md:56-65`: one architecture authority, no active frozen-core rule, and consistent 352-key contract. No active frozen-core implementation rule was found in the inspected agent-instruction files; the concrete documentation defect was an old verification report still advertised as current.

## 2. Findings and Phase 1 dispositions

The line references below identify the inspected base revision (`main@fb460b7`), before the branch edits. The corresponding fixes are on `audit/phase-1-canonical-architecture-20261013` in [PR #24](https://github.com/berkah-pos/Berkahtigaputeri/pull/24).

| Finding | Base evidence | Phase 1 correction |
|---|---|---|
| The repository-mandated preflight omitted the workbook validator from its numbered read order. | `AGENTS.md:6-16` | Added `scripts/sync_excel_to_supabase.py` as the final required preflight read. |
| Cursor/Copilot-style instructions omitted parts of the evidence protocol and integration report. | `.cursor/rules/berkah-pos.mdc:1-4`; `.github/muse-instructions.md:3-8` | Both direct agents to `AGENTS.md` and align their sequence with the canonical decision, roadmap, DOC_12, DOC_13, scoped contracts, and validator. |
| The documentation index omitted DOC_12/DOC_13 from the mandatory read order and called an old certification active. | `docs/permanent/README.md:5-20,61` | Updated the order and removed the claim that the legacy-named DOC_07 is the active certification. |
| A retired five-row, three-layer pilot checklist was not labelled superseded. | `docs/permanent/DOC_02_VERIFICATION.md:1-4` and its five-key/legacy UI instructions | Marked it HISTORICAL / SUPERSEDED with a do-not-execute warning and pointers to current authority. |
| A report dated 2026-10-04 still claimed to be “CURRENT HEAD” and the active certification despite referring to an old branch/SHA. | `docs/permanent/DOC_07_FINAL_VERIFICATION_CURRENT_HEAD.md:1-13` and its closing claim | Re-labelled it a historical snapshot; the old run/status matrix is no longer presented as current evidence. |
| The ASD mission and issue inventory described a 2026-10-05 baseline as a persistent live task list, with unchecked items treated as remaining work and an old direct-main workflow. | `docs/permanent/DOC_00_ASD_MISSION.md:4-5,47-56`; `docs/permanent/DOC_08_AUDIT_18_ISSUES.md:1-27` | Labelled both as historical inventories, require rechecking findings against current HEAD, and require branch/PR change control and hosted runners. Updated the ASD trigger instructions. |
| The prescribed validator command was not accepted by its argument parser. | `scripts/sync_excel_to_supabase.py:317-355` | Added `--expect-keys N`, which compares the validated workbook key count against the requested value. It does not override the canonical 352-row constraint. |
| The root README's 352-key badge linked to the stale “CURRENT HEAD” report, and its Final Pos Sync badge referenced a workflow absent from the current tree. | `README.md:1,3`; `.github/workflows/` tree on the audited base | Linked the key badge to the canonical decision and removed the misleading sync badge. Phase 4 must establish and verify the real fail-closed sync workflow before a status badge is restored. |

## 3. Verification evidence and limits

**SOURCE-VERIFIED:** The canonical documents and validator source were read through the connected GitHub repository interface. The required root instruction, architecture decision, roadmap, DOC_12, DOC_13, DOC_01–DOC_04, and workbook-sync wrapper were inspected.

**REPOSITORY-OBSERVED:** The current `main` ref at audit time was `fb460b7415d546ce6ff8a23430a56c683f6ffb5a`. The newest observed run for PR #23, `Canonical POS App CI` run `38342841128`, had conclusion `failure` on commit `969d78e0`; the sibling `Berkah POS Flutter CI` run `38342841108` had conclusion `success` on that same PR commit. These results are not for this Phase 1 branch and do not establish the app is green.

**TEST-EXECUTED:** The `Canonical Workbook Validation` job ran on GitHub-hosted `ubuntu-24.04`. Initial validation passed on `ac35d734cf0fb78bd34ad945ed3900eb7cf4112e` (PR run [`38347650115`](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38347650115), push run [`38347645962`](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38347645962)). After the workflow was expanded to rerun for permanent-document changes, validation also passed on the reviewed Phase 1 branch head `4aaca261f01dc4541bb9bae9e1a51993f4c8c8e3` (PR run [`38347749228`](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38347749228), push run [`38347745240`](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38347745240)). The job checked out the repository, installed `openpyxl` and `requests` into an isolated Python virtual environment, and passed the step executing `scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352`. This validates the checked-out workbook against the fixed 352-key contract without Supabase credentials or network writes. It does not verify live database state.

**NOT RUN / NOT VERIFIED:** A local `cat`/`find`/shell audit, `flutter analyze`, `flutter test`, `supabase db lint`, `gitleaks`, Playwright/browser screenshots, Flutter screenshots, live Supabase queries or policies, RLS tenant-A/tenant-B attacks, concurrency/load tests, Android AAB build/signature checks, Pages deployment verification, and a runner status command. The local environment could not resolve `github.com` for a clone, and no private local runner/database credentials were available here.

No deployment, security test, screenshot, or Flutter/runtime check is claimed as executed by this report.

## 4. Phase 1 acceptance

**PARTIAL / SOURCE + WORKBOOK VALIDATOR PASS.** The instruction-order, stale-certification, historical-backlog and validator CLI discrepancies are addressed in the proposed branch, and the 352-key workbook dry-run passed twice on hosted runner runs. PR review remains open. Phase 1 does not certify Phases 2–7, live 352-row Supabase inventory, Admin/APK/RPC runtime parity, tenant isolation, atomic versioning, or release readiness.

**Next action:** Review and merge PR #24 after verifying the passing workbook-validation check is attached to its latest head. Then continue with Phase 2 in roadmap order; do not mark later phases complete without their own source and runtime evidence.
