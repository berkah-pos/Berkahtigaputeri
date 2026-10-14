# Recovered SQL source candidates — 2026-10-14

These files were recovered from the reachable feature branch `feat/berkah-pos-play-compliance-20261011` at commit `ef87eb76225faf1d56a8d2a49d53de95c56ca9b8` in the primary repository. Candidate payloads are preserved outside `supabase/migrations/` so Supabase CLI cannot automatically apply them as a production migration set.

## Safety and identity

- These are **candidate sources**, not certified originals of any remote-applied migration.
- Supabase's remote migration registry records version/name metadata, not SQL-body checksums. Similar filenames or intent do not prove the contents are the same as SQL historically applied.
- Do not move these files into the active migrations folder, change remote migration history, or apply them to either existing project without exact-source provenance, a reviewed schema baseline, and a passing disposable replay.
- `core.sql` was also found on the source branch, but its blob SHA is `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` and its content size is **0 bytes**; it is not a usable bootstrap schema.
- `verify_tenant_links_rls.sql` is a verification script, not an applied migration. It is preserved under `verification/`.

## Provenance table

| Archived file | Source blob SHA | Original source |
|---|---|---|
| `20261009163000_stress_journal_invariants.sql` | `9804ace132fb5b9d2b505e819e2b2c0052a62cd1` | [supabase/migrations/20261009163000_stress_journal_invariants.sql](https://github.com/berkah-pos/Berkahtigaputeri/blob/feat/berkah-pos-play-compliance-20261011/supabase/migrations/20261009163000_stress_journal_invariants.sql) |
| `202610100002_fix_rls_tenant_links.sql` | `69e8369759d51e6526827c700191144d81da3db4` | [supabase/migrations/202610100002_fix_rls_tenant_links.sql](https://github.com/berkah-pos/Berkahtigaputeri/blob/feat/berkah-pos-play-compliance-20261011/supabase/migrations/202610100002_fix_rls_tenant_links.sql) |
| `202610100004_fix_atomic_posting.sql` | `89cd7e54fa602b87aa361d506b9edd7ef94e702b` | [supabase/migrations/202610100004_fix_atomic_posting.sql](https://github.com/berkah-pos/Berkahtigaputeri/blob/feat/berkah-pos-play-compliance-20261011/supabase/migrations/202610100004_fix_atomic_posting.sql) |
| `staging_clone_rls_test_helpers.sql` | `11f581343a48366bd8da90097ac6671f52410bcf` | [supabase/migrations/staging_clone_rls_test_helpers.sql](https://github.com/berkah-pos/Berkahtigaputeri/blob/feat/berkah-pos-play-compliance-20261011/supabase/migrations/staging_clone_rls_test_helpers.sql) |
| `verify_tenant_links_rls.sql` | `9524b6451ff4b3a04f7c252b61e8dc270619d0d2` | [supabase/migrations/verify_tenant_links_rls.sql](https://github.com/berkah-pos/Berkahtigaputeri/blob/feat/berkah-pos-play-compliance-20261011/supabase/migrations/verify_tenant_links_rls.sql) |

The archive is evidence preservation only. It is not proof of a clean schema replay.
