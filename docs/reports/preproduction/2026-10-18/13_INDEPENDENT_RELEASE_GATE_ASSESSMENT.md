# 13 — Independent Release-Gate Assessment

**Status workstream:** **BLOCKED — no integrated release candidate; release recommendation is not GO.**  
**Assessment date:** 2026-10-19 (Asia/Jakarta)  
**Canonical repository:** [berkah-pos/Berkahtigaputeri](https://github.com/berkah-pos/Berkahtigaputeri)  
**Base branch / exact base SHA before work:** main / 371b7fdf0bf672b37ceb1023e647f114221bf797  
**Work branch:** audit/preprod-independent-gates-2026-10-18  
**Report path:** docs/reports/preproduction/2026-10-18/13_INDEPENDENT_RELEASE_GATE_ASSESSMENT.md  
**Integrated candidate SHA:** **NONE SELECTED**. No SHA was synthesized or selected on behalf of the owner.  
**Final report commit:** the PR's current head SHA metadata is the authoritative identifier. A commit cannot safely contain its own final SHA without generating another commit; see PR metadata.  
**Scope of repository changes:** this report only. No source implementation, permanent ADR, production environment, DNS, database, secret, deployment or branch-protection setting was changed.

## 1. Executive result

**Overall assessment: BLOCKED. Do not issue GO or deploy a release.** GitHub's live main ref resolved to 371b7fdf0bf672b37ceb1023e647f114221bf797; comparison against that SHA returned identical/no change. On this commit, the GitHub check-runs API returned two Dependabot checks only, no product CI checks; the commit status API returned zero status entries. The branch endpoint reported protected=false. Reading the required-status-check protection endpoint returned HTTP 403 to this integration, so branch ruleset/required-check details could not be independently verified there.

There are genuine passing *component* runs on several open, unmerged branches: workbook/config fixtures, synthetic PostgreSQL role/grant tests, Flutter local tests, and a disposable PostgreSQL restore drill. They do not constitute a single release proof: they were tested on different heads and sometimes different base branches/merge checkouts; the application runtime, authenticated API, UAT and operational gates remain incomplete. A clean install, a green narrow workflow, a test artifact, or a previous SHA's green baseline does not satisfy a required gate for an unselected candidate.

Three critical source-level blockers were verified on the current main tree:

1. .github/workflows/canonical-workbook-validate.yml still invokes scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352. The owner ADR prohibits running this mutation-capable legacy writer in any mode; it must be replaced by the local-only exporter/validator. The invocation was **not run during this assessment**.
2. config/database.php tenant connection falls back to central/global DB credentials when tenant-specific username/password values are absent. This undermines the intended per-tenant least-privilege boundary. An unmerged hardening branch removes that fallback and its isolated PostgreSQL grant tests pass, but the change is not integrated.
3. Flutter pos-app still depends on supabase_flutter, initializes Supabase, and calls its effective-configuration RPC. The current owner decision selects Laravel Central API and prohibits all Supabase product use. Local-only mode does not make this runtime path compliant.

A fourth high-impact blocker is explicit in ImportCanonicalWorkbook::importCentral(): newly imported tenants receive a trial subscription expiring after 14 days. The proposed RC1 billing-boundary PR is unmerged, and its exact-head CI failed during PHPUnit execution with a PHP syntax error. The release owner must decide the signed v1 scope before this behavior can be accepted or excluded.

The accepted configuration contract remains **GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE**, exactly **352** workbook entries: global=1, template=3, tenant=100, service=140, device=108. POS and Akuntansi must be resolved separately. This is an acceptance oracle, not evidence that the exact current-main workbook has been rerun successfully.

## 2. Authority, candidate selection and evidence rules

### 2.1 Authority applied

The current platform authority is docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md: Hostinger KVM2/Coolify target, PHP 8.4, Laravel 13, Filament 5, Sanctum, PostgreSQL 17, a central database plus one distinct database and restricted runtime role per tenant, and no Supabase product use. The 2026-10-16 ADR remains subordinate where it conflicts. DOC_00_CANONICAL_ARCHITECTURE_DECISION.md owns the five-layer/352-entry configuration contract; DOC_14 is subordinate implementation guidance; the master roadmap determines phase order and gates.

The accepted matrix docs/permanent/ACCEPTANCE_MATRIX_CI_EVIDENCE.md says CI enforcement is not yet enabled by that documentation and every row is required for release acceptance. Its exact-head contract requires run/attempt/workflow/job identity, source head, base and tested merge SHA, actual checkout SHA, stack and DB engine, commands/exit codes and required artifacts. Missing, skipped, stale or wrong-stack evidence cannot pass.

### 2.2 Required reading and additional source review

The mandatory document set was inspected through the canonical GitHub repository:

1. AGENTS.md
2. docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md
3. docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md
4. docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md
5. docs/permanent/DOC_00_MASTER_ROADMAP.md
6. docs/permanent/README.md
7. docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md
8. docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md
9. docs/HARDENING/README.md
10. Root README.md

The additional higher-priority 2026-10-17 owner ADR, the permanent acceptance matrix and JSON companion, the dated CI evidence snapshot, canonical workbook workflow and legacy writer/parser, composer.json, config/database.php, routes/api.php, Flutter manifest/entry/config service, workbook importer, and the relevant open PR reports/workflow files/logs were also inspected. docs/HARDENING/README.md describes an older repository/snapshot and is treated as historical, not proof of current runtime state.

### 2.3 Candidate identity and CI state

| Identity field | Assessment result |
|---|---|
| Canonical repository | berkah-pos/Berkahtigaputeri |
| Live main SHA | 371b7fdf0bf672b37ceb1023e647f114221bf797 |
| Main comparison to recorded base SHA | Identical/no change |
| Owner-selected integrated candidate SHA | **NONE** |
| Main exact-commit product CI | No product check run returned on main SHA; two Dependabot checks only; commit status list count=0 |
| Main branch protection observation | Branch metadata reported protected=false; required-status endpoint returned 403, so full settings could not be inspected |
| Required-check aggregator | Matrix/JSON describe a fail-closed policy, but the matrix says enforcement is not enabled |
| Local reruns in this assessment | **NOT RUN**: no local repository checkout/test runtime was available through this GitHub review path |
| Source changes made | Report only |
| Production, Supabase, DNS or database operation | **NOT RUN** |

No PR was merged by this assessment, and no exact integrated SHA has been declared.

## 3. Final acceptance matrix

The statuses below are for the release candidate, not for a narrow test described in a linked PR. Component evidence is identified separately in §5. A gate remains blocked until its acceptance oracle is satisfied on the same exact integrated candidate and required identity/artifacts are available.

| ID | Required gate | Assessment status | Evidence / determining blocker |
|---|---|---|---|
| RG-P0-01 | Owner approval of v1 scope, target (local pilot vs hosted SaaS), data continuity, pricing/trial, support and user-facing claims | **BLOCKED** | No owner-approved signed release scope or single integrated candidate evidence index found. Draft governance PR #80 proposes a matrix but is neither a signed scope nor approval. |
| RG-P0-02 | Workbook exact inventory, 352 keys, required templates, uniqueness and deterministic SHA-256/repeat-run manifest | **BLOCKED on candidate; component evidence exists** | PR #77 has exact-head workbook/config CI pass and SHA-256/repeatability evidence on its stacked candidate; PR #78 reports tests NOT RUN. Main has no exact-SHA product workbook CI. Main workflow still invokes the prohibited legacy command. |
| RG-P0-03 | Five-layer effective config; inheritance, override, version/hash/CAS and one-service isolation (POS versus Akuntansi) | **BLOCKED** | PR #77 reports 352/352 normalized scopes and 10 Laravel contract tests/794 assertions on another merge checkout; Flutter main still uses the prohibited legacy RPC. No integrated Laravel-to-Flutter runtime parity proof. |
| RG-P0-04 | PostgreSQL 17 tenant DB/role isolation; actual grants, central denial, CRUD/sequence denial, provisioning/retry and tampering negatives | **BLOCKED** | PR #76's disposable role/provisioner suite passed; PR #79's isolated grants probes passed on separate heads. Neither establishes the integrated runtime broker plus HTTP/Host/device/domain/subscription boundary. PR #76 explicitly says those HTTP checks were NOT RUN. |
| RG-P0-05 | Authentication, secrets and protected central/tenant API | **BLOCKED / source conflict** | Main routes/api.php only registers a static platform-health route. Login, config, membership/device authorization and sync acceptance are not evidenced. Main config/database.php reuses central/global credentials as tenant fallback. No app-level secrets/role isolation or negative HTTP acceptance on candidate. |
| RG-P0-06 | Clean central/tenant migrations, schema integrity and compatible rollback/forward recovery on PostgreSQL 17 | **PARTIAL component evidence; release BLOCKED** | Baseline run 39005405149 passed on older SHA aab154f87342f2a02a1319e1d370ce831dbef522; PR #77/#79 baseline runs are on their own heads. No integrated candidate or staging migration/rollback exercise. MariaDB checks do not satisfy PostgreSQL 17 acceptance. |
| RG-P0-07 | POS checkout correctness, durable offline SQLite atomicity, restart/retry and honest pending/server-ack state | **PARTIAL; release BLOCKED** | PR #81 POS CI passed on its unmerged head and emitted a debug-only AAB. It covers client/local behavior; it does not replace the Supabase runtime, prove durable server receipt/ACK, or satisfy cloud replay/conflict acceptance. |
| RG-P0-08 | Ledger/inventory invariants: balanced double-entry, immutable posted journal/reversals, audit history, locked periods/COA, stock/costing and rollback-on-failure | **NOT VERIFIED / BLOCKED** | No exact integrated candidate run demonstrates these invariants end-to-end. Local Flutter pass is not financial acceptance; accounting/inventory fixture and UAT runs are not proven on an integrated candidate. |
| RG-P0-09 | Billing/trial/entitlement scope and webhook safety | **FAILED source scope; BLOCKED for release** | Main importer creates a 14-day trial for each new tenant. PR #82 proposes removing implicit trial grants and defaulting new subscriptions inactive/unconfigured, but CI run 39181047719 failed on exact head 42c966b9596014e1ac0cc97073f19bb898b4fc02 with PHPUnit parse error, exit 255. Owner scope/provider decision and regression pass are absent. |
| RG-P0-10 | DNS, TLS, trusted host, email send/delivery, SPF/DKIM/DMARC and edge headers | **BLOCKED / NOT VERIFIED** | PR #86 reports public DNS/HTTP/TLS probes were blocked by resolver/network errors, not that DNS is broken. A mailbox listing alone does not prove delivery; no DNS or edge mutation was performed. PR has no CI run on its head. |
| RG-P0-11 | KVM2/Coolify staging deployment, immutable image identity, PostgreSQL readiness, migration and authenticated transaction smoke | **NOT RUN / BLOCKED** | PR #87 is source/runbook planning only; no SSH, Coolify deployment, published immutable image digest, isolated staging app, or authenticated host/API smoke. The /api/v1/platform-health route is static and does not test database readiness. |
| RG-P0-12 | Backup/restore across central, tenants, files and recovery material; single-tenant restore and integrity | **PARTIAL; release BLOCKED** | PR #88 current-head run 39232962623 passed synthetic disposable PostgreSQL 17 central+two-tenant dump/encrypt/restore and synthetic file/key checks. Off-host provider, PITR, actual vault recovery, Coolify state, and owner-approved measured RPO/RTO remain untested. No operational production/staging backup was accessed. |
| RG-P0-13 | Rollback/forward recovery rehearsal against exact image/schema state | **NOT RUN / BLOCKED** | Synthetic database restore is not an application deployment rollback. No staging rollback, forward-fix or after-rollback transaction test. |
| RG-P0-14 | Observability and actionable alerts (DB readiness, failures, auth/security, sync backlog, backup and resource alerts) | **NOT RUN / BLOCKED** | No integrated deployed runtime or delivered/test-acknowledged alerts. Static health response and presence of runbooks are not monitoring proof. |
| RG-P0-15 | UAT, compatibility and business sign-off on intended artifact/device/environment | **NOT RUN / BLOCKED** | PR #89 is documentation-only and states no isolated runtime, synthetic identities, browser automation, physical device or UAT evidence was available. No owner UAT signature. |
| RG-P0-16 | Dependency/security scanning and immutable artifact identity | **PARTIAL historic/component evidence; release BLOCKED** | Locked Composer/audit smoke passed at old main SHA aab154f... and in component branches, but no integrated candidate has matching scan, SBOM/image digest, signing certificate, full dependency inventory and required logs. PR #81 artifact is debug-only, not a publishable signed release. |
| RG-P0-17 | Performance/capacity, security regression and owner-approved threshold budget | **NOT RUN / BLOCKED** | No integrated KVM2/PostgreSQL load measurement, p95/p99, CPU/RSS/IO/connection/queue measurements, or owner-approved thresholds. The proposed hardware envelope is not capacity proof. |
| RG-P0-18 | Exact-SHA governance, required checks, artifact completeness and final owner decision | **BLOCKED** | Candidate SHA is null. Main has no product CI checks on exact SHA; matrix says enforcement is not enabled; main branch metadata reports protected=false; required-check endpoint was inaccessible. No all-gates aggregator or signed owner go/no-go exists. |

**Acceptance summary:** zero complete release gates can be declared passed for an integrated candidate because no such candidate SHA exists. Partial component runs remain useful, scoped evidence; this report does not erase or relabel their successes or failures.

## 4. Findings and P0 closure review

### F-001 — Prohibited legacy Supabase writer remains in the active workbook workflow

- **Severity / confidence:** **P0 / High** (policy/safety guardrail failure; not a claim that a live mutation occurred during this assessment).
- **Source:** .github/workflows/canonical-workbook-validate.yml, final workbook validation step (around lines 60–65). Current command is python scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352.
- **Source behavior:** scripts/sync_excel_to_supabase.py imports the legacy parser/writer; full-sync mode reads Supabase service-key environment values and its sync() path upserts tenant/service/device payloads and writes remote configuration through HTTP/RPC. Dry-run returns before that path, but the latest owner ADR prohibits executing this mutation-capable script in any mode. The assessment did not execute it.
- **Reproduction/evidence:** directly compare the current workflow command, the wrapper's main()/sync() implementation and the 2026-10-17 no-Supabase owner ADR. This is a static reproduction of the policy violation, not proof of a live network write.
- **Impact:** a legacy script that appears to be a validator remains in an active CI path. Future arguments/config changes could re-enable remote writes, and the workflow currently violates the no-Supabase boundary regardless.
- **Proposed fix:** use scripts/export_workbook_for_laravel.py --validate-only; remove the prohibited writer from workflow execution entirely. Preserve regression tests and emit deterministic SHA-256 manifest evidence.
- **Closure evidence found:** PR #75 proposes that workflow replacement. Run **39072409362**, attempt 1, workflow Canonical Workbook Validation, file .github/workflows/canonical-workbook-validate.yml, event pull_request, source head b4412b2b0498e43723b7c911ddcc0bb854e4edd5, base 371b7fdf0bf672b37ceb1023e647f114221bf797, conclusion success: [run](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39072409362). It tests the PR correction only.
- **Residual:** PR #75 is open/unmerged; its pass is not main/current-candidate evidence. **P0 remains open** until reviewed integration and exact integrated candidate CI confirms the prohibited invocation is absent.

### F-002 — Tenant connection can inherit central/global credentials

- **Severity / confidence:** **P0 / High**.
- **Source:** config/database.php, connections.tenant.username and connections.tenant.password (approximately lines 21–23 on current main).
- **Verified behavior:** tenant username falls back from TENANT_DB_USERNAME to CENTRAL_DB_USERNAME/DB_USERNAME; password similarly falls back to central/global password values. The default username chain can resolve to postgres. This is a source fact; no live DB connection was attempted.
- **Impact:** missing tenant runtime config can silently select a more privileged central/global principal instead of failing closed, conflicting with the separate per-tenant restricted-role architecture.
- **Proposed fix:** require an explicit tenant runtime identity/password with a fail-closed unconfigured default; prohibit central/global fallback and keep broker/migrator credentials out of web/ordinary queue env. Add negative config/startup tests, then test actual PostgreSQL roles against synthetic tenant A/B and central DBs.
- **Candidate remediation evidence:** PR #79 changes config/database.php, .env.example, docker-compose.yml and adds a disposable PG17 probe. Run **39131351376**, attempt 1, workflow Laravel PostgreSQL 17 Baseline, .github/workflows/laravel-pg17-baseline.yml, event pull_request, source head 6062df7b9a0fd94db17107d654f9b3e16622531b, conclusion success: [run](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39131351376). Artifact **12138445929**, pg17-tenant-isolation-7de42ef09e53200ed8e0e57036d3956c6d59a82e; logs demonstrate expected database/schema/table/sequence/function and role-operation denials on PostgreSQL 17.11.
- **Residual:** low-level branch-local isolation harness does not prove integrated app provisioning/HTTP request boundaries. PR #79 remains open/unmerged. **P0 remains open** until explicit tenant configuration and the broker/request lifecycle are integrated and exact-candidate adversarial tests pass.

### F-003 — Flutter has a prohibited active Supabase runtime path

- **Severity / confidence:** **P0 / High**.
- **Source:** pos-app/pubspec.yaml declares supabase_flutter; pos-app/lib/main.dart imports and calls Supabase.initialize when Supabase build variables are set; pos-app/lib/core/config/config_service.dart retains SupabaseClient, session checks and get_effective_config RPC.
- **Impact:** cloud login/configuration still relies on a product forbidden by the current owner ADR; no candidate can claim the selected Laravel-only platform boundary or fully integrated SaaS operation.
- **Proposed fix:** replace the SDK, environment defines, initialization and RPC with a reviewed authenticated Laravel Central API client; preserve local-first SQLite/outbox semantics; add auth/config/token/offline/API parity tests and scans proving no active Supabase path remains.
- **Closure evidence found:** PR #81 scope is checkout/offline behavior, not removal of the Supabase runtime. Its CI pass does not close this issue.
- **Residual:** no integrated Flutter-to-Laravel API path or tested cloud sync exists on main. **P0 remains open**; no Supabase access was performed during this assessment.

### F-004 — Importer assigns a 14-day trial entitlement to every new tenant

- **Severity / confidence:** **P0 / High** until v1 scope and entitlement rules are owner-approved.
- **Source:** app/Console/Commands/ImportCanonicalWorkbook.php::importCentral(), the if ($isNew) branch creates a subscription with status trial and expiry now()->addDays(14).
- **Reproduction/evidence:** source path is executed as part of config:import-workbook for a genuinely new tenant. This command was **not run** because it writes database state. No production tenant was created during this assessment.
- **Impact:** provisioning/import implicitly grants product entitlement and activates trial semantics without an owner decision, provider lifecycle or demonstrated enforcement policy.
- **Proposed fix:** unless owner deliberately includes trial/subscription behavior in RC1, do not create active/trial subscriptions from workbook import. Default to unconfigured/inactive, exclude billing/webhooks from release, and test that importer does not grant entitlement.
- **Closure evidence found:** PR #82 proposes that correction and an inactive/unconfigured default. Exact-head CI **39181047719**, attempt 1, workflow Laravel PostgreSQL 17 Baseline, file .github/workflows/laravel-pg17-baseline.yml, event pull_request, source head 42c966b9596014e1ac0cc97073f19bb898b4fc02, conclusion failure: [run](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39181047719). PHPUnit reported syntax error, unexpected token "\\", expecting "{", and php artisan test exited **255**.
- **Residual:** PR #82 is open/unmerged and its exact-head CI failed. Owner scope confirmation and passing test/migration evidence are missing. **P0 remains open**.

### F-005 — Platform health endpoint reports success without testing database readiness

- **Severity / confidence:** **P1 / High**.
- **Source:** routes/api.php::api.v1.platform-health returns static JSON status=ok and database_target=PostgreSQL 17; it does not query PostgreSQL. It is the only API route visible in that file on main.
- **Impact:** a monitor may report success while the database is unreachable; this route is liveness metadata, not readiness or authenticated API proof.
- **Fix:** separate liveness and readiness; readiness must safely check DB connectivity without disclosing internals and be exercised against healthy/unavailable disposable PostgreSQL. Add route/auth tests for product APIs.
- **Residual:** no deployment/runtime smoke exists on a selected candidate.

### F-006 — Candidate evidence is distributed across non-integrated branches; release evidence cannot be aggregated

- **Severity / confidence:** **P0 / High**.
- **Verified state:** PRs #75, #76, #77, #78, #79, #80, #81, #82, #86, #87, #88 and #89 were open in the observed metadata. #77 is deliberately stacked on base SHA 6deafd0b6811caab68e22edcf224185505a19aa5, not main; tests on that merge checkout cannot be combined with the other PR results as one candidate.
- **Impact:** no immutable integrated SHA binds code, workflows, schema, resolver, tenant broker, Android artifact, UAT and recovery proof together. CI enforcement and required-check aggregation are not active/verified.
- **Fix:** release coordinator sequences owner-reviewed PRs through normal reviewed integration; then select one exact candidate SHA. Rerun every required check against that candidate, verify checkout/merge identity, require all artifacts, and issue owner decision only after evidence review.
- **Residual:** no candidate SHA exists in this assessment, so the result must remain **BLOCKED**, not an aggregate PASS.

## 5. CI evidence ledger — run IDs, attempts, tested identities and limits

Run metadata was fetched from the GitHub Actions API; job results and relevant raw logs were inspected where noted. “Success” means success for the described branch/workflow scope only. Workflow source head and synthetic merge checkout are distinguished where exposed.

| Run / attempt | Workflow file; event | Source head / base SHA | Result | Evidence and acceptance limit |
|---|---|---|---|---|
| [39005405149 / attempt 1](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) | .github/workflows/laravel-pg17-baseline.yml; push | Tested SHA aab154f87342f2a02a1319e1d370ce831dbef522 (old main at that time; not current) | **success** | Locked install/audit, boot/routes, disposable PG17 central/tenant migration smoke and image smoke. Historical baseline only. |
| [39072409362 / attempt 1](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39072409362) | .github/workflows/canonical-workbook-validate.yml; pull_request PR #75 | Head b4412b2b0498e43723b7c911ddcc0bb854e4edd5; base 371b7fdf0bf672b37ceb1023e647f114221bf797 | **success** | Local-only workbook validator replacement on PR #75; not integrated. |
| [39085544490 / attempt 1](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39085544490) | .github/workflows/pg17-tenant-boundary.yml; pull_request PR #76 | Head a95c8a3ffdcc3d9f97932d89df0674e9c4faea6c; base 371b7fdf0bf672b37ceb1023e647f114221bf797; artifacts reference synthetic merge c09b068fc619c646c0aeec961523f70be0db33e5 | **success** | PostgreSQL 17.11 role/grant/provisioner negative tests passed; artifact 12120481782. HTTP tenant/domain/subscription/device/Host/X-Forwarded-Host checks were NOT RUN. |
| [39098883108 / attempt 1](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39098883108) | .github/workflows/canonical-workbook-validate.yml; pull_request PR #77 | Head a4736d3cac3d0568960e847bd2609ecb62bee89f; base 6deafd0b6811caab68e22edcf224185505a19aa5 | **success** | Workbook inventory validation on a stacked branch, not main/current candidate. |
| [39098883096 / attempt 1](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39098883096) | .github/workflows/configuration-contract-pg17.yml; pull_request PR #77 | Head a4736d3cac3d0568960e847bd2609ecb62bee89f; base 6deafd0b6811caab68e22edcf224185505a19aa5; artifact identifies checkout 815e161c8092c04691701adb559de051040c8089 | **success** | Log: 352/352 normalized scopes, 10 tests/794 assertions, PG17.11 CAS race with one winner/one audit row. Artifact 12125314913; ZIP SHA-256 466ad2e2d982bebab12acab50d822dbd3b59d12f5be0afe3238f325b18f1d878. Config/manifest scope only. |
| [39098883104 / attempt 1](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39098883104) | .github/workflows/laravel-pg17-baseline.yml; pull_request PR #77 | Head a4736d3cac3d0568960e847bd2609ecb62bee89f; base 6deafd0b6811caab68e22edcf224185505a19aa5 | **success** | Locked PHP/Laravel/PG17 baseline on same stacked candidate family; not complete release acceptance. |
| [39131351376 / attempt 1](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39131351376) | .github/workflows/laravel-pg17-baseline.yml; pull_request PR #79 | Head 6062df7b9a0fd94db17107d654f9b3e16622531b; base 371b7fdf0bf672b37ceb1023e647f114221bf797; artifact identifies synthetic merge 7de42ef09e53200ed8e0e57036d3956c6d59a82e | **success** | Low-level PG17 role/grant isolation probes; artifact 12138445929. Does not prove full application provisioning and host/auth/API boundary; unmerged. |
| [39172242849 / attempt 1](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39172242849) | .github/workflows/pos-app-ci.yml; pull_request PR #81 | Head 77da4ae145b88ff4cd152e7f518516cc23ad7678; base 371b7fdf0bf672b37ceb1023e647f114221bf797 | **success** | Flutter analyzer/tests and debug App Bundle build passed. Artifact 12153067341; upload ZIP SHA-256 42035a681f3428ccadcbf5f5ead8619ab7cab9f07c1f0eac3b9dac75cc6a7583. Debug AAB only; not store-signed or server sync acceptance. |
| [39181047719 / attempt 1](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39181047719) | .github/workflows/laravel-pg17-baseline.yml; pull_request PR #82 | Head 42c966b9596014e1ac0cc97073f19bb898b4fc02; base 371b7fdf0bf672b37ceb1023e647f114221bf797 | **failure** | Job 117833737883; php artisan test/PHPUnit reported syntax error, unexpected token "\\", expecting "{", exit 255. Billing correction has no exact-head test pass. |
| [39232962623 / attempt 1](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39232962623) | .github/workflows/backup-restore-disposable.yml; pull_request PR #88 | Head 7a9b3a9563e34238a6518734363932fa685a6d32; base 371b7fdf0bf672b37ceb1023e647f114221bf797 | **success** | bash scripts/backup_restore/disposable_pg17_drill.sh; synthetic central+tenant A/B dump/encrypt/restore and synthetic file/key checks passed. Artifact 12178402031; ZIP SHA-256 29bcbde7bde9faee09227e96651d84f199cc80bf73b851054ea97e7ee7f155df. No off-host/PITR/vault/Coolify recovery. |

### Evidence quality and limitations

- GitHub run metadata identifies source PR head and event; logs/artifact names identify synthetic merge checkout where exposed. PR #77 uses a base other than main. Those passes must not be aggregated with #79/#81/#88 as an integrated candidate.
- PR #76 reports HTTP/Host/domain/auth tests as NOT RUN in its successful job. A green workflow does not override this gap.
- PR #88 is a real disposable restore pass for its scoped synthetic topology. Its report leaves off-host backup, PITR, real KMS/vault recovery, Coolify state, and owner-approved/measured RPO/RTO unverified.
- Run 39005405149 is historical for SHA aab154f..., not a current-main check. Run 39181047719 is an actual exact-head failure and must remain in the evidence record.
- Artifacts were referenced by GitHub IDs and recorded digests where available; they were not downloaded/executed locally. No tests were rerun locally; no workflow was dispatched, and no test credentials were issued.
- On the main SHA, no product check run was returned by the commit-check API. Open PR evidence belongs to each recorded PR head/base and is not evidence of required checks for main.

## 6. Unmerged branches, dependencies and ownership overlaps

| PR | Current observed head / base | Scoped component and disposition | Dependency / overlap to resolve |
|---|---|---|---|
| [#75](https://github.com/berkah-pos/Berkahtigaputeri/pull/75) | b4412b2b0498e43723b7c911ddcc0bb854e4edd5 / main base 371b7fdf0bf672b37ceb1023e647f114221bf797 | Local-only workflow replacement; own workflow passes | P0 dependency for workbook CI; integrate/review and rerun exact candidate. |
| [#76](https://github.com/berkah-pos/Berkahtigaputeri/pull/76) | a95c8a3ffdcc3d9f97932d89df0674e9c4faea6c / main | PostgreSQL broker and actual PG17 grants/provisioning tests; isolated suite passes | Reconcile with #79 tenant config/runtime hardening and actual Laravel tenant request/auth lifecycle. No HTTP/host/worker acceptance. |
| [#77](https://github.com/berkah-pos/Berkahtigaputeri/pull/77) | a4736d3cac3d0568960e847bd2609ecb62bee89f / stacked base 6deafd0b6811caab68e22edcf224185505a19aa5 | Deterministic manifest SHA-256 and Laravel PG17 config contract | Tests depend on base other than main and importer/config files overlap #82. Align safe local workflow (#75), review the base, then test the integrated SHA. |
| [#78](https://github.com/berkah-pos/Berkahtigaputeri/pull/78) | 6163ae2c848e8f9452e35cf5777bf8e07f981b8b / main | Workbook validator hardening report | PR body says workbook/runtime tests NOT RUN because clone/DNS unavailable. Reconcile with #77/#75; do not claim it passed. |
| [#79](https://github.com/berkah-pos/Berkahtigaputeri/pull/79) | 6062df7b9a0fd94db17107d654f9b3e16622531b / main | Removes tenant credential fallback and adds low-level PG17 probes | Review with #76's broker and platform owner. Probe is not proof of tenant request/membership/worker controls. |
| [#80](https://github.com/berkah-pos/Berkahtigaputeri/pull/80) | b166faf6b60e16206d3b87b9769cbe7698526c27 / main | Draft release scope + matrix | Proposed criteria only; not signed scope, required-check enforcement or owner go/no-go. Keep one reconciled matrix authority. |
| [#81](https://github.com/berkah-pos/Berkahtigaputeri/pull/81) | 77da4ae145b88ff4cd152e7f518516cc23ad7678 / main | POS local checkout/outbox UI and tests; CI passes | Not cloud sync and does not remove Supabase SDK. Must be integrated/tested with ledger/inventory invariants and the API/outbox ACK contract. |
| [#82](https://github.com/berkah-pos/Berkahtigaputeri/pull/82) | 42c966b9596014e1ac0cc97073f19bb898b4fc02 / main | Proposed trial/billing scope correction | Exact-head CI fails. ImportCanonicalWorkbook.php overlaps #77; route to one importer owner, fix syntax failure and rerun migration/importer regressions. |
| [#86](https://github.com/berkah-pos/Berkahtigaputeri/pull/86) | 5f4d20293ea495746e15d2c6f939afcbcaa80115 / main | DNS/TLS/email/edge read-only report; no CI run | Public DNS/TLS/MX/SPF/DKIM/DMARC and delivery remain BLOCKED, not FAILED. Route to SRE/mail owner; do not mutate DNS here. |
| [#87](https://github.com/berkah-pos/Berkahtigaputeri/pull/87) | 40e172c5213ed044501b714bfe66521d0af7c521 / main | KVM2/Coolify operational runbook/audit; no CI run | Planning only; host access/deployment/image identity/readiness/resources/rollback are NOT RUN. |
| [#88](https://github.com/berkah-pos/Berkahtigaputeri/pull/88) | 7a9b3a9563e34238a6518734363932fa685a6d32 / main | Synthetic PostgreSQL backup/restore; current-head CI passes | Separate from off-host/PITR/vault/host recovery and deployment rollback; retain only scoped evidence. |
| [#89](https://github.com/berkah-pos/Berkahtigaputeri/pull/89) | 4ce56c763710d457ba3740904b444e9a751076b5 / main | UAT/compatibility matrix; no CI run | No runtime, browser/device or business sign-off evidence; execute after final candidate and isolated target exist. |

This is the known workstream PR set observed during assessment, not a substitute for re-querying live PR status before selecting a future candidate. Any new/moved head makes older head-specific evidence stale for that head.

## 7. Test/command register for this assessment

| Command / check | Target/environment | Result | Artifact/log | Classification |
|---|---|---|---|---|
| Fetch live main ref and compare against 371b7fdf0bf672b37ceb1023e647f114221bf797 | GitHub repository metadata | Identical/no change | GitHub ref/compare response; no local artifact | **VERIFIED** for metadata |
| Fetch main commit check-runs + status | Main SHA | Two Dependabot checks only; status list total=0; no product workflow check listed | GitHub API response | **VERIFIED** for observed API response |
| Inspect config/ci/required-check-matrix.json and docs/permanent/ACCEPTANCE_MATRIX_CI_EVIDENCE.md | Source review | Matrix says fail-closed specification is not wired into required CI enforcement | Repository source | **VERIFIED** specification state, not release gate pass |
| Inspect canonical workbook workflow/writer, config/database.php, pos-app manifest/entry/config service, importer and routes/api.php | GitHub source review | Source findings recorded; no commands run against them | Source references in §4 | **VERIFIED** source findings, no runtime claim |
| python -m unittest discover -s scripts/tests -p 'test_*.py' | Local workbook tests | **NOT RUN** in this assessment | None | NOT RUN; don't confuse with remote PR CI |
| python scripts/export_workbook_for_laravel.py --validate-only against current-main checkout | Current main | **NOT RUN** locally | None | NOT RUN; current main workflow still calls legacy writer |
| python scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352 | Prohibited legacy command | **NOT RUN** by this assessment | None | Intentionally not run under owner ADR |
| bash scripts/security/test-pg17-tenant-boundary.sh (workflow tees output to pg17-tenant-security-transcript.txt) | PR #76 disposable PG17.11 | Exit 0; workflow success on PR head a95c8a3... | Run 39085544490, artifact 12120481782 | VERIFIED scoped component evidence; not release pass |
| php artisan test --filter=ConfigurationContractTest --display-warnings --fail-on-warning | PR #77 disposable PG17.11, synthetic merge checkout | Exit 0; 10 tests/794 assertions; 352/352 scopes, API fixture and CAS race passed | Run 39098883096, artifact 12125314913, ZIP digest in §5 | VERIFIED stacked component evidence |
| flutter analyze --no-pub; flutter test --no-pub; flutter build appbundle --debug --no-pub | PR #81 hosted runner | Relevant workflow steps passed; debug AAB emitted | Run 39172242849, artifact 12153067341 | VERIFIED client/debug scope only |
| php artisan test | PR #82 PG17 baseline workflow at head 42c966b... | **Exit 255**, PHPUnit syntax error unexpected token backslash, expecting opening brace | Run 39181047719, job 117833737883 | **FAILED** exact PR head |
| bash -n scripts/backup_restore/disposable_pg17_drill.sh; python3 -m py_compile scripts/backup_restore/validate_database_coverage.py scripts/backup_restore/test_validate_database_coverage.py; python3 -m unittest discover -s scripts/backup_restore -p 'test_*.py' -v; bash scripts/backup_restore/disposable_pg17_drill.sh | PR #88 GitHub-hosted runner and synthetic PG17 containers | Workflow success; synthetic central/A/B and file/key integrity restored | Run 39232962623, attempt 1; artifact 12178402031, ZIP digest in §5 | VERIFIED scripted recovery scope; off-host/PITR/vault/real secrets NOT RUN |
| Local clone, full exact-candidate test suite, end-to-end API/client, UAT and staging deploy | No local checkout/approved disposable target in this review | **NOT RUN** | None | NOT RUN / BLOCKED; no output fabricated |

## 8. Stale/missing evidence ledger

1. **No integrated candidate SHA selected.** This is the decisive blocker; no source SHA supports aggregation of all component evidence.
2. **Historical baseline:** run 39005405149 tested aab154f87342f2a02a1319e1d370ce831dbef522, not current main 371b7fdf...
3. **Stacked config PR:** #77 runs used a base 6deafd0b6811caab68e22edcf224185505a19aa5, not main; its results cannot be inherited by main.
4. **Different candidate heads:** PG17 broker (#76), fallback isolation (#79), Flutter POS (#81), billing (#82), and backup/restore (#88) have distinct PR heads and are not one tested candidate.
5. **Missing exact-main product checks:** check-runs API had Dependabot only and the commit status API returned zero status entries.
6. **Workbook SHA-256 proof:** candidate-specific SHA-256 manifest evidence exists in #77, but no matching integrated candidate. Main's workflow conflicts with no-Supabase authority.
7. **Tenant boundary:** low-level PostgreSQL tests exist on PR branches; full broker, HTTP host/auth/domain/device/subscription, long-running worker and operational secret separation are not one accepted result.
8. **POS/sync/ledger:** Flutter CI is branch-local/debug-only; authenticated API sync, durable receipt/idempotency and accounting/inventory invariants are not proven end-to-end on a candidate.
9. **Billing:** #82 current head has a concrete CI failure; trial-default correction is not closed.
10. **DNS/email/TLS and KVM2/Coolify:** PR #86/#87 reports are not run-backed acceptance. Resolver/network failure is BLOCKED, not proof of DNS failure.
11. **Recovery:** #88 current-head synthetic restore is a real scoped pass; off-host encrypted backup read-back, PITR, KMS/vault, Coolify/host recovery and approved/measured RPO/RTO remain missing.
12. **UAT, observability, performance and security scan aggregation:** no candidate-bound evidence proving these gates passed; no approved capacity thresholds, UAT sign-off or acknowledged alert.
13. **Required checks:** conventional branch metadata reports protected=false; direct protection read was inaccessible. The matrix itself says enforcement is not enabled. Owner/repo admin must verify required-check policy before release.

## 9. Dependencies, residual risks and next steps

The release coordinator should route cross-workstream changes instead of silently resolving ownership overlaps:

1. **CI/workbook owner:** review and integrate the local-only workflow replacement from PR #75; rerun that workflow on the exact next candidate. Never execute the prohibited legacy script.
2. **PostgreSQL security + Laravel platform owner:** reconcile PR #76 broker design with PR #79's no-fallback runtime config; implement/review the actual tenant lifecycle and prove PG17 roles plus HTTP/host/domain/device/subscription/worker isolation with synthetic fixtures.
3. **Configuration/API + Flutter owner:** reconcile PR #77's stacked base and PR #78 workbook changes; designate one owner for importer/resolver/manifest files. Replace Flutter's active Supabase SDK/RPC with authenticated Laravel API and prove POS/Accounting service isolation plus local SQLite/outbox behavior.
4. **Billing + importer owner and business owner:** resolve overlapping importer changes in PR #77/#82; decide whether subscriptions/trials are in v1. Fix PR #82's exact-head PHP failure and rerun importer/migration regressions on an integrated candidate.
5. **SRE/security:** keep PR #88 as scoped restore evidence; separately prove off-host, PITR, vault/key recovery, immutable candidate deploy, PostgreSQL readiness, rollout/rollback, alerts and approved capacity on disposable/staging platform. Close DNS/TLS/email unknowns with trustworthy probes and delivery tests under separate authorization.
6. **UAT/business owner:** after an immutable candidate and isolated environment exist, execute scenario matrix against the release artifact/representative device and sign the included local/cloud scope.
7. **Release governance/repo admin:** select owner-approved exact candidate SHA; verify check names/IDs, source/base/merge/checkout SHA, attempts, workflow revisions, security/artifact manifests and all required evidence. Enforce a reviewed fail-closed required-check set and protect the release branch. This assessment does not merge, tag, deploy or give final approval.

Residual risks include cross-tenant access while tenant credentials may fall back to central credentials, unauthorized entitlement/trial defaults, unsupported claims about cloud sync, false confidence from static health response, unrecoverable backups without off-host/PITR, and inability to roll back without immutable image/schema identity. No claim is made that exploitation or a production data mutation occurred; risks follow from verified source and missing/failed gates.

## 10. Recommendation

**Recommendation: BLOCKED — NO-GO until a single integrated candidate is selected and every applicable P0 gate is verified against its exact SHA.** This is an evidence-based recommendation, not owner release approval.

No candidate SHA is selected, no all-gates status set exists, and multiple P0 findings remain open. Successful component runs for workbook/config, isolated PG17 tests, Flutter debug build and synthetic backup restore are preserved as scoped proof; they cannot certify a product revision that has not been integrated and tested. The owner/release authority retains the final GO/NO-GO decision.

**Assessment safety boundary:** no merge, tag, release, deployment, production database access/mutation, DNS mutation, secret rotation, Supabase connection or legacy sync command execution was performed.
