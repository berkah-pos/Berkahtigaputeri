# DOC_17 — Supabase Source Recovery and Disposable Clean Replay

**Status:** REMOTE SQL BODIES RECOVERED; 139-BODY STAGING AND 12-BODY CLONE DISPOSABLE REPLAYS PASS; HOSTED ACL DRIFT BLOCKS CERTIFICATION  
**Captured:** 2026-10-14  
**Scope:** GitHub SQL provenance, read-only recovery from hosted migration ledgers, reconstructed staging schema, and isolated replay acceptance.  
**Authority:** Follow `AGENTS.md`, `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`, `DOC_00_MASTER_ROADMAP.md`, `DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md`, and `DOC_16_SUPABASE_MIGRATION_RECONCILIATION.md`.

## 1. Decision and safety boundary

The complete original migration SQL sequence was not present in the two reachable Git repositories. A second read-only recovery path succeeded: each project’s internal `supabase_migrations.schema_migrations.statements[1]` stores the SQL body associated with its version/name registry entry. All 139 staging bodies and 12 staging-clone bodies have been retrieved and archived with per-body SHA-256 and UTF-8 byte-count checks.

This does **not** authorize a migration, repair, reset, grant/revoke, or deployment on any hosted project. Historical replay tests run only in a fresh disposable local Supabase instance.

## 2. Git source search versus remote-body recovery

The source search covered the primary repository `berkah-pos/Berkahtigaputeri` (19 reachable branches), mirror `Andisatriawan/Berkahtigaputeri` (one reachable branch), main-line migration history, current migration directories, feature branches, and SQL-bearing documentation/test artefacts.

The active migration directory contains two non-exact historical candidates plus one new forward-only Phase 6 correction. The third file is not claimed to be recovered from either remote history:
- `20261008131700_p0_rls_identity_config_runtime_prep.sql`, blob SHA `07768fe035fec700b9b836b65f8a15657a9e4fe5`; its staging registry entry is version `20261008131537`, so it is not an exact Git/version match.
- `20261013120000_phase5_tenant_isolation_hardening.sql`, blob SHA `e4b487e66e041025e1d56796428e98826855b506`; staging and clone versions are `20261013085934` and `20261013085912`.
- `20261014201000_phase6_atomic_versioning_legacy_tax_compat.sql` is a forward-only fix for unchanged legacy tax keys echoed by full-object Admin saves. It is not a historical body and has not been applied to a hosted project.

Other recovered branch files stay under `supabase/reconciliation/recovered-source-candidates/` as partial candidates, not active migrations. The exact Git historical-source match count therefore remains **0**.

## 3. SQL recovered from the hosted migration registries

Archive: `supabase/reconciliation/recovered-remote-migration-statements-2026-10-14.json`  
Archive Git blob SHA: `c071e2ffd7bf135d1d269d311699a87d5a4f0ac0`

| Registry | Bodies | UTF-8 bytes | Result |
|---|---:|---:|---|
| Staging, PostgreSQL 17.6 | 139 | 926,910 | All bodies recovered |
| Staging-clone, PostgreSQL 17.11 | 12 | 61,346 | All bodies recovered |
| **Total** | **151** | **988,256** | Version/name and body-integrity checks pass |

Each registry row had one non-empty SQL entry in its `statements` array. The archive retains the recorded environment, version, name, exact SQL body, byte length, and SHA-256. The archive checker compares every archived version/name to the captured remote registry manifest and verifies body checksums. No high-confidence private-key/JWT/provider-secret/credential-URI pattern was found; long literal matches were reviewed in context and were application SQL/error strings. No business-row snapshots or tenant/device table dumps are included.

Important distinction: the **Git checkout** lacks exact historical blobs; the recorded SQL bodies were recovered from the live migration ledgers. Preserve both facts.

## 4. Reconstructed current target schema

The separately reconstructed schema-only target is in `supabase/reconciliation/reconstructed/staging-baseline/`, outside the active migration directory. Its reference comes from read-only PostgreSQL catalog introspection of staging.

| Structural inventory | Staging reference |
|---|---:|
| Application relations/tables in audited schemas | 67 |
| Constraints, including deferred constraint triggers | 615 |
| Non-constraint indexes | 49 |
| Functions | 169 (147 PL/pgSQL, 22 SQL-language) |
| Source RLS policies | 42 |
| Non-internal triggers | 49 |
| Tables with source RLS enabled | 66 of 67 |

This reconstructed target was initially verified on PR #39 and was re-run from the consolidation branch with expanded tests:
- [Current disposable clean replay run 38629812613](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629812613): **success** with Phase 6 implementation.
- Baseline and Tenant A/B tests: **50 pgTAP tests across 2 files, PASS**.
- Atomic-versioning RPC suite: **19 pgTAP assertions, PASS** after applying the forward fix to the disposable target only.
- Structural fingerprint comparison passed for relations, 169 routine definitions/security modes, 42 source policies, and 49 triggers under documented target-only deltas.
- The temporary local stack stopped successfully.

The target overlay deliberately enables RLS on `private.tenant_accounting_links`, adds a deny-all `anon` policy and an active-accounting-membership SELECT policy, revokes `anon`/`PUBLIC` EXECUTE on two trigger-helper functions, and hardens default privileges. These are forward-target changes, not historical statements.

## 5. Historical replay and external preconditions

The first replay of the 139 recorded staging SQL bodies in a fresh local database reached `20261004013605_p1_complete_pilot_device_relations`, then failed because `public.licences.toko_address` did not exist. The preceding recorded migration `20261003142407_admin_licence_config` uses `CREATE TABLE IF NOT EXISTS public.licences` with an older `address` column, while the next migration inserts/selects `toko_address`. The applied ledger therefore begins after some legacy schema existed out-of-band or in a pre-ledger setup step.

A schema-only bootstrap `supabase/reconciliation/historical-replay-bootstrap/20260929000000_legacy_licences.sql` is applied before the **139 unchanged staging migration bodies** in the disposable runner. The first replay established that `public.licences` also predates the ledger. A second replay reached `20261007184231_p1_cfg_01_config_5layer_strict_role` but failed because only five `app_config` rows existed and the recorded invariant requires exactly 352 canonical workbook keys (MD5 `1fd3d64219ecc7c333453c20da80e295`). Those rows are initialized by the canonical workbook sync outside the ledger, so a runner-only fixture is used; no workbook values are committed to the repository.

The workflow uses `scripts/prepare_supabase_historical_replay_fixtures.py` to load and validate the workbook using the same parser as the production dry-run. In the isolated runner only, it generates a temporary migration `20261007180000_replay_only_canonical_config_fixture.sql` between recorded migrations `20261007073026` and `20261007184231`; it seeds the 352 canonical `app_config` key/value rows at version 1 and inserts the recorded Auth guard identity with an empty password, unconfirmed email, and no session/token. The generated SQL/value rows stay in the runner's temporary directory and are not committed or emitted to logs. The latest verified combined run [38629812613](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629812613) passed the reconstructed target, exact staging historical replay, and separate staging-clone replay. The historical job applies all 139 archived staging migration bodies unchanged, with a runner-only canonical 352-key workbook fixture and a separately labelled schema-only pre-history bootstrap for `public.licences`, `public.app_config`, and `public.client_status`. The final read-only comparison passes for all 67 staging relations, their RLS flags and DDL fingerprints, all 169 routine definitions/security modes, 42 source policies, and 49 triggers. Earlier pre-history shape mismatches are resolved by the disposable bootstrap; no historical migration body was patched, and no hosted database was written. This proves staging schema replay against the captured catalog, not clone equivalence, data restore, extension-version parity, cron-job parity, or production readiness.

## 6. Replay workflow and remaining gates

Workflow: `.github/workflows/supabase-reconstructed-clean-replay.yml`.

The workflow runs reconstructed-target replay first, then the pre-history scaffold plus the exact staging SQL bodies in a separate disposable local Supabase project. The historical job verifies archive hashes, materializes the 139 staging bodies in version order, applies them locally, and compares relation/constraint/index fingerprints, routine definitions/security modes, RLS flags, policies, and triggers to the read-only staging reference.

- [x] Exhaustive reachable-Git source search and candidate provenance recorded.
- [x] All 139 staging and 12 clone SQL bodies recovered and SHA-256-verified.
- [x] Reconstructed target schema replay, 50 baseline/Tenant A-B pgTAP tests, 19 atomic-versioning pgTAP assertions, and structural comparison passed.
- [x] Initial historic replay failure diagnosed as a missing pre-history `public.licences` schema and represented by a separately labelled bootstrap.
- [x] Second replay failure diagnosed as a required 352-key canonical workbook inventory and represented by a generated runner-only fixture.
- [x] Bootstrap + workbook fixture + all 139 original staging migration bodies apply cleanly in a fresh disposable database.
- [x] Expanded schema-only pre-history bootstrap plus all 139 unchanged staging bodies passes exact structural fingerprint comparison in disposable replay (run 38629812613).
- [x] All 12 unchanged staging-clone bodies replay with clone-specific pre-history; 37 pgTAP tests and clone catalog fingerprint comparison pass in run 38629812613.
- [x] Read-only staging-clone drift inventory recorded; clone-specific disposable clean replay and clone-to-clone structural comparison pass. [ ] ACL/privilege remediation remains open because broad effective anon grants are observed.
- [ ] Tenant A/B hostile runtime tests, outbox/idempotency end-to-end tests, restore drills, disposable load/resilience tests, independent review, and explicit release approval.


## 7. Staging-clone drift inventory

The staging and staging-clone catalogs were compared read-only on 2026-10-14. Exact counts, object identifiers, fingerprints, and gate notes are kept in `supabase/reconciliation/staging-clone-drift-2026-10-14.json`.

| Catalog surface | Staging | Staging-clone | Difference requiring review |
|---|---:|---:|---|
| Relations | 67 | 71 | Four clone-only relations; three constraint fingerprints and one index fingerprint differ; one RLS flag differs |
| Functions | 169 | 134 | 39 staging-only signatures, four clone-only helpers, one shared body fingerprint differs |
| RLS policies | 42 | 42 | Same count does not mean same set: two staging-only and two clone-only policies, plus one changed fingerprint |
| Non-internal triggers | 49 | 41 | Eight staging triggers are absent from clone |
| Extensions | 6 | 5 | `pg_cron 1.6.4` exists on staging but not clone |

The privilege difference is more material than object counts: read-only catalog checks show 116 shared routine signatures differ in effective `anon` EXECUTE and 79 differ for `authenticated`. The clone has effective `anon` SELECT on 55 application relations and effective INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER on 54 each; staging has none of those effective application-table privileges in the inspected schemas. Of the clone's 104 security-definer routines with effective `anon` EXECUTE across the inspected schemas, 32 reside in schemas where `anon` has schema USAGE. These are privilege/catalog findings, not proof that each routine is reachable through a specific API or proof of an exploit; RLS and exposed API schemas need separate review.

**Disposition:** both environment-specific recorded histories now pass disposable replay and their own captured catalog fingerprints. This does not make the clone equivalent to staging or safe for production: broad effective anon ACLs and wider hostile application-surface tests remain open. Do not blindly transplant staging SQL or run a blanket permission rewrite on the hosted clone. No hosted database was modified.

Even after replay passes, this does **not** prove row-data restore, clone equivalence, production tenant isolation, backup recovery, extension-version parity, cron-job parity, or production readiness. Keep the Draft PR unmerged and do not write to an existing hosted Supabase project until each production gate is independently satisfied.


## Phase 6 atomic-versioning compatibility regression

The forward-only migration 20261014201000_phase6_atomic_versioning_legacy_tax_compat.sql allows unchanged legacy tax keys to be echoed by full-object Admin saves and strips them before persistence; new or changed protected tax values still fail with SQLSTATE 42501. Run 38629812613 passed the reconstructed target's 50 baseline/Tenant A-B assertions, 19 atomic-versioning assertions, the 139-body staging replay, and the 12-body clone replay. Backend Foundation CI run 38630659808 also passed after the push trigger was corrected. These are disposable CI results; the forward migration has not been applied to hosted staging or production.
