-- Stress-test observability and journal balance invariant.
-- Apply only to an isolated Supabase clone after inspecting its existing data.
-- The validated CHECK fails closed if any existing journal is unbalanced.

begin;

alter table public.accounting_journals
  add constraint chk_balance
  check (total_debit = total_credit);

-- The uniqueness scope is (tenant_id, transaction_ref), so group both columns.
-- Grouping only transaction_ref would false-positive if tenants reuse a reference.
create or replace view public.v_stress_validation
with (security_invoker = true)
as
select
  tenant_id,
  transaction_ref,
  count(*)::bigint as journal_count
from public.accounting_journals
group by tenant_id, transaction_ref
having count(*) > 1;

comment on view public.v_stress_validation is
  'Read-only stress-test validation: returns duplicate (tenant_id, transaction_ref) groups; expected to return zero rows.';

revoke all on table public.v_stress_validation from public, anon, authenticated;
grant select on table public.v_stress_validation to service_role;

commit;
