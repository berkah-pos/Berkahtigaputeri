# Reconstructed staging schema baseline

**Status: reconstructed from live staging catalog; disposable clean replay pending. Not historical SQL.**

This directory contains a schema-only reconstruction of the current staging catalog for local replay in GitHub-hosted CI. It is deliberately outside `supabase/migrations/`, because it is a final-state snapshot and not a trustworthy substitute for 139 missing historical migration files.

## Files and ordering

The clean-replay workflow assembles these fragments into one temporary migration, in this exact order:

1. `010_tables_and_sequences.sql` — 67 app tables, identity columns, the explicit serial sequence, and prerequisite extensions.
2. `020_constraints_and_indexes.sql` — 615 constraints, 49 non-constraint indexes, and sequence ownership.
3. `030_plpgsql_01.sql` through `030_plpgsql_13.sql` — 147 PL/pgSQL function definitions copied from `pg_get_functiondef`.
4. `031_sql_functions.sql` — 22 SQL-language functions.
5. `040_rls_policies_and_triggers.sql` — source RLS flags, 42 policies, and 49 non-internal triggers.
6. `050_object_acl.sql` — direct object grants reconstructed from catalog ACL arrays.
7. `060_target_default_privilege_hardening.sql` — reviewed *target-only* hardening deltas, including RLS on `private.tenant_accounting_links`, two additional policies, reduced anonymous sequence/trigger utility access, and least-privilege defaults for future objects.

`source-catalog-fingerprint.json` is the read-only source reference for relation, routine, policy and trigger structure. `replay_validation.test.sql` contains disposable pgTAP assertions. `config.toml` is local-only and is not linked to either remote project.

## Evidence boundary

A green replay proves the assembled schema can be created from an empty disposable Supabase database and compared against the selected staging catalog with only the documented target deltas. It does **not** recover the original migration order, recreate row data, prove historical SQL bodies, restore pg_cron jobs, certify the staging-clone, or substitute for hostile two-tenant runtime tests and backup/restore evidence.

Do not move these files into `supabase/migrations/`, run them against staging/clone/production, or use `migration repair` as a way to make history appear reconciled.
