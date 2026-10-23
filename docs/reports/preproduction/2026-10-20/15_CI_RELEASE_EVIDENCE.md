# Prompt 15 — CI, Dependency Security, Android Build & Release Compliance

**Repository:** berkah-pos/Berkahtigaputeri  
**Requested destination:** docs/reports/preproduction/2026-10-20/15_CI_RELEASE_EVIDENCE.md  
**Audit date:** 2026-10-21 (Asia/Jakarta)  
**Main SHA inspected:** 371b7fdf0bf672b37ceb1023e647f114221bf797  
**Disposition:** NO-GO for publisher-signed / Play Store release. CI design PARTIAL; current-head acceptance NOT VERIFIED.

## 1. Executive decision

Do not approve a production or Play Store release on this evidence. The exact main SHA has no relevant application CI record. The most recent inspected AAB workflow run built and uploaded a debug-signed test AAB; publisher-signed build and upload steps were skipped. The Flutter app still declares and documents the legacy Supabase runtime, contrary to the latest owner ADR prohibiting Supabase products and project access. The release workflow correctly blocks publisher-signed builds while the source markers remain.

The workbook validation workflow invokes the prohibited mutation-capable legacy script, scripts/sync_excel_to_supabase.py, with --dry-run. Current AGENTS.md and the 2026-10-17 owner ADR prohibit executing that script in every mode. A successful historical run does not waive this policy conflict.

The Android source manifest's declared permission set matches the documented allowlist. This is source evidence only: the effective merged manifest inside a current candidate AAB has not been extracted. No publisher-signed current-candidate artifact, accepted certificate fingerprint comparison, update-install test or Play Console acceptance is evidenced.

## 2. Authority, scope and method

The required repository reading order was followed: root AGENTS.md; DOC_00_CANONICAL_ARCHITECTURE_DECISION.md; ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md; the subordinate 2026-10-16 ADR; DOC_14; the master roadmap; permanent README; DOC_12; DOC_13; legacy DOC_01; Cursor rules; Copilot/Muse instructions; then the relevant workflows, app/build files and evidence.

Rules applied:
- Target stack is PHP 8.4, Laravel 13, Filament 5, Sanctum and private PostgreSQL 17 on KVM2/Coolify.
- All Supabase product use and project access are prohibited, including read-only. The legacy sync script is prohibited and must not be executed.
- Workflows should use GitHub-hosted ubuntu-24.04, actions pinned to full commit SHAs and minimum token permissions.
- A check passes only with real, exact-SHA workflow evidence. Missing evidence remains NOT RUN / NOT VERIFIED.
- Prompt 15 is limited to CI, dependency and release evidence. No application/business logic changes, secret access, workflow dispatch, signing, upload, publishing or deployment were performed.

Methods: read the active files through GitHub source, query exact main SHA and associated Actions runs/checks, inspect workflow run jobs/steps and artifact metadata. This was a read-only source/metadata audit.

## 3. Active workflow and trigger coverage

Five active workflow files were listed under .github/workflows at the reviewed main head.

| Workflow | Triggers and configured checks | Release-evidence boundary |
|---|---|---|
| .github/workflows/berkah-pos-aab.yml | Manual dispatch; push to main when pos-app/** or the workflow changes. Hosted Ubuntu 24.04; Flutter package resolution/analyze/tests; signing selection; AAB build and artifact upload. No pull_request trigger. | Test-only debug signing is an explicitly named path. No publisher release is accepted unless the required secrets exist and the legacy Supabase scan passes. Current main SHA has no matching run. |
| .github/workflows/pos-app-ci.yml | Pull request, push on any branch with selected pos-app/**, legacy supabase/**, static script and legacy doc paths; workflow_dispatch. Flutter analyze/test and debug AAB compile. | Fork-origin PRs are skipped by job-level if. Static “tenant isolation” step inspects legacy Supabase SQL and does not test PostgreSQL grants. Current SHA has no matching run. |
| .github/workflows/berkah-pos-trial-ci.yml | Pull request and push for berkah-pos-trial/**; workflow_dispatch. Separate app dependency resolution, validation, analyze/tests, debug APK and testing-only AAB/APK. | This is a separate trial application. Its artifact/results cannot be substituted for canonical pos-app results. |
| .github/workflows/canonical-workbook-validate.yml | Pull request/push path filters for workbook/scripts/docs; workflow_dispatch. Python tests followed by the legacy workbook script. | Policy conflict: invokes scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352 at line 68. Must not be treated as an approved validation workflow under current owner instructions. |
| .github/workflows/laravel-pg17-baseline.yml | Pull request/push path filters for Laravel, migrations, Composer, Docker/Compose and development docs; workflow_dispatch. Locked Composer/security checks, app smoke, disposable PG17 migrations and production-image HTTP smoke. | Good starter backend baseline design; not complete product API, real tenant-role isolation, Flutter migration or production-readiness proof. Current main SHA has no matching run. |

Common source positives: all five files set permissions to contents: read, use ubuntu-24.04 and reference GitHub Actions by complete commit SHA. The Laravel workflow keeps Composer advisory blocking enabled and tests fresh central and tenant migrations against disposable PostgreSQL 17. Those source controls do not close other gaps.

## 4. Exact-SHA CI and artifact evidence

### Current main

Current main is 371b7fdf0bf672b37ceb1023e647f114221bf797. An exact-SHA workflow-run query found only these two completed dynamic Dependabot-related runs:
- Run 39184121515 — success: https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39184121515
- Run 39186055413 — success: https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39186055413

The combined commit status was pending and no ordinary application status checks were returned. These dynamic runs do not prove Flutter, workbook, Laravel PG17 or AAB checks passed on this SHA. Current-head application CI acceptance is NOT VERIFIED.

### Prior candidate runs, kept separate

| SHA / run | CI-OBSERVED result | Boundary |
|---|---|---|
| ef167189fa7fcde9e761e50128c0fcf7c44c2285 — Laravel baseline run 39029945646 | Success. Its job completed manifest/lock/runtime assertions, Composer strict validation/platform/security checks, Laravel boot/routes/tests, fresh disposable PG17 central and tenant migrations, table smoke and production-image HTTP smoke. https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39029945646 | Starter PHP 8.4/Laravel 13/Filament 5/Sanctum/tenancy-candidate baseline on a prior SHA only. Does not prove the complete product API, tenant grant isolation, Flutter compliance, release signing, staging or production. |
| Same SHA ef167189... — workbook run 39029945653 | Success for the configured test/dry-run steps. https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39029945653 | The workflow invoked the prohibited legacy script. Historical success does not make it compliant or current-head evidence. |
| f093cacbbef018878098624a9d9c39ade503d779 — AAB run 39006250274 | Success for Flutter package resolution, analysis, tests, debug-signed AAB build, artifact upload and temporary-signing cleanup. https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39006250274 | Publisher build and upload steps were skipped. Uploaded artifact was explicitly berkah-pos-unified-test-aab-debug-signed, artifact ID 12091466299, SHA-256 archive digest 7d6438a76b34b252a188933b7379458905d1d70744d841104f4414e457efcbcd. This is not a publisher certificate fingerprint and is not Play submission evidence. |
| 3b98460bf95f435dda005a038a911dfc5d766e5c — canonical POS CI run 39004715942 | Historical canonical POS workflow success. https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39004715942 | Earlier source revision only; not current-head proof or publisher signing evidence. |
| aab154f87342f2a02a1319e1d370ce831dbef522 — Laravel baseline run 39005405149 | Starter baseline smoke pass recorded in docs/reports/LARAVEL_PG17_BASELINE_ACCEPTANCE_2026-10-17.md. https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149 | Historical initial scaffold evidence, not current-head or production acceptance. |

Do not combine these different SHAs into an aggregate GREEN result.

## 5. Android build and release source evidence

Source-verified configuration:
- Application ID and namespace: id.co.berkahtigaputeri.berkahpos.
- versionName 1.1.0, versionCode 2, minSdk 24, targetSdk 35. pubspec.yaml uses version 1.1.0+2.
- Source AndroidManifest.xml declares INTERNET, ACCESS_NETWORK_STATE, CAMERA, BLUETOOTH, BLUETOOTH_CONNECT and BLUETOOTH_SCAN (neverForLocation). It sets allowBackup=false.
- Release workflow runs Java 17; discovers Android SDK tools; installs Android compile platforms/build tools; obtains official Flutter stable release metadata and verifies the downloaded archive SHA-256.
- Publisher-signing secrets are scoped to signing steps. If any required signing secret is missing, the workflow selects a debug-signed, testing-only artifact name. Temporary signing files are removed by an if: always() cleanup step.
- The publisher path scans app source for legacy Supabase markers and fails closed if those remain.

Not verified:
- A publisher-signed AAB from the current candidate.
- The accepted previous upload certificate SHA-256 and any match to a candidate artifact.
- Enforced certificate mismatch rejection; workflow output currently prints/reminds a human to compare rather than checking a pinned owner-approved fingerprint.
- Extracted package/version/target/merged-permission metadata from the exact release AAB.
- Installation/update compatibility on the intended Android device.
- Play Console validation or production use.

## 6. Findings register

### F15-01 — CI invokes prohibited legacy Supabase writer
**Severity:** P1. **Confidence:** High.  
**Evidence:** canonical-workbook-validate.yml line 68 executes scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352. AGENTS.md and the current owner ADR prohibit execution in any mode.  
**Risk:** violates the current platform boundary and could normalize an active mutation-capable path as approved CI. “Dry-run” does not waive the prohibition.  
**Acceptance:** a separate offline-only validator must prove required sheets, unique keys, 352 total entries and type counts (1 global, 3 templates, 100 tenants, 140 service rows, 108 devices) plus deterministic manifest/hash, with no Supabase SDK, URL, credential, RPC or network path. Do not delete historical script evidence as part of this audit.  
**Handoff:** Prompt 01 workbook/importer and Prompt 15 CI owner.

### F15-02 — Flutter dependency/runtime violates no-Supabase decision
**Severity:** P1. **Confidence:** High.  
**Evidence:** pos-app/pubspec.yaml line 16 declares supabase_flutter: ^2.6.3. pos-app/README.md documents legacy paths in lib/main.dart and lib/core/config/config_service.dart. The AAB workflow blocks publisher build while such markers remain.  
**Risk:** current client is not compliant, and no tested Laravel replacement for authentication/configuration/sync has been evidenced in this audit. Removing the package without a replacement risks breaking required app flows.  
**Acceptance:** replace legacy path alongside tested Laravel APIs, then run dependency resolution, analysis, full tests, API positive/negative auth tests and source/dependency/built-artifact scanning. Never add Supabase credentials to clear the gate.  
**Handoff:** Prompts 02/03, 06, 11 and 15.

### F15-03 — No relevant CI recorded on exact current main SHA
**Severity:** P1. **Confidence:** High.  
**Evidence:** exact-SHA query for 371b7fdf... returned only runs 39184121515 and 39186055413, both dynamic Dependabot-related. Relevant application/backend runs inspected are older SHAs.  
**Risk:** reviewers may incorrectly aggregate historic Flutter, workbook and backend passes into a current release claim. Path-filtered workflows do not necessarily rerun on documentation-only commits.  
**Acceptance:** execute required workflows for one nominated immutable candidate SHA; retain run IDs, completed job/step status, logs, artifact digests and tested SHA. No required check may be pending, skipped or inherited from another SHA.  
**Handoff:** Prompt 15 and final auditor Prompt 18.

### F15-04 — Upload-certificate compatibility is a reminder, not an enforced gate
**Severity:** P1. **Confidence:** High.  
**Evidence:** AAB workflow lines 204–233 prints the fingerprint when release signing is enabled, but does not compare it to an owner-confirmed accepted fingerprint or fail on mismatch. The observed AAB run was debug-signed only.  
**Risk:** a different keystore could successfully sign an artifact that cannot update the intended installed app or be accepted as the expected release.  
**Acceptance:** obtain the accepted upload-certificate SHA-256 from an owner-controlled release record, compare it automatically with the candidate AAB before artifact promotion, fail closed on mismatch and verify the intended update path. Never log private key values.  
**Handoff:** Prompt 15 and human release approver.

### F15-05 — Play Data Safety and privacy policy identify Supabase as active backend
**Severity:** P1. **Confidence:** High.  
**Evidence:** play-store/data-safety.md lines 10, 22, 28, 43 and 47; play-store/privacy-policy.md lines 5, 13–15 and 26–30 describe Supabase. The owner ADR prohibits Supabase. The app source still contains the legacy client, so it is neither compliant nor correct to claim the migration already occurred.  
**Risk:** store declarations may not describe the actual submitted SDK/data/network flows. This does not assert a Play submission occurred.  
**Acceptance:** inspect the actual compliant AAB, its SDKs, reachable UI, permissions and network destinations; then revise policy/Data Safety and reconcile them against the exact Play Console declaration with owner review.  
**Handoff:** Prompt 15, Prompt 06 and accountable privacy/Play owner.

### F15-06 — Flutter dependencies and build toolchain are not fully reproducible
**Severity:** P2. **Confidence:** High for dynamic SDK; medium-high for absent lock pending local exact-checkout confirmation.  
**Evidence:** the public repo listing does not include pos-app/pubspec.lock (direct contents lookup returned 404); Flutter workflows select the latest stable release dynamically; Gradle uses Flutter's default compileSdk and NDK versions; workbook CI installs unpinned openpyxl and requests. Archive checksum verification ensures integrity of the selected file but does not pin a particular version.  
**Risk:** rerunning the same source revision can resolve different SDK/dependency/build versions.  
**Acceptance:** confirm lock status in an exact local checkout; make an owner-reviewed lockfile decision; pin Flutter, Android SDK/NDK/build tools and Python validator dependencies; run reproducibility checks and retain tool versions, lock hashes and artifact digest.  
**Handoff:** Prompt 15 and Prompt 06.

### F15-07 — Source permission allowlist not verified against packaged AAB
**Severity:** P2. **Confidence:** High.  
**Evidence:** source manifest lists INTERNET, ACCESS_NETWORK_STATE, CAMERA, BLUETOOTH, BLUETOOTH_CONNECT and BLUETOOTH_SCAN. No inspected current-candidate AAB has had its effective merged manifest extracted.  
**Risk:** plugin/manifest merging can introduce permissions not visible in the base manifest.  
**Acceptance:** extract and inspect the final candidate AAB manifest; assert package/version/target SDK and the exact allowlist; fail on any forbidden or unexpected permission.  
**Handoff:** Prompt 15 release gate.

### F15-08 — Fork-origin Flutter PR validation may be skipped
**Severity:** P2. **Confidence:** High.  
**Evidence:** pos-app-ci.yml lines 33–36 uses a job condition excluding pull requests whose head repository is a fork.  
**Risk:** contributors' changes may have no executed validation, and a skipped status may be misread as a passed check or evade branch-protection expectations.  
**Acceptance:** document explicit fork policy. If validating forks, do so without secrets or write permissions; if excluded, ensure skipped jobs are not accepted as passing checks and maintainers validate the candidate SHA before merge.  
**Handoff:** Prompt 15 CI maintainer.

### F15-09 — Static tenant-isolation check asserts legacy Supabase text, not PostgreSQL isolation
**Severity:** P2. **Confidence:** High.  
**Evidence:** pos-app-ci.yml invokes scripts/check_phase5_tenant_isolation.py. That script reads Supabase migration/test SQL and Flutter ConfigService text fragments; a pass does not create PostgreSQL roles, inspect grants or execute tenant A/B denial tests.  
**Risk:** reviewers can overstate a static legacy-contract result as proof of real target-stack tenant isolation.  
**Acceptance:** release gating must use executable tests on disposable PostgreSQL 17, real tenant databases/users/roles and actual grant-negative cases. Mark the legacy checker as source lint only or move it out of target-stack acceptance in a separate reviewed change. This audit did not run it.  
**Handoff:** Prompt 05 tenant provisioning/isolation and Prompt 15 CI maintainer.

## 7. Release gate matrix

| Gate | Status | Evidence required for GO |
|---|---|---|
| Current-head application CI | NOT VERIFIED | Required app/backend/workbook checks completed on one nominated SHA with logs and artifact identities. |
| Composer strict validation/platform/security audit | CI-OBSERVED PASS on historical ef167189...; NOT VERIFIED on current main | Rerun exact candidate with blocking audit. |
| Flutter dependency lock and pinned toolchain | PARTIAL / NOT VERIFIED | Confirm lockfile, pin SDK/toolchain and run resolution/analyze/full tests. |
| Debug AAB compile | CI-OBSERVED PASS on historical revision | Candidate-SHA build log and artifact digest; debug AAB is never release proof. |
| Publisher-signed AAB | NOT PASSED / NO-GO | Compliant app source and tested Laravel replacement; successful publisher-signing build. |
| Certificate continuity | NOT VERIFIED | Owner-approved certificate fingerprint match and successful update-path test. |
| Package/version/target SDK | SOURCE-VERIFIED only | Extract metadata from final candidate AAB. |
| Merged permission allowlist | NOT VERIFIED | Inspect final merged AAB manifest and fail on unexpected permissions. |
| No-Supabase path | FAIL at source/workflow level | Tested Laravel replacement; remove active SDK/runtime/config paths; remove prohibited legacy-script invocation from CI; scan source and artifact. |
| Play privacy/Data Safety | FAIL / stale | Align documents and Play declaration with actual exact candidate artifact and data flow. |
| Tenant isolation/API sync | Outside this task's certification; NOT VERIFIED | Prompt 05 and related specialists to produce PostgreSQL role/grant and end-to-end evidence. |
| Staging, device, Play and production | NOT RUN / NOT VERIFIED | Named staging, physical update install, Play review and owner release approval. |

## 8. GO / NO-GO decision

**Current decision: NO-GO** for publisher-signed or Play Store release.

Release can be reconsidered only after a named immutable candidate SHA has passed all required checks together; Flutter dependency resolution/analyzer/tests are executed; the active Supabase client and prohibited workflow path are removed through separately reviewed implementation; a publisher-signed AAB is built and its certificate matches the owner-confirmed accepted upload certificate; the final AAB's package/version/target SDK/merged permissions are extracted and validated; privacy/Data Safety declarations match the artifact; and all other mandatory security, tenant-isolation, backup/recovery and owner-approval gates have evidence.

Any unknown is a blocker, not a waiver. This report does not approve production.

## 9. Execution record and source fingerprints

**Performed:** read-only repository-source inspection and GitHub metadata/step/artifact review.

**Not run:** workflow dispatch, YAML linter, Composer/Flutter command locally, AAB extraction, final manifest scan, certificate comparison, physical device update test, Play Console submission, staging/production test or Supabase connection. Secrets were not accessed. The prohibited workbook script was not executed.

**Repository change:** this report only. No workflow, application, dependency or runtime files were changed. It is submitted on a dedicated audit branch for review.

### Inspected source fingerprints

| File | Blob SHA | Lines relevant |
|---|---|---|
| .github/workflows/berkah-pos-aab.yml | f154bb0b38d17f78323b4183ba9a19e5cfc093ba | 3–22; 88–125; 150–153; 155–202; 204–255 |
| .github/workflows/pos-app-ci.yml | 2d8be9cfccc9063cd7cd366b6003aa7be790d2d1 | 3–43; 95–112; 140–162 |
| .github/workflows/berkah-pos-trial-ci.yml | 0bc9d74319a5d2d699811413b2138c9caeadc758 | 3–25; 27–66; 72–82; 110–142 |
| .github/workflows/canonical-workbook-validate.yml | cf6c5d276b3869f1291d78eae0caedadfd09d4b9 | 4–34; 35–68 |
| .github/workflows/laravel-pg17-baseline.yml | e9488f17c11c1fa11c1c986cab81253fcbd0e84c | 3–60; 61–79; 130–221 |
| pos-app/pubspec.yaml | 42cfaa46b6a8067160b736b217100cb61ab6ee32 | 4; 9–23 |
| pos-app/android/app/build.gradle | d58f06529961893c9a19308cc681e6a7beea778d | 11–27; 38–45; 48–64; 72–80 |
| pos-app/android/app/src/main/AndroidManifest.xml | f6dc100ad473436b6d91ac4706b873cc7b838dca | 3–24 |
| pos-app/README.md | 29d8abc69a3b7f1f3b0876872e8a5ba184a56ad3 | 19–30; 60–64 |
| play-store/data-safety.md | f845a18c968ad71b3ce342b0bc818b92e9be4990 | 1–51 |
| play-store/privacy-policy.md | 81d9401d0ea1c3faa43a7eb8256aefb981d9560 | 5; 13–30 |
| scripts/check_phase5_tenant_isolation.py | c5dd8e1feadc64bea621fee47d52750c01dab268 | 1–69; reads archived Supabase migration/test SQL and Flutter config source text |

**Final status:** NO-GO. Several useful CI hardening controls are present, but the active client violates the no-Supabase decision, a prohibited script remains in CI, the observed AAB is debug-signed only, certificate continuity and packaged permissions are unverified, privacy documents are stale, and current-head app CI evidence is absent.
