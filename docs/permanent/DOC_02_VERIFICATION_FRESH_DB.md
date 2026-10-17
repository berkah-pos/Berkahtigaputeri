> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> Supabase-era instructions and results below are retained as history only. They are not current acceptance evidence and do not authorize connection to any Supabase project, including read-only access. Never run `scripts/sync_excel_to_supabase.py`, including `--dry-run`.
>
> Current authority: [DOC_00](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](DOC_00_MASTER_ROADMAP.md), [authority map](AUTHORITY_AND_SUPERSESSION_MAP.md). The initial Laravel/PostgreSQL smoke evidence is scoped to exact commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149); current target privilege/API/recovery acceptance remains NOT VERIFIED.
>
> ---
>
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
