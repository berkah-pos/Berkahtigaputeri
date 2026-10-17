> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.** This retained document records a legacy Supabase-era workflow, retired implementation contract, or dated verification snapshot. Its commands, SQL, project identifiers, identity claims and “green/certified/current” labels are historical evidence only. Do not follow them against any hosted environment or connect to a Supabase project. Current platform authority: [ADR-2026-10-17 no-Supabase decision](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md). Current target and acceptance: [DOC_14](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md). Current configuration semantics only: [DOC_00](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md). See the [authority/supersession map](../reports/ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md) and [dated audit snapshot](../reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md).

---

# Fresh DB rebuild verification - P0-2 Fix
## Steps to verify fix
1. Create empty Supabase project
2. Run in order:
   - DOC_02_SUPABASE_SCHEMA_V1.sql
   - DOC_02_FINAL_POS_RELATIONAL_OWNERSHIP.sql (now self-contained with ADD IF NOT EXISTS)
   - DOC_03_RLS_AUTH.sql
3. Expected: No error "column user_id does not exist"
4. Before fix: fails at ALTER COLUMN user_id because column missing
5. After fix: passes with ADD COLUMN IF NOT EXISTS

CI: Add job that runs psql -f in order on ephemeral DB
