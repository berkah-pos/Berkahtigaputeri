# ALL GREEN Loop Audit

## Scope

This audit documents the fail-closed execution contract for Berkah POS clone verification. Source Supabase cztlmwzfrhyafgawphgw is read-only. Target clone txwzhesvcjftybrlhnzs is the only database write target. Git scope is berkah-ajb-dev/Berkahtigaputeri, branch fix/clone-atomic-posting-20261010. Andisatriawan/umkm is out of scope and is never a source or remote deletion target.

## Original bugs addressed

1. Only 8 of 21 required transaction mappings were covered by the earlier contract.
2. A stress test could print PASS after process failure through fallback output such as || echo.
3. A crash test could terminate the parent shell under set -e, obscuring the real SQLSTATE and rollback evidence.
4. An anonymous-role query error could be mistaken for a zero-row result.
5. Restore/retry loops lacked a deterministic attempt limit.
6. Endpoint identity and source/clone aggregate parity were not fail-closed contract checks.

## Fixes in generated assets

- Validate source and clone endpoint identity before queries and writes; never send DDL or write SQL to the source.
- Check count and sorted MD5 for the protected 352-key app_config contract on both projects.
- Compare exact transaction-type/reference pairs, not only row counts, and list mismatches.
- Treat psql errors as failures. A failed anon-role query is never converted to zero.
- Remove the broad tenant_isolation_all policy; create an explicit authenticated membership-scoped SELECT policy using the real accounting_memberships.tenant_id column.
- Grant only the narrow schema usage/table SELECT needed for an anon RLS proof; the deny policy must return zero rows, with no anon write privilege.
- Execute stress only in explicit --full mode and require both the real process exit code and empty validation view.
- Use distinct Terminal A and Terminal B sessions for crash termination; require SQLSTATE 57P01 and zero journal/evidence rows after reconnect.
- Bound retry attempts. Create final verdict and transition PRs only after all six checks pass.
- Carry the required AAB SHA as a provided value, clearly marked as not recomputed by this script.

## Observed baseline on 2026-10-10

These read-only observations are not a GREEN claim:

- Source and clone app_config each have 352 keys and MD5 1fd3d64219ecc7c333453c20da80e295.
- The clone transaction_type_map has 21 rows, but its names/references differ from the supplied manifest. The source does not have public.transaction_type_map.
- Source SUM(accounting_journal_lines.debit) was 502300; clone sum was 30500, a difference of 471800.
- SET ROLE anon followed by SELECT from private.tenant_accounting_links failed with SQLSTATE 42501 due missing schema USAGE. That error is not zero-row evidence.
- Clone CRASH-TEST-001 exists once with journal UUID 21e09fe8-ccd9-4055-9da1-f7ea3d4b20e1.
- Clone v_stress_validation returned zero rows at inspection time; no 50-VU stress run occurred during asset generation.
- The target branch lacked tests/stress/pos-concurrent.js and checked-in schema.sql. The script fails closed when the stress runner is absent and hashes a temporary, read-only source schema-only pg_dump instead.

## Accounting contract boundary

The manifest expects types such as RETUR_JUAL, RETUR_BELI, BIAYA_OPERASIONAL and TRANSFER_KAS; the deployed clone posting function accepts a different set, including RETUR_PENJUALAN, BAYAR_VENDOR and STOCK_OPNAME. Adding mapping labels or translating account rules without compatible posting builders and authorized account semantics does not make the transaction post correctly. Do not guess mappings, alter the protected 352-key contract, or copy source journals into the clone to manufacture parity.

## Closure criteria

All six gates must pass on a single exact execution: (0) source/clone 352-key contract, (1) exact 21 mapping pairs and drained outbox, (2) RLS enabled, successful anon count of zero and proof journal, (3) real 50-VU/600-second stress run and empty validation view, (4) stable idempotency UUID, externally terminated two-session transaction with SQLSTATE 57P01, zero consistency issues and no evidence with null journal ID, and (5) source/clone debit sums plus schema SHA-256 provenance. No all-green verdict is warranted until logs show every gate.
