# ALL GREEN Loop Audit

## Scope

This audit documents the fail-closed execution contract for Berkah POS clone verification. Source Supabase cztlmwzfrhyafgawphgw is read-only. Target clone txwzhesvcjftybrlhnzs is the only database write target. Git scope is berkah-ajb-dev/Berkahtigaputeri, branch fix/clone-atomic-posting-20261010. Andisatriawan/umkm is out of scope and is never a source or remote deletion target.

## Original bugs addressed

1. Only 8 of 21 required transaction mappings were covered by the earlier contract.
2. A stress test could print PASS after process failure through fallback output such as || echo.
3. A crash test could terminate the parent shell under set -e, obscuring the real SQLSTATE and rollback evidence.
4. An anonymous-role query error could be mistaken for a zero-row result.
5. Restore/retry loops lacked a deterministic attempt limit.
6. Endpoint identity and provenance checks did not distinguish a test clone from a full DR restore.

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
- Capture a schema-only dump and SHA-256 on the authorized runner; label source-versus-test-clone sums as an expected profile rather than forcing journal parity.
- Keep full DR restore parity separate; do not claim a DR restore pass from the atomic-posting test clone.
- Carry the required AAB SHA as a provided value, clearly marked as not recomputed by this script.

## Baseline and current evidence on 2026-10-10

These results do not yet justify an ALL GREEN verdict:

- Source and clone app_config each have 352 keys and MD5 1fd3d64219ecc7c333453c20da80e295 (Check 0 remains PASS).
- The source has no public.transaction_type_map, so that table is not compared source-to-clone. The clone has 21 rows. The prior manifest on this branch used unsupported transaction labels and incorrect source types; commit 2e610ea09321ccb8cefeaa5bf6b1470d69d50e0c aligns all 21 expected pairs to the clone table and `create_auto_journal`. A clone-side pair diff returned zero mismatches/unexpected rows, and private.pos_outbox has 0 unacknowledged rows.
- The reported pre-fixture baseline remains source debit sum 502300 and clone test baseline 30500 (difference 471800, `expected_for_test_clone`). No production financial records were copied. A new clone-only `PROOF-B-001` test journal was added afterward with debit=credit=1000; it is not part of the pre-fixture 30500 baseline.
- `SET ROLE anon` followed by SELECT from private.tenant_accounting_links now executes successfully and returns 0 rows (Check 2 anon proof PASS); the prior SQLSTATE 42501 was not treated as zero-row evidence.
- `PROOF-B-001` exists exactly once under `TENANT_B_TEST`, with two lines whose debit and credit each sum to 1000; the test_b membership is active.
- Clone `CRASH-TEST-001` exists once with journal UUID 21e09fe8-ccd9-4055-9da1-f7ea3d4b20e1. `validate_journal_consistency()` currently returns 0 rows and evidence rows with null journal_id are 0.
- `v_stress_validation` currently returns 0 rows, but no 50-VU/600-second load has been run during this execution; Check 3 remains pending.
- The stress harness, metrics template, and balance-invariant migration are now included on this branch. The report must only contain p95/p99 from a real run. The literal external two-session backend-kill test and source schema SHA-256 capture remain pending on the authorized runner.

## Accounting contract boundary

The clone's live `create_auto_journal` function is authoritative for supported transaction types. The expected manifest now lists exactly the 21 accepted `p_transaction_type` values and the corresponding `source_type` values used by the function and `transaction_type_map`; for example, all four `JUAL_*` sale variants map to `pos_sale`, and `TERIMA_PIUTANG_PPH23` maps to `ar_receipt`. The source has no `public.transaction_type_map`, so the comparison is clone-only versus manifest. Do not add unsupported labels or force the database to match the prior incorrect manifest. Do not alter the protected 352-key contract or copy source journals into the test clone to manufacture parity.

## Closure criteria

The mapping/outbox gate (Check 1) and RLS/proof fixture gate (Check 2) are now verified on the clone. Remaining requirements are: (3) a real 50-VU/600-second run with measured p95/p99 and an empty `v_stress_validation`; (4) stable idempotency plus the literal two-session backend termination with SQLSTATE 57P01, zero journal/evidence rows after reconnect, zero consistency issues, and no null-journal evidence; and (5) capture the source schema SHA-256 on the authorized runner while documenting `source_sum=502300`, `clone_test_sum=30500`, `diff=471800`, `classification=expected_for_test_clone`. A full DR restore is a separate mode and is not asserted by this test-clone report. Do not mark PRs ready or declare ALL GREEN until the runner evidence is recorded.
