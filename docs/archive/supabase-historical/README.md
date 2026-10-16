# Historical Supabase Source Archive

**Status: HISTORICAL / SUPERSEDED — NOT ACTIVE RUNTIME. Do not execute these files.**  
**Source ref:** `main` at `e394912f3258a3efcb4bb5900fb84d57e2a27c22`.  
**Selected target (not deployed):** Laravel Central API + PostgreSQL 17, with separate tenant databases/roles, after source identification and reviewed migrations/acceptance.

This directory preserves repository source history removed from the Laravel migration branch. It is an audit/migration archive, not an executable migration path. The archived files must not be invoked by CI, deployment, app runtime, or routine operator procedures. Their historical SQL describes the former Supabase-hosted schema and runtime boundary. It is migration evidence only; do not treat it as a complete live schema dump or execute it unchanged as a target migration. Retaining the files does not certify their historical claims or prove live schema state.

Each archive copy was fetched directly from `main` and stored byte-for-byte. Original Git blob SHAs are recorded for provenance.

| Original `main` path | Archived path | Original blob SHA |
|---|---|---|
| `docs/permanent/DOC_02_FINAL_POS_RELATIONAL_OWNERSHIP.sql` | `docs/archive/supabase-historical/docs/permanent/DOC_02_FINAL_POS_RELATIONAL_OWNERSHIP.sql` | `9586350887a5c7337d58d8a2c6459569c9967631` |
| `docs/permanent/DOC_02_SUPABASE_SCHEMA_V1.sql` | `docs/archive/supabase-historical/docs/permanent/DOC_02_SUPABASE_SCHEMA_V1.sql` | `c557fe0d7cf1fc5ae0bbb58b7bffad5a4b496e85` |
| `docs/permanent/DOC_03_RLS_AUTH.sql` | `docs/archive/supabase-historical/docs/permanent/DOC_03_RLS_AUTH.sql` | `896221b6b861fff0cd2d9a1a4c429c21e7c53cdf` |
| `docs/permanent/DOC_03_RLS_AUTH_FIXED.sql` | `docs/archive/supabase-historical/docs/permanent/DOC_03_RLS_AUTH_FIXED.sql` | `ccbd69487d5d8122ca04962877ec6d4744036f65` |
| `docs/permanent/DOC_03_VERIFICATION.md` | `docs/archive/supabase-historical/docs/permanent/DOC_03_VERIFICATION.md` | `432b0586a324a8395d91a83b57c1243e09a33ba6` |
| `docs/permanent/DOC_05_FEATURE_FLAGS.sql` | `docs/archive/supabase-historical/docs/permanent/DOC_05_FEATURE_FLAGS.sql` | `d0c061eb3124e6cb581aba68a416a06abfdd5c84` |
| `docs/permanent/DOC_06_ATOMIC_VERSIONING_RPC.sql` | `docs/archive/supabase-historical/docs/permanent/DOC_06_ATOMIC_VERSIONING_RPC.sql` | `77f05d5ceeffc1e20df77bb14cd212bd827f6dc6` |
| `docs/permanent/DOC_08_RPC_EFFECTIVE_CONFIG.sql` | `docs/archive/supabase-historical/docs/permanent/DOC_08_RPC_EFFECTIVE_CONFIG.sql` | `90386fe12b939fa3c1d7cc2b836797310a2409fd` |
| `supabase/migrations/20261008131700_p0_rls_identity_config_runtime_prep.sql` | `docs/archive/supabase-historical/supabase/migrations/20261008131700_p0_rls_identity_config_runtime_prep.sql` | `07768fe035fec700b9b836b65f8a15657a9e4fe5` |
| `supabase/migrations/20261013120000_phase5_tenant_isolation_hardening.sql` | `docs/archive/supabase-historical/supabase/migrations/20261013120000_phase5_tenant_isolation_hardening.sql` | `e4b487e66e041025e1d56796428e98826855b506` |
| `supabase/tests/tenant_isolation.test.sql` | `docs/archive/supabase-historical/supabase/tests/tenant_isolation.test.sql` | `d79c0914f2a69396707353edbab09f53c82d5e84` |

## Active-path boundary

The SQL documents, migrations and pgTAP test above are relocated outside the active `supabase/migrations/` path, so a routine Supabase CLI migration command in this branch cannot pick them up as active migrations. The Laravel target does not use legacy Supabase RPC/RLS/Edge Function paths.

Other deleted operational scripts and the legacy Edge Function are intentionally outside this SQL/schema/migration restoration scope. They remain absent from the active branch and are not represented as migrated, retired in a hosted environment, or otherwise resolved by this archive.

## Use restrictions

- Read only for schema mapping, historical audit and reviewed migration planning.
- Never add credentials, connection URLs/tokens or production rows while inspecting or testing archived files.
- Do not replay against production or staging. Translate required behavior into Laravel/MariaDB migrations and executable tests after independent review.
- Any future use requires a documented migration mapping, verified backup/rollback plan and explicit environment approval.
