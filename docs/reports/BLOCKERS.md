# Phase 3 Blockers — 2026-10-15

**Status: BLOCKED / RED.** Phase 3 must remain in draft review and must not proceed to Phase 4 until the execution blockers below are addressed.

## 1. GitHub Actions backend workflow startup failure

Multiple candidate-head runs terminate with `startup_failure` before a job is created. Representative evidence from repeated candidate-head runs:

- [KVM2 Laravel Backend CI — run 38751380158](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751380158): `startup_failure`, jobs API returned an empty list.
- [Canonical POS App CI — run 38751378044](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751378044): `startup_failure`, jobs API returned an empty list.
- [Phase 2 Tenant Grant Security CI — run 38751375975](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751375975): `startup_failure`, jobs API returned an empty list.

Earlier repeated attempts include KVM2 runs `38751004652` and `38750859176`, which failed the same way. This is not a test pass and does not establish whether the PHP/application changes pass or fail.

**Required owner action:** inspect repository/organization Actions startup and runner orchestration for these workflow IDs; restore a working hosted-runner job start, then re-run the current Phase 3 head. Do not bypass the gates or mark CI green manually.

## 2. Tests that must execute when the backend runner starts

- PHP syntax validation and Composer dependency resolution.
- Laravel Pint/format checks.
- `ImportCanonicalWorkbookTest`, including generated manifest counts/hash through the importer validator.
- `EffectiveConfigResolverTest` for one-service-only resolution.
- `EffectiveConfigAuthorizationTest` for active membership, domain association, and explicit device owner enforcement.
- `VersionedConfigWriterTest` for positive versions and stale compare-and-swap rejection.
- Central migration on disposable MariaDB, followed by tenant/central isolation tests and actual `SHOW GRANTS` evidence.

The workbook validation job is independently green: [run 38751374350](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751374350) passed the existing 9 parser tests, the exact 352-key/hash exporter validation, and the 5-test workbook metadata/financial regression suite. This does not substitute for the blocked Laravel/database gates.

## 3. Device ownership lifecycle review

Non-super-admin effective-config requests fail closed when a device has no explicit registered `owner_user_id` or the owner does not match the authenticated user. The workbook supplies a tenant/device association but does not define per-user ownership for every device. The owner must review and confirm the trusted registration/assignment flow before production use.

## 4. Other AGENTS.md Section 8 acceptance gates

The measured resource-budget and k6 burst, real-engine credential/grant separation, hostile Host/domain/cache behavior, tenant A/B adversarial database isolation, concurrent/interrupted provisioning, DG-4 backup/restore/PITR/single-tenant restore, and Flutter config parity gates remain **NOT RUN / NOT VERIFIED**. They are not inferred from source presence or from the workbook-only green workflow.

## Required disposition

Keep PR [#46](https://github.com/berkah-pos/Berkahtigaputeri/pull/46) draft. No Phase 4 work starts until the backend CI starts real jobs, PHP/database tests pass on the candidate head, and the owner reviews the remaining Section 8 evidence gates. No production or remote database changes were made as part of this Phase 3 work.


## Latest exact-head check — 2026-10-15 22:30 WIB

After reconciling Phase 3 against the latest Phase 2 base (branch comparison: 22 commits ahead, 0 behind), the newest candidate-head runs remain blocked before jobs start:

- [Canonical Workbook Validation — run 38751971667](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751971667): **PASS**.
- [KVM2 Laravel Backend CI — run 38751973605](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751973605): **startup_failure**, no jobs.
- [Canonical POS App CI — run 38751978004](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751978004): **startup_failure**, no jobs.
- [Phase 2 Tenant Grant Security CI — run 38751975962](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38751975962): **startup_failure**, no jobs.

Source-review fixes corrected an over-escaped PHP namespace separator and a Python integer-string regex. These fixes are not substitutes for a successful PHP lint/test run. Phase 3 remains blocked pending actual backend job execution, PHPUnit, disposable-MariaDB migration/security evidence, and owner review.

## Phase 4 — Dependency baseline prevents execution of isolation suites
**Status: BLOCKED / RED.** Added 2026-10-15 after workflow start was restored and Composer dependency resolution was reached.

### Exact evidence
- On candidate head `ffbef2723f1a14a6c5c7a20d4ae4c01684afd8da`, [KVM2 Laravel Backend CI run 38768877967](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38768877967), [Phase 2 Tenant Grant Security CI run 38768878239](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38768878239), and [Canonical POS App CI run 38768878087](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38768878087) all created jobs but failed at their Composer dependency-install step.
- Composer's detailed resolver output says the allowed Laravel `^11.0` and Filament `^3.2` dependency candidates are blocked by its active security-advisory policy. It did not reach migrations, tenant grant assertions, HTTP isolation tests, or the A→B queue worker test.
- `composer.lock` is absent, so there is no reproducible, source-reviewed resolution to install.
- Root `AGENTS.md` Section 3 and DOC_14 specify the target PHP 8.4 / Laravel 13 / Filament 5 / Composer-locked and tested `stancl/tenancy` v3.10.x stack. The current manifest is Laravel 11 / Filament 3, and `audit/ADR-2026-10-15-STACK-BASELINE-EXCEPTION.md` explicitly remains PROPOSED / NOT ACCEPTED.
- Laravel's official [release notes](https://laravel.com/framework/docs/11.x/releases) list Laravel 11 security fixes ending March 12, 2026. As of this report date, the old stack is not an acceptable way to bypass Composer policy.

### Required owner decision
Review and either **reject the proposed temporary-stack exception and authorize the target-stack upgrade** (recommended), or explicitly decline the target change and specify an alternative supported dependency baseline. An exception to the version target alone must not be treated as permission to disable Composer advisory blocking or mass-ignore advisories.

Until that decision and dependency baseline are reviewed:
- Do not change `composer.policy.advisories.block`, pass `--no-blocking`, use `--no-security-blocking`, or add broad advisory ignores to obtain a green build.
- Do not generate a lock file that preserves the currently blocked Laravel 11 / Filament 3 graph as a workaround.
- Keep PR #47 draft/RED and do not begin Phase 5. Once the baseline is approved, perform the framework/Filament compatibility migration, produce and review `composer.lock`, then run migrations and the three real MariaDB-backed Phase 4 suites.
- No production resource, database, domain, DNS or deployment was modified.
