# DOC_17 — Supabase Source Recovery and Disposable Clean Replay

**Status:** RECONSTRUCTED TARGET SCHEMA REPLAY PASSED; HISTORICAL SOURCE RECOVERY BLOCKED  
**Captured:** 2026-10-14  
**Scope:** GitHub SQL source recovery, current staging catalog reconstruction, and isolated replay acceptance.  
**Authority:** Follow `AGENTS.md`, `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`, `DOC_00_MASTER_ROADMAP.md`, `DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md`, and `DOC_16_SUPABASE_MIGRATION_RECONCILIATION.md`.

## 1. Decision

The complete historic applied-migration source is not available in the two reachable Git repository sources. A schema-only final-state snapshot has therefore been reconstructed from read-only PostgreSQL catalog definitions on staging and is being tested only on an isolated local Supabase project.

These are separate deliverables:

- **Historical source recovery:** still **BLOCKED**. The registry stores version/name metadata rather than historical SQL body checksums; no candidate may be claimed exact by filename or intent.
- **Reconstructed state snapshot:** created in `supabase/reconciliation/reconstructed/staging-baseline/`, intentionally outside the active migration folder. The disposable clean replay, 16 pgTAP assertions, and staging structural-fingerprint comparison have now passed on PR #39 head `fd442e2307004af6910560726f7f98055972521a`.
- **Target architecture hardening:** two additional tenant-accounting policies, RLS enablement for the tenant-accounting link table, and least-privilege default ACLs are explicit *reconstruction deltas*, not assertions about what was historically deployed.

No existing remote database has been written, repaired, reset, or migrated during this recovery.

## 2. Repository search and provenance

The exhaustive reachable-source sweep covered:

- Primary repository: `berkah-pos/Berkahtigaputeri`, 19 reachable branches.
- Mirror copy: `Andisatriawan/Berkahtigaputeri`, its single reachable branch.
- Main-line Git history for `supabase/migrations/`, both current migration directories, extra SQL-bearing feature branches, and SQL in permanent documentation/test artifacts.
- The older alias `berkah-ajb-dev/Berkahtigaputeri` did not resolve as a repository.

The current `main` and mirror copies hold the same two candidate migration blobs:

| Tracked file | Blob SHA | Classification |
|---|---|---|
| `20261008131700_p0_rls_identity_config_runtime_prep.sql` | `07768fe035fec700b9b836b65f8a15657a9e4fe5` | Candidate only; remote staging version is `20261008131537`, not exact |
| `20261013120000_phase5_tenant_isolation_hardening.sql` | `e4b487e66e041025e1d56796428e98826855b506` | Candidate only; remote versions are `20261013085934` and `20261013085912`, not exact |

Five further SQL files recovered from `feat/berkah-pos-play-compliance-20261011` have been byte-preserved under `supabase/reconciliation/recovered-source-candidates/`: stress journal invariants, tenant-accounting-link RLS adjustment, atomic journal posting, clone RLS test helpers, and a verification script. The last is a verification artifact, not a migration. The branch's `core.sql` file was 0 bytes and is not a bootstrap schema. Archived source blobs are SHA-1-checked by `scripts/check_supabase_source_recovery.py`.

The entire remote registries remain:

| Environment | Registry rows | Candidate but not exact | SQL source missing | Exact SQL + version matches |
|---|---:|---:|---:|---:|
| Staging | 139 | 2 | 137 | 0 |
| Staging-clone | 12 | 7 | 5 | 0 |

The full per-version inventory is recorded in `supabase/reconciliation/source-recovery-manifest-2026-10-14.json`. The search did not recover the complete 139/12 ordered SQL histories. Do not repair version history to hide this fact.

## 3. Staging-catalog reconstruction

The read-only source is staging project `cztlmwzfrhyafgawphgw`, PostgreSQL 17.6. The schema-only reference fingerprint lives at `supabase/reconciliation/reconstructed/staging-baseline/source-catalog-fingerprint.json`.

| Object inventory | Captured source |
|---|---:|
| Application tables/relations in audited schemas | 67 |
| Constraints | 615 |
| Non-constraint indexes | 49 |
| Functions | 169 — 147 PL/pgSQL and 22 SQL-language |
| RLS policies | 42 |
| Non-internal triggers | 49 |
| Tables with RLS enabled | 66 of 67 |
| Explicit non-identity sequence | 1 |

The source snapshot preserves table column/default definitions, constraints, indexes, function definitions, direct object ACLs, policy expressions and trigger definitions. It does not copy business rows, secrets, credentials, `app_config` values, tenant/device seed records, the remote migration ledger, or scheduled-job data.

## 4. Explicit target-only hardening differences

Read-only catalog inspection found `private.tenant_accounting_links` had RLS disabled in staging. The reconstructed target enables RLS and adds two policies:

1. A deny-all policy for `anon`.
2. A membership-scoped SELECT policy for authenticated users, requiring active membership in the referenced accounting tenant.

The target deliberately does **not** grant direct SELECT on this cross-tenant mapping table to `anon` or `authenticated`; the new policy remains defense in depth if a direct-read contract is explicitly approved later. Existing callers and RPCs must be inventoried before any hosted rollout.

The target also revokes anonymous/PUBLIC access to application sequences and two trigger-utility functions that were otherwise callable as `anon` on staging. It clears global and per-schema default grants to `PUBLIC`, `anon`, `authenticated` and `service_role` for future tables, sequences and functions across the application schemas. Newly created objects must receive deliberate explicit grants.

These are forward-looking reconstruction changes for the latest tenant-isolation/least-privilege goal. They are **not described as historic SQL** and have not been applied to remote projects.

## 5. Clean-replay protocol

Workflow: `.github/workflows/supabase-reconstructed-clean-replay.yml`.

1. Validate provenance hashes and expected source/DDL counts.
2. Create a temporary Supabase project under the GitHub runner's temp directory with no linked project ID or credentials.
3. Assemble the schema snapshot and target overlay into a temporary one-file migration.
4. Start local Supabase, clean-reset the local database, and replay the single reconstructed snapshot.
5. Run 16 pgTAP assertions covering table/routine/constraint/policy/trigger counts, RLS, anonymous access, sequence access, and default ACLs.
6. Run the read-only catalog fingerprint query locally and compare against the saved staging fingerprint, allowing only the explicitly listed target deltas.
7. Stop the temporary containers regardless of outcome.

The workflow uses the pinned Supabase CLI release `2.120.0` and has read-only GitHub workflow permissions. It has no remote Supabase token, password, `db push`, `migration repair`, or remote reset step.

A green run is necessary but not sufficient for production release. It proves disposable final-state schema creation, not historical replay, row-data restore, application-level two-tenant behavior, or cross-environment equivalence.


### Verified replay evidence (2026-10-14)

- Current PR head at verification: `fd442e2307004af6910560726f7f98055972521a`.
- Hosted isolated replay: [run 38523201897](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38523201897) — **success**.
- Supabase CLI `2.120.0` binary checksum verified; local PostgreSQL container `17.11.0.004`; no remote project was linked or modified.
- Fresh local reset and reconstructed migration: **pass**.
- pgTAP: **16 tests, all passed**, including table/routine/constraint/policy/trigger counts and anonymous grants/RLS/default-ACL assertions.
- Catalog fingerprint: **pass** — 67 relations, 615 constraints, 49 non-constraint indexes, 169 routine definitions/security modes, 42 source policies, and 49 source triggers matched. The only accepted target deltas are enabling RLS on `private.tenant_accounting_links`, adding two reviewed policies, and revoking the two named trigger-helper anonymous EXECUTE grants.
- Teardown of the disposable stack: **pass**.

The pass proves that the reconstructed target schema can be built cleanly and matches the recorded staging structural fingerprint under the documented deltas. It does **not** prove the missing 139/12 historical migration SQL bodies, clone equivalence, production data restore, application-level tenant isolation end-to-end, extension/cron parity, or release readiness.

## 6. Acceptance gates and remaining blocks

- [x] Exhaustive search of both repositories' reachable branches and migration histories recorded.
- [x] Recoverable SQL candidates preserved outside the active migration path, with source blob provenance.
- [x] Current staging object catalog reconstructed into a schema-only snapshot.
- [x] Reference structural fingerprint captured without exporting business rows.
- [x] Target-only tenant-accounting RLS and least-privilege deltas labelled separately.
- [x] Static source/artifact checker green on current candidate commit.
- [x] Disposable clean replay passes from a fresh database.
- [x] Structural comparison passes against the staging reference with only the documented target deltas.
- [ ] Clone-only relation/routine drift reconciled and replayed independently.
- [ ] Complete historical SQL bodies recovered or formally superseded by a reviewed baseline migration strategy.
- [ ] Tenant A/B hostile runtime tests, transaction/outbox end-to-end tests, backup/restore drills, load tests, and production release approval.

The reconstructed target snapshot has passed clean replay and structural comparison, but clone-specific drift and complete historical SQL recovery remain unresolved. Status is **RECONSTRUCTED TARGET SCHEMA REPLAYED — NOT CERTIFIED**. This does not authorize any hosted database migration or production release.
