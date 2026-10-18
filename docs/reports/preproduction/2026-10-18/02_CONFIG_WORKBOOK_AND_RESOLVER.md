# Pre-production workstream 02 — Config workbook and resolver

**Evidence date:** 2026-10-18 (Asia/Jakarta)  
**Workstream status:** **BLOCKED** — exporter/test changes are committed to the dedicated branch, but the workbook was not revalidated with this exporter, tests were not executed, and the Laravel runtime resolver is missing from the inspected base.  
**Scope:** canonical workbook schema, validator/exporter determinism, relation/key checks, resolver presence, and related CI controls only.

## 1. Executive summary

The canonical contract requires seven sheets in an exact order, 352 exported keys (1 global, 3 templates, 100 tenants, 140 services, 108 devices), and resolution in the order GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE. One effective configuration must resolve one requested service only; POS and Akuntansi must not be merged.

Static inspection found the base exporter too permissive for that contract: it skipped malformed or duplicate headers, counted entry types by prefix, did not fully reconcile source rows to exported keys, consumed workbook cells in data-only mode without rejecting formulas, used a fixed MD5 keyset digest as its only key-integrity check, and serialized row-derived lists without sorting them. The branch updates the exporter with strict key grammar, required tabular headers, literal-cell/formula/error rejection, duplicate JSON-property checks, relational key reconciliation, deterministic ordering, and SHA-256 digests. A missing standalone contract-test script was added with synthetic-only positive and negative cases.

This is **not a PASS**. The exporter changes and tests have not been executed in this environment. The current workbook Git blob is unchanged from a historical run that reported the 352 counts, but the exporter blob at that historical run differs from the exporter on the current base. That run therefore does not validate the current exporter. The Laravel resolver and its named test file were absent at the base SHA, so runtime layer order and single-service isolation remain unverified.

No database synchronization, database query, migration, or production write was performed. The prohibited Supabase sync script was not executed, including in dry-run mode. No workflow YAML or permanent authority document was changed.

## 2. Git identity and change inventory

| Item | Evidence |
|---|---|
| Repository | berkah-pos/Berkahtigaputeri |
| Base branch / exact base SHA | main / 371b7fdf0bf672b37ceb1023e647f114221bf797 |
| Work branch | audit/preprod-config-contract-2026-10-18 |
| Exporter commit | 2a7b1970a9bf129078afb875812f82532ef9f03b |
| Contract-test commit | bb5dad3477619a286d918f73c53ec0fb22fc77c3 |
| Final code/test commit SHA | bb5dad3477619a286d918f73c53ec0fb22fc77c3 (the report-only commit is subsequent) |
| Workbook blob at base | cb8775f498487eece091c32b2774f45daa183afd |
| Files changed in-scope | scripts/export_workbook_for_laravel.py; added scripts/test_canonical_workbook_contract.py; this report |
| Files deliberately not changed | Workbook .xlsx, Laravel resolver/importer, workflow YAML, ADRs, DOC_00, Supabase scripts |
| PR | Draft PR #78: https://github.com/berkah-pos/Berkahtigaputeri/pull/78; no merge or approval is authorized by this workstream. |

Repository clone was attempted with:

    git clone --depth 1 https://github.com/berkah-pos/Berkahtigaputeri.git /tmp/Berkahtigaputeri

**Result:** exit code 128; the shell reported that it could not resolve github.com. The repository was inspected through GitHub file/commit metadata instead of a local checkout. This prevented local Python execution against the real workbook and prevented creation of a locally generated manifest.

## 3. Authority and reading record

Read in the required order from the canonical repository:

1. AGENTS.md
2. docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md
3. docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md
4. docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md
5. docs/permanent/DOC_00_MASTER_ROADMAP.md
6. docs/permanent/README.md
7. docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md
8. docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md
9. docs/permanent/DOC_01_3_LAYER_CONFIG.md
10. .cursor/rules/berkah-pos.mdc
11. .github/muse-instructions.md
12. docs/HARDENING/README.md
13. root README.md
14. Scoped sources and acceptance evidence: scripts/export_workbook_for_laravel.py, scripts/sync_excel_to_supabase.py (static inspection only), scripts/sync_excel_to_supabase_legacy.py (static inspection only), app/Console/Commands/ImportCanonicalWorkbook.php, config/ci/required-check-matrix.json, .github/workflows/canonical-workbook-validate.yml, and related CI evidence reports.

**Authority rule applied:** the 2026-10-17 owner ADR's no-Supabase decision overrides older Supabase instructions and historical reports. DOC_00 remains authority for the workbook contract and five-layer configuration semantics. No authority document was edited.

## 4. Acceptance gates

| Gate | Acceptance criterion | Status | Evidence / blocker |
|---|---|---|---|
| CFG-01 | Exact seven sheet names and order | **BLOCKED** | Exact sheet order check is implemented in exporter lines 281-300, but the modified code was not executed against the workbook. Workbook blob: cb8775f498487eece091c32b2774f45daa183afd. |
| CFG-02 | Required headers, duplicate/blank headers, required fields, literal text types and blank/null handling | **BLOCKED** | Strict table/header parsing and text identifier checks added at exporter lines 71-163; synthetic negative tests added but not run. Actual workbook header/type outcomes are unknown in this execution. |
| CFG-03 | Formula and cached-value handling is fail-closed | **BLOCKED** | Formula and Excel error cells on configuration sheets are rejected at exporter lines 252-269. Actual workbook formula scan was not executed. |
| CFG-04 | Exact 352 count and category counts | **PARTIAL / BLOCKED** | Historical run 38856048876 reported success on SHA 6e31574ecc04ecae6a535fe409cf415ec18655cc; workbook blob is identical to current base, but validator blob differs. No current code/data execution was performed. |
| CFG-05 | Unique and canonical key syntax | **BLOCKED** | Canonical grammar, duplicate detection and type counts added at lines 219-250 and 323-346; tests cover malformed and duplicate keys but are NOT RUN. |
| CFG-06 | Referential integrity across templates, tenants, services, devices, and APP_CONFIG_EXPORT | **BLOCKED** | Exact source/export key-set equality and tenant/service/device scope checks added at lines 359-465; tests cover missing parents and cross-scope keys. Not run. |
| CFG-07 | Deterministic serialization and SHA-256 | **BLOCKED** | Stable projected-list ordering, UTF-8/LF compact JSON, source_workbook_sha256, keyset_sha256 and manifest_sha256 added at lines 444-498. No output manifest or repeat-run hashes were generated. |
| CFG-08 | Runtime order GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE | **BLOCKED** | app/Services/EffectiveConfigResolver.php was not found at the base SHA; GitHub Contents API returned 404. No runtime resolver code could be evaluated. |
| CFG-09 | Requested-service-only resolution; POS/Akuntansi isolation; tenant/device mismatch rejection | **BLOCKED** | tests/Unit/Services/EffectiveConfigResolverTest.php also returned 404 at base. Workbook source/export linkage is stricter in the branch, but does not prove runtime resolver isolation. |
| CFG-10 | No Supabase side effects and no obsolete sync invocation | **VERIFIED for this agent's actions; CONFLICT remains in repo** | No sync was run. Static inspection shows the canonical workbook workflow at .github/workflows/canonical-workbook-validate.yml:68 invokes the prohibited scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352. Workflow YAML is outside this workstream and remains unchanged. |
| CFG-11 | Exact-head CI and safe artifact evidence | **BLOCKED** | No CI run was recorded for the new branch/head. Current validation and repeatability commands were not executed; no canonical manifest artifact was generated in this run. |

## 5. Findings

### F-01 — Runtime resolver and resolver tests missing

- **Severity / confidence:** P1 / High.
- **Status:** BLOCKED; not fixed in this workstream.
- **Evidence:** On base SHA 371b7fdf0bf672b37ceb1023e647f114221bf797, retrieving app/Services/EffectiveConfigResolver.php and tests/Unit/Services/EffectiveConfigResolverTest.php returned GitHub Contents API 404 Not Found. The acceptance matrix names resolver tests, but path references and historical test summaries are not implementation evidence.
- **Impact:** Required precedence, explicit override semantics, tenant/device scope authorization, and POS-versus-Akuntansi isolation cannot be proven at runtime. Workbook validation alone is insufficient.
- **Required next action:** Route to the configuration/API contract owner to implement/integrate the five-layer resolver and tests on the accepted Laravel/PostgreSQL target. Require tests for override/inheritance, missing template, tenant/device mismatch, wrong requested service, POS/Akuntansi cross-merge, deterministic version/hash and compare-and-swap. Do not add a disconnected substitute resolver merely to satisfy file-presence checks.

### F-02 — Existing workbook-validation workflow conflicts with the no-Supabase authority

- **Severity / confidence:** P1 / High.
- **Status:** Open dependency; workflow intentionally not edited.
- **Evidence:** .github/workflows/canonical-workbook-validate.yml:58-68 runs a workbook test-discovery step and then invokes scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352. The legacy script contains mutation-capable REST/RPC calls. The current root instructions expressly prohibit running that script, including dry-run.
- **Impact:** Current CI is not a suitable safe validation path under the latest architecture authority, even though its checked-in invocation uses a dry-run argument. A future edit to triggering paths or manual dispatch could execute a forbidden legacy code path.
- **Required next action:** Route to the workflow owner. Replace that invocation with the offline scripts/export_workbook_for_laravel.py --validate-only and standalone deterministic contract tests in a separately reviewed workflow change. Do not execute or manually dispatch the current workflow from this audit.

### F-03 — The base exporter did not enforce enough of the workbook contract

- **Severity / confidence:** P1 / High.
- **Status:** Corrective code proposed in this branch; closure NOT VERIFIED.
- **Evidence:** Base exporter blob af759fe3b736047de077f68e907e3e2eb9031e8e read the workbook with data_only=True, filtered blank headers, counted keys by prefix, verified the historical MD5 only, and did not require source/export service and device key equality. The branch changes exporter behavior in lines 71-269 and 281-498.
- **Impact:** Malformed workbook rows, formulas with stale cached results, non-canonical keys, or a valid-but-wrong app_config_key could evade checks or map to the wrong service/device configuration. MD5 alone and row-order-dependent serialization did not meet the SHA-256/repeatability acceptance contract.
- **Corrective work:** Added strict table/header parsing, literal configuration-cell enforcement, duplicate JSON property rejection, exact canonical key grammar, exact equality between exported keys and source sheet projections, tenant/service/device scope checks, sorted projected rows, and SHA-256 values while preserving the legacy MD5 field for importer compatibility.
- **Required next action:** Run the new test file and the offline exporter against the actual canonical workbook and review any schema/header mismatch before accepting the change. No source/test pass is claimed here.

### F-04 — Actual workbook row counts and output hashes not independently regenerated

- **Severity / confidence:** P1 / High for acceptance evidence.
- **Status:** BLOCKED.
- **Evidence:** Current workbook Git blob SHA is cb8775f498487eece091c32b2774f45daa183afd; querying the same path at old tested SHA 6e31574ecc04ecae6a535fe409cf415ec18655cc returned the same blob SHA. Historical evidence for run 38856048876 reports 352 keys and counts 1/3/100/140/108, but its exporter blob was 7cc291ad7d6d777d2c3472737a4744f5112d23ed, not the current base exporter blob af759fe3b736047de077f68e907e3e2eb9031e8e.
- **Impact:** Historical same-workbook evidence is useful but cannot substitute for executing the current exporter/new checks. No source data mismatch is confirmed; current output is unverified.
- **Required next action:** In an environment with a local checkout, run the offline validator, export to two clean local directories, compare bytes and SHA-256, and attach the sanitized manifest and command logs. Never run the old sync script.

## 6. Test commands and execution evidence

| Command / check | Environment | Exit / status | Result / artifact |
|---|---|---|---|
| git clone --depth 1 https://github.com/berkah-pos/Berkahtigaputeri.git /tmp/Berkahtigaputeri | Shell in this session | **128** | Failed: DNS resolution for github.com unavailable; no local checkout. Sanitized output recorded above. |
| python scripts/export_workbook_for_laravel.py --validate-only | Intended local/offline Python | **NOT RUN** | No local repository/workbook in shell; no output/counts claimed. |
| python scripts/test_canonical_workbook_contract.py | Intended local/offline Python | **NOT RUN** | Test file added, but no Python test process was started. |
| python -m unittest discover -s scripts/tests -p 'test_*.py' | Intended local/offline Python | **NOT RUN** | No local checkout. Current CI sequence is also blocked by the prohibited sync-script step and was not dispatched. |
| Export twice to clean directories, then compare manifest bytes and SHA-256 | Intended local/offline Python | **NOT RUN** | No manifest/log artifact produced by this session. |
| python scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352 | Prohibited legacy path | **NOT RUN — deliberate** | Forbidden by the latest no-Supabase authority even in dry-run mode. |
| CI: Canonical Workbook Validation, run 38856048876, job 116827669252 | Historical GitHub Actions record | success in historical evidence | Tested SHA 6e31574ecc04ecae6a535fe409cf415ec18655cc; https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048876. Attempt number and raw logs were not independently retrieved here. This run predates the current exporter and is not exact-head evidence for this branch. |
| CI on audit/preprod-config-contract-2026-10-18 | GitHub Actions | **NOT RUN / NOT VERIFIED** | No workflow result is attributed to this branch. The changed paths do not match the current workbook workflow's listed source/test paths, and the workflow was not manually dispatched. |

## 7. Mismatches and deterministic artifact status

- Required workbook inventory is 1 + 3 + 100 + 140 + 108 = 352. Historical CI evidence reported this inventory on an older SHA; the workbook Git blob is identical at the inspected refs. This is **CLAIMED / historical**, not a fresh validation result.
- No actual count/key mismatch has been demonstrated from the current workbook in this execution.
- Confirmed source gaps at base: missing runtime resolver path; missing matrix-named tests/Unit/Services/EffectiveConfigResolverTest.php; missing matrix-named standalone scripts/test_canonical_workbook_contract.py.
- Corrective exporter and synthetic test source were committed on the work branch. Since neither actual workbook validation nor tests ran, **no manifest/hash artifact is claimed as generated**. The updated exporter will emit source_workbook_sha256, keyset_sha256, manifest_sha256, and retain keyset_md5 when run in a safe local environment.
- No workbook content was modified; no secret, customer payload, or live database data was copied into this report.

## 8. Dependencies, residual risks, and next steps

1. **Configuration/API contract owner:** implement and test the missing Laravel resolver and versioned configuration writer behavior; this workstream did not fabricate runtime integration.
2. **Workflow owner:** remove the prohibited sync script from the workbook-validation workflow and update CI to run only safe offline validators/tests. This workstream did not edit YAML.
3. **QA/evidence owner:** run exact-head tests on the eventual integrated candidate SHA; record workflow/run ID, attempt, checked-out SHA, commands, exits, sanitized logs and generated manifest/hash artifacts.
4. **Workbook owner:** review any rejection caused by real workbook headers, boolean encodings or formulas. Do not weaken strict checks without evidence and a contract decision.
5. Until these items are complete, keep the release gate **BLOCKED**. No PR merge, production migration, deployment or go-live approval is made by this report.

## 9. Recommendation

**BLOCKED** — corrective exporter/test source exists on the work branch, but workbook validation, deterministic export, tests, and Laravel resolver behavior have not been executed or proven on an exact integrated candidate SHA. BLOCKED is not PASS.
