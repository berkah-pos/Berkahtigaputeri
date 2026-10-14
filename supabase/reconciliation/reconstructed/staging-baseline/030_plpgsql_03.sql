-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source. PL/pgSQL bodies are installed before SQL-language wrappers.

-- private.assert_sufficient_liquid_funds(p_tenant_id uuid, p_account_code text, p_amount bigint)
CREATE OR REPLACE FUNCTION private.assert_sufficient_liquid_funds(p_tenant_id uuid, p_account_code text, p_amount bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_balance bigint;
begin
  if p_account_code not in ('1-1010','1-1020','1-1030') then raise exception 'invalid_liquid_account' using errcode='23514'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'liquid_outflow_amount_must_be_positive' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':liquid:'||p_account_code,7336));
  select coalesce(sum(debit-credit),0)::bigint into v_balance
  from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code=p_account_code;
  if v_balance<p_amount then raise exception 'insufficient_liquid_funds' using errcode='23514'; end if;
end;
$function$;
-- private.build_bad_debt_allowance_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
CREATE OR REPLACE FUNCTION private.build_bad_debt_allowance_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_source text:=nullif(btrim(coalesce(p_facts->>'source_sale_ref','')),'');
  v_rec public.customer_receivables%rowtype;
  v_target bigint;
  v_current bigint:=0;
  v_delta bigint;
  v_journal jsonb:='[]'::jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_business_date is null or v_source is null then raise exception 'receivable_allowance_source_required' using errcode='22023'; end if;
  if coalesce(p_facts->>'target_allowance','') !~ '^(0|[1-9][0-9]*)$' then raise exception 'target_allowance_required' using errcode='22023'; end if;
  v_target:=(p_facts->>'target_allowance')::bigint;
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':allowance:'||v_source,7335));
  select * into strict v_rec from public.customer_receivables r where r.tenant_id=p_tenant_id and r.sale_transaction_ref=v_source for update;
  if v_target>v_rec.remaining_amount then raise exception 'allowance_cannot_exceed_outstanding_receivable' using errcode='23514'; end if;
  select coalesce((select a.allowance_amount from public.receivable_allowances a where a.tenant_id=p_tenant_id and a.sale_transaction_ref=v_source),0) into v_current;
  v_delta:=v_target-v_current;
  if v_delta=0 then raise exception 'receivable_allowance_target_unchanged' using errcode='22023'; end if;
  if v_delta>0 then
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','6-6070','debit',v_delta,'credit',0,'memo','Estimasi piutang tidak tertagih'));
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','1-1080','debit',0,'credit',v_delta,'memo','Cadangan kerugian piutang'));
  else
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','1-1080','debit',abs(v_delta),'credit',0,'memo','Pengurangan cadangan piutang'));
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','6-6070','debit',0,'credit',abs(v_delta),'memo','Pembalikan estimasi piutang'));
  end if;
  return jsonb_build_object('journal_lines',v_journal,'tax_snapshot','{}'::jsonb,'source_sale_ref',v_source,'customer_ref',v_rec.customer_ref,'previous_allowance',v_current,'target_allowance',v_target,'delta',v_delta);
exception when no_data_found then raise exception 'customer_receivable_not_found' using errcode='P0002';
end;
$function$;
-- private.build_customer_receipt_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
CREATE OR REPLACE FUNCTION private.build_customer_receipt_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_source text:=nullif(btrim(coalesce(p_facts->>'source_sale_ref','')),'');
  v_customer text:=nullif(btrim(coalesce(p_facts->>'customer_id','')),'');
  v_amount bigint;
  v_method text:=upper(coalesce(p_facts->>'payment_method',''));
  v_payment_account text;
  v_journal jsonb:='[]'::jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_business_date is null then raise exception 'business_date_required' using errcode='22023'; end if;
  if v_source is null then raise exception 'source_sale_ref_required' using errcode='22023'; end if;
  if v_customer is null then raise exception 'customer_required_for_receivable_collection' using errcode='22023'; end if;
  if coalesce(p_facts->>'gross_receipt','') !~ '^[1-9][0-9]*$' then raise exception 'gross_receipt_required' using errcode='22023'; end if;
  v_amount:=(p_facts->>'gross_receipt')::bigint;
  if v_method='CASH' then v_payment_account:='1-1010';
  elsif v_method='QRIS' then v_payment_account:='1-1020';
  elsif v_method='BANK' then v_payment_account:='1-1030';
  else raise exception 'payment_method_must_be_cash_qris_or_bank' using errcode='22023'; end if;
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',v_payment_account,'debit',v_amount,'credit',0,'memo','Penerimaan pembayaran pelanggan'));
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','1-1050','debit',0,'credit',v_amount,'memo','Pengurangan piutang pelanggan'));
  return jsonb_build_object('journal_lines',v_journal,'source_sale_ref',v_source,'customer_id',v_customer,'gross_receipt',v_amount);
end;
$function$;
-- private.build_customer_withholding_receipt_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
CREATE OR REPLACE FUNCTION private.build_customer_withholding_receipt_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_source text:=nullif(btrim(coalesce(p_facts->>'source_sale_ref','')),'');
  v_customer text:=nullif(btrim(coalesce(p_facts->>'customer_id','')),'');
  v_cert text:=nullif(upper(btrim(coalesce(p_facts->>'withholding_certificate_number',''))),'');
  v_method text:=upper(coalesce(p_facts->>'payment_method',''));
  v_rec public.customer_receivables%rowtype;
  v_party public.tax_parties%rowtype;
  v_rule jsonb;
  v_tax bigint;
  v_cash bigint;
  v_pay_account text;
  v_journal jsonb:='[]'::jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if v_source is null or v_customer is null or v_cert is null or length(v_cert)<3 then raise exception 'withholding_receipt_identity_and_certificate_required' using errcode='22023'; end if;
  select * into strict v_rec from public.customer_receivables r where r.tenant_id=p_tenant_id and r.sale_transaction_ref=v_source for update;
  if v_rec.customer_ref<>v_customer then raise exception 'customer_receivable_customer_mismatch' using errcode='23514'; end if;
  if p_business_date<v_rec.business_date then raise exception 'customer_receipt_before_credit_sale_date' using errcode='23514'; end if;
  if v_rec.withholding_tax_object<>'SERVICE' or v_rec.withholding_base_remaining<=0 or v_rec.customer_tax_party_id is null then raise exception 'receivable_not_eligible_for_inbound_pph23' using errcode='23514'; end if;
  if v_rec.remaining_amount<>v_rec.original_amount then raise exception 'withholding_receivable_requires_full_uncollected_balance' using errcode='23514'; end if;
  if exists(select 1 from public.customer_withholding_tax_credits c where c.tenant_id=p_tenant_id and (c.source_sale_ref=v_source or c.certificate_number=v_cert)) then raise exception 'duplicate_withholding_credit_evidence' using errcode='23505'; end if;
  select * into strict v_party from public.tax_parties p where p.tenant_id=p_tenant_id and p.party_id=v_rec.customer_tax_party_id and p.party_kind='CUSTOMER' and p.is_withholding_agent and p.valid_from<=p_business_date and (p.valid_to is null or p.valid_to>=p_business_date);
  v_rule:=private.resolve_tax_rate_snapshot('PPH23','SERVICE',p_business_date,'DEFAULT');
  v_tax:=round(v_rec.withholding_base_remaining::numeric*(v_rule->>'effective_rate')::numeric)::bigint;
  if v_tax<=0 or v_tax>=v_rec.remaining_amount then raise exception 'invalid_customer_withholding_amount' using errcode='23514'; end if;
  v_cash:=v_rec.remaining_amount-v_tax;
  if v_method='CASH' then v_pay_account:='1-1010'; elsif v_method='BANK' then v_pay_account:='1-1030'; else raise exception 'receipt_method_must_be_cash_or_bank' using errcode='22023'; end if;
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',v_pay_account,'debit',v_cash,'credit',0,'memo','Penerimaan customer setelah PPh23'));
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','1-1100','debit',v_tax,'credit',0,'memo','Kredit pajak PPh23 dipotong customer'));
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','1-1050','debit',0,'credit',v_rec.remaining_amount,'memo','Pelunasan piutang customer'));
  return jsonb_build_object(
    'journal_lines',v_journal,
    'tax_snapshot',jsonb_build_object('inbound_withholding',v_rule||jsonb_build_object('certificate_number',v_cert,'base',v_rec.withholding_base_remaining,'tax_amount',v_tax,'customer_tax_party_id',v_rec.customer_tax_party_id,'source_sale_ref',v_source)),
    'source_sale_ref',v_source,'customer_id',v_customer,'certificate_number',v_cert,
    'withholding_base',v_rec.withholding_base_remaining,'withholding_amount',v_tax,'cash_received',v_cash,'gross_receipt',v_rec.remaining_amount
  );
exception when no_data_found then raise exception 'customer_withholding_source_dependency_missing' using errcode='23514';
end; $function$;
-- private.build_depreciation_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
CREATE OR REPLACE FUNCTION private.build_depreciation_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_asset uuid;
  v_a public.fixed_assets%rowtype;
  v_count integer;
  v_seq integer;
  v_month date:=date_trunc('month',p_business_date)::date;
  v_expected_month date;
  v_basis bigint;
  v_target bigint;
  v_amount bigint;
  v_journal jsonb:='[]'::jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_business_date is null then raise exception 'business_date_required' using errcode='22023'; end if;
  begin v_asset:=(p_facts->>'asset_id')::uuid; exception when others then raise exception 'asset_id_required' using errcode='22023'; end;
  select * into strict v_a from public.fixed_assets a where a.tenant_id=p_tenant_id and a.asset_id=v_asset for update;
  if v_a.status<>'ACTIVE' then raise exception 'fixed_asset_not_active_for_depreciation' using errcode='23514'; end if;
  if p_business_date<v_a.depreciation_start_date then raise exception 'depreciation_before_start_date' using errcode='23514'; end if;
  select count(*)::integer into v_count from public.fixed_asset_depreciation_events e where e.tenant_id=p_tenant_id and e.asset_id=v_asset;
  v_seq:=v_count+1;
  if v_seq>v_a.useful_life_months then raise exception 'fixed_asset_fully_depreciated' using errcode='23514'; end if;
  v_expected_month:=(date_trunc('month',v_a.depreciation_start_date)::date + make_interval(months=>v_seq-1))::date;
  if v_month<>v_expected_month then raise exception 'depreciation_month_must_be_posted_sequentially' using errcode='23514'; end if;
  v_basis:=v_a.cost-v_a.residual_value;
  if v_seq=v_a.useful_life_months then v_target:=v_basis; else v_target:=round(v_basis::numeric*v_seq::numeric/v_a.useful_life_months::numeric)::bigint; end if;
  v_amount:=v_target-v_a.accumulated_depreciation;
  if v_amount<=0 then raise exception 'invalid_depreciation_amount' using errcode='23514'; end if;
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','6-6060','debit',v_amount,'credit',0,'memo','Penyusutan peralatan'));
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','1-1070','debit',0,'credit',v_amount,'memo','Akumulasi penyusutan peralatan'));
  return jsonb_build_object('journal_lines',v_journal,'tax_snapshot','{}'::jsonb,'asset_id',v_asset,'sequence_no',v_seq,'depreciation_month',v_month,'amount',v_amount,'accumulated_after',v_target);
exception when no_data_found then raise exception 'fixed_asset_not_found' using errcode='P0002';
end;
$function$;
-- private.build_extended_withholding_payment_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
CREATE OR REPLACE FUNCTION private.build_extended_withholding_payment_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_source text:=nullif(btrim(coalesce(p_facts->>'source_ref','')),''); v_method text:=upper(coalesce(p_facts->>'payment_method','')); v_pay_account text;
  v_l public.extended_withholding_liabilities%rowtype; v_rule jsonb; v_tax bigint; v_cash bigint; v_journal jsonb:='[]'::jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_facts ? 'tax_object' or p_facts ? 'withholding_rate' or p_facts ? 'withholding_base' or p_facts ? 'gross_liability' then raise exception 'extended_withholding_payment_economics_are_source_authoritative' using errcode='42501'; end if;
  if v_source is null then raise exception 'extended_withholding_source_ref_required' using errcode='22023'; end if;
  select * into strict v_l from public.extended_withholding_liabilities l where l.tenant_id=p_tenant_id and l.source_transaction_ref=v_source for update;
  if p_business_date<v_l.business_date then raise exception 'withholding_payment_before_source_date' using errcode='23514'; end if;
  if v_l.remaining_amount<=0 or v_l.remaining_amount<>v_l.original_amount or v_l.withholding_base_remaining<>v_l.withholding_base_original then raise exception 'extended_withholding_requires_full_open_liability' using errcode='23514'; end if;
  v_rule:=private.resolve_tax_rate_snapshot('PPH23',v_l.tax_object_code,p_business_date,'DEFAULT');
  v_tax:=round(v_l.withholding_base_remaining::numeric*(v_rule->>'effective_rate')::numeric)::bigint;
  if v_tax<=0 or v_tax>=v_l.remaining_amount then raise exception 'invalid_extended_pph23_withholding' using errcode='23514'; end if;
  v_cash:=v_l.remaining_amount-v_tax;
  if v_method='CASH' then v_pay_account:='1-1010'; elsif v_method='BANK' then v_pay_account:='1-1030'; else raise exception 'payment_method_must_be_cash_or_bank' using errcode='22023'; end if;
  perform private.assert_sufficient_liquid_funds(p_tenant_id,v_pay_account,v_cash);
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',v_l.liability_account,'debit',v_l.remaining_amount,'credit',0,'memo','Pelunasan kewajiban '||lower(v_l.tax_object_code)));
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',v_pay_account,'debit',0,'credit',v_cash,'memo','Pembayaran net setelah PPh23'));
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','2-2050','debit',0,'credit',v_tax,'memo','PPh23 dipotong 15%'));
  return jsonb_build_object('journal_lines',v_journal,'tax_snapshot',v_rule,'vendor_party_id',v_l.counterparty_party_id,'tax_code','PPH23','tax_object',v_l.tax_object_code,'withholding_base',v_l.withholding_base_remaining,'withholding_amount',v_tax,'gross_liability',v_l.remaining_amount,'cash_paid',v_cash,'source_ref',v_source);
exception when no_data_found then raise exception 'extended_withholding_liability_not_found' using errcode='P0002';
end; $function$;
-- private.build_extended_withholding_source_lines(p_tenant_id uuid, p_transaction_ref text, p_business_date date, p_facts jsonb, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION private.build_extended_withholding_source_lines(p_tenant_id uuid, p_transaction_ref text, p_business_date date, p_facts jsonb, p_actor uuid, p_device_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_party_id uuid; v_party public.tax_parties%rowtype; v_ref text; v_amount bigint; v_object text; v_expense_account text; v_liability_account text; v_journal jsonb:='[]'::jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_facts ? 'tax_object' or p_facts ? 'withholding_rate' or p_facts ? 'withholding_base' then raise exception 'withholding_tax_object_rate_and_base_are_server_authoritative' using errcode='42501'; end if;
  begin v_party_id:=(p_facts->>'counterparty_tax_party_id')::uuid; exception when others then raise exception 'counterparty_tax_party_required' using errcode='22023'; end;
  v_ref:=nullif(btrim(coalesce(p_facts->>'counterparty_ref','')),'');
  if v_ref is null or coalesce(p_facts->>'gross_amount','') !~ '^[1-9][0-9]*$' then raise exception 'counterparty_ref_and_gross_amount_required' using errcode='22023'; end if;
  v_amount:=(p_facts->>'gross_amount')::bigint;
  select * into strict v_party from public.tax_parties p where p.tenant_id=p_tenant_id and p.party_id=v_party_id and p.valid_from<=p_business_date and (p.valid_to is null or p.valid_to>=p_business_date);
  v_object:=upper(coalesce(v_party.tax_object,''));
  if v_object='ROYALTY' then
    if v_party.party_kind<>'VENDOR' then raise exception 'royalty_counterparty_must_be_vendor_evidence' using errcode='23514'; end if;
    v_expense_account:='6-6100'; v_liability_account:='2-2020';
  elsif v_object='INTEREST' then
    if v_party.party_kind<>'VENDOR' then raise exception 'interest_counterparty_must_be_vendor_evidence' using errcode='23514'; end if;
    v_expense_account:='6-6090'; v_liability_account:='2-2020';
  elsif v_object='DIVIDEND' then
    if v_party.party_kind<>'SHAREHOLDER' or coalesce((v_party.metadata->>'pph23_15_applicable')::boolean,false) is not true then raise exception 'dividend_pph23_15_requires_shareholder_legal_evidence' using errcode='23514'; end if;
    v_expense_account:='3-3020'; v_liability_account:='2-2080';
  else raise exception 'counterparty_not_eligible_for_pph23_15_source' using errcode='23514'; end if;
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',v_expense_account,'debit',v_amount,'credit',0,'memo','Pengakuan '||lower(v_object)));
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',v_liability_account,'debit',0,'credit',v_amount,'memo','Kewajiban '||lower(v_object)));
  return jsonb_build_object('journal_lines',v_journal,'tax_snapshot',jsonb_build_object('source_tax_object',v_object,'withholding_base',v_amount,'counterparty_party_id',v_party_id),'counterparty_party_id',v_party_id,'counterparty_ref',v_ref,'tax_object',v_object,'gross_amount',v_amount,'withholding_base',v_amount,'liability_account',v_liability_account);
exception when no_data_found then raise exception 'extended_withholding_counterparty_evidence_missing' using errcode='23514';
end; $function$;
-- private.build_fixed_asset_acquisition_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
CREATE OR REPLACE FUNCTION private.build_fixed_asset_acquisition_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ref text:=nullif(btrim(coalesce(p_facts->>'asset_ref','')),'');
  v_name text:=nullif(btrim(coalesce(p_facts->>'asset_name','')),'');
  v_cost bigint;
  v_residual bigint:=0;
  v_life integer;
  v_start date;
  v_method text:=upper(coalesce(p_facts->>'payment_method',''));
  v_payment_account text;
  v_journal jsonb:='[]'::jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_business_date is null or v_ref is null or v_name is null then raise exception 'fixed_asset_identity_required' using errcode='22023'; end if;
  if coalesce(p_facts->>'cost','') !~ '^[1-9][0-9]*$' then raise exception 'fixed_asset_cost_required' using errcode='22023'; end if;
  v_cost:=(p_facts->>'cost')::bigint;
  if p_facts ? 'residual_value' then
    if coalesce(p_facts->>'residual_value','') !~ '^(0|[1-9][0-9]*)$' then raise exception 'invalid_residual_value' using errcode='22023'; end if;
    v_residual:=(p_facts->>'residual_value')::bigint;
  end if;
  if v_residual>=v_cost then raise exception 'residual_value_must_be_less_than_cost' using errcode='23514'; end if;
  if coalesce(p_facts->>'useful_life_months','') !~ '^[1-9][0-9]*$' then raise exception 'useful_life_months_required' using errcode='22023'; end if;
  v_life:=(p_facts->>'useful_life_months')::integer;
  if v_life<1 or v_life>600 then raise exception 'useful_life_months_out_of_range' using errcode='22023'; end if;
  begin v_start:=(p_facts->>'depreciation_start_date')::date; exception when others then raise exception 'depreciation_start_date_required' using errcode='22023'; end;
  if v_start<p_business_date then raise exception 'depreciation_start_cannot_precede_acquisition' using errcode='23514'; end if;
  if v_method='CASH' then v_payment_account:='1-1010'; elsif v_method='BANK' then v_payment_account:='1-1030'; else raise exception 'asset_payment_method_must_be_cash_or_bank' using errcode='22023'; end if;
  if exists(select 1 from public.fixed_assets a where a.tenant_id=p_tenant_id and a.asset_ref=v_ref) then raise exception 'fixed_asset_ref_already_exists' using errcode='23505'; end if;
  perform private.assert_sufficient_liquid_funds(p_tenant_id,v_payment_account,v_cost);
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','1-1060','debit',v_cost,'credit',0,'memo','Peralatan toko'));
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',v_payment_account,'debit',0,'credit',v_cost,'memo','Pembelian peralatan'));
  return jsonb_build_object('journal_lines',v_journal,'tax_snapshot','{}'::jsonb,'asset_ref',v_ref,'asset_name',v_name,'cost',v_cost,'residual_value',v_residual,'useful_life_months',v_life,'depreciation_start_date',v_start);
end;
$function$;
-- private.build_owner_capital_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
CREATE OR REPLACE FUNCTION private.build_owner_capital_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_amount bigint; v_method text:=upper(coalesce(p_facts->>'payment_method','')); v_account text; v_journal jsonb:='[]'::jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_business_date is null or coalesce(p_facts->>'amount','') !~ '^[1-9][0-9]*$' then raise exception 'owner_capital_amount_required' using errcode='22023'; end if;
  v_amount:=(p_facts->>'amount')::bigint;
  if v_method='CASH' then v_account:='1-1010'; elsif v_method='BANK' then v_account:='1-1030'; else raise exception 'owner_capital_method_must_be_cash_or_bank' using errcode='22023'; end if;
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',v_account,'debit',v_amount,'credit',0,'memo','Setoran modal pemilik'));
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','3-3010','debit',0,'credit',v_amount,'memo','Modal pemilik'));
  return jsonb_build_object('journal_lines',v_journal,'tax_snapshot','{}'::jsonb,'amount',v_amount);
end;
$function$;
-- private.build_owner_draw_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
CREATE OR REPLACE FUNCTION private.build_owner_draw_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_amount bigint; v_method text:=upper(coalesce(p_facts->>'payment_method','')); v_payment text; v_journal jsonb:='[]'::jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_business_date is null or coalesce(p_facts->>'amount','') !~ '^[1-9][0-9]*$' then raise exception 'owner_draw_amount_required' using errcode='22023'; end if;
  v_amount:=(p_facts->>'amount')::bigint;
  if v_method='CASH' then v_payment:='1-1010'; elsif v_method='BANK' then v_payment:='1-1030'; else raise exception 'owner_draw_method_must_be_cash_or_bank' using errcode='22023'; end if;
  perform private.assert_sufficient_liquid_funds(p_tenant_id,v_payment,v_amount);
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','3-3030','debit',v_amount,'credit',0,'memo','Prive pemilik'));
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',v_payment,'debit',0,'credit',v_amount,'memo','Pengambilan pemilik'));
  return jsonb_build_object('journal_lines',v_journal,'tax_snapshot','{}'::jsonb,'amount',v_amount);
end;
$function$;
-- private.build_owner_turnover_tax_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
CREATE OR REPLACE FUNCTION private.build_owner_turnover_tax_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_month_start date:=date_trunc('month',p_business_date)::date;
  v_month_end date:=(date_trunc('month',p_business_date)+interval '1 month - 1 day')::date;
  v_self_count int; v_self public.tax_parties%rowtype; v_rule jsonb; v_month bigint; v_before bigint; v_after bigint; v_exempt bigint:=0; v_taxable bigint; v_tax bigint; v_limit bigint; v_exempt_limit bigint;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if coalesce(p_facts,'{}'::jsonb)<>'{}'::jsonb then raise exception 'owner_turnover_tax_accepts_no_manual_economic_inputs' using errcode='42501'; end if;
  if p_business_date<>v_month_end then raise exception 'owner_turnover_tax_business_date_must_be_month_end' using errcode='22023'; end if;
  if v_month_end>=current_date then raise exception 'owner_turnover_tax_period_must_be_completed' using errcode='23514'; end if;
  if v_month_start<date '2026-05-01' then raise exception 'historical_umkm_tax_rule_incomplete_for_partial_pre_pp20_period' using errcode='23514'; end if;
  select count(*) into v_self_count from public.tax_parties p where p.tenant_id=p_tenant_id and p.party_kind='SELF'
    and p.valid_from<=v_month_start and (p.valid_to is null or p.valid_to>=v_month_end)
    and private.is_pph_final_umkm_evidence_valid(p.tax_regime,p.taxpayer_type,p.turnover_eligibility,p.certificate_status,p.legal_basis,v_month_end)
    and coalesce((p.metadata->>'umkm_all_turnover_captured')::boolean,false)
    and coalesce((p.metadata->>'umkm_prior_year_eligibility_verified')::boolean,false);
  if v_self_count<>1 then raise exception 'exactly_one_verified_self_umkm_final_profile_required' using errcode='23514'; end if;
  select * into strict v_self from public.tax_parties p where p.tenant_id=p_tenant_id and p.party_kind='SELF'
    and p.valid_from<=v_month_start and (p.valid_to is null or p.valid_to>=v_month_end)
    and private.is_pph_final_umkm_evidence_valid(p.tax_regime,p.taxpayer_type,p.turnover_eligibility,p.certificate_status,p.legal_basis,v_month_end)
    and coalesce((p.metadata->>'umkm_all_turnover_captured')::boolean,false)
    and coalesce((p.metadata->>'umkm_prior_year_eligibility_verified')::boolean,false);
  v_rule:=private.resolve_tax_rate_snapshot('PPH_FINAL_UMKM','TURNOVER',v_month_end,'DEFAULT');
  v_limit:=coalesce((v_rule->'metadata'->>'turnover_limit_idr')::bigint,4800000000);
  v_exempt_limit:=coalesce((v_rule->'metadata'->>'wp_op_exempt_first_idr')::bigint,500000000);
  v_month:=private.umkm_gross_turnover_between(p_tenant_id,v_month_start,v_month_end);
  v_before:=private.umkm_gross_turnover_between(p_tenant_id,make_date(extract(year from v_month_start)::int,1,1),v_month_start-1);
  v_after:=v_before+v_month;
  if v_self.taxpayer_type='OP' then
    v_exempt:=least(v_month,greatest(v_exempt_limit-v_before,0));
  end if;
  v_taxable:=v_month-v_exempt;
  v_tax:=round(v_taxable::numeric*(v_rule->>'effective_rate')::numeric)::bigint;
  return jsonb_build_object(
    'journal_lines',case when v_tax>0 then jsonb_build_array(
      jsonb_build_object('account_code','6-6110','debit',v_tax,'credit',0,'memo','PPh Final UMKM bulan '||to_char(v_month_start,'YYYY-MM')),
      jsonb_build_object('account_code','2-2060','debit',0,'credit',v_tax,'memo','Utang PPh Final UMKM bulan '||to_char(v_month_start,'YYYY-MM'))
    ) else '[]'::jsonb end,
    'tax_snapshot',v_rule||jsonb_build_object('taxpayer_type',v_self.taxpayer_type,'turnover_limit_idr',v_limit,'wp_op_exempt_first_idr',v_exempt_limit,'prior_year_eligibility_verified',true,'all_turnover_captured',true),
    'period_start',v_month_start,'period_end',v_month_end,'taxpayer_type',v_self.taxpayer_type,
    'gross_turnover_month',v_month,'gross_turnover_ytd_before',v_before,'gross_turnover_ytd_after',v_after,
    'exempt_turnover_month',v_exempt,'taxable_turnover_month',v_taxable,'tax_amount',v_tax
  );
exception when no_data_found then raise exception 'owner_umkm_final_tax_dependency_missing' using errcode='23514';
end; $function$;
-- private.build_payroll_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION private.build_payroll_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb, p_actor uuid, p_device_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_employee uuid;
  v_profile public.employee_tax_profiles%rowtype;
  v_profile_count bigint;
  v_month date:=date_trunc('month',p_business_date)::date;
  v_year integer:=extract(year from p_business_date)::integer;
  v_cash bigint;
  v_pension bigint:=0;
  v_religious bigint:=0;
  v_is_final boolean;
  v_calc jsonb;
  v_rule jsonb;
  v_allowance bigint:=0;
  v_gross bigint;
  v_job bigint;
  v_ytd_gross bigint:=0;
  v_ytd_job bigint:=0;
  v_ytd_pension bigint:=0;
  v_ytd_religious bigint:=0;
  v_prior bigint:=0;
  v_annual_taxable bigint:=0;
  v_annual_tax bigint:=0;
  v_adjustment bigint:=0;
  v_salary_payable bigint;
  v_i integer;
  v_new_allowance bigint;
  v_journal jsonb:='[]'::jsonb;
  v_snapshot jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_business_date is null then raise exception 'business_date_required' using errcode='22023'; end if;
  begin v_employee:=(p_facts->>'employee_party_id')::uuid;
  exception when others then raise exception 'employee_party_id_required' using errcode='22023'; end;
  if coalesce(p_facts->>'cash_compensation','') !~ '^[1-9][0-9]*$' then
    raise exception 'cash_compensation_required' using errcode='22023';
  end if;
  v_cash:=(p_facts->>'cash_compensation')::bigint;
  if p_facts ? 'employee_pension_contribution' then
    if coalesce(p_facts->>'employee_pension_contribution','') !~ '^(0|[1-9][0-9]*)$' then
      raise exception 'invalid_employee_pension_contribution' using errcode='22023';
    end if;
    v_pension:=(p_facts->>'employee_pension_contribution')::bigint;
  end if;
  if p_facts ? 'mandatory_religious_contribution' then
    if coalesce(p_facts->>'mandatory_religious_contribution','') !~ '^(0|[1-9][0-9]*)$' then
      raise exception 'invalid_mandatory_religious_contribution' using errcode='22023';
    end if;
    v_religious:=(p_facts->>'mandatory_religious_contribution')::bigint;
  end if;
  if v_pension+v_religious>v_cash then
    raise exception 'employee_deductions_exceed_cash_compensation' using errcode='23514';
  end if;

  if not exists(
    select 1 from public.tax_parties tp
    where tp.tenant_id=p_tenant_id and tp.party_id=v_employee and tp.party_kind='EMPLOYEE'
      and tp.valid_from<=p_business_date and (tp.valid_to is null or tp.valid_to>=p_business_date)
  ) then raise exception 'effective_employee_tax_party_required' using errcode='23514'; end if;

  select count(*) into v_profile_count
  from public.employee_tax_profiles p
  where p.tenant_id=p_tenant_id and p.employee_party_id=v_employee
    and p.valid_from<=p_business_date and (p.valid_to is null or p.valid_to>=p_business_date);
  if v_profile_count<>1 then raise exception 'exactly_one_effective_employee_tax_profile_required' using errcode='23514'; end if;
  select * into strict v_profile
  from public.employee_tax_profiles p
  where p.tenant_id=p_tenant_id and p.employee_party_id=v_employee
    and p.valid_from<=p_business_date and (p.valid_to is null or p.valid_to>=p_business_date);

  if exists(
    select 1 from public.payroll_tax_evidence e
    where e.tenant_id=p_tenant_id and e.employee_party_id=v_employee and e.payroll_month=v_month
  ) then raise exception 'employee_payroll_month_already_posted' using errcode='23505'; end if;

  v_is_final := extract(month from p_business_date)=12
    or (v_profile.valid_to is not null and date_trunc('month',v_profile.valid_to)::date=v_month);

  if exists(
    select 1 from public.payroll_tax_evidence e
    where e.tenant_id=p_tenant_id and e.employee_party_id=v_employee
      and extract(year from e.payroll_month)=v_year and e.is_final_period
  ) then raise exception 'employee_tax_year_already_finalized' using errcode='23514'; end if;
  if v_is_final and exists(
    select 1 from public.payroll_tax_evidence e
    where e.tenant_id=p_tenant_id and e.employee_party_id=v_employee
      and extract(year from e.payroll_month)=v_year and e.payroll_month>v_month
  ) then raise exception 'final_period_cannot_precede_existing_payroll_month' using errcode='23514'; end if;

  select
    coalesce(sum(e.taxable_gross),0)::bigint,
    coalesce(sum(e.job_expense_deduction),0)::bigint,
    coalesce(sum(e.employee_pension_contribution),0)::bigint,
    coalesce(sum(e.mandatory_religious_contribution),0)::bigint,
    coalesce(sum(greatest(e.withholding_adjustment,0)),0)::bigint
  into v_ytd_gross,v_ytd_job,v_ytd_pension,v_ytd_religious,v_prior
  from public.payroll_tax_evidence e
  where e.tenant_id=p_tenant_id and e.employee_party_id=v_employee
    and extract(year from e.payroll_month)=v_year and e.payroll_month<v_month;

  if not v_is_final then
    v_calc:=private.pph21_periodic_calc(v_profile.ter_category,v_cash,v_profile.tax_method,p_business_date);
    v_gross:=(v_calc->>'taxable_gross')::bigint;
    v_allowance:=(v_calc->>'tax_allowance')::bigint;
    v_adjustment:=(v_calc->>'withholding_adjustment')::bigint;
    v_rule:=v_calc->'rule';
    v_job:=least(round(v_gross::numeric*0.05)::bigint,500000);
    v_ytd_gross:=v_ytd_gross+v_gross;
    v_ytd_job:=v_ytd_job+v_job;
    v_ytd_pension:=v_ytd_pension+v_pension;
    v_ytd_religious:=v_ytd_religious+v_religious;
  else
    if v_profile.tax_method='EMPLOYEE_BORNE' then
      v_gross:=v_cash;
      v_job:=least(round(v_gross::numeric*0.05)::bigint,500000);
      v_ytd_gross:=v_ytd_gross+v_gross;
      v_ytd_job:=v_ytd_job+v_job;
      v_ytd_pension:=v_ytd_pension+v_pension;
      v_ytd_religious:=v_ytd_religious+v_religious;
      v_annual_taxable:=greatest(v_ytd_gross-v_ytd_job-v_ytd_pension-v_ytd_religious-v_profile.ptkp_amount,0);
      v_annual_taxable:=(v_annual_taxable/1000)*1000;
      v_annual_tax:=private.pph21_article17_tax(v_annual_taxable);
      v_adjustment:=v_annual_tax-v_prior;
      v_rule:=jsonb_build_object(
        'tax_code','PPH21_FINAL','method','ARTICLE_17_FINAL_PERIOD','legal_basis','PMK 168/2023 jo. PP 58/2023',
        'ptkp_status',v_profile.ptkp_status,'ptkp_amount',v_profile.ptkp_amount,'taxable_income_rounded_down_1000',v_annual_taxable
      );
    else
      v_allowance:=0;
      for v_i in 1..100 loop
        if v_cash::numeric+v_allowance::numeric>9223372036854775807::numeric then
          raise exception 'payroll_value_out_of_range' using errcode='22003';
        end if;
        v_gross:=v_cash+v_allowance;
        v_job:=least(round(v_gross::numeric*0.05)::bigint,500000);
        v_annual_taxable:=greatest(
          (v_ytd_gross+v_gross)-(v_ytd_job+v_job)-(v_ytd_pension+v_pension)-(v_ytd_religious+v_religious)-v_profile.ptkp_amount,
          0
        );
        v_annual_taxable:=(v_annual_taxable/1000)*1000;
        v_annual_tax:=private.pph21_article17_tax(v_annual_taxable);
        v_adjustment:=v_annual_tax-v_prior;
        v_new_allowance:=greatest(v_adjustment,0);
        if v_new_allowance=v_allowance then exit; end if;
        v_allowance:=v_new_allowance;
        if v_i=100 then raise exception 'pph21_final_gross_up_did_not_converge' using errcode='23514'; end if;
      end loop;
      v_gross:=v_cash+v_allowance;
      v_job:=least(round(v_gross::numeric*0.05)::bigint,500000);
      v_ytd_gross:=v_ytd_gross+v_gross;
      v_ytd_job:=v_ytd_job+v_job;
      v_ytd_pension:=v_ytd_pension+v_pension;
      v_ytd_religious:=v_ytd_religious+v_religious;
      v_annual_taxable:=greatest(v_ytd_gross-v_ytd_job-v_ytd_pension-v_ytd_religious-v_profile.ptkp_amount,0);
      v_annual_taxable:=(v_annual_taxable/1000)*1000;
      v_annual_tax:=private.pph21_article17_tax(v_annual_taxable);
      v_adjustment:=v_annual_tax-v_prior;
      v_rule:=jsonb_build_object(
        'tax_code','PPH21_FINAL','method','ARTICLE_17_FINAL_PERIOD_GROSS_UP','legal_basis','PMK 168/2023 jo. PP 58/2023',
        'ptkp_status',v_profile.ptkp_status,'ptkp_amount',v_profile.ptkp_amount,'taxable_income_rounded_down_1000',v_annual_taxable,
        'iterations',v_i
      );
    end if;
  end if;

  if v_adjustment>=0 then
    v_salary_payable:=v_gross-v_adjustment;
  else
    v_salary_payable:=v_gross+abs(v_adjustment);
  end if;
  if v_salary_payable<=0 then raise exception 'invalid_salary_payable_amount' using errcode='23514'; end if;

  v_journal:=v_journal||jsonb_build_array(jsonb_build_object(
    'account_code','6-6010','debit',v_gross,'credit',0,'memo','Beban gaji'
  ));
  if v_adjustment<0 then
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object(
      'account_code','2-2040','debit',abs(v_adjustment),'credit',0,'memo','Pengembalian kelebihan potong PPh 21'
    ));
  end if;
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object(
    'account_code','2-2030','debit',0,'credit',v_salary_payable,'memo','Utang gaji bersih'
  ));
  if v_adjustment>0 then
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object(
      'account_code','2-2040','debit',0,'credit',v_adjustment,'memo','PPh 21 yang harus disetor'
    ));
  end if;

  v_snapshot:=jsonb_build_object(
    'legal_basis','PMK 168/2023 jo. PP 58/2023',
    'profile_id',v_profile.profile_id,
    'employee_party_id',v_employee,
    'payroll_month',v_month,
    'is_final_period',v_is_final,
    'tax_method',v_profile.tax_method,
    'ptkp_status',v_profile.ptkp_status,
    'ptkp_amount',v_profile.ptkp_amount,
    'ter_category',v_profile.ter_category,
    'cash_compensation',v_cash,
    'tax_allowance',v_allowance,
    'taxable_gross',v_gross,
    'employee_pension_contribution',v_pension,
    'mandatory_religious_contribution',v_religious,
    'job_expense_deduction',v_job,
    'ytd_taxable_gross',v_ytd_gross,
    'ytd_job_expense',v_ytd_job,
    'ytd_pension_contribution',v_ytd_pension,
    'ytd_religious_contribution',v_ytd_religious,
    'annual_taxable_income',v_annual_taxable,
    'annual_pph21',v_annual_tax,
    'prior_withholding',v_prior,
    'withholding_adjustment',v_adjustment,
    'salary_payable_amount',v_salary_payable,
    'rule',v_rule
  );

  return jsonb_build_object('journal_lines',v_journal,'tax_snapshot',v_snapshot);
end;
$function$;