# Pre-production workstream 02 — Config workbook and resolver

**Evidence date:** 2026-10-20 (Asia/Jakarta)  
**Workstream status:** **BLOCKED** — the actual workbook structure and aggregate key/relationship inventory were independently inspected read-only, and exporter/tests received additional source changes; however, the Python exporter and tests remain NOT RUN, no exporter manifest hashes were generated, the Laravel effective-config resolver/tests are absent from the base, and the existing workbook workflow invokes a prohibited legacy sync script.  
**Scope:** canonical workbook schema, validator/exporter determinism, relation/key checks, resolver presence, and related CI controls only.

## 1. Executive summary

The canonical contract requires seven sheets in this exact order and 352 exported keys (1 global, 3 templates, 100 tenants, 140 services, 108 devices), with effective configuration resolved GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE. A configuration request must resolve only its requested service; POS and Akuntansi are not merged.

A read-only OOXML/ZIP inspection of the actual workbook object (Git blob cb8775f498487eece091c32b2774f45daa183afd) verified the sheet order, data-row counts, 352 unique canonical keys, expected category counts 1/3/100/140/108, zero duplicate/invalid keys, valid JSON-object values for all 352 entries, matching type and source-sheet labels, matching tenant/template assignments for all 140 service and 108 device rows, zero missing/extra source-linked keys, and zero formula cells. The sanitized aggregate output is 02_CONFIG_WORKBOOK_VALIDATION_SUMMARY.json; no configuration payloads or customer fields are included.

Static inspection found the main-branch exporter too permissive for the contract: it filtered blank headers, counted by prefix, did not fully reconcile source rows to export keys, read cached formula values with data_only=True, used MD5 as its only keyset integrity check, and serialized projections without stable sorting. The branch hardens key grammar, headers, formula/error rejection, strict JSON and duplicate JSON-property checks, referential/scope checks, deterministic sorting, and SHA-256 output. During this pass, the exporter was additionally changed to require type, source_sheet, and sync_status headers and check that type and source_sheet match the key canonical scope; synthetic negative tests were added for these mismatches.

This is **not a PASS**. The custom read-only workbook inspection is direct evidence for workbook structure and aggregate relationships, but it is not execution of scripts/export_workbook_for_laravel.py. Neither that Python exporter nor its synthetic tests ran here; no exporter-generated keyset_sha256 or manifest_sha256 and no two-run byte comparison were produced. The Laravel resolver and its named test file are absent at the inspected base SHA, so runtime five-layer behavior and service isolation remain unverified.

No database synchronization, database query, migration, or production write was performed. The prohibited Supabase sync script was not executed, including in dry-run mode. No workflow YAML, workbook bytes, or permanent authority document was changed.

## 2. Git identity and change inventory

| Item | Evidence |
|---|---|
| Repository | berkah-pos/Berkahtigaputeri |
| Base branch / exact base SHA | main / 371b7fdf0bf672b37ceb1023e647f114221bf797 |
| Work branch | audit/preprod-config-contract-2026-10-18 |
| Exporter hardening commits | 2a7b1970a9bf129078afb875812f82532ef9f03b; scope-label validation added at 3627b7eb128c3190b8249d5d7e8a5257edf0e98b |
| Contract-test commits | bb5dad3477619a286d918f73c53ec0fb22fc77c3; type/source negative tests added at a66c73b8e67e715d61d5b2bfe35cf2e6ec07f3c7 |
| Code/test checkpoint SHA before metadata/report refresh | a66c73b8e67e715d61d5b2bfe35cf2e6ec07f3c7 |
| Workbook Git blob at base | cb8775f498487eece091c32b2774f45daa183afd |
| Files changed in-scope | scripts/export_workbook_for_laravel.py; scripts/test_canonical_workbook_contract.py; sanitized 02_CONFIG_WORKBOOK_VALIDATION_SUMMARY.json; this report |
| Files deliberately not changed | Workbook .xlsx, Laravel resolver/importer, workflow YAML, ADRs, DOC_00, prohibited Supabase sync scripts |
| PR | Draft PR #78: https://github.com/berkah-pos/Berkahtigaputeri/pull/78; no merge or approval is authorized by this workstream. |

Repository clone was attempted with:

    git clone --depth 1 https://github.com/berkah-pos/Berkahtigaputeri.git /tmp/Berkahtigaputeri

**Result:** exit code 128; the shell reported that it could not resolve github.com. Repository source and workbook bytes were therefore inspected through read-only GitHub file/commit metadata instead of a local checkout. An in-memory, read-only OOXML parser counted rows, examined canonical key strings, parsed aggregate JSON-object structure and compared source/export parent/key mappings. It emitted only the sanitized metadata artifact noted above. The Python exporter and test suite were still not executed.

## 3. Authority and reading record

Read in the required order from the canonical repository, including the current no-Supabase authority:

1. AGENTS.md
2. docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md
3. docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md
4. docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md
5. docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md
6. docs/permanent/DOC_00_MASTER_ROADMAP.md
7. docs/permanent/README.md
8. docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md
9. docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md
10. docs/permanent/DOC_01_3_LAYER_CONFIG.md
11. .cursor/rules/berkah-pos.mdc
12. .github/muse-instructions.md
13. docs/HARDENING/README.md
14. root README.md
15. Scoped sources and acceptance evidence: scripts/export_workbook_for_laravel.py, scripts/sync_excel_to_supabase.py (static inspection only), scripts/sync_excel_to_supabase_legacy.py (static inspection only), app/Console/Commands/ImportCanonicalWorkbook.php, config/ci/required-check-matrix.json, .github/workflows/canonical-workbook-validate.yml, and related CI evidence reports.

**Authority rule applied:** the 2026-10-17 owner ADR's no-Supabase decision overrides older Supabase instructions and historical reports. DOC_00 remains authority for the workbook contract and five-layer configuration semantics. No authority document was edited.

## 4. Acceptance gates

| Gate | Acceptance criterion | Status | Evidence / blocker |
|---|---|---|---|
| CFG-01 | Exact seven sheet names and order | **VERIFIED (workbook structure)** | Direct workbook inspection confirms the exact seven sheet names/order at Git blob cb8775f498487eece091c32b2774f45daa183afd. Exporter re-execution is separate and remains NOT RUN. |
| CFG-02 | Required headers, duplicate/blank headers, required fields, literal text types and blank/null handling | **PARTIAL** | Actual headings were inspected and required columns used by the branch exporter are present; canonical data rows yielded expected identifier/key relationships. Strict Python header/null/type validation was not executed, so full acceptance remains open. |
| CFG-03 | Formula and cached-value handling is fail-closed | **PARTIAL** | Read-only OOXML inspection observed zero formula cells; branch exporter loads with data_only=False and rejects formulas/errors. Excel error-cell validation through the Python exporter remains NOT RUN. |
| CFG-04 | Exact 352 count and category counts | **VERIFIED (workbook structure)** | APP_CONFIG_EXPORT has 352 rows, exact categories 1/3/100/140/108, zero invalid keys and zero duplicates. This is not an exporter test pass. |
| CFG-05 | Unique and canonical key syntax | **VERIFIED (workbook structure)** | All 352 keys matched canonical key grammar and were unique in direct inspection; template IDs are BASIC/PRO/ENTERPRISE. Python validator/test execution remains NOT RUN. |
| CFG-06 | Referential integrity across templates, tenants, services, devices, and APP_CONFIG_EXPORT | **VERIFIED (workbook structure)** | Direct inspection found zero missing/extra exported keys, zero tenant/service/device orphans, zero duplicate service pairs, zero service/device template assignment mismatches, zero invalid JSON objects, and zero type/source_sheet mismatches. Strict exporter execution remains NOT RUN. |
| CFG-07 | Deterministic serialization and SHA-256 | **BLOCKED** | Source code now sorts projections/JSON and computes source/keyset/manifest SHA-256; exporter was not run, no manifest digest was emitted, and no two-export byte comparison exists. Git blob SHA fingerprints the workbook object only; it is not an exporter manifest hash. |
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

### F-03 — Base exporter was too permissive; corrective exporter code is not executed

- **Severity / confidence:** P1 / High.
- **Status:** SOURCE-VERIFIED changes; tests NOT RUN; closure BLOCKED.
- **Evidence:** Base exporter blob af759fe3b736047de077f68e907e3e2eb9031e8e loaded with data_only=True, filtered blank headers, counted by prefix and emitted order-dependent projections. The branch exporter now fails closed on strict headers/formula/error cells/JSON/key grammar, reconciles source/export keys and tenant/service/device scope, sorts projections and emits SHA-256 digests. A follow-up change also requires type, source_sheet and sync_status headers and checks type/source ownership against canonical key category (code commit 3627b7eb128c3190b8249d5d7e8a5257edf0e98b). Synthetic tests were added for wrong type/source-sheet mappings.
- **Impact:** Without these controls, stale formula caches, duplicate/malformed keys and scope-crossing references could evade validation. Source code presence does not establish runtime behavior.
- **Corrective work:** Strict workbook parser/exporter and synthetic negative cases are committed to this branch; direct workbook inspection found no current aggregate key/source mismatch.
- **Required next action:** Run the offline exporter and isolated synthetic tests on a local checkout or a new safe workflow approved by the workflow owner. Do not call the legacy sync wrapper.

### F-04 — Workbook data structure verified; exporter digest not yet regenerated

- **Severity / confidence:** P1 / High for acceptance evidence.
- **Status:** PARTIAL — structure verified; Python exporter/hash acceptance BLOCKED.
- **Evidence:** The read-only workbook inspection artifact records the workbook Git blob cb8775f498487eece091c32b2774f45daa183afd, all seven sheets/row counts, 352 unique key-category totals, zero source/export mapping mismatches, zero formula cells, and zero template/source scope mismatches. Historical run 38856048876 is not exact-head evidence for the current exporter.
- **Impact:** The canonical workbook structure is consistent with DOC_00, but deterministic serialization, SHA-256 manifest/keyset values and same-input repeated export equality have not been executed.
- **Required next action:** On a machine with a local checkout, run python scripts/export_workbook_for_laravel.py --validate-only; export twice into clean directories and compare exact bytes plus SHA-256. Do not run the prohibited script.


### F-05 — Importer trusts manifest metadata instead of validating its contents

- **Severity / confidence:** P1 / High.
- **Status:** Open dependency; importer was not changed because this workstream is limited to workbook validation/export and resolver contract tests.
- **Evidence:** `app/Console/Commands/ImportCanonicalWorkbook.php:44-60` (`validateManifest`) checks the schema version, compares the *provided* `keyset_md5` field to a constant, checks top-level counts/list lengths, and verifies only that `global_config` is an array. It does not recompute the digest from the manifest's actual keys, verify `manifest_sha256` / `keyset_sha256`, or validate each item’s identifier, parent, and tenant/service/device scope before import. The `handle()` path calls `validateManifest()` and then starts central and device imports (`ImportCanonicalWorkbook.php:27-35`).
- **Impact:** An edited or malformed manifest can retain the expected count fields and supplied MD5 string while carrying altered config or mismatched record relationships. The static review does not prove a live bad import occurred; no import command was run.
- **Required next action:** The configuration importer owner should independently validate the complete manifest *before any database write*: recompute canonical keyset and manifest hashes, validate exact key grammar and actual record counts, validate every tenant/template/service/device mapping and scope, and fail without writes on any mismatch. Add negative tests that alter a config value, identifiers, parent references, service/device scope, and supplied digest while preserving top-level counts. A plain hash detects accidental corruption, not an adversary able to rewrite both content and digest; authenticity must be handled separately if the threat model requires it.

### F-06 — Synthetic test file is outside the configured discovery root

- **Severity / confidence:** P2 / High.
- **Status:** Open dependency; no workflow was edited.
- **Evidence:** The acceptance matrix names unittest discovery under scripts/tests, while the new synthetic file is scripts/test_canonical_workbook_contract.py. The current workbook workflow path filter watches scripts/tests/** but not the new root-level test, then calls the prohibited sync script as its last step.
- **Impact:** Existing automated discovery will not execute these new tests; moving them under scripts/tests would also match a workflow that currently invokes forbidden legacy code.
- **Required next action:** The workflow owner must first replace the prohibited step with a safe offline exporter command, then wire the tests into CI and run them on the exact PR head.

## 6. Test commands and execution evidence

| Command / check | Environment | Exit / status | Result / artifact |
|---|---|---|---|
| git clone --depth 1 https://github.com/berkah-pos/Berkahtigaputeri.git /tmp/Berkahtigaputeri | Shell in this session | **128** | Failed: DNS resolution for github.com unavailable; no local checkout. Sanitized output recorded above. |
| Read-only OOXML/ZIP workbook inspection | In-memory isolated tool context; input was the GitHub workbook object at blob cb8775f498487eece091c32b2774f45daa183afd | **Completed; process exit code N/A** | Seven ordered sheets; correct 1/3/100/140/108 counts; 352 unique keys; matching type/source labels; no parent/scope mismatch; zero formula cells. Sanitized artifact: 02_CONFIG_WORKBOOK_VALIDATION_SUMMARY.json. This is not the Python exporter. |
| python scripts/export_workbook_for_laravel.py --validate-only | Intended local/offline Python | **NOT RUN** | No local repository checkout; exporter validation output/hashes not claimed. |
| python scripts/test_canonical_workbook_contract.py | Intended local/offline Python | **NOT RUN** | Source exists but no Python test process was started. |
| python -m unittest discover -s scripts/tests -p test_*.py | Intended local/offline Python | **NOT RUN** | No local checkout. The workflow also ends by invoking a prohibited legacy script and was not dispatched. |
| Export twice to clean directories, then compare manifest bytes and SHA-256 | Intended local/offline Python | **NOT RUN** | No exporter-generated manifest or repeat-run SHA-256 artifact. |
| GitHub Actions run query for checkpoint SHA a66c73b8e67e715d61d5b2bfe35cf2e6ec07f3c7 | GitHub Actions API, read-only | **0 runs returned** | No exact-head workflow run ID, attempt, tested SHA or URL exists for that checkpoint. No workflow was manually dispatched. |
| python scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352 | Prohibited legacy path | **NOT RUN — deliberate** | Forbidden by the latest no-Supabase authority even in dry-run mode. |
| CI: Canonical Workbook Validation, run 38856048876, job 116827669252 | Historical GitHub Actions record | success in historical evidence | Tested SHA 6e31574ecc04ecae6a535fe409cf415ec18655cc; https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048876. Attempt number and raw logs were not independently retrieved here. This run predates the current exporter and is not exact-head evidence for this branch. |
| CI on audit/preprod-config-contract-2026-10-18 | GitHub Actions | **NOT RUN / NOT VERIFIED** | No workflow result is attributed to this branch. The changed paths do not match the current workbook workflow's listed source/test paths, and the workflow was not manually dispatched. |

## 7. Mismatches and deterministic artifact status

- **Directly VERIFIED from the actual workbook object:** exact sheet order; nonempty row counts 9/3/25/100/108/140/352 for README/TEMPLATES/GLOBAL/TENANTS_MASTER/DEVICES/SERVICES/APP_CONFIG_EXPORT; 352 unique canonical keys with category totals 1/3/100/140/108; expected template IDs; zero key duplicates/invalid key shapes; valid JSON-object parse for all 352 exported values; zero type-to-key-category mismatches; zero source-sheet-to-key-category mismatches; zero missing/extra source-linked keys; zero duplicate service pairs; zero orphan tenant parents; zero service/device template-parent mismatches; zero formula cells.
- The sanitized metadata artifact is 02_CONFIG_WORKBOOK_VALIDATION_SUMMARY.json. Workbook Git blob SHA is cb8775f498487eece091c32b2774f45daa183afd; this is the Git content fingerprint, not the new exporter SHA-256 manifest or keyset digest.
- **NOT GENERATED / NOT VERIFIED:** Python-exporter source SHA-256, keyset SHA-256 and manifest SHA-256; two-export byte equality; actual Python validator/test results. No data mismatch was found by structural inspection, but the strict exporter may still catch a schema/null/value issue when executed.
- Source-only application gap at base: app/Services/EffectiveConfigResolver.php and tests/Unit/Services/EffectiveConfigResolverTest.php were absent; matrix/documentation references do not establish runtime behavior.
- Automated discovery gap: the new synthetic test file is at scripts/test_canonical_workbook_contract.py, outside the configured scripts/tests discovery root. It was kept outside that path because changes under scripts/tests trigger the obsolete workflow that runs the prohibited sync wrapper. Once the workflow owner removes that call, route the test into the approved test-discovery path or add an explicit safe test command in the workflow.
- No workbook content was modified; no secret, config payload or customer data was copied into the report or summary artifact.

## 8. Dependencies, residual risks, and next steps

1. **Configuration/API contract owner:** implement and test the missing Laravel resolver and versioned configuration writer behavior; this workstream did not fabricate runtime integration.
2. **Workflow owner:** remove the prohibited sync script from the workbook-validation workflow and update CI to run only safe offline validators/tests. This workstream did not edit YAML.
3. **QA/evidence owner:** run exact-head tests on the eventual integrated candidate SHA; record workflow/run ID, attempt, checked-out SHA, commands, exits, sanitized logs and generated manifest/hash artifacts.
4. **Workbook owner:** review any rejection caused by real workbook headers, boolean encodings or formulas. Do not weaken strict checks without evidence and a contract decision.
5. Until these items are complete, keep the release gate **BLOCKED**. No PR merge, production migration, deployment or go-live approval is made by this report.

## 9. Recommendation

**BLOCKED** — corrective exporter/test source exists on the work branch, but workbook validation, deterministic export, tests, and Laravel resolver behavior have not been executed or proven on an exact integrated candidate SHA. BLOCKED is not PASS.
