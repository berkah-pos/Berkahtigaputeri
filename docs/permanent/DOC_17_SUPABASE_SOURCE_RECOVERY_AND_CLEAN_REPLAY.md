# DOC_17 — Supabase Source Recovery and Disposable Clean Replay

**Status:** REMOTE SQL BODIES RECOVERED; TARGET RECONSTRUCTION PASSED; PRE-HISTORY BOOTSTRAP REPLAY PENDING  
**Captured:** 2026-10-14  
**Scope:** GitHub SQL provenance, read-only recovery from hosted migration ledgers, reconstructed staging schema, and isolated replay acceptance.  
**Authority:** Follow `AGENTS.md`, `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`, `DOC_00_MASTER_ROADMAP.md`, `DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md`, and `DOC_16_SUPABASE_MIGRATION_RECONCILIATION.md`.

## 1. Decision and safety boundary

The complete original migration SQL sequence was not present in the two reachable Git repositories. A second read-only recovery path succeeded: each project’s internal `supabase_migrations.schema_migrations.statements[1]` stores the SQL body associated with its version/name registry entry. All 139 staging bodies and 12 staging-clone bodies have been retrieved and archived with per-body SHA-256 and UTF-8 byte-count checks.

This does **not** authorize a migration, repair, reset, grant/revoke, or deployment on any hosted project. Historical replay tests run only in a fresh disposable local Supabase instance.

## 2. Git source search versus remote-body recovery

The source search covered the primary repository `berkah-pos/Berkahtigaputeri` (19 reachable branches), mirror `Andisatriawan/Berkahtigaputeri` (one reachable branch), main-line migration history, current migration directories, feature branches, and SQL-bearing documentation/test artefacts.

Git still contains only two current tracked candidate files in `supabase/migrations/`:
- `20261008131700_p0_rls_identity_config_runtime_prep.sql`, blob SHA `07768fe035fec700b9b836b65f8a15657a9e4fe5`; its staging registry entry is version `20261008131537`, so it is not an exact Git/version match.
- `20261013120000_phase5_tenant_isolation_hardening.sql`, blob SHA `e4b487e66e041025e1d56796428e98826855b506`; staging and clone versions are `20261013085934` and `20261013085912`.

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

This reconstructed target replay passed on PR #39 head `fd442e2307004af6910560726f7f98055972521a`:
- [Disposable target replay run 38523201897](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38523201897): **success**.
- **16 pgTAP assertions passed**.
- Structural fingerprint comparison passed for relations, 169 routine definitions/security modes, 42 source policies, and 49 triggers under documented target-only deltas.
- The temporary local stack stopped successfully.

The target overlay deliberately enables RLS on `private.tenant_accounting_links`, adds a deny-all `anon` policy and an active-accounting-membership SELECT policy, revokes `anon`/`PUBLIC` EXECUTE on two trigger-helper functions, and hardens default privileges. These are forward-target changes, not historical statements.

## 5. Historical replay and the pre-history schema gap

The first unmodified replay attempt used a fresh local database and the 139 exact staging migration bodies. It reached `20261004013605_p1_complete_pilot_device_relations`, then failed because `public.licences.toko_address` did not exist. This is a real pre-history gap—not an archive checksum error and not a runner startup issue.

The preceding recorded migration `20261003142407_admin_licence_config` uses `CREATE TABLE IF NOT EXISTS public.licences` with a legacy column named `address`, while the next migration inserts/selects `toko_address`. In live staging the relation already exists with `toko_address`; the applied ledger therefore begins after some legacy schema already existed out-of-band or in a pre-ledger setup step.

To keep original history untouched, the workflow now adds a separately labelled schema-only pre-history bootstrap `supabase/reconciliation/historical-replay-bootstrap/20260929000000_legacy_licences.sql` before the **139 unmodified recorded staging migrations**. It recreates only the pre-existing `public.licences` schema using the read-only live catalog and known migration deltas; it inserts no rows and does not pre-create the `tenant_id` field, which is added by recorded history. Replay with this scaffold is **pending**. If the next error reveals more absent pre-history prerequisites, document them separately rather than patching original migration bodies.

## 6. Replay workflow and remaining gates

Workflow: `.github/workflows/supabase-reconstructed-clean-replay.yml`.

The workflow runs reconstructed-target replay first, then the pre-history scaffold plus the exact staging SQL bodies in a separate disposable local Supabase project. The historical job verifies archive hashes, materializes the 139 staging bodies in version order, applies them locally, and compares relation/constraint/index fingerprints, routine definitions/security modes, RLS flags, policies, and triggers to the read-only staging reference.

- [x] Exhaustive reachable-Git source search and candidate provenance recorded.
- [x] All 139 staging and 12 clone SQL bodies recovered and SHA-256-verified.
- [x] Reconstructed target schema replay, 16 pgTAP assertions, and structural comparison passed.
- [x] Initial historic replay failure diagnosed as a missing pre-history `public.licences` schema.
- [ ] Pre-history scaffold plus all 139 original staging migration bodies replay cleanly.
- [ ] Exact structural fingerprint comparison passes after historic replay.
- [ ] Clone-only relation/routine/ACL drift has a separate reviewed reconstruction and verification plan.
- [ ] Tenant A/B hostile runtime tests, outbox/idempotency end-to-end tests, restore drills, disposable load/resilience tests, independent review, and explicit release approval.

Even after replay passes, this does **not** prove row-data restore, clone equivalence, production tenant isolation, backup recovery, extension-version parity, cron-job parity, or production readiness. Keep the Draft PR unmerged and do not write to an existing hosted Supabase project until each production gate is independently satisfied.
