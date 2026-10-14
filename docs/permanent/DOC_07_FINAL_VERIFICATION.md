# DOC_07 — FINAL POS CURRENT-BRANCH VERIFICATION

**Status: PARTIAL / RELEASE BLOCKED.** Canonical source contracts and targeted disposable CI suites are green, but this document is not a production security certification or approval to merge/deploy.
**Repository:** berkah-pos/Berkahtigaputeri  
**Working branch:** chore/consolidate-single-main-repo  
**Architecture authority:** DOC_00_CANONICAL_ARCHITECTURE_DECISION.md  
**Captured:** 2026-10-15 (Asia/Jakarta)  
**Implementation revision exercised by Phase 6 replay:** d620161a5f67d58c2dbc0f260b4c651cffe70e96  
**Disposable replay revision:** 3a9cd7254698381827e4863418e55c876e9ed9a2  
**Backend CI/path-filter verification:** dc9c13bdf36662435e0d8bc7a70d6004cf7c063b

## 1. Canonical architecture and inventory

Canonical inheritance remains exactly:

GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE

The workbook is config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx with sheets README_PRODUCTION, TEMPLATES, GLOBAL, TENANTS_MASTER, DEVICES, SERVICES, and APP_CONFIG_EXPORT.

Canonical inventory confirmed by workbook dry-run and archived manifest:
- 1 global + 3 templates (BASIC, PRO, ENTERPRISE) + 100 tenants + 140 service keys + 108 devices = 352 keys.
- Keyset MD5: 1fd3d64219ecc7c333453c20da80e295.
- Supabase shape: app_config(key PRIMARY KEY, value JSONB, updated_at).
- Runtime resolves only requested pos or akuntansi service and merges top-level values in canonical order.

Evidence: [Canonical Workbook Validation run 38629719283](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629719283) passed 21 Python tests and printed EXPECTED KEY COUNT VERIFIED: 352, the canonical keyset digest, and DRY-RUN OK without Supabase credentials or network writes.

## 2. Admin, Flutter, RPC and synchronization

- Admin parity fixture checks the exact five requested rows for POS and Akuntansi independently, verifies top-level precedence/device override, and tests a versioned tenant save that preserves hidden canonical fields. The fixture passed in workbook validation CI.
- Flutter ConfigService uses authenticated get_effective_config(p_tenant, p_device, p_service) as its only cloud configuration resolver. [Canonical POS App CI run 38629719307](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629719307) succeeded and reported no Dart analyzer issues. This is CI evidence, not evidence that a production-signed APK was installed on physical hardware.
- Workbook synchronization retains versioned update_app_config_atomic, fail-closed missing-credential/RPC-error handling, exact inventory verification, and canonical key-manifest assertion.
- The backend push filter now reruns source-recovery and historical replay preconditions when relevant scripts/workbook/manifest files change. [Supabase Backend Foundation CI run 38630659808](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38630659808) passed on the reviewed trigger definition.

## 3. Phase 5 and Phase 6 database evidence

[Supabase Reconstructed Baseline Clean Replay run 38629812613](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629812613) passed on a GitHub-hosted runner using only disposable local Supabase databases:
- Reconstructed target baseline + targeted Tenant A/B security tests: 50 pgTAP tests across 2 files, PASS.
- Atomic versioning after the forward-only migration 20261014201000_phase6_atomic_versioning_legacy_tax_compat.sql: 19 pgTAP assertions, PASS.
- Historical staging: all 139 recorded migration bodies replayed unchanged and matched the captured staging catalog fingerprint.
- Historical staging-clone: all 12 recorded migration bodies replayed unchanged under a clone-specific pre-history baseline; 37 pgTAP tests and its captured clone catalog fingerprint passed.

Atomic version assertions cover positive version, expected-version CAS, stale-version rejection with SQLSTATE 40001, server-owned N-to-N+1 bump, direct-DML bypass denial, template/device identity guards, audit history, and legacy-tax compatibility. Unchanged old tax fields may be echoed by Admin and are stripped before persistence; new/changed protected tax fields remain denied.

Historical replay proves schema behavior against captured references in disposable environments. No hosted database was written, and replaying each database against its own captured fingerprint does not make staging-clone equivalent to staging.

## 4. Security and operational disposition

**Still open — do not merge to main or deploy to production yet:**

1. Read-only catalog evidence still shows staging-clone broad effective anon permissions, including 32 public-schema SECURITY DEFINER routines executable by anon and effective anon SELECT on 55 application relations. These need object-by-object review and an independently reviewed, narrow forward-only ACL migration.
2. Full hostile Tenant A/B testing across direct REST reads/writes, reporting/export, all inventory/accounting RPCs, storage, subscriptions, sync/outbox, and installed APK is incomplete. The 50 pgTAP assertions are targeted coverage, not the complete matrix.
3. Backup/restore drills, migration failure/retry, representative load/resilience, monitoring checks, and independent release review remain outstanding.
4. No production Supabase project has been positively identified/authorized. The Phase 6 compatibility migration has not been applied to hosted staging or production.
5. Exact original base-versus-fork SHA-256 comparison is complete and archived (Section 7). The single differing workflow was reviewed; the canonical base version was retained. The latest verified Git bundle/ZIP artifacts are also available (Section 6).

## 5. Current decision

- Source / CI contract acceptance: GREEN for the checks listed above.
- Phase 6 atomic RPC test acceptance: GREEN in disposable local PostgreSQL.
- Overall migration reconciliation: BLOCKED by hosted clone ACL drift and release/restore/security gates.
- Main merge / production release: NOT APPROVED until the remaining gates are independently completed.

This updates older historical DOC_07 snapshots only for the scoped evidence above; it does not turn their old live-verification claims into current verification.


## 6. Generated repository exports

Hosted workflow [Consolidated Main Repo Export — run 38631992229](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38631992229) succeeded on commit `dbea77b0ceb67f9492be1b36377620975b073c54`.

- **Git bundle:** [download artifact](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38631992229/artifacts/11925864688). The runner ran `git bundle verify`; the bundle includes `refs/heads/chore/consolidate-single-main-repo` at the exported commit. File size 1,785,170 bytes; SHA-256 `23937680b832b681da63ff437e8880b5b27c5b2fb8163ff6413e302aa6fa4677`.
- **Source ZIP:** [download artifact](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38631992229/artifacts/11926029695). The runner validated the archive, counted 329 files, and confirmed it excludes `.git` metadata. File size 941,219 bytes; SHA-256 `afea2531398e0cb151a099e7bf1998b25be9cc231cd5c64c074fbc3807f06c64`.
- **Export manifest:** [download artifact](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38631992229/artifacts/11925924630).
- The three GitHub Actions artifacts expire on **2026-11-13**. Download and keep a separate copy before that date.

Subsequent export run [38632908917](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632908917), on commit abc92ade724ee70ab2220cd1e488f556bac145ab, refreshed the files after adding the SHA-256 report and updated documentation. The refreshed bundle is [artifact 11927760590](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632908917/artifacts/11927760590), 1,798,482 bytes, SHA-256 94327d0feb1f18d8cdbf0b9503ffc55dbac1f36bed5a9720a748d59dbabc26a9. The refreshed ZIP is [artifact 11927665637](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632908917/artifacts/11927665637), 331 files excluding .git, 945,864 bytes, SHA-256 2ecc1e04c43edba0189d5c822f45bec025988196d142bd4a1e6fda28bdfd435e. These refreshed artifacts expire 2026-11-13.

The phase-roll-up revision 29c6f041406b4074a82bc386bd17e939cc9d607a was exported and verified in [run 38633380528](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38633380528). Bundle artifact [11927950907](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38633380528/artifacts/11927950907): 1,806,860 bytes, SHA-256 05daff49e7e07a6075ba4f8ad222f73c2cff8ce298394aff6c588d61609e8e07. ZIP artifact [11927481262](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38633380528/artifacts/11927481262): 336 files excluding .git, 952,652 bytes, SHA-256 293894359dd3d49737044bb4a6b28cbf21a14ae810069037fd21b469a42840aa. Export manifest: [artifact 11927196399](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38633380528/artifacts/11927196399). These artifacts expire 2026-11-13; export is rerun on each branch push.

The original base-versus-fork SHA-256 diff report is a separate outstanding artifact; tree/blob screening is not substituted for that report.

## 7. Original base-versus-fork SHA-256 comparison

Hosted comparison: [Original Source SHA256 Comparison — run 38632527070](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632527070). The job completed successfully after checking out the exact source snapshots read-only and hashing all included file contents.

- Base: `berkah-pos/Berkahtigaputeri`, commit `98befcd5807585dd0c1b84085fc4a6e73fd90f2b`, 164 files.
- Fork patch: `Andisatriawan/Berkahtigaputeri`, commit `b02a47448eddfc2db6efb1c336b6cda0b4c85556`, 164 files.
- Comparison: **163 IDENTICAL**, **1 MODIFIED**, **0 ONLY_IN_MAIN**, **0 ONLY_IN_FORK**; 164 unique paths in the union.
- Full CSV and JSON summary: [download comparison artifact](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632527070/artifacts/11926312229). It includes per-path status, both SHA-256 digests and byte counts. Artifact retention expires **2026-11-13**.

The only modified path is `.github/workflows/berkah-pos-trial-ci.yml`:
- Base SHA-256 `b4741fdcec2aa142eae5ab3c1d702c7d6e5abf01d339eeda3c80a8adffc41f9f`, 5,654 bytes.
- Fork SHA-256 `0279c8906a89b87d6c185954e6f4939a6d5bbcf2d0900545d6c9f794b5a89350`, 3,721 bytes.

The base version was retained. Relative to the fork file it includes hosted-runner Android SDK location checks, NDK installation with retry, official stable Flutter archive SHA-256 verification, explicit non-production smoke-build labeling, and upload of debug APK plus release-smoke APK/AAB artifacts. The fork version omits some of these setup/verification steps and uploads only the debug APK. This was a read-only comparison of the specified historical snapshots; it did not change or push to the fork.
