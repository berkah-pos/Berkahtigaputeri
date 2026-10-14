-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source. PL/pgSQL bodies are installed before SQL-language wrappers.

-- private.compute_accounting_hard_gate(p_tenant_id uuid)
CREATE OR REPLACE FUNCTION private.compute_accounting_hard_gate(p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tb bigint; v_assets bigint; v_liab bigint; v_equity bigint; v_income bigint; v_bs bigint;
  v_inv_subledger bigint; v_inv_gl bigint; v_inv_delta bigint;
  v_negative bigint; v_sale_missing_cogs bigint; v_cogs_bad bigint; v_duplicate bigint;
  v_tax_ambiguity bigint; v_tax_missing_snapshot bigint; v_input_vat_invalid bigint;
  v_tax_mutated bigint; v_closed_post bigint; v_audit_missing bigint; v_legacy_sale_lineage bigint; v_supplier_subledger bigint; v_supplier_gl bigint; v_supplier_delta bigint; v_supplier_negative bigint; v_ext_ap bigint; v_ext_div bigint; v_div_gl bigint; v_div_delta bigint; v_ext_negative bigint; v_customer_subledger bigint; v_customer_gl bigint; v_customer_delta bigint; v_customer_negative bigint; v_tax_gl_mismatch bigint; v_tax_line_mismatch bigint; v_tax_event_lineage bigint; v_salary_subledger bigint; v_salary_gl bigint; v_salary_delta bigint; v_salary_negative bigint; v_pph21_payroll bigint; v_pph21_gl bigint; v_pph21_delta bigint; v_asset_cost_subledger bigint; v_asset_cost_gl bigint; v_asset_cost_delta bigint; v_asset_accum_subledger bigint; v_asset_accum_gl bigint; v_asset_accum_delta bigint; v_asset_invalid bigint; v_allowance_subledger bigint; v_allowance_gl bigint; v_allowance_delta bigint; v_allowance_exceeds bigint; v_negative_liquid bigint; v_tax_payment_errors bigint; v_vat_settlement_errors bigint; v_inbound_pph23_credit bigint; v_inbound_pph23_gl bigint; v_inbound_pph23_delta bigint; v_umkm_period_errors bigint; v_pph25_expected bigint; v_pph25_gl bigint; v_pph25_delta bigint; v_pph29_expected bigint; v_pph29_gl bigint; v_pph29_delta bigint; v_corp_tax_exp_expected bigint; v_corp_tax_exp_gl bigint; v_corp_tax_exp_delta bigint; v_corp_period_errors bigint; v_corp_loss_errors bigint; v_pph25_authority_errors bigint;
begin
  if not exists(select 1 from public.accounting_tenants t where t.tenant_id=p_tenant_id) then
    raise exception 'tenant_not_found' using errcode='P0002';
  end if;

  select coalesce(sum(l.debit-l.credit),0)::bigint into v_tb
  from public.accounting_journal_lines l where l.tenant_id=p_tenant_id;

  select
    coalesce(sum(case when c.account_type in ('Aset Lancar','Aset Tetap') then l.debit-l.credit else 0 end),0)::bigint,
    coalesce(sum(case when c.account_type='Kewajiban' then l.credit-l.debit else 0 end),0)::bigint,
    coalesce(sum(case when c.account_type='Ekuitas' then l.credit-l.debit else 0 end),0)::bigint,
    coalesce(sum(case when c.account_type='Pendapatan' then l.credit-l.debit when c.account_type in ('HPP','Beban') then -(l.debit-l.credit) else 0 end),0)::bigint
  into v_assets,v_liab,v_equity,v_income
  from public.accounting_journal_lines l join public.accounting_coa c on c.account_code=l.account_code
  where l.tenant_id=p_tenant_id;
  v_bs:=v_assets-(v_liab+v_equity+v_income);

  select coalesce(sum(inventory_value),0)::bigint into v_inv_subledger
  from public.inventory_average_projection where tenant_id=p_tenant_id;
  select coalesce(sum(debit-credit),0)::bigint into v_inv_gl
  from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code='1-1040';
  v_inv_delta:=v_inv_subledger-v_inv_gl;

  select count(*)::bigint into v_negative
  from public.inventory_average_projection where tenant_id=p_tenant_id and (on_hand_qty<0 or inventory_value<0);

  -- Official invariant: a stocked POS sale must have positive COGS and an equal
  -- inventory credit. Do not conflate absence of the newer line-evidence table
  -- with absence of COGS in legacy journals.
  select count(*)::bigint into v_sale_missing_cogs
  from public.accounting_journals j
  left join lateral (
    select
      coalesce(sum(case when l.account_code='5-5010' then l.debit-l.credit else 0 end),0)::bigint as cogs,
      coalesce(sum(case when l.account_code='1-1040' then l.credit-l.debit else 0 end),0)::bigint as inventory_out
    from public.accounting_journal_lines l
    where l.tenant_id=j.tenant_id and l.journal_id=j.journal_id
  ) x on true
  left join public.accounting_transaction_evidence e
    on e.tenant_id=j.tenant_id and e.transaction_ref=j.transaction_ref
  where j.tenant_id=p_tenant_id and j.source_type='pos_sale'
    and (
      (
        e.evidence_id is not null
        and exists(
          select 1 from public.sale_line_evidence s
          where s.tenant_id=j.tenant_id and s.transaction_ref=j.transaction_ref and s.line_kind='STOCK'
        )
        and (x.cogs<=0 or x.inventory_out<>x.cogs)
      )
      or
      (
        e.evidence_id is null
        and (x.cogs<=0 or x.inventory_out<>x.cogs)
      )
    );

  select count(*)::bigint into v_cogs_bad
  from public.sale_line_evidence s
  where s.tenant_id=p_tenant_id and s.line_kind='STOCK' and s.original_cogs<=0;

  -- Diagnostic only: legacy sales can have correct immutable GL COGS but lack
  -- the newer product/quantity evidence schema. This is not the same invariant
  -- as sale_without_cogs_count and therefore is reported separately.
  select count(*)::bigint into v_legacy_sale_lineage
  from public.accounting_journals j
  where j.tenant_id=p_tenant_id and j.source_type='pos_sale'
    and not exists(
      select 1 from public.accounting_transaction_evidence e
      where e.tenant_id=j.tenant_id and e.transaction_ref=j.transaction_ref
    )
    and not exists(
      select 1 from public.accounting_journals r
      where r.tenant_id=j.tenant_id and r.reversal_of=j.journal_id
    );

  select count(*)::bigint into v_duplicate from (
    select transaction_ref from public.accounting_journals
    where tenant_id=p_tenant_id and source_type<>'reversal'
    group by transaction_ref having count(*)>1
  ) d;

  with required(tax_code,object_code,category) as (values
    ('PPN','NON_LUXURY','DEFAULT'),('PPN','LUXURY_CONSUMER','DEFAULT'),
    ('PPH23','SERVICE','DEFAULT'),('PPH23','ASSET_RENT_NON_LAND_BUILDING','DEFAULT'),
    ('PPH23','DIVIDEND','DEFAULT'),('PPH23','INTEREST','DEFAULT'),('PPH23','ROYALTY','DEFAULT'),
    ('PPH_FINAL_4_2','LAND_BUILDING_RENT','DEFAULT'),('PPH_FINAL_UMKM','TURNOVER','DEFAULT'),
    ('PPH_BADAN','GENERAL','DEFAULT')
  ), bad as (
    select r.* from required r
    where (select count(*) from public.tax_rates t
           where t.tax_code=r.tax_code and t.object_code=r.object_code and t.category=r.category
             and t.effective_date<=current_date and (t.end_date is null or t.end_date>=current_date))<>1
    union all
    select 'PPH21_TER',c.category,'CURRENT' from (values('A'),('B'),('C')) c(category)
    where not exists(select 1 from public.tax_rate_brackets b where b.tax_code='PPH21_TER' and b.category=c.category and b.effective_date<=current_date and (b.end_date is null or b.end_date>=current_date))
  ), overlap_rates as (
    select 1 x from public.tax_rates a join public.tax_rates b on a.tax_rate_id<b.tax_rate_id
      and a.tax_code=b.tax_code and a.object_code=b.object_code and a.category=b.category
      and daterange(a.effective_date,coalesce(a.end_date+1,'infinity'::date),'[)') && daterange(b.effective_date,coalesce(b.end_date+1,'infinity'::date),'[)')
  ), overlap_brackets as (
    select 1 x from public.tax_rate_brackets a join public.tax_rate_brackets b on a.bracket_id<b.bracket_id
      and a.tax_code=b.tax_code and a.category=b.category
      and int8range(a.lower_bound,coalesce(a.upper_bound+1,9223372036854775807::bigint),'[)') && int8range(b.lower_bound,coalesce(b.upper_bound+1,9223372036854775807::bigint),'[)')
      and daterange(a.effective_date,coalesce(a.end_date+1,'infinity'::date),'[)') && daterange(b.effective_date,coalesce(b.end_date+1,'infinity'::date),'[)')
  )
  select (select count(*) from bad)+(select count(*) from overlap_rates)+(select count(*) from overlap_brackets)
  into v_tax_ambiguity;

  select count(*)::bigint into v_tax_missing_snapshot
  from public.tax_documents d where d.tenant_id=p_tenant_id
    and (jsonb_typeof(d.legal_rule_snapshot)<>'object' or d.legal_rule_snapshot='{}'::jsonb or nullif(btrim(d.legal_rule_snapshot->>'legal_basis'),'') is null);

  select (
    (select count(*) from public.tax_documents d where d.tenant_id=p_tenant_id and d.document_type='VAT_INPUT' and d.creditable_input_vat and d.invoice_status<>'VALID')
    +
    (select count(*) from public.accounting_journal_lines l where l.tenant_id=p_tenant_id and l.account_code='1-1090' and l.debit>0 and not exists(
      select 1 from public.tax_documents d where d.tenant_id=p_tenant_id and d.document_type='VAT_INPUT' and d.journal_id=l.journal_id and d.invoice_status='VALID' and d.creditable_input_vat
    ))
  )::bigint into v_input_vat_invalid;

  select count(*)::bigint into v_tax_mutated
  from public.tax_documents d where d.tenant_id=p_tenant_id and d.status in ('SUBMITTED','ACCEPTED','REPORTED','CANCELLED','REPLACED')
    and (d.sealed_hash is null or d.sealed_hash<>encode(extensions.digest(convert_to(concat_ws('|',
      d.tenant_id::text,d.tax_document_id::text,d.document_type,d.transaction_ref,d.business_date::text,
      coalesce(d.vat_transaction_code,''),d.dpp::text,d.tax_amount::text,d.gross_amount::text,
      d.tax_rate_snapshot::text,d.legal_rule_snapshot::text,coalesce(d.journal_id::text,'')
    ),'UTF8'),'sha256'),'hex'));

  select count(*)::bigint into v_closed_post
  from public.accounting_journals j where j.tenant_id=p_tenant_id and exists(
    select 1 from public.accounting_periods p where p.tenant_id=j.tenant_id and p.status='closed' and j.journal_date between p.period_start and p.period_end
  );

  select (
    (select count(*) from public.accounting_transaction_evidence e where e.tenant_id=p_tenant_id and (e.actor_user_id is null or nullif(btrim(e.device_id),'') is null or length(btrim(e.reason))<3))
    +(select count(*) from public.inventory_average_events e where e.tenant_id=p_tenant_id and (e.actor_user_id is null or nullif(btrim(e.device_id),'') is null or length(btrim(e.reason))<3))
    +(select count(*) from public.tax_documents d where d.tenant_id=p_tenant_id and (d.actor_user_id is null or nullif(btrim(d.device_id),'') is null or length(btrim(d.reason))<3))
    +(select count(*) from public.tax_document_events e where e.tenant_id=p_tenant_id and (e.actor_user_id is null or nullif(btrim(e.device_id),'') is null or length(btrim(e.reason))<3))
    +(select count(*) from private.audit_logs a where a.tenant_id=p_tenant_id::text and (a.actor_id is null or nullif(btrim(a.device_id),'') is null or length(btrim(a.reason))<3))
    +(select count(*) from public.vat_period_settlements s where s.tenant_id=p_tenant_id and (s.actor_user_id is null or nullif(btrim(s.device_id),'') is null or length(btrim(s.reason))<3))
    +(select count(*) from public.customer_withholding_tax_credits c where c.tenant_id=p_tenant_id and (c.actor_user_id is null or nullif(btrim(c.device_id),'') is null or length(btrim(c.reason))<3))
  )::bigint into v_audit_missing;

  select coalesce(sum(remaining_amount),0)::bigint, count(*) filter (where remaining_amount<0)::bigint
  into v_supplier_subledger,v_supplier_negative
  from public.supplier_liabilities where tenant_id=p_tenant_id;
  select coalesce(sum(remaining_amount) filter (where liability_account='2-2020'),0)::bigint,
         coalesce(sum(remaining_amount) filter (where liability_account='2-2080'),0)::bigint,
         count(*) filter (where remaining_amount<0)::bigint
  into v_ext_ap,v_ext_div,v_ext_negative from public.extended_withholding_liabilities where tenant_id=p_tenant_id;
  v_supplier_subledger:=v_supplier_subledger+v_ext_ap;
  v_supplier_negative:=v_supplier_negative+v_ext_negative;
  select coalesce(sum(credit-debit),0)::bigint into v_supplier_gl
  from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code='2-2020';
  v_supplier_delta:=v_supplier_subledger-v_supplier_gl;
  select coalesce(sum(credit-debit),0)::bigint into v_div_gl from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code='2-2080';
  v_div_delta:=v_ext_div-v_div_gl;
  select coalesce(sum(remaining_amount),0)::bigint, count(*) filter (where remaining_amount<0)::bigint
  into v_customer_subledger,v_customer_negative
  from public.customer_receivables where tenant_id=p_tenant_id;
  select coalesce(sum(debit-credit),0)::bigint into v_customer_gl
  from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code='1-1050';
  v_customer_delta:=v_customer_subledger-v_customer_gl;

  select coalesce(sum(remaining_amount),0)::bigint, count(*) filter (where remaining_amount<0)::bigint
  into v_salary_subledger,v_salary_negative
  from public.employee_payables where tenant_id=p_tenant_id;
  select coalesce(sum(credit-debit),0)::bigint into v_salary_gl
  from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code='2-2030';
  v_salary_delta:=v_salary_subledger-v_salary_gl;
  select coalesce(sum(withholding_adjustment),0)::bigint into v_pph21_payroll
  from public.payroll_tax_evidence where tenant_id=p_tenant_id;
  select coalesce(sum(credit-debit),0)::bigint into v_pph21_gl
  from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code='2-2040';
  v_pph21_delta:=v_pph21_payroll-v_pph21_gl;

  select coalesce(sum(cost),0)::bigint,coalesce(sum(accumulated_depreciation),0)::bigint,count(*) filter(where accumulated_depreciation<0 or accumulated_depreciation>cost-residual_value)::bigint into v_asset_cost_subledger,v_asset_accum_subledger,v_asset_invalid from public.fixed_assets where tenant_id=p_tenant_id;
  select coalesce(sum(debit-credit),0)::bigint into v_asset_cost_gl from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code='1-1060';
  select coalesce(sum(credit-debit),0)::bigint into v_asset_accum_gl from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code='1-1070';
  v_asset_cost_delta:=v_asset_cost_subledger-v_asset_cost_gl; v_asset_accum_delta:=v_asset_accum_subledger-v_asset_accum_gl;
  select coalesce(sum(allowance_amount),0)::bigint into v_allowance_subledger from public.receivable_allowances where tenant_id=p_tenant_id;
  select coalesce(sum(credit-debit),0)::bigint into v_allowance_gl from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code='1-1080';
  v_allowance_delta:=v_allowance_subledger-v_allowance_gl;
  select count(*)::bigint into v_allowance_exceeds from public.receivable_allowances a join public.customer_receivables r on r.tenant_id=a.tenant_id and r.sale_transaction_ref=a.sale_transaction_ref where a.tenant_id=p_tenant_id and a.allowance_amount>r.remaining_amount;

  select count(*)::bigint into v_negative_liquid from (
    select account_code,coalesce(sum(debit-credit),0)::bigint balance
    from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code in ('1-1010','1-1020','1-1030')
    group by account_code having coalesce(sum(debit-credit),0)<0
  ) q;

  select count(*)::bigint into v_vat_settlement_errors from public.vat_period_settlements s
  where s.tenant_id=p_tenant_id and (
    s.output_vat_charged<>coalesce((select sum(d.tax_amount) from public.tax_documents d where d.tenant_id=s.tenant_id and d.document_type in ('VAT_OUTPUT','VAT_REPLACEMENT') and d.business_date between s.period_start and s.period_end and d.status in ('VALIDATED','SUBMITTED','ACCEPTED','REPORTED')),0)
    or s.output_vat_reductions<>coalesce((select sum(d.tax_amount) from public.tax_documents d where d.tenant_id=s.tenant_id and d.document_type='VAT_RETURN' and d.business_date between s.period_start and s.period_end and d.status in ('VALIDATED','SUBMITTED','ACCEPTED','REPORTED')),0)
    or s.input_vat_current<>coalesce((select sum(d.tax_amount) from public.tax_documents d where d.tenant_id=s.tenant_id and d.document_type='VAT_INPUT' and d.business_date between s.period_start and s.period_end and d.status in ('VALIDATED','ACCEPTED','REPORTED') and d.invoice_status='VALID' and d.creditable_input_vat and d.journal_id is not null),0)
    or s.carry_in<>coalesce((select p.carry_out from public.vat_period_settlements p where p.tenant_id=s.tenant_id and p.period_end=s.period_start-1),0)
    or (s.offset_used+s.return_credit_reclass>0 and not exists(select 1 from public.accounting_transaction_evidence e where e.tenant_id=s.tenant_id and e.journal_id=s.settlement_journal_id and e.transaction_type='TUTUP_PPN_MASA'))
    or (s.offset_used>0 and coalesce((select sum(case when l.account_code='2-2010' then l.debit-l.credit else 0 end) from public.accounting_journal_lines l where l.tenant_id=s.tenant_id and l.journal_id=s.settlement_journal_id),0)<>s.offset_used-s.return_credit_reclass)
    or (s.offset_used+s.return_credit_reclass>0 and coalesce((select sum(case when l.account_code='1-1090' then l.credit-l.debit else 0 end) from public.accounting_journal_lines l where l.tenant_id=s.tenant_id and l.journal_id=s.settlement_journal_id),0)<>s.offset_used-s.return_credit_reclass)
  );

  select count(*)::bigint into v_tax_payment_errors from public.tax_payment_refs r
  where r.tenant_id=p_tenant_id and r.status='PAID' and (
    r.payment_journal_id is null or nullif(btrim(coalesce(r.payment_reference,'')),'') is null or r.paid_at is null
    or not exists(
      select 1 from public.accounting_transaction_evidence e
      where e.tenant_id=r.tenant_id and e.journal_id=r.payment_journal_id and e.transaction_type='SETOR_PAJAK'
        and e.facts_snapshot->>'payment_ref_id'=r.payment_ref_id::text
    )
    or coalesce((select sum(case r.tax_code when 'PPN' then case when l.account_code='2-2010' then l.debit-l.credit else 0 end when 'PPH21' then case when l.account_code='2-2040' then l.debit-l.credit else 0 end when 'PPH23' then case when l.account_code='2-2050' then l.debit-l.credit else 0 end when 'PPH_FINAL' then case when l.account_code='2-2060' then l.debit-l.credit else 0 end when 'PPH25' then case when l.account_code='1-1110' then l.debit-l.credit else 0 end when 'PPH29' then case when l.account_code='2-2070' then l.debit-l.credit else 0 end else 0 end) from public.accounting_journal_lines l where l.tenant_id=r.tenant_id and l.journal_id=r.payment_journal_id),0)<>r.amount
  );

  select greatest(coalesce(sum(c.tax_amount),0)-coalesce((select sum(p.pph23_credit_applied) from public.corporate_annual_tax_periods p where p.tenant_id=p_tenant_id),0),0)::bigint into v_inbound_pph23_credit from public.customer_withholding_tax_credits c where c.tenant_id=p_tenant_id;
  select coalesce(sum(debit-credit),0)::bigint into v_inbound_pph23_gl from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code='1-1100';
  v_inbound_pph23_delta:=v_inbound_pph23_credit-v_inbound_pph23_gl;

  select greatest(coalesce(sum(r.amount),0)-coalesce((select sum(p.pph25_credit_applied) from public.corporate_annual_tax_periods p where p.tenant_id=p_tenant_id),0),0)::bigint into v_pph25_expected
  from public.tax_payment_refs r where r.tenant_id=p_tenant_id and r.tax_code='PPH25' and r.status='PAID';
  select coalesce(sum(debit-credit),0)::bigint into v_pph25_gl from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code='1-1110';
  v_pph25_delta:=v_pph25_expected-v_pph25_gl;

  select greatest(coalesce((select sum(p.pph29_payable) from public.corporate_annual_tax_periods p where p.tenant_id=p_tenant_id),0)-coalesce((select sum(r.amount) from public.tax_payment_refs r where r.tenant_id=p_tenant_id and r.tax_code='PPH29' and r.status='PAID'),0),0)::bigint into v_pph29_expected;
  select coalesce(sum(credit-debit),0)::bigint into v_pph29_gl from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code='2-2070';
  v_pph29_delta:=v_pph29_expected-v_pph29_gl;

  select coalesce(sum(corporate_tax_due),0)::bigint into v_corp_tax_exp_expected from public.corporate_annual_tax_periods where tenant_id=p_tenant_id;
  select coalesce(sum(debit-credit),0)::bigint into v_corp_tax_exp_gl from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code='6-6120';
  v_corp_tax_exp_delta:=v_corp_tax_exp_expected-v_corp_tax_exp_gl;

  select count(*)::bigint into v_corp_period_errors from public.corporate_annual_tax_periods p
  where p.tenant_id=p_tenant_id and (
    p.commercial_profit_before_tax<>private.corporate_commercial_profit_before_tax(p.tenant_id,p.tax_year)
    or p.fiscal_positive_adjustments<>coalesce((select sum(a.amount) from public.corporate_fiscal_adjustments a where a.tenant_id=p.tenant_id and a.tax_year=p.tax_year and a.direction='POSITIVE'),0)
    or p.fiscal_negative_adjustments<>coalesce((select sum(a.amount) from public.corporate_fiscal_adjustments a where a.tenant_id=p.tenant_id and a.tax_year=p.tax_year and a.direction='NEGATIVE'),0)
    or p.gross_turnover<>private.corporate_gross_turnover_between(p.tenant_id,make_date(p.tax_year,1,1),make_date(p.tax_year,12,31))
    or p.fiscal_loss_applied<>coalesce((select sum(x.amount_applied) from public.corporate_fiscal_loss_applications x where x.tenant_id=p.tenant_id and x.target_annual_period_id=p.annual_period_id),0)
    or (p.fiscal_loss_created>0 and not exists(select 1 from public.corporate_fiscal_loss_carryforwards l where l.tenant_id=p.tenant_id and l.origin_tax_year=p.tax_year and l.original_loss=p.fiscal_loss_created and l.source_annual_period_id=p.annual_period_id))
    or (p.corporate_tax_due>0 and not exists(select 1 from public.accounting_transaction_evidence e where e.tenant_id=p.tenant_id and e.journal_id=p.annual_journal_id and e.transaction_type='PPH_BADAN_TAHUNAN'))
  );

  select count(*)::bigint into v_corp_loss_errors from public.corporate_fiscal_loss_carryforwards l
  where l.tenant_id=p_tenant_id and (
    l.expires_after_tax_year<>l.origin_tax_year+5
    or coalesce((select sum(a.amount_applied) from public.corporate_fiscal_loss_applications a where a.loss_id=l.loss_id),0)>l.original_loss
    or exists(select 1 from public.corporate_fiscal_loss_applications a where a.loss_id=l.loss_id and (a.target_tax_year<=l.origin_tax_year or a.target_tax_year>l.expires_after_tax_year))
  );

  select count(*)::bigint into v_pph25_authority_errors from public.corporate_pph25_authorities a
  join public.corporate_annual_tax_periods p on p.annual_period_id=a.source_annual_period_id and p.tenant_id=a.tenant_id
  where a.tenant_id=p_tenant_id and (
    a.tax_year<>p.tax_year+1
    or a.annual_installment_basis<>greatest(p.corporate_tax_due-p.pph23_credit_available,0)
    or a.monthly_amount<>round(a.annual_installment_basis::numeric/12)::bigint
    or (a.superseded_from_month is not null and (a.superseded_from_month<=a.effective_from_month or a.superseded_from_month>a.effective_to_month))
  );

  select count(*)::bigint into v_umkm_period_errors from public.owner_turnover_tax_periods p
  where p.tenant_id=p_tenant_id and (
    p.gross_turnover_month<>private.umkm_gross_turnover_between(p.tenant_id,p.period_start,p.period_end)
    or p.gross_turnover_ytd_before<>private.umkm_gross_turnover_between(p.tenant_id,make_date(extract(year from p.period_start)::int,1,1),p.period_start-1)
    or (p.tax_amount>0 and not exists(select 1 from public.accounting_transaction_evidence e where e.tenant_id=p.tenant_id and e.journal_id=p.tax_journal_id and e.transaction_type='PPH_FINAL_UMKM_BULANAN'))
    or (p.tax_amount>0 and not exists(select 1 from public.tax_documents d where d.tenant_id=p.tenant_id and d.tax_document_id=p.tax_document_id and d.document_type='PPH_FINAL' and d.tax_amount=p.tax_amount and d.journal_id=p.tax_journal_id))
  );

  select count(*)::bigint into v_tax_gl_mismatch
  from public.tax_documents d
  left join lateral (
    select
      coalesce(sum(case when l.account_code='2-2010' then l.credit-l.debit else 0 end),0)::bigint as vat_output_net,
      coalesce(sum(case when l.account_code='1-1090' then l.debit-l.credit else 0 end),0)::bigint as vat_input_net,
      coalesce(sum(case when l.account_code='2-2040' then l.credit-l.debit else 0 end),0)::bigint as pph21_net,
      coalesce(sum(case when l.account_code='2-2050' then l.credit-l.debit else 0 end),0)::bigint as pph23_net,
      coalesce(sum(case when l.account_code='2-2060' then l.credit-l.debit else 0 end),0)::bigint as pph_final_net
    from public.accounting_journal_lines l
    where l.tenant_id=d.tenant_id and l.journal_id=d.journal_id
  ) g on true
  where d.tenant_id=p_tenant_id and (
    (d.document_type in ('VAT_OUTPUT','VAT_REPLACEMENT') and (d.journal_id is null or g.vat_output_net<>d.tax_amount))
    or (d.document_type in ('VAT_RETURN','VAT_CANCELLATION') and (d.journal_id is null or g.vat_output_net<>-d.tax_amount))
    or (d.document_type='VAT_INPUT' and d.journal_id is not null and (
      (d.creditable_input_vat and g.vat_input_net<>d.tax_amount)
      or (not d.creditable_input_vat and g.vat_input_net<>0)
    ))
    or (d.document_type='PPH21_26' and (d.journal_id is null or g.pph21_net<>d.tax_amount))
    or (d.document_type='PPH23_UNIFICATION' and (d.journal_id is null or g.pph23_net<>d.tax_amount))
    or (d.document_type='PPH_FINAL' and (d.journal_id is null or g.pph_final_net<>d.tax_amount))
  );

  select count(*)::bigint into v_tax_line_mismatch
  from public.tax_documents d
  left join lateral (
    select count(*)::bigint n,
           coalesce(sum(l.dpp),0)::bigint dpp,
           coalesce(sum(l.tax_amount),0)::bigint tax_amount,
           coalesce(sum(l.gross_amount),0)::bigint gross_amount
    from public.tax_document_lines l where l.tax_document_id=d.tax_document_id
  ) x on true
  where d.tenant_id=p_tenant_id and d.document_type in ('VAT_OUTPUT','VAT_RETURN','VAT_REPLACEMENT')
    and (x.n=0 or x.dpp<>d.dpp or x.tax_amount<>d.tax_amount or x.gross_amount<>d.gross_amount);

  select count(*)::bigint into v_tax_event_lineage
  from public.tax_documents d
  where d.tenant_id=p_tenant_id and (
    (
      d.document_type='VAT_INPUT' and (
        not exists(select 1 from public.tax_document_events e where e.tax_document_id=d.tax_document_id and e.event_type='REGISTERED')
        or (d.status<>'DRAFT' and not exists(select 1 from public.tax_document_events e where e.tax_document_id=d.tax_document_id and e.event_type='INPUT_INVOICE_VALIDATED'))
        or (d.journal_id is not null and not exists(select 1 from public.tax_document_events e where e.tax_document_id=d.tax_document_id and e.event_type='JOURNAL_LINKED'))
      )
    )
    or (
      d.document_type<>'VAT_INPUT' and not exists(
        select 1 from public.tax_document_events e where e.tax_document_id=d.tax_document_id and e.event_type='VALIDATED'
      )
    )
    or (d.status in ('SUBMITTED','ACCEPTED','REJECTED','REPORTED') and not exists(
      select 1 from public.tax_document_events e where e.tax_document_id=d.tax_document_id and e.event_type='SUBMITTED'))
    or (d.status in ('ACCEPTED','REPORTED') and not exists(
      select 1 from public.tax_document_events e where e.tax_document_id=d.tax_document_id and e.event_type='CORETAX_ACK'))
    or (d.status='REJECTED' and not exists(
      select 1 from public.tax_document_events e where e.tax_document_id=d.tax_document_id and e.event_type='CORETAX_REJECTED'))
  );

  return jsonb_build_object(
    'trial_balance_delta',v_tb,
    'balance_sheet_delta',v_bs,
    'inventory_subledger_minus_gl_1_1040',v_inv_delta,
    'supplier_liability_subledger_minus_gl_2_2020',v_supplier_delta,
    'supplier_liability_negative_count',v_supplier_negative,'dividend_liability_subledger_minus_gl_2_2080',v_div_delta,
    'customer_receivable_subledger_minus_gl_1_1050',v_customer_delta,
    'customer_receivable_negative_count',v_customer_negative,
    'salary_payable_subledger_minus_gl_2_2030',v_salary_delta,
    'salary_payable_negative_count',v_salary_negative,
    'payroll_pph21_evidence_minus_gl_2_2040',v_pph21_delta,
    'fixed_asset_cost_subledger_minus_gl_1_1060',v_asset_cost_delta,
    'fixed_asset_accum_subledger_minus_gl_1_1070',v_asset_accum_delta,
    'fixed_asset_invalid_count',v_asset_invalid,
    'receivable_allowance_subledger_minus_gl_1_1080',v_allowance_delta,
    'receivable_allowance_exceeds_receivable_count',v_allowance_exceeds,
    'negative_liquid_asset_count',v_negative_liquid,'tax_payment_reconciliation_error_count',v_tax_payment_errors,'vat_period_settlement_error_count',v_vat_settlement_errors,'inbound_pph23_credit_subledger_minus_gl_1_1100',v_inbound_pph23_delta,'pph25_prepayment_subledger_minus_gl_1_1110',v_pph25_delta,'pph29_payable_subledger_minus_gl_2_2070',v_pph29_delta,'corporate_tax_expense_subledger_minus_gl_6_6120',v_corp_tax_exp_delta,'corporate_annual_tax_period_error_count',v_corp_period_errors,'corporate_fiscal_loss_error_count',v_corp_loss_errors,'pph25_authority_error_count',v_pph25_authority_errors,'owner_umkm_turnover_tax_period_error_count',v_umkm_period_errors,
    'tax_document_gl_mismatch_count',v_tax_gl_mismatch,
    'tax_document_line_mismatch_count',v_tax_line_mismatch,
    'tax_document_event_lineage_missing_count',v_tax_event_lineage,
    'negative_stock_count',v_negative,
    'sale_without_cogs_count',v_sale_missing_cogs,
    'stocked_sale_cogs_nonpositive_count',v_cogs_bad,
    'duplicate_source_posting_count',v_duplicate,
    'effective_tax_rule_ambiguity_count',v_tax_ambiguity,
    'tax_document_missing_legal_snapshot_count',v_tax_missing_snapshot,
    'credited_input_vat_without_valid_invoice_count',v_input_vat_invalid,
    'posted_tax_document_mutation_count',v_tax_mutated,
    'closed_period_posting_count',v_closed_post,
    'audit_lineage_missing_count',v_audit_missing,
    'legacy_pos_sale_without_line_evidence_count',v_legacy_sale_lineage,
    'all_zero',(v_tb=0 and v_bs=0 and v_inv_delta=0 and v_negative=0 and v_sale_missing_cogs=0 and v_cogs_bad=0 and v_duplicate=0 and v_tax_ambiguity=0 and v_tax_missing_snapshot=0 and v_input_vat_invalid=0 and v_tax_mutated=0 and v_closed_post=0 and v_audit_missing=0 and v_supplier_delta=0 and v_supplier_negative=0 and v_div_delta=0 and v_customer_delta=0 and v_customer_negative=0 and v_tax_gl_mismatch=0 and v_tax_line_mismatch=0 and v_tax_event_lineage=0 and v_salary_delta=0 and v_salary_negative=0 and v_pph21_delta=0 and v_asset_cost_delta=0 and v_asset_accum_delta=0 and v_asset_invalid=0 and v_allowance_delta=0 and v_allowance_exceeds=0 and v_negative_liquid=0 and v_tax_payment_errors=0 and v_vat_settlement_errors=0 and v_inbound_pph23_delta=0 and v_pph25_delta=0 and v_pph29_delta=0 and v_corp_tax_exp_delta=0 and v_corp_period_errors=0 and v_corp_loss_errors=0 and v_pph25_authority_errors=0 and v_umkm_period_errors=0)
  );
end;
$function$;
-- private.create_tax_document_internal(p_tenant_id uuid, p_document_type text, p_transaction_ref text, p_business_date date, p_counterparty_id uuid, p_facility_context text, p_tax_snapshot jsonb, p_dpp bigint, p_tax_amount bigint, p_gross_amount bigint, p_journal_id uuid, p_invoice_status text, p_creditable_input_vat boolean, p_reference_document_id uuid, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION private.create_tax_document_internal(p_tenant_id uuid, p_document_type text, p_transaction_ref text, p_business_date date, p_counterparty_id uuid, p_facility_context text, p_tax_snapshot jsonb, p_dpp bigint, p_tax_amount bigint, p_gross_amount bigint, p_journal_id uuid, p_invoice_status text, p_creditable_input_vat boolean, p_reference_document_id uuid, p_actor uuid, p_device_id text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; v_code text; v_legal jsonb;
begin
  if p_actor is null or p_device_id is null or length(btrim(p_device_id))=0 or p_reason is null or length(btrim(p_reason))<3 then raise exception 'tax_document_audit_lineage_required' using errcode='22023'; end if;
  if p_dpp<0 or p_tax_amount<0 or p_gross_amount<0 then raise exception 'invalid_tax_document_amounts' using errcode='23514'; end if;
  if p_document_type in ('VAT_OUTPUT','VAT_INPUT','VAT_RETURN','VAT_REPLACEMENT','VAT_CANCELLATION') and p_gross_amount<>p_dpp+p_tax_amount then raise exception 'vat_document_gross_must_equal_dpp_plus_tax' using errcode='23514'; end if;
  if jsonb_typeof(p_tax_snapshot)<>'object' or coalesce(p_tax_snapshot->>'legal_basis','')='' then raise exception 'tax_document_legal_rule_snapshot_required' using errcode='23514'; end if;
  v_code:=case when p_document_type in ('VAT_OUTPUT','VAT_INPUT','VAT_RETURN','VAT_REPLACEMENT','VAT_CANCELLATION') then private.resolve_vat_transaction_code(p_facility_context) else null end;
  v_legal:=jsonb_build_object('legal_basis',p_tax_snapshot->>'legal_basis','tax_rate_id',p_tax_snapshot->>'tax_rate_id','vat_transaction_code',v_code,'facility_context',upper(coalesce(p_facility_context,'NORMAL')),'snapshot_at',now());
  insert into public.tax_documents(tenant_id,document_type,transaction_ref,reference_document_id,counterparty_id,business_date,vat_transaction_code,facility_context,dpp,tax_amount,gross_amount,tax_rate_snapshot,legal_rule_snapshot,invoice_status,creditable_input_vat,status,journal_id,actor_user_id,device_id,reason)
  values(p_tenant_id,p_document_type,btrim(p_transaction_ref),p_reference_document_id,p_counterparty_id,p_business_date,v_code,upper(coalesce(p_facility_context,'NORMAL')),p_dpp,p_tax_amount,p_gross_amount,p_tax_snapshot,v_legal,p_invoice_status,p_creditable_input_vat,'VALIDATED',p_journal_id,p_actor,btrim(p_device_id),btrim(p_reason))
  returning tax_document_id into v_id;
  insert into public.tax_document_events(tax_document_id,tenant_id,event_type,details,actor_user_id,device_id,reason)
  values(v_id,p_tenant_id,'VALIDATED',jsonb_build_object('document_type',p_document_type,'transaction_ref',btrim(p_transaction_ref)),p_actor,btrim(p_device_id),btrim(p_reason));
  return v_id;
end;
$function$;
-- private.enforce_customer_receivable_evidence()
CREATE OR REPLACE FUNCTION private.enforce_customer_receivable_evidence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_customer text;
  v_source text;
  v_amount bigint;
  v_ar_delta bigint;
  v_tax bigint:=0;
  v_cash bigint:=0;
  v_cert text;
  v_rec public.customer_receivables%rowtype;
  v_orig_type text;
  v_wh jsonb:='{}'::jsonb;
  v_wh_base bigint:=0;
  v_wh_object text:='NONE';
  v_customer_party uuid;
begin
  if new.transaction_type='JUAL_KREDIT' then
    v_customer:=nullif(btrim(coalesce(new.facts_snapshot->>'customer_id','')),'');
    if v_customer is null then raise exception 'customer_required_for_credit_sale' using errcode='22023'; end if;
    select coalesce(sum(l.debit-l.credit),0)::bigint into v_ar_delta
    from public.accounting_journal_lines l
    where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='1-1050';
    if v_ar_delta<=0 then raise exception 'credit_sale_receivable_missing' using errcode='23514'; end if;
    v_wh:=coalesce(new.tax_snapshot->'inbound_withholding','{}'::jsonb);
    if v_wh<>'{}'::jsonb then
      v_wh_object:=upper(coalesce(v_wh->>'object_code','NONE'));
      v_wh_base:=coalesce((v_wh->>'base')::bigint,0);
      begin v_customer_party:=(new.facts_snapshot->>'customer_tax_party_id')::uuid;
      exception when others then raise exception 'customer_tax_party_required_for_inbound_withholding' using errcode='22023'; end;
      if v_wh_object<>'SERVICE' or v_wh_base<=0 then raise exception 'invalid_inbound_withholding_source_snapshot' using errcode='23514'; end if;
      if not exists(
        select 1 from public.tax_parties p
        where p.tenant_id=new.tenant_id and p.party_id=v_customer_party and p.party_kind='CUSTOMER' and p.is_withholding_agent
          and p.valid_from<=new.business_date and (p.valid_to is null or p.valid_to>=new.business_date)
      ) then raise exception 'customer_withholding_agent_evidence_invalid' using errcode='23514'; end if;
    end if;
    insert into public.customer_receivables(
      tenant_id,sale_transaction_ref,customer_ref,business_date,original_amount,remaining_amount,
      sale_journal_id,actor_user_id,device_id,reason,customer_tax_party_id,withholding_tax_object,withholding_base_original,withholding_base_remaining
    ) values(
      new.tenant_id,new.transaction_ref,v_customer,new.business_date,v_ar_delta,v_ar_delta,
      new.journal_id,new.actor_user_id,new.device_id,new.reason,v_customer_party,v_wh_object,v_wh_base,v_wh_base
    );

  elsif new.transaction_type='TERIMA_PIUTANG' then
    v_source:=nullif(btrim(coalesce(new.facts_snapshot->>'source_sale_ref','')),'');
    v_customer:=nullif(btrim(coalesce(new.facts_snapshot->>'customer_id','')),'');
    if v_source is null or v_customer is null then raise exception 'receivable_collection_identity_required' using errcode='22023'; end if;
    if coalesce(new.facts_snapshot->>'gross_receipt','') !~ '^[1-9][0-9]*$' then raise exception 'gross_receipt_required' using errcode='22023'; end if;
    v_amount:=(new.facts_snapshot->>'gross_receipt')::bigint;
    select * into v_rec from public.customer_receivables r where r.tenant_id=new.tenant_id and r.sale_transaction_ref=v_source for update;
    if not found then raise exception 'customer_receivable_not_found' using errcode='P0002'; end if;
    if v_rec.withholding_tax_object<>'NONE' then raise exception 'withholding_receivable_requires_pph23_receipt_flow' using errcode='23514'; end if;
    if v_rec.customer_ref<>v_customer then raise exception 'customer_receivable_customer_mismatch' using errcode='23514'; end if;
    if new.business_date<v_rec.business_date then raise exception 'customer_receipt_before_credit_sale_date' using errcode='23514'; end if;
    if v_rec.remaining_amount<v_amount then raise exception 'customer_receipt_exceeds_outstanding_receivable' using errcode='23514'; end if;
    if v_rec.remaining_amount-v_amount < coalesce((select a.allowance_amount from public.receivable_allowances a where a.tenant_id=new.tenant_id and a.sale_transaction_ref=v_source),0) then raise exception 'receivable_collection_requires_allowance_reduction' using errcode='23514'; end if;
    select coalesce(sum(l.credit-l.debit),0)::bigint into v_ar_delta from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='1-1050';
    if v_ar_delta<>v_amount then raise exception 'customer_receipt_gl_mismatch' using errcode='23514'; end if;
    update public.customer_receivables set remaining_amount=remaining_amount-v_amount,updated_at=now() where tenant_id=new.tenant_id and sale_transaction_ref=v_source;
    insert into public.customer_receivable_allocations(
      tenant_id,receipt_transaction_ref,sale_transaction_ref,customer_ref,amount_applied,
      receipt_journal_id,business_date,actor_user_id,device_id,reason,cash_received,withheld_tax_amount
    ) values(
      new.tenant_id,new.transaction_ref,v_source,v_customer,v_amount,
      new.journal_id,new.business_date,new.actor_user_id,new.device_id,new.reason,v_amount,0
    );

  elsif new.transaction_type='TERIMA_PIUTANG_PPH23' then
    v_source:=nullif(btrim(coalesce(new.facts_snapshot->>'source_sale_ref','')),'');
    v_customer:=nullif(btrim(coalesce(new.facts_snapshot->>'customer_id','')),'');
    if v_source is null or v_customer is null then raise exception 'receivable_collection_identity_required' using errcode='22023'; end if;
    select * into strict v_rec from public.customer_receivables r where r.tenant_id=new.tenant_id and r.sale_transaction_ref=v_source for update;
    if v_rec.customer_ref<>v_customer or v_rec.withholding_tax_object<>'SERVICE' or v_rec.withholding_base_remaining<=0 then raise exception 'inbound_pph23_receivable_source_mismatch' using errcode='23514'; end if;
    if new.business_date<v_rec.business_date then raise exception 'customer_receipt_before_credit_sale_date' using errcode='23514'; end if;
    select coalesce(sum(case when l.account_code='1-1050' then l.credit-l.debit else 0 end),0)::bigint,
           coalesce(sum(case when l.account_code='1-1100' then l.debit-l.credit else 0 end),0)::bigint,
           coalesce(sum(case when l.account_code in ('1-1010','1-1030') then l.debit-l.credit else 0 end),0)::bigint
      into v_ar_delta,v_tax,v_cash
    from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id;
    if v_ar_delta<>v_rec.remaining_amount or v_tax<=0 or v_cash+v_tax<>v_ar_delta then raise exception 'inbound_pph23_receipt_gl_mismatch' using errcode='23514'; end if;
    v_cert:=upper(btrim(new.facts_snapshot->>'withholding_certificate_number'));
    if v_cert is null or length(v_cert)<3 then raise exception 'withholding_certificate_number_required' using errcode='22023'; end if;
    insert into public.customer_withholding_tax_credits(
      tenant_id,source_sale_ref,receipt_transaction_ref,customer_tax_party_id,certificate_number,tax_object_code,
      withholding_base,tax_amount,legal_rule_snapshot,receipt_journal_id,business_date,actor_user_id,device_id,reason
    ) values(
      new.tenant_id,v_source,new.transaction_ref,v_rec.customer_tax_party_id,v_cert,'SERVICE',v_rec.withholding_base_remaining,v_tax,
      coalesce(new.tax_snapshot->'inbound_withholding','{}'::jsonb),new.journal_id,new.business_date,new.actor_user_id,new.device_id,new.reason
    );
    update public.customer_receivables set remaining_amount=0,withholding_base_remaining=0,updated_at=now() where tenant_id=new.tenant_id and sale_transaction_ref=v_source;
    insert into public.customer_receivable_allocations(
      tenant_id,receipt_transaction_ref,sale_transaction_ref,customer_ref,amount_applied,
      receipt_journal_id,business_date,actor_user_id,device_id,reason,cash_received,withheld_tax_amount
    ) values(
      new.tenant_id,new.transaction_ref,v_source,v_customer,v_ar_delta,
      new.journal_id,new.business_date,new.actor_user_id,new.device_id,new.reason,v_cash,v_tax
    );

  elsif new.transaction_type='RETUR_PENJUALAN' then
    v_source:=nullif(btrim(coalesce(new.facts_snapshot->>'original_transaction_ref','')),'');
    select e.transaction_type into v_orig_type from public.accounting_transaction_evidence e where e.tenant_id=new.tenant_id and e.transaction_ref=v_source;
    if v_orig_type='JUAL_KREDIT' then
      select * into v_rec from public.customer_receivables r where r.tenant_id=new.tenant_id and r.sale_transaction_ref=v_source for update;
      if not found then raise exception 'credit_sale_receivable_not_found' using errcode='P0002'; end if;
      if v_rec.withholding_tax_object<>'NONE' then raise exception 'withholding_receivable_return_requires_dedicated_correction_flow' using errcode='23514'; end if;
      select coalesce(sum(l.credit-l.debit),0)::bigint into v_ar_delta from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='1-1050';
      if v_ar_delta<=0 then raise exception 'credit_sale_return_receivable_reduction_missing' using errcode='23514'; end if;
      if v_rec.remaining_amount<v_ar_delta then raise exception 'credit_sale_return_exceeds_open_receivable_requires_refund_flow' using errcode='23514'; end if;
      if v_rec.remaining_amount-v_ar_delta < coalesce((select a.allowance_amount from public.receivable_allowances a where a.tenant_id=new.tenant_id and a.sale_transaction_ref=v_source),0) then raise exception 'credit_sale_return_requires_allowance_reduction' using errcode='23514'; end if;
      update public.customer_receivables set remaining_amount=remaining_amount-v_ar_delta,updated_at=now() where tenant_id=new.tenant_id and sale_transaction_ref=v_source;
    end if;
  end if;
  return new;
end; $function$;
-- private.enforce_extended_withholding_evidence()
CREATE OR REPLACE FUNCTION private.enforce_extended_withholding_evidence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_party uuid; v_ref text; v_object text; v_gross bigint; v_base bigint; v_liability_account text; v_delta bigint; v_tax bigint; v_cash bigint; v_l public.extended_withholding_liabilities%rowtype;
begin
  if new.transaction_type='PPH23_15_ACCRUAL' then
    v_party:=(new.facts_snapshot->>'counterparty_tax_party_id')::uuid; v_ref=btrim(new.facts_snapshot->>'counterparty_ref');
    v_object:=upper(new.tax_snapshot->>'source_tax_object'); v_base:=(new.tax_snapshot->>'withholding_base')::bigint;
    v_liability_account:=case v_object when 'DIVIDEND' then '2-2080' else '2-2020' end;
    select coalesce(sum(l.credit-l.debit),0)::bigint into v_delta from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code=v_liability_account;
    if v_delta<=0 or v_delta<>v_base then raise exception 'extended_withholding_source_gl_mismatch' using errcode='23514'; end if;
    insert into public.extended_withholding_liabilities(tenant_id,source_transaction_ref,counterparty_ref,counterparty_party_id,business_date,tax_object_code,liability_account,original_amount,remaining_amount,withholding_base_original,withholding_base_remaining,source_journal_id,actor_user_id,device_id,reason)
    values(new.tenant_id,new.transaction_ref,v_ref,v_party,new.business_date,v_object,v_liability_account,v_delta,v_delta,v_base,v_base,new.journal_id,new.actor_user_id,new.device_id,new.reason);
  elsif new.transaction_type='BAYAR_PPH23_15' then
    v_ref:=btrim(new.facts_snapshot->>'source_ref');
    select * into strict v_l from public.extended_withholding_liabilities l where l.tenant_id=new.tenant_id and l.source_transaction_ref=v_ref for update;
    select coalesce(sum(case when l.account_code=v_l.liability_account then l.debit-l.credit else 0 end),0)::bigint,
           coalesce(sum(case when l.account_code='2-2050' then l.credit-l.debit else 0 end),0)::bigint,
           coalesce(sum(case when l.account_code in ('1-1010','1-1030') then l.credit-l.debit else 0 end),0)::bigint
      into v_delta,v_tax,v_cash from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id;
    if v_delta<>v_l.remaining_amount or v_tax<=0 or v_cash+v_tax<>v_delta then raise exception 'extended_withholding_payment_gl_mismatch' using errcode='23514'; end if;
    update public.extended_withholding_liabilities set remaining_amount=0,withholding_base_remaining=0,updated_at=now() where tenant_id=new.tenant_id and source_transaction_ref=v_ref;
    insert into public.extended_withholding_payments(tenant_id,payment_transaction_ref,source_transaction_ref,counterparty_party_id,tax_object_code,gross_applied,cash_paid,withholding_amount,payment_journal_id,business_date,legal_rule_snapshot,actor_user_id,device_id,reason)
    values(new.tenant_id,new.transaction_ref,v_ref,v_l.counterparty_party_id,v_l.tax_object_code,v_delta,v_cash,v_tax,new.journal_id,new.business_date,new.tax_snapshot,new.actor_user_id,new.device_id,new.reason);
  end if;
  return new;
end; $function$;
-- private.enforce_owner_adjustment_evidence()
CREATE OR REPLACE FUNCTION private.enforce_owner_adjustment_evidence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_asset uuid;
  v_a public.fixed_assets%rowtype;
  v_cost bigint;
  v_amount bigint;
  v_accum_credit bigint;
  v_expense bigint;
  v_seq integer;
  v_month date;
  v_expected_month date;
  v_basis bigint;
  v_target bigint;
  v_source text;
  v_rec public.customer_receivables%rowtype;
  v_previous bigint:=0;
  v_target_allowance bigint;
  v_delta bigint;
  v_allowance_gl bigint;
begin
  if new.transaction_type='BELI_ASET_TUNAI' then
    v_cost:=(new.facts_snapshot->>'cost')::bigint;
    select coalesce(sum(l.debit-l.credit),0)::bigint into v_amount from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='1-1060';
    if v_amount<>v_cost then raise exception 'fixed_asset_acquisition_gl_mismatch' using errcode='23514'; end if;
    insert into public.fixed_assets(tenant_id,asset_ref,asset_name,acquisition_date,depreciation_start_date,cost,residual_value,useful_life_months,depreciation_method,accumulated_depreciation,status,acquisition_journal_id,actor_user_id,device_id,reason)
    values(new.tenant_id,btrim(new.facts_snapshot->>'asset_ref'),btrim(new.facts_snapshot->>'asset_name'),new.business_date,(new.facts_snapshot->>'depreciation_start_date')::date,v_cost,coalesce((new.facts_snapshot->>'residual_value')::bigint,0),(new.facts_snapshot->>'useful_life_months')::integer,'STRAIGHT_LINE',0,'ACTIVE',new.journal_id,new.actor_user_id,new.device_id,new.reason);
  elsif new.transaction_type='PENYUSUTAN_BULANAN' then
    v_asset:=(new.facts_snapshot->>'asset_id')::uuid;
    select * into strict v_a from public.fixed_assets a where a.tenant_id=new.tenant_id and a.asset_id=v_asset for update;
    select count(*)::integer+1 into v_seq from public.fixed_asset_depreciation_events e where e.tenant_id=new.tenant_id and e.asset_id=v_asset;
    if v_seq>v_a.useful_life_months then raise exception 'fixed_asset_fully_depreciated' using errcode='23514'; end if;
    v_month:=date_trunc('month',new.business_date)::date;
    v_expected_month:=(date_trunc('month',v_a.depreciation_start_date)::date+make_interval(months=>v_seq-1))::date;
    if v_month<>v_expected_month then raise exception 'depreciation_month_must_be_posted_sequentially' using errcode='23514'; end if;
    v_basis:=v_a.cost-v_a.residual_value;
    if v_seq=v_a.useful_life_months then v_target:=v_basis; else v_target:=round(v_basis::numeric*v_seq::numeric/v_a.useful_life_months::numeric)::bigint; end if;
    v_amount:=v_target-v_a.accumulated_depreciation;
    select coalesce(sum(l.debit-l.credit),0)::bigint into v_expense from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='6-6060';
    select coalesce(sum(l.credit-l.debit),0)::bigint into v_accum_credit from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='1-1070';
    if v_amount<=0 or v_expense<>v_amount or v_accum_credit<>v_amount then raise exception 'depreciation_gl_mismatch' using errcode='23514'; end if;
    insert into public.fixed_asset_depreciation_events(tenant_id,asset_id,depreciation_month,sequence_no,amount,accumulated_after,journal_id,transaction_ref,actor_user_id,device_id,reason)
    values(new.tenant_id,v_asset,v_month,v_seq,v_amount,v_target,new.journal_id,new.transaction_ref,new.actor_user_id,new.device_id,new.reason);
    update public.fixed_assets set accumulated_depreciation=v_target,status=case when v_target=v_basis then 'FULLY_DEPRECIATED' else 'ACTIVE' end,updated_at=now() where tenant_id=new.tenant_id and asset_id=v_asset;
  elsif new.transaction_type='ATUR_CADANGAN_PIUTANG' then
    v_source:=btrim(new.facts_snapshot->>'source_sale_ref');
    select * into strict v_rec from public.customer_receivables r where r.tenant_id=new.tenant_id and r.sale_transaction_ref=v_source for update;
    v_target_allowance:=(new.facts_snapshot->>'target_allowance')::bigint;
    select coalesce((select a.allowance_amount from public.receivable_allowances a where a.tenant_id=new.tenant_id and a.sale_transaction_ref=v_source),0) into v_previous;
    v_delta:=v_target_allowance-v_previous;
    if v_target_allowance>v_rec.remaining_amount or v_delta=0 then raise exception 'invalid_receivable_allowance_target' using errcode='23514'; end if;
    select coalesce(sum(l.credit-l.debit),0)::bigint into v_allowance_gl from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='1-1080';
    select coalesce(sum(l.debit-l.credit),0)::bigint into v_expense from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='6-6070';
    if v_allowance_gl<>v_delta or v_expense<>v_delta then raise exception 'receivable_allowance_gl_mismatch' using errcode='23514'; end if;
    insert into public.receivable_allowances(tenant_id,sale_transaction_ref,customer_ref,allowance_amount) values(new.tenant_id,v_source,v_rec.customer_ref,v_target_allowance)
      on conflict(tenant_id,sale_transaction_ref) do update set allowance_amount=excluded.allowance_amount,updated_at=now();
    insert into public.receivable_allowance_events(tenant_id,adjustment_transaction_ref,sale_transaction_ref,previous_allowance,target_allowance,delta,journal_id,business_date,actor_user_id,device_id,reason)
    values(new.tenant_id,new.transaction_ref,v_source,v_previous,v_target_allowance,v_delta,new.journal_id,new.business_date,new.actor_user_id,new.device_id,new.reason);
  end if;
  return new;
end;
$function$;
-- private.enforce_payroll_evidence()
CREATE OR REPLACE FUNCTION private.enforce_payroll_evidence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_s jsonb;
  v_employee uuid;
  v_profile uuid;
  v_expense bigint;
  v_salary bigint;
  v_pph bigint;
  v_source text;
  v_payable public.employee_payables%rowtype;
  v_amount bigint;
begin
  if new.transaction_type='GAJI_BULANAN' then
    v_s:=new.tax_snapshot;
    if jsonb_typeof(v_s)<>'object' or nullif(v_s->>'legal_basis','') is null then raise exception 'payroll_tax_snapshot_required' using errcode='23514'; end if;
    v_employee:=(v_s->>'employee_party_id')::uuid;
    v_profile:=(v_s->>'profile_id')::uuid;
    if v_employee is distinct from (new.facts_snapshot->>'employee_party_id')::uuid then raise exception 'payroll_employee_snapshot_mismatch' using errcode='23514'; end if;

    select coalesce(sum(l.debit-l.credit),0)::bigint into v_expense
    from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='6-6010';
    select coalesce(sum(l.credit-l.debit),0)::bigint into v_salary
    from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='2-2030';
    select coalesce(sum(l.credit-l.debit),0)::bigint into v_pph
    from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='2-2040';
    if v_expense<>(v_s->>'taxable_gross')::bigint
       or v_salary<>(v_s->>'salary_payable_amount')::bigint
       or v_pph<>(v_s->>'withholding_adjustment')::bigint then
      raise exception 'payroll_gl_does_not_match_tax_evidence' using errcode='23514';
    end if;

    insert into public.payroll_tax_evidence(
      tenant_id,payroll_ref,employee_party_id,profile_id,payroll_month,business_date,is_final_period,
      tax_method,ptkp_status,ptkp_amount,ter_category,cash_compensation,tax_allowance,taxable_gross,
      employee_pension_contribution,mandatory_religious_contribution,job_expense_deduction,
      ytd_taxable_gross,ytd_job_expense,ytd_pension_contribution,ytd_religious_contribution,
      annual_taxable_income,annual_pph21,prior_withholding,withholding_adjustment,salary_payable_amount,
      rule_snapshot,journal_id,actor_user_id,device_id,reason
    ) values(
      new.tenant_id,new.transaction_ref,v_employee,v_profile,(v_s->>'payroll_month')::date,new.business_date,(v_s->>'is_final_period')::boolean,
      v_s->>'tax_method',v_s->>'ptkp_status',(v_s->>'ptkp_amount')::bigint,v_s->>'ter_category',
      (v_s->>'cash_compensation')::bigint,(v_s->>'tax_allowance')::bigint,(v_s->>'taxable_gross')::bigint,
      (v_s->>'employee_pension_contribution')::bigint,(v_s->>'mandatory_religious_contribution')::bigint,(v_s->>'job_expense_deduction')::bigint,
      (v_s->>'ytd_taxable_gross')::bigint,(v_s->>'ytd_job_expense')::bigint,(v_s->>'ytd_pension_contribution')::bigint,(v_s->>'ytd_religious_contribution')::bigint,
      (v_s->>'annual_taxable_income')::bigint,(v_s->>'annual_pph21')::bigint,(v_s->>'prior_withholding')::bigint,(v_s->>'withholding_adjustment')::bigint,
      (v_s->>'salary_payable_amount')::bigint,v_s->'rule',new.journal_id,new.actor_user_id,new.device_id,new.reason
    );
    insert into public.employee_payables(
      tenant_id,payroll_ref,employee_party_id,business_date,original_amount,remaining_amount,payroll_journal_id,
      actor_user_id,device_id,reason
    ) values(
      new.tenant_id,new.transaction_ref,v_employee,new.business_date,(v_s->>'salary_payable_amount')::bigint,(v_s->>'salary_payable_amount')::bigint,
      new.journal_id,new.actor_user_id,new.device_id,new.reason
    );
  elsif new.transaction_type='BAYAR_GAJI' then
    v_source:=nullif(btrim(coalesce(new.facts_snapshot->>'source_payroll_ref','')),'');
    if v_source is null then raise exception 'source_payroll_ref_required' using errcode='22023'; end if;
    select * into v_payable from public.employee_payables p
    where p.tenant_id=new.tenant_id and p.payroll_ref=v_source for update;
    if not found then raise exception 'salary_payable_not_found' using errcode='P0002'; end if;
    select coalesce(sum(l.debit-l.credit),0)::bigint into v_amount
    from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='2-2030';
    if v_amount<=0 or v_amount>v_payable.remaining_amount then raise exception 'salary_payment_gl_mismatch' using errcode='23514'; end if;
    update public.employee_payables set remaining_amount=remaining_amount-v_amount,updated_at=now()
      where tenant_id=new.tenant_id and payroll_ref=v_source;
    insert into public.payroll_payment_allocations(
      tenant_id,payment_transaction_ref,payroll_ref,employee_party_id,amount_applied,payment_journal_id,business_date,
      actor_user_id,device_id,reason
    ) values(
      new.tenant_id,new.transaction_ref,v_source,v_payable.employee_party_id,v_amount,new.journal_id,new.business_date,
      new.actor_user_id,new.device_id,new.reason
    );
  end if;
  return new;
end;
$function$;
-- private.enforce_supplier_liability_evidence()
CREATE OR REPLACE FUNCTION private.enforce_supplier_liability_evidence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_vendor uuid;
  v_supplier_ref text;
  v_source_ref text;
  v_ap_delta bigint;
  v_liability public.supplier_liabilities%rowtype;
  v_input_doc public.tax_documents%rowtype;
  v_withholding bigint;
  v_expected_withholding bigint:=0;
  v_expected_tax jsonb;
  v_party public.tax_parties%rowtype;
  v_expected_tax_code text;
  v_expected_rate_object text;
begin
  if new.transaction_type in ('BELI_KREDIT','BEBAN_VENDOR_KREDIT') then
    v_supplier_ref:=nullif(btrim(coalesce(new.facts_snapshot->>'supplier_id','')),'');
    if v_supplier_ref is null then raise exception 'supplier_required_for_credit_liability' using errcode='22023'; end if;
    begin v_vendor:=(new.facts_snapshot->>'vendor_party_id')::uuid;
    exception when others then raise exception 'vendor_tax_party_required_for_credit_liability' using errcode='22023'; end;
    if not exists(
      select 1 from public.tax_parties tp
      where tp.tenant_id=new.tenant_id and tp.party_id=v_vendor and tp.party_kind='VENDOR'
        and tp.valid_from<=new.business_date and (tp.valid_to is null or tp.valid_to>=new.business_date)
    ) then raise exception 'vendor_tax_party_evidence_invalid' using errcode='23514'; end if;

    if nullif(btrim(coalesce(new.facts_snapshot->>'input_tax_document_id','')),'') is not null then
      select * into strict v_input_doc
      from public.tax_documents d
      where d.tenant_id=new.tenant_id
        and d.tax_document_id=(new.facts_snapshot->>'input_tax_document_id')::uuid
        and d.document_type='VAT_INPUT';
      if v_input_doc.counterparty_id is distinct from v_vendor then
        raise exception 'input_tax_invoice_vendor_mismatch' using errcode='23514';
      end if;
    end if;

    select coalesce(sum(l.credit-l.debit),0)::bigint into v_ap_delta
    from public.accounting_journal_lines l
    where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='2-2020';
    if v_ap_delta<=0 then raise exception 'supplier_liability_missing' using errcode='23514'; end if;

    if new.transaction_type='BELI_KREDIT' then
      if upper(coalesce(nullif(btrim(new.facts_snapshot->>'tax_object'),''),'NONE'))<>'NONE' then
        raise exception 'inventory_purchase_cannot_define_withholding_tax_object' using errcode='23514';
      end if;
      insert into public.supplier_liabilities(
        tenant_id,purchase_transaction_ref,supplier_ref,vendor_party_id,business_date,
        original_amount,remaining_amount,purchase_journal_id,actor_user_id,device_id,reason,
        liability_kind,tax_object_code,withholding_base_original,withholding_base_remaining
      ) values(
        new.tenant_id,new.transaction_ref,v_supplier_ref,v_vendor,new.business_date,
        v_ap_delta,v_ap_delta,new.journal_id,new.actor_user_id,new.device_id,new.reason,
        'INVENTORY','NONE',0,0
      );
    else
      select * into strict v_party
      from public.tax_parties tp
      where tp.tenant_id=new.tenant_id and tp.party_id=v_vendor;
      if coalesce(new.facts_snapshot->>'withholding_base','') !~ '^[1-9][0-9]*$' then
        raise exception 'withholding_base_required_for_vendor_expense' using errcode='22023';
      end if;
      insert into public.supplier_liabilities(
        tenant_id,purchase_transaction_ref,supplier_ref,vendor_party_id,business_date,
        original_amount,remaining_amount,purchase_journal_id,actor_user_id,device_id,reason,
        liability_kind,tax_object_code,withholding_base_original,withholding_base_remaining
      ) values(
        new.tenant_id,new.transaction_ref,v_supplier_ref,v_vendor,new.business_date,
        v_ap_delta,v_ap_delta,new.journal_id,new.actor_user_id,new.device_id,new.reason,
        case when upper(v_party.tax_object)='SERVICE' then 'SERVICE' else 'RENT' end,
        upper(v_party.tax_object),
        (new.facts_snapshot->>'withholding_base')::bigint,
        (new.facts_snapshot->>'withholding_base')::bigint
      );
    end if;

  elsif new.transaction_type='BAYAR_VENDOR' then
    v_source_ref:=nullif(btrim(coalesce(new.facts_snapshot->>'source_purchase_ref','')),'');
    if v_source_ref is null then raise exception 'source_purchase_ref_required' using errcode='22023'; end if;
    select * into v_liability
    from public.supplier_liabilities s
    where s.tenant_id=new.tenant_id and s.purchase_transaction_ref=v_source_ref
    for update;
    if not found then raise exception 'supplier_liability_not_found' using errcode='P0002'; end if;
    if new.business_date<v_liability.business_date then raise exception 'supplier_payment_before_source_liability_date' using errcode='23514'; end if;

    select coalesce(sum(l.debit-l.credit),0)::bigint into v_ap_delta
    from public.accounting_journal_lines l
    where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code='2-2020';
    if v_ap_delta<=0 or v_ap_delta>v_liability.remaining_amount then
      raise exception 'supplier_payment_gl_liability_mismatch' using errcode='23514';
    end if;

    select coalesce(sum(l.credit-l.debit),0)::bigint into v_withholding
    from public.accounting_journal_lines l
    where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code in ('2-2050','2-2060');

    if v_liability.tax_object_code='NONE' then
      if v_withholding<>0 then raise exception 'source_liability_does_not_allow_withholding' using errcode='23514'; end if;
    else
      if v_ap_delta<>v_liability.remaining_amount then
        raise exception 'taxed_supplier_liability_requires_full_settlement' using errcode='23514';
      end if;
      select * into strict v_party from public.tax_parties tp
      where tp.tenant_id=new.tenant_id and tp.party_id=v_liability.vendor_party_id
        and tp.valid_from<=new.business_date and (tp.valid_to is null or tp.valid_to>=new.business_date);
      if v_liability.tax_object_code='LAND_BUILDING_RENT' then
        v_expected_tax_code:='PPH_FINAL_4_2'; v_expected_rate_object:='LAND_BUILDING_RENT';
      elsif v_liability.tax_object_code in ('SERVICE','ASSET_RENT_NON_LAND_BUILDING') then
        if upper(v_party.tax_regime)='PPH_FINAL_UMKM' then
          if not private.is_pph_final_umkm_evidence_valid(
            v_party.tax_regime,v_party.taxpayer_type,v_party.turnover_eligibility,
            v_party.certificate_status,v_party.legal_basis,new.business_date
          ) then raise exception 'vendor_final_tax_evidence_invalid' using errcode='23514'; end if;
          v_expected_tax_code:='PPH_FINAL_UMKM'; v_expected_rate_object:='TURNOVER';
        else
          v_expected_tax_code:='PPH23'; v_expected_rate_object:=v_liability.tax_object_code;
        end if;
      else
        raise exception 'unsupported_source_liability_tax_object' using errcode='23514';
      end if;
      v_expected_tax:=private.resolve_tax_rate_snapshot(v_expected_tax_code,v_expected_rate_object,new.business_date,'DEFAULT');
      v_expected_withholding:=round(v_liability.withholding_base_remaining::numeric*(v_expected_tax->>'effective_rate')::numeric)::bigint;
      if v_withholding<>v_expected_withholding then
        raise exception 'supplier_payment_withholding_does_not_match_source_tax_rule' using errcode='23514';
      end if;
    end if;

    update public.supplier_liabilities
      set remaining_amount=remaining_amount-v_ap_delta,
          withholding_base_remaining=case when tax_object_code='NONE' then withholding_base_remaining else 0 end,
          updated_at=now()
    where tenant_id=new.tenant_id and purchase_transaction_ref=v_source_ref;

    insert into public.supplier_payment_allocations(
      tenant_id,payment_transaction_ref,purchase_transaction_ref,vendor_party_id,
      gross_applied,cash_paid,withholding_amount,payment_journal_id,business_date,
      actor_user_id,device_id,reason
    ) values(
      new.tenant_id,new.transaction_ref,v_source_ref,v_liability.vendor_party_id,
      v_ap_delta,v_ap_delta-v_withholding,v_withholding,new.journal_id,new.business_date,
      new.actor_user_id,new.device_id,new.reason
    );
  end if;
  return new;
end;
$function$;
-- private.enforce_tax_remittance_evidence()
CREATE OR REPLACE FUNCTION private.enforce_tax_remittance_evidence()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ref_id uuid; v_ref public.tax_payment_refs%rowtype; v_account text; v_debit bigint; v_cash_credit bigint; v_payment_reference text;
begin
  if new.transaction_type<>'SETOR_PAJAK' then return new; end if;
  v_ref_id:=(new.facts_snapshot->>'payment_ref_id')::uuid; v_payment_reference:=btrim(new.facts_snapshot->>'payment_reference');
  select * into strict v_ref from public.tax_payment_refs r where r.tenant_id=new.tenant_id and r.payment_ref_id=v_ref_id for update;
  if v_ref.status<>'CREATED' then raise exception 'tax_payment_reference_not_open' using errcode='23514'; end if;
  v_account:=case v_ref.tax_code when 'PPN' then '2-2010' when 'PPH21' then '2-2040' when 'PPH23' then '2-2050' when 'PPH_FINAL' then '2-2060' when 'PPH25' then '1-1110' when 'PPH29' then '2-2070' else null end;
  select coalesce(sum(l.debit-l.credit),0)::bigint into v_debit from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code=v_account;
  select coalesce(sum(l.credit-l.debit),0)::bigint into v_cash_credit from public.accounting_journal_lines l where l.tenant_id=new.tenant_id and l.journal_id=new.journal_id and l.account_code in ('1-1010','1-1030');
  if v_debit<>v_ref.amount or v_cash_credit<>v_ref.amount then raise exception 'tax_remittance_gl_mismatch' using errcode='23514'; end if;
  update public.tax_payment_refs set status='PAID',payment_reference=v_payment_reference,paid_at=now(),payment_journal_id=new.journal_id,updated_at=now() where tenant_id=new.tenant_id and payment_ref_id=v_ref_id and status='CREATED';
  if not found then raise exception 'tax_payment_reference_state_conflict' using errcode='40001'; end if;
  return new;
end; $function$;
-- private.get_pos_role_internal(p_device_id text)
CREATE OR REPLACE FUNCTION private.get_pos_role_internal(p_device_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_tenant text;
  v_role text;
begin
  if v_actor is null then raise exception 'authenticated session required' using errcode='42501'; end if;
  select d.tenant_id into v_tenant
  from public.devices d
  where d.device_id = trim(p_device_id) and d.user_id = v_actor;
  if v_tenant is null then raise exception 'device is not bound to actor' using errcode='42501'; end if;
  select m.role into v_role
  from private.pos_memberships m
  where m.tenant_id = v_tenant and m.user_id = v_actor and m.is_active = true;
  return v_role;
end;
$function$;
-- private.guard_app_config_inventory()
CREATE OR REPLACE FUNCTION private.guard_app_config_inventory()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin perform private.assert_app_config_inventory(); return null; end; $function$;
-- private.guard_coretax_export_gate()
CREATE OR REPLACE FUNCTION private.guard_coretax_export_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_document_type text;
  v_expected_template text;
BEGIN
  IF NEW.payload_sha256 IS NULL
     OR NEW.payload_sha256 !~ '^[0-9a-f]{64}$'
     OR NEW.payload_sha256 <> encode(
       extensions.digest(convert_to(NEW.xml_payload, 'UTF8'), 'sha256'),
       'hex'
     ) THEN
    RAISE EXCEPTION 'coretax_payload_sha256_mismatch' USING errcode = '23514';
  END IF;

  SELECT d.document_type INTO v_document_type
  FROM public.tax_documents AS d
  WHERE d.tax_document_id = NEW.tax_document_id
    AND d.tenant_id = NEW.tenant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'coretax_export_document_tenant_mismatch' USING errcode = '23514';
  END IF;

  v_expected_template := CASE v_document_type
    WHEN 'VAT_OUTPUT' THEN 'FAKTUR_KELUARAN'
    WHEN 'VAT_REPLACEMENT' THEN 'FAKTUR_KELUARAN'
    WHEN 'PPH23_UNIFICATION' THEN 'BPPU'
    WHEN 'PPH21_26' THEN 'BPMP'
    ELSE NULL
  END;
  IF v_expected_template IS NULL OR NEW.xml_template_code IS DISTINCT FROM v_expected_template THEN
    RAISE EXCEPTION 'coretax_template_document_type_mismatch' USING errcode = '23514';
  END IF;

  IF NOT private.can_export_coretax(NEW.tenant_id, NEW.tax_document_id) THEN
    RAISE EXCEPTION 'coretax_export_blocked_by_accounting_snapshot_or_template_gate' USING errcode = '23514';
  END IF;

  RETURN NEW;
END;
$function$;
-- private.guard_coretax_template()
CREATE OR REPLACE FUNCTION private.guard_coretax_template()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if current_user<>'postgres' and not private.btp_is_super_admin() then raise exception 'coretax template mutation denied' using errcode='42501'; end if;
  if tg_op='DELETE' then raise exception 'coretax template history is immutable' using errcode='55000'; end if;
  if tg_op='UPDATE' then
    if old.is_verified and (old.template_code,old.template_version,old.official_source_url,old.official_last_update,old.xml_template,old.generator_spec,old.template_sha256,old.verified_by,old.verified_at)
      is distinct from (new.template_code,new.template_version,new.official_source_url,new.official_last_update,new.xml_template,new.generator_spec,new.template_sha256,new.verified_by,new.verified_at) then
      raise exception 'verified coretax template content is immutable' using errcode='55000';
    end if;
    if old.is_active and new.is_active then return new; end if;
    if old.is_active and not new.is_active then return new; end if;
    if not old.is_active and new.is_active and not new.is_verified then raise exception 'unverified coretax template cannot be activated' using errcode='23514'; end if;
  end if;
  return new;
end;
$function$;