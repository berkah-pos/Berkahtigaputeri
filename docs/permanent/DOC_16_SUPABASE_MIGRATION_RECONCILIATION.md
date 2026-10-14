# DOC_16 — Supabase Migration and Schema Reconciliation Ledger

**Status: BLOCKED — staging's 139-body replay and staging-clone's 12-body replay both pass in disposable local Supabase; targeted RLS and atomic-versioning assertions pass. Hosted ACL drift, broader adversarial coverage, restore/resilience and release approval remain open.**
**Captured:** 2026-10-14; exact snapshot time is recorded in the JSON ledger.
**Repository:** `berkah-pos/Berkahtigaputeri`
**Working branch:** `chore/consolidate-single-main-repo`
**Related work:** [PR #39](https://github.com/berkah-pos/Berkahtigaputeri/pull/39), [audit issue #40](https://github.com/berkah-pos/Berkahtigaputeri/issues/40)
**Machine-readable ledger:** [remote-migration-ledger-2026-10-14.json](../../supabase/reconciliation/remote-migration-ledger-2026-10-14.json)
**Repeatable read-only SQL:** [catalog_fingerprint.sql](../../supabase/reconciliation/catalog_fingerprint.sql)

## 1. Decision

Read-only migration history has been recovered from both remote ledgers. Staging's 139 recorded migration bodies and staging-clone's 12 recorded bodies each replay unchanged in their respective disposable environments and match their captured catalog fingerprints. The reconstructed staging target passes 50 baseline/Tenant A-B pgTAP tests plus 19 atomic-versioning assertions. **Overall migration reconciliation remains blocked** because staging-clone's privilege model differs materially, broader hostile cross-surface tests are incomplete, and restore/resilience/release gates remain open. Do not run `supabase db push`, `supabase migration repair`, or `supabase db reset` against either existing remote project. Do not create empty migration files, rename files solely to match remote timestamps, or bulk-revoke/grant execution to silence advisor findings.

The connected project inventory currently exposes staging and staging-clone. No production project was positively identified. The two staging projects are not interchangeable schema replicas.

## 2. Migration registry versus Git

| Source | Migration-history rows / tracked SQL files | PostgreSQL |
|---|---:|---|
| Supabase staging | **139** applied-history rows | 17.6 |
| Supabase staging-clone | **12** applied-history rows | 17.11 |
| Git `supabase/migrations/` | **3** SQL files | Local CLI config targets PG 17 |

**There are zero exact version-prefix matches** between the tracked SQL filenames and the remote applied versions captured. The source files are only semantic candidates for two remote entries, with different timestamps (and a different P0 recorded name):

| Tracked file | Possible staging record | Possible clone record | Finding |
|---|---|---|---|
| `20261008131700_p0_rls_identity_config_runtime_prep.sql` | `20261008131537 / p0_rls_identity_config_runtime_prep_20261008` | No P0 record found | Same concept does not prove identical SQL; clone registry lacks this entry |
| `20261013120000_phase5_tenant_isolation_hardening.sql` | `20261013085934 / phase5_tenant_isolation_hardening` | `20261013085912 / phase5_tenant_isolation_hardening` | Same stem, different version prefixes; replay equivalence not proven |

Follow-up Git provenance review on 2026-10-14 confirmed that the P0 candidate blob `07768fe035fec700b9b836b65f8a15657a9e4fe5` exists in [commit `d8cd93f`](https://github.com/berkah-pos/Berkahtigaputeri/commit/d8cd93f3a307fdde730d265c739d664ffd7c8574), and the Phase 5 candidate blob `e4b487e66e041025e1d56796428e98826855b506` exists in [commit `dfcc4f6`](https://github.com/berkah-pos/Berkahtigaputeri/commit/dfcc4f60fda442bb8fc24bafe4f6696f575e8dae). These remain non-exact Git candidates. A separate read-only inspection of the underlying `supabase_migrations.schema_migrations.statements[1]` recovered all 151 recorded SQL bodies: staging 139 bodies (926,910 bytes) and staging-clone 12 (61,346 bytes), archived with per-body SHA-256 in `supabase/reconciliation/recovered-remote-migration-statements-2026-10-14.json`. Git exact-source matches remain zero; all recorded remote SQL bodies are archived with per-body SHA-256. Staging's ordered replay and schema fingerprint pass on [run 38536536840](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38536536840); clone-specific baseline/replay remains a separate blocked gate.

The Git checkout has two non-exact historical SQL candidates plus one forward-only Phase 6 correction. All 139 staging and 12 clone historical bodies are archived with byte counts and SHA-256. The archive contains migration code only, not business table snapshots, tenant/device rows, or app_config row data.

## 3. Read-only schema fingerprint comparison

The catalog fingerprint query inspected relation structure (column/constraint/index hashes), routine signatures/body hash/execution ACL, RLS policy fingerprints, triggers, extensions, and hashes of the canonical `app_config` values. It did not return business rows or modify either database.

| Metric | Staging | Staging-clone |
|---|---:|---:|
| PostgreSQL version | 17.6 | 17.11 |
| Relations in audited application schemas | 67 | 71 |
| Routines in `public/private/accounting_private/inventory_private` | 169 | 134 |
| `SECURITY DEFINER` routines | 139 | 113 |
| Public-schema `SECURITY DEFINER` functions callable as `anon` | 0 | 32 |
| Public-schema `SECURITY DEFINER` functions callable as `authenticated` | 45 | 33 |
| RLS policies | 42 | 42 |
| Non-internal triggers | 49 | 41 |
| `app_config` keys | 352 | 352 |
| Tenant/device row counts | 103 / 110 | 2 / 2 |

### Confirmed differences

- `app_config` key-set hash is `1fd3d64219ecc7c333453c20da80e295` in both projects; the ordered key/value fingerprint is `71cbd474ca826c0a3768da2c02621ce9` in both. This demonstrates matching fingerprints for this table only, not full schema or behavioral parity.
- Clone-only relations: `private.pos_outbox`, `public.transaction_type_map`, `public.v_outbox_unacked`, and `public.v_stress_validation`.
- Five shared relation fingerprints differ: `private.tenant_accounting_links` (RLS enabled state), `public.config_history` (indexes), and `public.accounting_journals`, `public.accounting_transaction_evidence`, and `public.extended_withholding_liabilities` (constraints).
- Staging has 39 routine signatures absent from the clone; the clone has four clone-only routine signatures. The whole-routine fingerprint comparison reports **117 shared routine fingerprint differences**. A follow-up catalog comparison separates these: one shared routine body fingerprint differs (`public.create_auto_journal(...)`), while effective EXECUTE flags differ for 116 shared signatures for `anon` and 79 for `authenticated`. Do not interpret the 117 combined fingerprint differences as 117 different function bodies.
- Eight staging triggers are absent from the clone. Policy counts match but policy sets do not: two unique names on each side and one changed policy fingerprint.
- `pg_cron` is installed on staging and absent from staging-clone.

Staging-clone is therefore **not a structurally equivalent replay of staging**. The 103 tenants/110 devices versus 2 tenants/2 devices also shows that the clone has a reduced dataset; it is not proof of production-like data volume.

## 4. Advisor findings that need triage

| Finding | Staging | Staging-clone |
|---|---:|---:|
| RLS enabled with no policy (INFO) | 38 | 40 |
| Unindexed foreign keys (INFO) | 79 | 80 |
| SECURITY DEFINER callable as `anon` (catalog) | 0 | 32 |
| SECURITY DEFINER callable as `authenticated` (Advisor) | 45 | 33 |
| Leaked-password protection warning | 1 | 1 |
| Multiple permissive policies (WARN) | 7 | 5 |
| Unused indexes (INFO) | 16 | 23 |

The 32 anonymous-callable public `SECURITY DEFINER` functions on the clone are a **security review gate**. Callable does not itself prove successful exploitation; each function must be reviewed for caller identity, tenant/device ownership, fixed `search_path`, and exact grants. Do not bulk-revoke or create permissive policies without validating valid callers. RLS-enabled/no-policy may be intentional default-deny for internal tables.
 
### Additional effective-privilege catalog triage — staging versus clone
 
A second read-only check used `information_schema.role_table_grants` and `pg_catalog` (2026-10-14):
 
- **Staging:** zero public-table grants to `anon`; two public functions are executable by `anon`, and neither is `SECURITY DEFINER`.
- **Staging-clone:** `anon` has table grants on **54 public relations**, represented by **378 role/table/privilege rows** — all seven privileges (`SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER`) for each relation. All 54 relations have RLS enabled, none was found with RLS disabled, and no policy in the audited `public` schema targets `anon` or `PUBLIC`. This is not evidence that ordinary row-level REST calls can read/write rows; RLS without an applicable policy is default-deny. It is nevertheless **HIGH-priority least-privilege debt**. PostgreSQL explicitly states that RLS does not govern `TRUNCATE` or `REFERENCES`, so blanket grants must not be treated as harmless merely because RLS is enabled ([PostgreSQL 17 row-security documentation](https://www.postgresql.org/docs/17/ddl-rowsecurity.html)).
- The clone exposes 37 public functions to `anon`, including 32 `SECURITY DEFINER` functions. All 34 `public`-schema `SECURITY DEFINER` functions have `search_path = ''`, which is a useful hardening control but does not establish correct caller authorization.
- Four of the 32 anonymously executable `SECURITY DEFINER` function bodies do not directly mention `auth.uid()`: `assert_config_contract()`, `create_self_tax_party_for_config_tenant(...)`, `get_compliance_readiness(uuid,text,text)`, and `get_config_tenant_compliance_readiness(...)`. Source inspection shows the config assertion returns an inventory digest, while the mutating/helper paths delegate into device/member-role checks; those indirect paths still require negative and positive runtime tests under actual JWT/PostgREST contexts. Two payroll tax calculation functions do directly require authenticated identity but are not tenant-specific data access. These text-pattern results are triage, not a substitute for semantic per-function review.
 
Do not apply a broad grant migration to the remote clone as part of this audit. Before any privilege change, inventory intended callers, test legitimate authenticated/service-role flows, prove anonymous table and RPC requests are denied, verify no required public contract breaks, then apply an approved forward-only change to an isolated database and review it. Callable does not itself prove successful exploitation; each function must be reviewed for caller identity, tenant/device ownership, fixed `search_path`, and exact grants. Do not bulk-revoke or create permissive policies without validating valid callers. RLS-enabled/no-policy may be intentional default-deny for internal tables.

The current read-only clone comparison is detailed in [`staging-clone-drift-2026-10-14.json`](../../supabase/reconciliation/staging-clone-drift-2026-10-14.json). It remains a high-priority reconciliation/security review, not an instruction to alter the hosted clone.

## 5. Why filenames cannot solve this

The source files represent only a small part of the live schema surface. Missing migration names do not contain SQL definitions. Marking rows applied, renaming files, or replaying approximate matches can conceal drift and repeat security/data changes. Current CI validates source/config contracts; it is not a full database dump, migration replay, tenant-isolation test, or production certification.

## 6. Safe completion sequence

1. **Preserve the verified staging replay.** The run on 2026-10-14 applied all 139 recorded staging migration bodies byte-for-byte unchanged in a fresh disposable local Supabase database, with a runner-only canonical 352-key workbook fixture and explicitly labelled pre-history schema bootstrap. The final read-only comparator passed against the captured staging catalog. Do not edit recorded bodies or move the replay-only fixture/bootstrap into active migrations.
2. **Reconcile staging-clone independently.** The 12 recorded clone SQL bodies have now replayed unchanged with a clone-specific disposable pre-history scaffold and passed the captured clone catalog fingerprint and 37 pgTAP assertions in run 38629812613. Use the clone-drift inventory to classify clone-only relations/helpers, constraint/index changes, policy differences, and missing pg_cron. Matching clone-to-clone fingerprints do not imply equivalence to staging or security approval.
3. **Review privileges object-by-object.** Staging-clone has broad effective `anon` table privileges and material routine EXECUTE differences. Inventory actual callers, exposed schemas, direct/PUBLIC grants, function auth/device/member checks, and required PostgREST contracts before proposing a forward-only ACL migration. Do not mass-revoke or grant permissions on either hosted database.
4. **Extend hostile isolated tests.** Targeted reconstructed-target pgTAP assertions now prove Tenant A/B effective-config isolation, cross-tenant device rejection and service separation. Still prove the wider cross-read/cross-write matrix through direct REST, reports, accounting/inventory operations, storage, subscriptions and write RPCs; verify outbox/idempotency and tenant-accounting-link behavior.
5. **Restore and resilience gates.** Run a separate backup/restore drill, migration failure/retry validation, and representative load/resilience tests in disposable environments. Record exact commit, workflow IDs, SQL/test counts, and any remaining limits.
6. **Approval and remote rollout.** Keep the Draft PR unmerged and keep remote `db push`, migration repair/reset, grant/revoke, and deployment prohibited until clone reconciliation, tenant isolation, restore/load, and independent review pass. Production has not been positively identified or authorized.

## 7. What actually ran / changed

- Read-only operations re-run on 2026-10-14: migration registries, the committed `catalog_fingerprint.sql` against both project IDs, and Supabase Security/Performance Advisors. Counts and object diffs were recalculated; no writes were performed.
- No database writes: no DDL, migration apply, migration repair, reset, row modifications, grants/revokes, or high-volume stress workload.
- Repository changes on this Draft PR: this evidence ledger, full machine-readable migration registries and fingerprints, read-only SQL, and a validator.
- Status remains **BLOCKED** for overall reconciliation, not for disposable replay. Run 38629812613 passed the reconstructed target (50 pgTAP tests plus 19 atomic-versioning assertions), the 139-body staging replay, and the 12-body clone replay with their respective catalog comparisons. No hosted DDL, migration, grants/revokes, config sync or production action was performed. Clone's broad anon grants, wider hostile testing, backup/restore, load/resilience, independent review and release approval remain open.

## References

- [Supabase CLI — database dump](https://supabase.com/docs/reference/cli/supabase-db-dump)
- [Supabase CLI — pull remote schema](https://supabase.com/docs/reference/cli/supabase-db-pull)
- [Supabase security linter: SECURITY DEFINER executable](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
- [Supabase security linter: RLS enabled without policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)


## Phase 6 addendum — atomic config versioning

The consolidation branch now contains a forward-only migration, 20261014201000_phase6_atomic_versioning_legacy_tax_compat.sql, fixing the case where the Admin echoes unchanged protected legacy tax keys while saving the full tenant object. Changed/new protected tax fields are still rejected; unchanged keys are stripped before persistence. Run 38629812613 passed the real-RPC 19-assertion suite in disposable local Supabase. This migration has not been applied to a hosted project.
