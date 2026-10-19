# Pre-production Audit 04 — Authentication, Secrets and Sessions

**Status: BLOCKED — partial hardening only; not release-ready.**  
**Report date:** 2026-10-19 (Asia/Jakarta)  
**Repository:** berkah-pos/Berkahtigaputeri  
**Branch:** audit/preprod-auth-secrets-2026-10-18  
**Base SHA:** 371b7fdf0bf672b37ceb1023e647f114221bf797  
**PR:** [#92 — security: harden production secrets and token expiry](https://github.com/berkah-pos/Berkahtigaputeri/pull/92) (draft; not merged)  
**Code head submitted for initial CI:** 0f0631fb71a4df341a612fe5d6284be7efd532ab  
**Initial exact-SHA workflow:** [run 39279237267](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39279237267), workflow “Laravel PostgreSQL 17 Baseline”, run number 209, attempt 1, tested SHA 0f0631fb71a4df341a612fe5d6284be7efd532ab, status **QUEUED** at report drafting. Its conclusion and job logs were not yet available. This report does not claim that run passed. If added in a later commit, that run is explicitly not exact-SHA evidence for the newer report commit.

**Source follow-up after initial report draft:** a later source commit removed tenant/privilege fields from User mass-assignment and added the missing central password_reset_tokens table migration. Current source head before this report-only amendment: 7799f453e6e106c73243a86de02fdc2014d5eb81. Exact-head workflow [run 39280386505](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39280386505), attempt 1, was still QUEUED at the last inspection. This is source-head evidence metadata only; do not infer test success. Subsequent changes to this report are documentation-only and trigger their own CI run.

## 1. Executive summary

The canonical application target is Laravel 13 / PHP 8.4 / Sanctum / private PostgreSQL 17. The backend remains a starter scaffold, not a delivered authentication service. Source inspection found that routes/api.php exposes only GET /api/v1/platform-health; there are no login/logout/token issuance/revocation/password-reset/email-verification routes, no route-level login throttle, and no MFA implementation visible in the Laravel tree inspected. The reset broker configuration names password_reset_tokens, but the inspected central migration does not create that table.

Some baseline controls exist in source: the central User model uses Laravel’s hashed password cast and hides password/remember_token; Filament panel access checks is_active and is_super_admin. These are not proof of a functioning, abuse-resistant auth lifecycle. In particular, there is no API middleware proving that an inactive user’s existing bearer token is rejected.

This branch makes the limited changes within its ownership: removes the deterministic APP_KEY fallback from local Compose; adds a production-startup validator for app key, debug mode, HTTPS, secure cookies, session lifetime, central DB account/password placeholders and mail transport; defaults Sanctum bearer-token expiration to 60 minutes; adds narrow regression tests and a redacted full-history Gitleaks CI step. At report drafting, tests and scan were queued for the submitted code head; no local execution result is claimed.

**Release recommendation: BLOCKED.** Login/rate-limit, email verification/reset, logout and revocation, disabled-account invalidation, role/tenant tampering defenses, MFA for the primary admin, and runtime/logging verification remain open acceptance gates. No production secrets were rotated; no production database, mailbox, DNS or Supabase project was accessed.

## 2. Scope, revision and files

### In-scope review

Laravel auth model/config, API routes/bootstrap middleware, central user/token/reset schema, session/Sanctum settings, Compose/Docker entrypoint, environment examples, logging config, PHPUnit fixtures, Gitleaks ignore rules, and the Laravel CI workflow.

### Files changed on this branch

| Path | Change |
|---|---|
| docker/validate-production-env.sh | New fail-closed production env checks; never prints secret values. |
| docker/entrypoint.sh | Runs validation before migrations or service start. |
| docker-compose.yml | Removes deterministic default APP_KEY; local startup requires a user-supplied key in .env. |
| config/sanctum.php | Changes bearer-token expiry default from unlimited (null) to 60 minutes via SANCTUM_EXPIRATION_MINUTES. |
| .env.example | Labels DB passwords as local-only placeholders, documents key generation, token/session defaults and intentionally empty SMTP settings. |
| tests/security/production-env-guard.sh | New negative/positive regression test for startup configuration validation. |
| app/Models/Central/User.php | Removes tenant_id, is_super_admin and is_active from mass-assignable fields; privileged changes now require explicit server-side assignment. |
| database/migrations/central/2026_10_19_000001_create_password_reset_tokens_table.php | Adds central password-reset token storage; route/delivery/replay behavior is still not implemented or tested. |
| tests/Feature/CentralUserSecurityTest.php | Tests password hashing/hidden field, non-mass-assignable tenant/privilege fields and bounded Sanctum expiry config. |
| .github/workflows/laravel-pg17-baseline.yml | Adds Gitleaks full-history scan with redacted output and production-env-guard test; includes report paths in triggers. |
| docs/reports/preproduction/2026-10-18/04_AUTH_SECRETS_AND_SESSIONS.md | This report. |

No permanent architecture document, database migration, production configuration, tenant-provisioning source or monitoring configuration was changed.

## 3. Mandatory documents read

Read in repository-required order:

1. AGENTS.md.
2. docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md.
3. docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md.
4. docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md.
5. docs/permanent/DOC_00_MASTER_ROADMAP.md.
6. docs/permanent/README.md.
7. docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md.
8. docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md.
9. docs/HARDENING/README.md.
10. Root README.md.
11. Relevant auth/session/config/schema/test/CI files identified in §2.

Authority outcome: the 2026-10-17 owner ADR overrides conflicting operational parts of the 2026-10-16 ADR and forbids all Supabase project/product access, including read-only. The canonical configuration contract remains GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE and exactly 352 workbook entries. This workstream did not change that contract. Historical staging notes or earlier workflow outcomes are not current runtime proof.

## 4. Acceptance-gate matrix

Status meanings: **VERIFIED** = directly evidenced; **CLAIMED** = source/configuration or documentation only; **FAILED** = an executed test/check fails; **BLOCKED** = required functionality/evidence absent; **NOT RUN** = a check has not executed.

| ID | Acceptance criterion | Status | Evidence and blocker |
|---|---|---|---|
| AUTH-01 | Passwords are not persisted in plaintext | **VERIFIED (source)** / test **NOT RUN at authoring** | app/Models/Central/User.php uses the hashed cast and hides password; regression test added. No DB persistence path was exercised. |
| AUTH-02 | Login response avoids user enumeration; credential failures are uniform | **BLOCKED** | No Laravel login endpoint/controller or integration test found. |
| AUTH-03 | Login throttling / abuse limits enforced server-side | **BLOCKED** | No RateLimiter::for or auth route throttle found. |
| AUTH-04 | Role, active state, tenant and device claims derived/verified server-side | **BLOCKED** | No authenticated business API routes exist to test. This branch removes tenant_id, is_super_admin and is_active from User mass-assignment; authorization/policy enforcement and account/device/tenant checks remain absent. |
| AUTH-05 | Email verification is enforced for relevant accounts | **BLOCKED** | User schema has email_verified_at, but delivery/verification route and enforcement middleware were not found. |
| AUTH-06 | Password reset is short-lived, non-replayable and rate-limited | **BLOCKED** | config/auth.php names password_reset_tokens, expiry 60 minutes and throttle 60 seconds. This branch adds the missing central table migration; reset/verification routes, notifications, enforced throttling, one-time consumption, session invalidation and replay tests are still absent. |
| AUTH-07 | Session/token expiry and cookie protections | **PARTIAL** | Sanctum expiry changed to 60 minutes; startup validator requires secure session cookie and a 1–60 minute session lifetime in production. Regression/CI status was not available at authoring. No staging test. |
| AUTH-08 | Logout/revocation across device/session | **BLOCKED** | Token issuance/logout/revocation routes are absent. Token schema includes expires_at, but no revoke path was found. |
| AUTH-09 | Disabled account invalidates existing credentials | **BLOCKED** | is_active is checked for Filament panel access only. No API auth middleware or disabled-user token-rejection test found. |
| AUTH-10 | Primary administrator MFA | **BLOCKED** | Implementation/configuration/enforcement and staging evidence are absent. Implemented **NO**, configured **NO**, enforced **NO**, staging **NOT RUN**. |
| AUTH-11 | Startup fails closed on missing/invalid production secrets | **SOURCE VERIFIED; TEST NOT RUN at authoring** | New docker/validate-production-env.sh is invoked before migrations/server start. Regression script covers invalid/missing keys, debug, HTTP URL, insecure cookie, excessive session lifetime, privileged DB login, placeholders and missing mail. CI run queued. |
| AUTH-12 | No real secret in .env.example / Compose defaults | **PARTIAL / SCAN CONFIRMATION PENDING** | .env.example uses blank APP_KEY and explicitly labelled local DB placeholders; deterministic Compose key fallback removed. All 31 historical candidates are now source-classified false positives with exact scoped entries in .gitleaksignore. The final post-allowlist full-history scan is queued; a clean result is NOT VERIFIED. |
| AUTH-13 | Secret scanner and redacted output | **FAILED on prior heads / current scan NOT VERIFIED** | Run 39281549803 reported 31 matches; run 39282823359 after 30 exceptions reported one match, verified as a deterministic MD5 keyset-integrity check in archived SQL and narrowly allowlisted. Latest post-final-allowlist scan [39283367189](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39283367189) was QUEUED at the last check. No clean scan is claimed until a completed run is verified against its tested candidate SHA. |
| AUTH-14 | No sensitive auth values in logs | **NOT RUN** | config/logging.php configures stderr/single channels, but runtime tests have not proved reset/token/password/SMTP/payload redaction. |
| AUTH-15 | Rotation runbook exists | **VERIFIED (document)** | §7 documents procedures only. No actual rotation was authorized or executed. |

## 5. Findings: severity, confidence and action

### F-01 — No production auth API/lifecycle — P1 / High confidence / BLOCKED

**Evidence:** routes/api.php:1–10 contains only the GET platform-health route; bootstrap/app.php:9–21 adds routing and JSON exception behavior but no project-specific authentication middleware. Current Laravel source did not expose login throttling or auth:sanctum-protected business endpoints. A Sanctum dependency/model/token table does not prove an auth service.

**Impact:** No end-to-end login/logout identity contract can be tested; account authentication, user enumeration, role/tenant tampering and token revocation acceptance cannot pass. A health response is not an authenticated product API.

**Required fix:** In a reviewed implementation commit, define login, current-user/session, logout-current-token and revoke-all-tokens endpoints; issue credentials only after server-side credential/account checks; return generic auth failures; protect sensitive endpoints with auth:sanctum and policies; add server-derived tenant membership/device/subscription resolution. Never accept client-controlled is_super_admin, is_active, tenant_id or entitlement as authorization.

**Closure tests:** valid/invalid login; unknown email versus wrong password same response shape/status; missing/invalid/revoked token denied; current-token logout; revoke-all devices; inactive user rejected after token issuance; forged tenant/device/role payload rejected.

### F-02 — Primary admin MFA absent — P1 / High confidence / BLOCKED

**Evidence:** composer.json:11–25 includes Laravel Sanctum but no dedicated MFA dependency; scoped routes/config/model files do not provide authenticator enrollment, recovery, enforcement middleware or staging observation.

**Impact:** A compromised central super-admin credential may provide privileged access without a second factor.

**Required fix:** Add a supported Laravel-compatible TOTP implementation or a reviewed passkey/WebAuthn mechanism for central administrators. Require enrollment before privileged panel access, verify second factor on login and step-up for sensitive changes, protect recovery codes, audit enable/disable/recovery, rate-limit attempts, and prevent an admin from removing their last required factor without a controlled recovery process. Enforce centrally, not merely in UI.

**Closure tests:** MFA enrollment/challenge, invalid and replayed code rejection, throttled attempts, single-use recovery codes, step-up, admin route denial without MFA, and isolated staging evidence. Adding a dependency alone does not mean MFA is configured/enforced.

### F-03 — Password reset and verification are configuration-only/incomplete — P1 / High confidence / BLOCKED

**Evidence:** config/auth.php:10–17 sets password broker table/expiry/throttle; database/migrations/central/2026_10_17_000001_create_central_platform_tables.php creates users and personal_access_tokens but not the reset table. This branch adds database/migrations/central/2026_10_19_000001_create_password_reset_tokens_table.php:11–20. Reset/verify routes, notification transport, replay tests and reset-triggered session invalidation were not found.

**Impact:** The reset path cannot be certified and may fail because its backing table and controller flow are absent. A verification timestamp can exist in schema without being enforced.

**Required fix:** Implement Laravel's password broker with a central token table and proper email delivery; store only reset-token hashes under the framework contract; use uniform response text for known/unknown emails; throttle by normalized identity and source IP; atomically consume reset tokens; revoke existing personal access tokens and sessions after reset; enforce email verification for the account types the owner requires. Production mail must not use log/array transport.

**Closure tests:** valid, expired and replayed reset; concurrent replay; throttling; unknown-email response equivalence; isolated test delivery without tokens in logs; old token/session denied after password change.

### F-04 — Token revocation and disabled-user enforcement not implemented — P1 / High confidence / BLOCKED

**Evidence:** app/Models/Central/User.php:23–26 checks is_active/is_super_admin only in canAccessPanel; config/sanctum.php:7–12 sets token expiry but no active-user middleware. No revoke/logout route exists. The personal_access_tokens table in database/migrations/central/2026_10_17_000001_create_central_platform_tables.php includes expires_at, but the table alone does not invalidate inactive accounts.

**Impact:** If bearer-token routes are added without a common active-account check, an already-issued token could remain usable after account deactivation. This is a release-gap, not a demonstrated exploit against a deployed API route.

**Required fix:** Apply central active-user validation to each protected API/admin request; on deactivation/password reset/security incident revoke relevant access tokens and sessions; add explicit per-device token naming/revocation and audited revoke-all operation. Token expiry is not a substitute for revocation.

### F-05 — No login or reset abuse throttling — P1 / High confidence / BLOCKED

**Evidence:** routes/api.php:1–10 has no auth endpoints, and search of the scoped Laravel source found no RateLimiter::for declaration or auth route throttle. config/auth.php:10–17 does not create a request limiter by itself.

**Impact:** Future credential endpoints may be susceptible to brute force, credential stuffing and reset-mail abuse if shipped without server-side throttling.

**Required fix:** Define named per-IP and per-account (normalized email/user ID) throttles; preserve generic responses; apply separate tight limits to MFA and reset requests; add cooldown/backoff/abuse telemetry without causing permanent account-lockout denial of service. Use shared limiter state if horizontal scaling is later introduced.

### F-06 — Deterministic APP_KEY fallback in Compose — P2 / High confidence / CHANGE MADE; test pending

**Evidence:** base docker-compose.yml:23–27 supplied a deterministic APP_KEY fallback. This branch replaces it with a required local setting. docker/entrypoint.sh:4 calls docker/validate-production-env.sh before migrations/service start; that script checks app key, debug mode, HTTPS, secure cookie, session lifetime, central DB account/password placeholder and mail transport without printing secret values.

**Impact:** If the fixed key were reused outside isolated development, signed/encrypted Laravel state could become predictable across installations.

**Action made:** Removed fallback; added fail-closed validator and negative/positive shell tests in tests/security/production-env-guard.sh. CI was queued at report authoring; closure is not yet TEST-EXECUTED.

### F-07 — Sanctum token expiry was unlimited by default — P2 / High confidence / CHANGE MADE; tests pending

**Evidence:** baseline config/sanctum.php:7–12 set expiration to null. The branch now sets it from SANCTUM_EXPIRATION_MINUTES, default 60, and adds a config regression test.

**Impact:** Bearer tokens might otherwise remain valid indefinitely unless individually revoked. An expiry default does not implement token issuance, logout, revoke-all or active-user enforcement.

**Action made:** Bound expiry to 60 minutes by default. Actual token expiry was NOT RUN / NOT VERIFIED because the API flow is absent.

### F-08 — Privilege-field mass assignment — P2 / Medium confidence / CHANGE MADE; tests pending

**Evidence:** baseline app/Models/Central/User.php:18–20 listed tenant_id, is_super_admin and is_active in $fillable. The branch removes them from the fillable list; no current public user-update route was found, and no externally reachable mass-assignment exploit was demonstrated.

**Impact:** removing them from fillable prevents accidental mass assignment through ordinary fill/create/update payloads. It does not implement authorization for routes that do not exist yet.

**Action made:** tenant and privilege fields are no longer mass assignable; a regression test asserts they are excluded from getFillable(). CI has not yet provided a result for that test.

**Closure tests:** attempt these fields through every future registration/profile payload and assert DB state is unchanged; verify only audited admin actions can update them.

### F-09 — Runtime DB role separation needs DBA/security validation — P2 / High confidence / DEPENDENCY

**Evidence:** examples/local Compose use a PostgreSQL postgres account for local boot. Production validator rejects common cluster-admin usernames for the central runtime account. No actual target runtime-role/grant test was executed.

**Impact:** Using a cluster admin as app runtime defeats least privilege.

**Dependency:** PostgreSQL workstream must prove real central/per-tenant role grants, PUBLIC privilege state and tenant-A-to-tenant-B denials with disposable PostgreSQL 17 roles. This report did not change provisioning source and does not claim its grants are safe.

### F-10 — Legacy mobile/static-admin auth paths conflict with current owner policy — P1 / High confidence / CROSS-WORKSTREAM

**Evidence:** pos-app/pubspec.yaml, pos-app/lib/main.dart and pos-app/lib/core/config/config_service.dart retain the legacy Supabase client path; btp-admin contains legacy static client auth. The 2026-10-17 owner ADR prohibits Supabase use. Those paths were not edited by this workstream.

**Impact:** The product has no compliant end-to-end client identity flow until the clients use the reviewed Laravel API. A public client key or client-supplied tenant/device ID is not authorization.

**Action:** Route the migration to mobile/static-admin/API owners. Replace these paths with tested Laravel endpoints, then scan active app bundles. Do not connect to an existing Supabase project to validate them.

### F-11 — Full-history Gitleaks candidates and false-positive classification — P2 / High confidence / SCAN CONFIRMATION PENDING

**Evidence:** run 39281009902/job 118154946586 scanned 1,598 commits (~12.88 MB) and reported 31 findings/exit 1, but did not output per-finding metadata. Run 39281549803/job 118156700715 emitted sanitized metadata for 31 matches at PR merge-ref SHA a0720108359e1b01b3e26937e80dfc4b21982ae4. Run 39282823359 after 30 scoped exceptions reported one remaining match; blob c071e2ffd7bf135d1d269d311699a87d5a4f0ac0 was retrieved, and line 663 was confirmed as a SQL keyset-integrity digest. A 31st exact exception was committed in .gitleaksignore.

**Impact:** Gitleaks correctly blocked CI while 31 generic-api-key-rule matches were present. Source metadata and context now support classifying all 31 as checksums, CI/source references, descriptive slugs, or an archived SQL keyset-integrity digest—not active credentials. This is a source-reviewed false-positive disposition, not yet proof of a clean post-allowlist scan. No matched value is reproduced here.

**False-positive evidence and scoped disposition:**

| Category | Count | Direct evidence and disposition |
|---|---:|---|
| Canonical workbook/config keyset digests, checksum fields, CI output hashes and source-reference identifiers | 30 findings | Source and metadata identify deterministic MD5/SHA-256/keyset values, CI validator output, source commit IDs/URLs, or historical reconciliation digests. These are non-secret validation/reference values and are allowlisted only for exact commit/path/rule/line. |
| Operational-readiness descriptive slugs | 1 finding | docs/runbooks/operational-readiness.md:101 is explanatory backup-history prose; the candidate strings are lowercase/hyphenated, contain no digits or uppercase, have low measured entropy (3.77 and 3.54 bits/character), and are not assigned to a credential field. A precise ignore entry documents the location. |
| Archived SQL keyset-integrity MD5 | 1 finding | supabase/reconciliation/recovered-remote-migration-statements-2026-10-14.json:663, commit 28f7040fcb29b85e69fe3f4fe8d9e4ac4bf650fc. Direct blob review established this is a computed MD5 over sorted config keys, checked against an expected digest for the canonical 352-entry inventory; it is not an authentication credential. It is allowlisted at this exact commit/path/rule/line. |

**Action made:** scripts/security/sanitize_gitleaks_report.py copies only allowlisted metadata fields (rule, description, file path, line/column, commit, entropy, tags and fingerprint) and drops Secret/Match/Raw/author/email. tests/security/test_sanitize_gitleaks_report.py verifies those fields are omitted; the local test passed 2/2. The workflow writes a Gitleaks JSON report to temporary runner storage, logs only sanitized metadata, continues through other checks, and enforces nonzero scanner exit at the end. .gitleaksignore now has 31 exact, evidence-backed false-positive entries; no blanket ignore was added.

**Closure / response:** verify the post-final-allowlist full-history scan completes cleanly on the tested candidate SHA; record run ID, attempt, tested SHA, conclusion and sanitized log evidence. Do not infer a pass from queued status metadata. No production rotation was performed or authorized; no matched value is reproduced and no Supabase project was accessed.

## 6. Secret scan and classification — sanitized

### Inspected sources

Current configuration/source references for APP_KEY, database credentials, reset-token config, Sanctum/token model, SMTP fields and Gitleaks-ignore entries; .env.example; docker-compose.yml; phpunit.xml; Docker entrypoint; central user/token migration; current Laravel CI workflow; .gitignore.

### Sanitized results

| Category | Result | Classification |
|---|---|---|
| Production DB/SMTP/API/private signing credentials | **NOT VERIFIED by complete scan** | No credential value is reproduced. Source search is not a full repository-history scan. |
| .env.example | **SOURCE-VERIFIED: placeholders only** | Blank APP_KEY; database placeholders explicitly local-only; SMTP values empty. Never use the local DB values in a hosted environment. |
| Compose APP_KEY | **FIXED IN CHANGE** | Deterministic all-zero fallback removed; Compose now requires a user-supplied local APP_KEY. |
| PHPUnit/CI APP_KEY and PG fixture credentials | **TEST FIXTURES / expected false-positive candidates** | Explicit APP_ENV=testing and disposable PostgreSQL CI configuration. Never reuse outside CI. Scanner still must determine/report whether it flags them. |
| Gitleaks ignores for deterministic keyset MD5 hashes | **EXPECTED FALSE POSITIVES, historical fingerprints** | Configuration digests are not credential material; current ignore entries are scoped by commit/path/rule/line. |
| Legacy public client-side Supabase key/path | **PUBLIC-BY-DESIGN BUT ARCHITECTURALLY STALE** | Not a secret credential, but the client path is prohibited by the current owner ADR and needs separate migration/removal. |
| Full Gitleaks result | **31 findings classified as false positives; final scan NOT VERIFIED** | [Run 39281549803](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39281549803), job 118156700715, scanned PR merge-ref SHA `a0720108359e1b01b3e26937e80dfc4b21982ae4`: 1,603 commits, ~12.89 MB, 31 findings. After 30 exact exceptions, [run 39282823359](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39282823359) scanned 1,606 commits / ~12.90 MB and reported one match: `supabase/reconciliation/recovered-remote-migration-statements-2026-10-14.json:663`, commit `28f7040fcb29b85e69fe3f4fe8d9e4ac4bf650fc`. Direct blob review of blob `c071e2ffd7bf135d1d269d311699a87d5a4f0ac0` showed the archived SQL computes an MD5 over sorted configuration keys to validate the expected 352-key inventory; this is an integrity checksum, not a credential. The 31st precise exception was added to `.gitleaksignore` in commit `5cd6ce2a4df10ecab67af5f8f0685a19d374dfda`. Latest post-final-allowlist run [39283367189](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39283367189) was QUEUED when checked. No clean scan is claimed pending that run. |

### Exact commands/results

| Command / operation | Environment | Exit code/result | Artifact |
|---|---|---|---|
| Source inspection via GitHub file API on branch audit/preprod-auth-secrets-2026-10-18 | GitHub, based on SHA 371b7fdf0bf672b37ceb1023e647f114221bf797 | Source inspection completed; not a process/test command | Paths/links cited in this report. |
| gitleaks git --no-banner --redact --exit-code 1, using ghcr.io/gitleaks/gitleaks:v8.30.1 and checkout fetch-depth 0 | GitHub-hosted ubuntu-24.04 | **NOT RUN to completion at report drafting**; run 39279237267 queued; exit code unavailable | [Run logs](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39279237267). |
| bash tests/security/production-env-guard.sh inside built PHP 8.4 development image | Disposable CI container | **NOT RUN to completion at report drafting**; same queued run | [Run logs](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39279237267). |
| php artisan test inside built image with disposable PostgreSQL 17 service | Disposable CI-only PG17; never production | **NOT RUN by audit session**; run queued | Same run URL. |
| composer validate --strict --no-check-publish | Container build/CI | **NOT RUN by audit session**; run queued | Same run URL. |
| composer audit --locked --no-interaction | Container build/CI | **NOT RUN by audit session**; run queued | Same run URL. |
| Production/staging login/reset/MFA/revocation tests | Isolated runtime required | **NOT RUN / BLOCKED** — endpoints/runtime/staging evidence unavailable | No artifact exists. |
| Production secret rotation | Requires owner/provider authorization | **NOT RUN** — explicitly outside authorization | No values accessed or changed. |

CI results from an earlier SHA (including the historic Laravel baseline at aab154f87342f2a02a1319e1d370ce831dbef522) do not prove this branch head or the final report revision passed.

### Supplemental local smoke test (2026-10-19)

The production-env guard was tested locally after fetching its tracked source, using synthetic-only credentials. This execution container is not a Git checkout of the repo, so the validator/test were reconstructed into a temporary harness from the exact fetched branch contents. This is **supplemental logic evidence, not an exact-SHA repository test**.

| Exact command | Environment | Exit code/result | Sanitized artifact |
|---|---|---|---|
| `sh -n /tmp/berkah-auth-audit/docker/validate-production-env.sh` | Local container, POSIX shell syntax check | **0 — PASS** | Temporary script in `/tmp/berkah-auth-audit/docker/validate-production-env.sh` |
| `bash -n /tmp/berkah-auth-audit/tests/security/production-env-guard.sh` | Local container, Bash syntax check | **0 — PASS** | Temporary script in `/tmp/berkah-auth-audit/tests/security/production-env-guard.sh` |
| `bash /tmp/berkah-auth-audit/tests/security/production-env-guard.sh` | Local container, PHP 8.4.24 / Bash 5.2.37; no DB or network used | **0 — PASS, 12/12 assertions**: valid synthetic production configuration accepted; missing/weak APP_KEY, debug mode, HTTP APP_URL, insecure cookie, excessive session lifetime, cluster-admin DB username, DB-password placeholder, log mailer, missing SMTP credential rejected; local-mode bypass accepted | `/tmp/berkah-auth-audit/production-env-guard-output.sanitized.txt` contains PASS lines only. Harness is ephemeral, not a committed artifact. |
| `php -l /tmp/berkah-auth-audit/config-sanctum.php` | PHP 8.4.24 | **0 — no syntax errors** | Temporary file reconstructed from tracked config |
| `php -l /tmp/berkah-auth-audit/CentralUserSecurityTest.php` | PHP 8.4.24 | **0 — no syntax errors** | Temporary file reconstructed from tracked test |
| `php -l /tmp/berkah-auth-audit/password-reset-migration.php` | PHP 8.4.24 | **0 — no syntax errors** | Temporary file reconstructed from tracked migration |
| `python3 /tmp/berkah-auth-audit/tests/security/test_sanitize_gitleaks_report.py` | Local container / Python | **0 — 2/2 unit tests passed**; synthetic report input confirms Secret/Match/Raw/author/email fields are not emitted, while rule/path/line metadata remain | Temporary reconstructed test; not an exact GitHub checkout. |
| `python3 -m py_compile /tmp/berkah-auth-audit/scripts/security/sanitize_gitleaks_report.py /tmp/berkah-auth-audit/tests/security/test_sanitize_gitleaks_report.py` | Local container / Python | **0 — PASS** | Temporary reconstructed copies of the branch files. |
| Laravel/PHPUnit integration suite | This local harness has no repository checkout or installed Laravel vendor tree | **NOT RUN** | No local PHPUnit artifact |
| Gitleaks full-history scan | GitHub-hosted CI | **Prior scans FAILED; post-final-allowlist scan QUEUED** | Run 39281549803 scanned 1,603 commits and reported 31 matches; run 39282823359 after 30 exceptions reported the archived SQL MD5 guard at line 663. Direct blob review confirmed it as a deterministic keyset checksum and exception 31 was added. Run 39283367189 was QUEUED at the last status check; no post-final-allowlist clean result is claimed. |

These supplemental tests do not exercise a built production image, Laravel boot, PostgreSQL, actual token issuance/expiry, auth endpoints, logs, reset/replay, or MFA. `shellcheck` was **NOT RUN** because it is not installed locally.

## 7. Rotation and incident-response runbook

**Safety boundary:** This is a procedure only. No real secret rotation, mailbox/domain change, token mass-revocation or production resource modification was performed. Each real rotation requires owner approval, a named environment, change window, backup/rollback steps and sanitized evidence. Never paste secret values into GitHub, logs, PR text or reports.

### 7.1 Common pre-flight

1. Owner authorizes the exact secret type, environment and service; identify consumers and overlap/expiry constraints.
2. Record a change ticket, impacted deployments/workers, rollback criteria, verification steps and incident contact. Ensure no secret value appears in shell history, process lists, CI logs, docker inspect output, logs, artifacts or chat.
3. Create the replacement in the approved secret manager/provider. Use least privilege and unique per-environment values; overlap credentials only where supported.
4. Apply first to isolated staging with a synthetic account; do positive health/auth tests and negative old-credential/revocation tests. Never copy production data into routine staging tests.
5. Deploy the reviewed configuration/image by reference; restart authorized services/workers. Verify behavior and secret-version metadata, never secret values.
6. After the agreed overlap/rollback period, revoke old material at the issuer/provider. Record timestamps, safe version identifiers, owner and sanitized evidence.
7. If acceptance fails, halt rollout and follow rehearsed rollback/forward recovery; do not silently re-enable a compromised secret.

### 7.2 PostgreSQL central/tenant credentials

1. DBA provisions a replacement least-privilege role/password pair under the accepted PostgreSQL design. Never use postgres/superuser credentials for normal Laravel web/queue services.
2. On disposable PostgreSQL 17, verify that the replacement role can access only the intended DB and is denied DDL/role creation and cross-tenant access.
3. Store replacement credentials in the environment-specific secret manager; update correct Coolify service variables without echoing them, then restart affected services.
4. Run readiness and an authenticated canary/read check that exposes no customer data; verify old credentials are rejected after revocation.
5. Revoke old credentials only after all consumers use the replacement. Inventory web, queue, scheduler, migration and tenant services; provisioning/migrator credentials remain separate/private.
6. Keep DBA recovery credentials out of the app environment. No live role/grant change is authorized by this report.

### 7.3 Laravel APP_KEY

1. Inventory all Laravel encryption/signing uses, cookies, sessions, encrypted model/DB fields and stored encrypted secrets. Verify the current key can be recovered from the vault.
2. Plan for invalidation/data impact: changing APP_KEY can invalidate encrypted cookies/sessions and make old encrypted values unreadable. Confirm support for prior-key decryption (APP_PREVIOUS_KEYS if the exact locked Laravel version supports it) before relying on overlap. Otherwise plan explicit re-encryption.
3. Generate a cryptographically random replacement via the reviewed Laravel key-generation mechanism on a trusted host; inject only via secret manager and never commit it.
4. Rehearse in disposable/staging. Validate cookies/sessions, encrypted fields, queues and workers before production.
5. In the approved window, deploy coherently to every instance sharing encrypted state. Force session/token renewal where required; verify health and decryption; keep rollback material secured through the agreed checkpoint.
6. Remove old key material from active config only after verifying dependencies. Do not print either key.

### 7.4 Sanctum tokens and future JWT/signing keys

- Current Laravel baseline uses Sanctum personal access tokens; no JWT implementation or JWT signing key was found in the scoped tree. JWT rotation is **not applicable today**, not implemented.
- For a token compromise, revoke affected or all user tokens using an approved audited server-side procedure; invalidate web sessions if needed and disable the account when warranted. Confirm the old token is rejected. Do not rely on expiry alone.
- If JWT/custom signed API credentials are introduced later, document algorithm, key custody, key ID/kid, issuer/audience/expiry and revocation. Where supported, use a controlled overlap: verifier accepts old and new public keys while issuers sign only with the new key; after maximum token TTL plus clock skew, remove old verifier key and prove old tokens fail. Never place signing keys in Flutter/static HTML.

### 7.5 SMTP credentials

1. Obtain owner approval and use provider rotation controls.
2. Create a new least-privilege SMTP credential where supported; update the secret-manager version and restart the Laravel web/queue/worker services that send mail.
3. Send a controlled verification/reset test to an authorized test mailbox. Confirm logs contain neither reset links/tokens, SMTP credentials, nor message payloads.
4. Confirm delivery/provider audit status, then revoke the old credential. Production mail must not use log/array transport.

### 7.6 Third-party API keys

1. Inventory the provider, scope, consumers and billing implications; ask the credential owner to create a replacement with minimal scope.
2. Validate the new key in staging and confirm only intended API calls are possible. Use a short overlap only if provider supports it.
3. Update production secret manager under an approved change, restart consumers, perform a low-risk canary and inspect provider-side audit events.
4. Revoke old key after consumer verification. If overlap is impossible, schedule a coordinated cutover and agree rollback first.
5. For legacy Supabase client material, the current owner policy prohibits project access/use. Do not test or rotate it from this workstream; route retirement to authorized mobile/static-admin owners and use only the provider’s separately authorized account procedure if the owner explicitly directs it.

### 7.7 Mobile signing/upload key material

- Inspect key aliases, expiry/fingerprint and custody via approved release tooling without printing private key material. Signing certificate identity is a release contract; casual rotation may break updates.
- Follow the owner-authorized Google Play App Signing/upload-key reset process if compromise/scheduled replacement warrants it. Preserve an encrypted restricted backup and rehearse recovery.
- Treat BERKAH_UPLOAD_* only as metadata in the change record. Never output values in logs/artifacts. The mobile release and signing-certificate scope belongs to the release workstream.

## 8. Cross-workstream dependencies and residual risk

1. **Laravel/API owner:** implement login/logout, reset-token table/notification flow, verification, throttling, authorization middleware/policies, active-user enforcement, audit events and token issue/revoke contract; feature-test against isolated PostgreSQL 17.
2. **MFA/admin owner:** choose TOTP or passkey policy; implement enrollment/recovery/enforcement and test on isolated staging.
3. **PostgreSQL provisioning/security owner:** prove actual runtime roles/grants and keep privileged credentials out of public web/normal queue services.
4. **Flutter/static-admin migration owner:** replace legacy client authentication with the Laravel API; no Supabase access/fallback.
5. **SRE/operations owner:** inject unique per-environment secrets, configure HTTPS/Secure cookies/trusted proxies, secret-manager access/audit, redacted logs and token-expiry monitoring. Confirm the entrypoint is used by every web/worker service in deployment.
6. **Independent QA/reviewer:** obtain exact-candidate-SHA CI evidence, full Gitleaks output, auth negative tests, session/revocation tests, MFA staging evidence and independently review the remediation.

Residual risk remains significant: no production/staging auth runtime was available; login/reset/verification/MFA/revocation endpoints are absent; full-history scan and regression test result were queued at authoring; log redaction was not exercised; no secret rotation occurred.

## 9. Current evidence snapshot (continuation)

- Base SHA: `371b7fdf0bf672b37ceb1023e647f114221bf797`; the branch is dedicated, ahead of main and open/unmerged.
- Run 39281549803 (workflow #232, attempt 1) tested PR merge-ref SHA `a0720108359e1b01b3e26937e80dfc4b21982ae4`: 1,603 commits / ~12.89 MB, 31 findings, exit 1. Sanitized metadata was available in the job log.
- Run 39282823359 after 30 precise exceptions scanned 1,606 commits / ~12.90 MB and reported one match. Direct blob review (blob `c071e2ffd7bf135d1d269d311699a87d5a4f0ac0`) confirmed line 663 is an MD5 keyset-integrity guard for the canonical 352-entry workbook. The 31st exact exception was added in `.gitleaksignore` commit `5cd6ce2a4df10ecab67af5f8f0685a19d374dfda`.
- Latest post-final-allowlist workflow run observed, `39283367189`, was still QUEUED at the latest check. No clean scan is claimed until a completed scan is matched to its tested SHA and sanitized output confirms no findings.
- Local harness evidence: shell syntax checks exited 0; three PHP lint checks exited 0; production-env guard exited 0 with 12/12 synthetic assertions; sanitizer tests exited 0 with 2/2 passing; Python `py_compile` exited 0. These do not execute Laravel/Composer/DB, issue tokens, test MFA or validate a built production image.

## 10. Final recommendation

**BLOCKED — not PASS.** This branch contains scoped startup/secrets/token-expiry hardening and a draft PR, but it does not close the missing authentication lifecycle, MFA, revocation, reset/verification and abuse-protection gates. Do not deploy as production auth, do not rotate secrets based only on this audit, do not merge without review, and do not claim a test or scan passed until exact-SHA CI logs confirm it.
