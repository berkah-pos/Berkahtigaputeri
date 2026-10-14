-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source. PL/pgSQL bodies are installed before SQL-language wrappers.

-- private.build_purchase_lines(p_tenant_id uuid, p_transaction_ref text, p_business_date date, p_facts jsonb, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION private.build_purchase_lines(p_tenant_id uuid, p_transaction_ref text, p_business_date date, p_facts jsonb, p_actor uuid, p_device_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lines jsonb:=coalesce(p_facts->'lines','[]'::jsonb); v_line jsonb; v_count int; v_i int:=0;
  v_product uuid; v_qty bigint; v_unit_cost bigint; v_base bigint; v_total_base bigint:=0;
  v_vat_mode text:=upper(coalesce(nullif(btrim(p_facts->>'vat_mode'),''),'NONE'));
  v_doc_id uuid; v_doc public.tax_documents%rowtype; v_tax bigint:=0; v_inventory_value bigint:=0; v_liability bigint:=0;
  v_alloc bigint:=0; v_alloc_used bigint:=0; v_line_value bigint; v_journal jsonb:='[]'::jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_transaction_ref is null or length(btrim(p_transaction_ref))=0 or p_business_date is null then raise exception 'purchase_identity_required' using errcode='22023'; end if;
  if jsonb_typeof(v_lines)<>'array' or jsonb_array_length(v_lines)<1 or jsonb_array_length(v_lines)>50 then raise exception 'purchase_lines_required' using errcode='22023'; end if;
  if v_vat_mode not in ('NONE','CREDITABLE','NON_CREDITABLE') then raise exception 'invalid_purchase_vat_mode' using errcode='22023'; end if;
  v_count:=jsonb_array_length(v_lines);

  for v_line in select value from jsonb_array_elements(v_lines) loop
    if coalesce(v_line->>'qty','') !~ '^[1-9][0-9]*$' or coalesce(v_line->>'unit_cost','') !~ '^[1-9][0-9]*$' then raise exception 'purchase_qty_cost_must_be_positive_integer_rupiah' using errcode='22023'; end if;
    begin v_product:=(v_line->>'product_id')::uuid; exception when others then raise exception 'valid_product_id_required' using errcode='22023'; end;
    if not exists(select 1 from public.product_master p where p.tenant_id=p_tenant_id and p.product_id=v_product and p.is_active) then raise exception 'inventory_product_not_active' using errcode='23503'; end if;
    v_qty:=(v_line->>'qty')::bigint; v_unit_cost:=(v_line->>'unit_cost')::bigint;
    if v_qty::numeric*v_unit_cost::numeric>9223372036854775807::numeric then raise exception 'purchase_value_out_of_range' using errcode='22003'; end if;
    v_total_base:=v_total_base+(v_qty*v_unit_cost);
  end loop;

  if v_vat_mode<>'NONE' then
    begin v_doc_id:=(p_facts->>'input_tax_document_id')::uuid; exception when others then raise exception 'input_tax_document_id_required' using errcode='22023'; end;
    select * into strict v_doc from public.tax_documents
    where tax_document_id=v_doc_id and tenant_id=p_tenant_id and document_type='VAT_INPUT';
    if v_doc.status not in ('VALIDATED','ACCEPTED','REPORTED') then raise exception 'input_tax_invoice_not_validated' using errcode='23514'; end if;
    if v_doc.dpp<>v_total_base then raise exception 'purchase_dpp_does_not_match_input_tax_invoice' using errcode='23514'; end if;
    if v_vat_mode='CREDITABLE' then
      if v_doc.invoice_status<>'VALID' or not v_doc.creditable_input_vat or v_doc.tax_amount<=0 then raise exception 'input_tax_invoice_not_creditable' using errcode='23514'; end if;
    else
      if v_doc.creditable_input_vat then raise exception 'creditable_input_vat_cannot_be_capitalized' using errcode='23514'; end if;
    end if;
    v_tax:=v_doc.tax_amount;
  elsif p_facts ? 'input_tax_document_id' and nullif(btrim(p_facts->>'input_tax_document_id'),'') is not null then
    raise exception 'vat_mode_required_when_input_tax_document_present' using errcode='22023';
  end if;

  v_i:=0;
  for v_line in select value from jsonb_array_elements(v_lines) loop
    v_i:=v_i+1; v_product:=(v_line->>'product_id')::uuid; v_qty:=(v_line->>'qty')::bigint; v_unit_cost:=(v_line->>'unit_cost')::bigint; v_base:=v_qty*v_unit_cost;
    v_alloc:=0;
    if v_vat_mode='NON_CREDITABLE' and v_tax>0 then
      if v_i=v_count then v_alloc:=v_tax-v_alloc_used; else v_alloc:=round(v_tax::numeric*v_base::numeric/v_total_base::numeric)::bigint; v_alloc_used:=v_alloc_used+v_alloc; end if;
    end if;
    v_line_value:=v_base+v_alloc;
    perform inventory_private.average_receive_value(p_tenant_id,v_product,v_qty,v_line_value,'purchase:'||btrim(p_transaction_ref)||':'||v_i::text,btrim(p_transaction_ref),p_actor,p_device_id,p_reason);
    v_inventory_value:=v_inventory_value+v_line_value;
  end loop;

  v_liability:=v_total_base+v_tax;
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','1-1040','debit',v_inventory_value,'credit',0,'memo','Persediaan pembelian'));
  if v_vat_mode='CREDITABLE' and v_tax>0 then v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','1-1090','debit',v_tax,'credit',0,'memo','PPN pembelian yang bisa diperhitungkan')); end if;
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','2-2020','debit',0,'credit',v_liability,'memo','Utang supplier'));
  return jsonb_build_object(
    'journal_lines',v_journal,'vat_mode',v_vat_mode,'input_tax_document_id',v_doc_id,
    'tax_snapshot',case when v_doc_id is null then '{}'::jsonb else v_doc.tax_rate_snapshot end,
    'inventory_value',v_inventory_value,'input_vat',case when v_vat_mode='CREDITABLE' then v_tax else 0 end,
    'liability',v_liability
  );
end;
$function$


-- private.build_salary_payment_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
CREATE OR REPLACE FUNCTION private.build_salary_payment_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_payroll_ref text:=nullif(btrim(coalesce(p_facts->>'source_payroll_ref','')),'');
  v_payable public.employee_payables%rowtype;
  v_amount bigint;
  v_method text:=upper(coalesce(p_facts->>'payment_method',''));
  v_payment_account text;
  v_claim_employee uuid;
  v_journal jsonb:='[]'::jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_business_date is null or v_payroll_ref is null then raise exception 'salary_payment_identity_required' using errcode='22023'; end if;
  select * into strict v_payable
  from public.employee_payables p
  where p.tenant_id=p_tenant_id and p.payroll_ref=v_payroll_ref
  for update;
  if p_business_date<v_payable.business_date then raise exception 'salary_payment_before_payroll_date' using errcode='23514'; end if;
  if v_payable.remaining_amount<=0 then raise exception 'salary_already_fully_paid' using errcode='23514'; end if;
  if p_facts ? 'employee_party_id' and nullif(btrim(p_facts->>'employee_party_id'),'') is not null then
    begin v_claim_employee:=(p_facts->>'employee_party_id')::uuid;
    exception when others then raise exception 'invalid_employee_party_id' using errcode='22023'; end;
    if v_claim_employee<>v_payable.employee_party_id then raise exception 'salary_payment_employee_mismatch' using errcode='23514'; end if;
  end if;
  if p_facts ? 'amount' then
    if coalesce(p_facts->>'amount','') !~ '^[1-9][0-9]*$' then raise exception 'salary_payment_amount_invalid' using errcode='22023'; end if;
    v_amount:=(p_facts->>'amount')::bigint;
  else v_amount:=v_payable.remaining_amount; end if;
  if v_amount>v_payable.remaining_amount then raise exception 'salary_payment_exceeds_outstanding' using errcode='23514'; end if;
  if v_method='CASH' then v_payment_account:='1-1010';
  elsif v_method='BANK' then v_payment_account:='1-1030';
  else raise exception 'salary_payment_method_must_be_cash_or_bank' using errcode='22023'; end if;
  perform private.assert_sufficient_liquid_funds(p_tenant_id,v_payment_account,v_amount);
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','2-2030','debit',v_amount,'credit',0,'memo','Pelunasan utang gaji'));
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',v_payment_account,'debit',0,'credit',v_amount,'memo','Pembayaran gaji'));
  return jsonb_build_object(
    'journal_lines',v_journal,
    'source_payroll_ref',v_payroll_ref,
    'employee_party_id',v_payable.employee_party_id,
    'amount',v_amount,
    'tax_snapshot','{}'::jsonb
  );
exception when no_data_found then
  raise exception 'salary_payable_not_found' using errcode='P0002';
end;
$function$


-- private.build_sale_lines(p_tenant_id uuid, p_transaction_ref text, p_business_date date, p_facts jsonb, p_payment_account text, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION private.build_sale_lines(p_tenant_id uuid, p_transaction_ref text, p_business_date date, p_facts jsonb, p_payment_account text, p_actor uuid, p_device_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lines jsonb:=coalesce(p_facts->'lines','[]'::jsonb);
  v_line jsonb; v_i int:=0; v_line_key text; v_kind text; v_product uuid; v_service uuid; v_qty bigint; v_amount bigint;
  v_self_count int; v_self public.tax_parties%rowtype; v_is_pkp boolean;
  v_inclusive boolean:=coalesce((p_facts->>'prices_include_vat')::boolean,false);
  v_facility text:=upper(coalesce(nullif(btrim(p_facts->>'facility_context'),''),'NORMAL'));
  v_master_exempt boolean; v_line_taxable boolean; v_line_object text; v_unit_price bigint; v_list_amount bigint; v_discount bigint; v_item_code text; v_item_name text;
  v_tax jsonb:='{}'::jsonb; v_line_tax jsonb:='{}'::jsonb; v_tax_rules jsonb:='[]'::jsonb; v_rate numeric:=0; v_tax_code text;
  v_dpp bigint; v_vat bigint; v_gross bigint; v_cogs bigint:=0;
  v_stock_dpp bigint:=0; v_service_dpp bigint:=0; v_taxable_dpp bigint:=0; v_taxable_gross bigint:=0; v_total_vat bigint:=0; v_total_gross bigint:=0; v_total_cogs bigint:=0;
  v_any_taxable boolean:=false; v_sale_evidence jsonb:='[]'::jsonb; v_journal jsonb:='[]'::jsonb; v_line_wh text:='NONE'; v_wh_object text:='NONE'; v_line_wh_base bigint:=0; v_wh_base bigint:=0;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_payment_account not in ('1-1010','1-1020','1-1030','1-1050') then raise exception 'invalid_internal_payment_mapping' using errcode='23514'; end if;
  if p_transaction_ref is null or length(btrim(p_transaction_ref))=0 or p_business_date is null then raise exception 'sale_identity_required' using errcode='22023'; end if;
  if jsonb_typeof(v_lines)<>'array' or jsonb_array_length(v_lines)<1 or jsonb_array_length(v_lines)>50 then raise exception 'sale_lines_required' using errcode='22023'; end if;
  if v_facility='ASSET_16D' then raise exception 'asset_16d_not_supported_by_pos_sale_intent' using errcode='22023'; end if;
  v_tax_code:=private.resolve_vat_transaction_code(v_facility);

  select count(*) into v_self_count from public.tax_parties tp
  where tp.tenant_id=p_tenant_id and tp.party_kind='SELF'
    and tp.valid_from<=p_business_date and (tp.valid_to is null or tp.valid_to>=p_business_date)
    and ((tp.is_pkp and tp.certificate_status='VALID') or (not tp.is_pkp and tp.certificate_status in ('VALID','NOT_REQUIRED')));
  if v_self_count<>1 then raise exception 'exactly_one_effective_self_tax_profile_required' using errcode='23514'; end if;
  select * into strict v_self from public.tax_parties tp
  where tp.tenant_id=p_tenant_id and tp.party_kind='SELF'
    and tp.valid_from<=p_business_date and (tp.valid_to is null or tp.valid_to>=p_business_date)
    and ((tp.is_pkp and tp.certificate_status='VALID') or (not tp.is_pkp and tp.certificate_status in ('VALID','NOT_REQUIRED')));
  v_is_pkp:=v_self.is_pkp;
  if p_facts ? 'is_pkp' and coalesce((p_facts->>'is_pkp')::boolean,false) is distinct from v_is_pkp then
    raise exception 'tenant_pkp_status_mismatch' using errcode='23514';
  end if;

  for v_line in select value from jsonb_array_elements(v_lines) loop
    v_i:=v_i+1;
    v_line_key:=coalesce(nullif(btrim(v_line->>'line_key'),''),v_i::text);
    v_kind:=upper(coalesce(v_line->>'kind',''));
    if v_kind not in ('STOCK','SERVICE') then raise exception 'invalid_sale_line_kind' using errcode='22023'; end if;
    if coalesce(v_line->>'qty','') !~ '^[1-9][0-9]*$' then raise exception 'sale_qty_must_be_positive_integer' using errcode='22023'; end if;
    if v_line ? 'discount_amount' and coalesce(v_line->>'discount_amount','') !~ '^(0|[1-9][0-9]*)$' then raise exception 'sale_discount_must_be_nonnegative_integer_rupiah' using errcode='22023'; end if;
    v_qty:=(v_line->>'qty')::bigint;
    v_discount:=case when v_line ? 'discount_amount' then (v_line->>'discount_amount')::bigint else null end;

    if v_kind='STOCK' then
      begin v_product:=(v_line->>'product_id')::uuid; exception when others then raise exception 'valid_product_id_required_for_stock_line' using errcode='22023'; end;
      select p.ppn_exempt,p.vat_object_code,p.price,p.sku,p.name_id into strict v_master_exempt,v_line_object,v_unit_price,v_item_code,v_item_name
      from public.product_master p
      where p.tenant_id=p_tenant_id and p.product_id=v_product and p.is_active;
      v_service:=null; v_line_wh:='NONE';
    else
      if v_line ? 'product_id' and nullif(btrim(v_line->>'product_id'),'') is not null then raise exception 'service_line_cannot_reference_inventory_product' using errcode='22023'; end if;
      begin v_service:=(v_line->>'service_profile_id')::uuid; exception when others then raise exception 'service_profile_id_required' using errcode='22023'; end;
      select s.vat_exempt,s.vat_object_code,s.unit_price,s.service_code,s.name_id,s.pph23_object_code into strict v_master_exempt,v_line_object,v_unit_price,v_item_code,v_item_name,v_line_wh
      from public.service_tax_profiles s
      where s.tenant_id=p_tenant_id and s.service_profile_id=v_service
        and s.valid_from<=p_business_date and (s.valid_to is null or s.valid_to>=p_business_date);
      v_product:=null;
    end if;

    if v_qty::numeric*v_unit_price::numeric>9223372036854775807::numeric then raise exception 'sale_value_out_of_range' using errcode='22003'; end if;
    v_list_amount:=v_qty*v_unit_price;
    if v_line ? 'amount' and coalesce(v_line->>'amount','') !~ '^[1-9][0-9]*$' then raise exception 'sale_amount_claim_must_be_positive_integer_rupiah' using errcode='22023'; end if;
    if v_discount is null then
      if not (v_line ? 'amount') then raise exception 'sale_discount_or_amount_claim_required' using errcode='22023'; end if;
      v_amount:=(v_line->>'amount')::bigint;
      if v_amount>v_list_amount then raise exception 'sale_amount_exceeds_server_list_amount' using errcode='23514'; end if;
      v_discount:=v_list_amount-v_amount;
    else
      if v_discount>=v_list_amount then raise exception 'sale_discount_must_be_less_than_list_amount' using errcode='22023'; end if;
      v_amount:=v_list_amount-v_discount;
      if v_line ? 'amount' and (v_line->>'amount')::bigint<>v_amount then raise exception 'sale_amount_does_not_match_server_price_and_discount' using errcode='23514'; end if;
    end if;

    v_line_taxable:=v_is_pkp and not v_master_exempt;
    if v_line ? 'taxable' and (v_line->>'taxable')::boolean is distinct from v_line_taxable then raise exception 'sale_line_taxability_mismatch' using errcode='23514'; end if;
    if v_line ? 'tax_object_code' and upper(btrim(v_line->>'tax_object_code')) is distinct from v_line_object then raise exception 'sale_line_tax_object_mismatch' using errcode='23514'; end if;

    v_line_tax:='{}'::jsonb; v_rate:=0;
    if v_line_taxable then
      v_line_tax:=private.resolve_tax_rate_snapshot('PPN',v_line_object,p_business_date,'DEFAULT');
      v_rate:=(v_line_tax->>'effective_rate')::numeric;
      v_any_taxable:=true;
      v_tax_rules:=v_tax_rules||jsonb_build_array(jsonb_build_object('line_key',v_line_key,'object_code',v_line_object,'rule',v_line_tax));
      if v_tax='{}'::jsonb then v_tax:=v_line_tax; end if;
    end if;

    if v_line_taxable and v_facility='NORMAL' then
      if v_inclusive then v_dpp:=round(v_amount::numeric/(1+v_rate))::bigint; v_vat:=v_amount-v_dpp; v_gross:=v_amount;
      else v_dpp:=v_amount; v_vat:=round(v_dpp::numeric*v_rate)::bigint; v_gross:=v_dpp+v_vat; end if;
    else v_dpp:=v_amount; v_vat:=0; v_gross:=v_amount; end if;
    if v_dpp<=0 or v_gross<=0 or v_vat<0 then raise exception 'invalid_sale_tax_calculation' using errcode='23514'; end if;

    v_line_wh_base:=0;
    if v_kind='SERVICE' and v_line_wh='SERVICE' then
      v_line_wh_base:=case when v_line_taxable and v_inclusive then v_dpp else v_amount end;
      if v_line_wh_base<=0 then raise exception 'invalid_inbound_pph23_base' using errcode='23514'; end if;
      if v_wh_object='NONE' then v_wh_object:=v_line_wh; elsif v_wh_object<>v_line_wh then raise exception 'mixed_inbound_withholding_objects_not_supported' using errcode='23514'; end if;
      v_wh_base:=v_wh_base+v_line_wh_base;
    end if;
    if v_kind='STOCK' then
      v_cogs:=private.apply_sale_avg(p_tenant_id,v_product,v_qty,'sale:'||btrim(p_transaction_ref)||':'||v_line_key,btrim(p_transaction_ref),p_actor,p_device_id,p_reason);
      if v_cogs<=0 then raise exception 'stocked_sale_cogs_must_be_positive' using errcode='23514'; end if;
      v_stock_dpp:=v_stock_dpp+v_dpp; v_total_cogs:=v_total_cogs+v_cogs;
    else v_cogs:=0; v_service_dpp:=v_service_dpp+v_dpp; end if;
    if v_line_taxable then v_taxable_dpp:=v_taxable_dpp+v_dpp; v_taxable_gross:=v_taxable_gross+v_gross; end if;
    v_total_vat:=v_total_vat+v_vat; v_total_gross:=v_total_gross+v_gross;
    v_sale_evidence:=v_sale_evidence||jsonb_build_array(jsonb_build_object(
      'line_key',v_line_key,'line_kind',v_kind,'product_id',v_product,'service_profile_id',v_service,'item_code',v_item_code,'item_name',v_item_name,
      'quantity',v_qty,'unit_price',v_unit_price,'list_amount',v_list_amount,'discount_amount',v_discount,
      'revenue_account',case when v_kind='STOCK' then '4-4010' else '4-4050' end,
      'dpp',v_dpp,'vat_amount',v_vat,'gross_amount',v_gross,'original_cogs',v_cogs,'taxable',v_line_taxable,'tax_object_code',v_line_object,
      'tax_snapshot',case when v_line_taxable then v_line_tax||jsonb_build_object('taxable',true,'vat_transaction_code',v_tax_code,'facility_context',v_facility,'object_code',v_line_object) else jsonb_build_object('taxable',false,'master_exempt',v_master_exempt) end
    ));
  end loop;

  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',p_payment_account,'debit',v_total_gross,'credit',0,'memo','Pembayaran penjualan'));
  if v_stock_dpp>0 then v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','4-4010','debit',0,'credit',v_stock_dpp,'memo','Penjualan barang')); end if;
  if v_service_dpp>0 then v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','4-4050','debit',0,'credit',v_service_dpp,'memo','Pendapatan jasa')); end if;
  if v_total_vat>0 then v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','2-2010','debit',0,'credit',v_total_vat,'memo','PPN dari penjualan')); end if;
  if v_total_cogs>0 then
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','5-5010','debit',v_total_cogs,'credit',0,'memo','Harga modal rata-rata otomatis'));
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','1-1040','debit',0,'credit',v_total_cogs,'memo','Pengurangan persediaan'));
  end if;
  return jsonb_build_object('journal_lines',v_journal,'sale_lines',v_sale_evidence,
    'tax_snapshot',(case when v_any_taxable then v_tax||jsonb_build_object('vat_transaction_code',v_tax_code,'facility_context',v_facility,'line_rules',v_tax_rules) else '{}'::jsonb end) || case when v_wh_base>0 then jsonb_build_object('inbound_withholding',jsonb_build_object('tax_code','PPH23','object_code',v_wh_object,'base',v_wh_base,'base_authority','SERVICE_CONSIDERATION_EX_VAT')) else '{}'::jsonb end,
    'is_pkp',v_is_pkp,'vat_transaction_code',case when v_any_taxable then v_tax_code else null end,'tax_document_required',v_any_taxable,
    'dpp',v_stock_dpp+v_service_dpp,'taxable_dpp',v_taxable_dpp,'vat_amount',v_total_vat,'gross_amount',v_total_gross,'taxable_gross',v_taxable_gross);
exception when no_data_found then raise exception 'sale_tax_master_dependency_missing' using errcode='23514';
end;
$function$


-- private.build_sale_return_lines(p_tenant_id uuid, p_return_ref text, p_business_date date, p_facts jsonb, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION private.build_sale_return_lines(p_tenant_id uuid, p_return_ref text, p_business_date date, p_facts jsonb, p_actor uuid, p_device_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_original_ref text:=btrim(coalesce(p_facts->>'original_transaction_ref',''));
  v_orig public.accounting_transaction_evidence%rowtype; v_orig_line public.sale_line_evidence%rowtype;
  v_lines jsonb:=coalesce(p_facts->'lines','[]'::jsonb); v_req jsonb; v_line_key text; v_qty bigint;
  v_prev_qty bigint; v_prev_dpp bigint; v_prev_vat bigint; v_prev_cogs bigint; v_remaining bigint;
  v_dpp bigint; v_vat bigint; v_cogs bigint; v_total_dpp bigint:=0; v_total_vat bigint:=0; v_total_cogs bigint:=0;
  v_payment text; v_journal jsonb:='[]'::jsonb; v_return_evidence jsonb:='[]'::jsonb; v_first_tax jsonb:='{}'::jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if v_original_ref='' or p_return_ref is null or length(btrim(p_return_ref))=0 then raise exception 'return_identity_required' using errcode='22023'; end if;
  select * into strict v_orig from public.accounting_transaction_evidence where tenant_id=p_tenant_id and transaction_ref=v_original_ref;
  if v_orig.transaction_type not in ('JUAL_TUNAI','JUAL_QRIS','JUAL_TRANSFER','JUAL_KREDIT') then raise exception 'original_transaction_is_not_sale' using errcode='23514'; end if;
  if p_business_date<v_orig.business_date then raise exception 'sale_return_before_original_sale_date' using errcode='23514'; end if;
  v_payment:=case v_orig.transaction_type when 'JUAL_TUNAI' then '1-1010' when 'JUAL_QRIS' then '1-1020' when 'JUAL_TRANSFER' then '1-1030' when 'JUAL_KREDIT' then '1-1050' end;
  if jsonb_typeof(v_lines)<>'array' or jsonb_array_length(v_lines)<1 or jsonb_array_length(v_lines)>50 then raise exception 'return_lines_required' using errcode='22023'; end if;

  for v_req in select value from jsonb_array_elements(v_lines) loop
    v_line_key:=btrim(coalesce(v_req->>'line_key',''));
    if v_line_key='' or coalesce(v_req->>'qty','') !~ '^[1-9][0-9]*$' then raise exception 'valid_return_line_key_and_qty_required' using errcode='22023'; end if;
    v_qty:=(v_req->>'qty')::bigint;
    select * into strict v_orig_line from public.sale_line_evidence where tenant_id=p_tenant_id and transaction_ref=v_original_ref and line_key=v_line_key;
    select coalesce(sum(quantity),0),coalesce(sum(dpp_reversed),0),coalesce(sum(vat_reversed),0),coalesce(sum(cogs_restored),0)
      into v_prev_qty,v_prev_dpp,v_prev_vat,v_prev_cogs
    from public.sale_return_line_evidence where tenant_id=p_tenant_id and original_transaction_ref=v_original_ref and line_key=v_line_key;
    v_remaining:=v_orig_line.quantity-v_prev_qty;
    if v_qty>v_remaining then raise exception 'return_quantity_exceeds_original_remaining' using errcode='23514'; end if;
    if v_qty=v_remaining then
      v_dpp:=v_orig_line.dpp-v_prev_dpp; v_vat:=v_orig_line.vat_amount-v_prev_vat; v_cogs:=v_orig_line.original_cogs-v_prev_cogs;
    else
      v_dpp:=round(v_orig_line.dpp::numeric*v_qty::numeric/v_orig_line.quantity::numeric)::bigint;
      v_vat:=round(v_orig_line.vat_amount::numeric*v_qty::numeric/v_orig_line.quantity::numeric)::bigint;
      v_cogs:=round(v_orig_line.original_cogs::numeric*v_qty::numeric/v_orig_line.quantity::numeric)::bigint;
    end if;
    if v_dpp<0 or v_vat<0 or v_cogs<0 then raise exception 'invalid_return_allocation' using errcode='23514'; end if;
    if v_orig_line.line_kind='STOCK' then
      if v_cogs<=0 then raise exception 'stock_return_original_cogs_required' using errcode='23514'; end if;
      perform inventory_private.average_restore_original(p_tenant_id,v_orig_line.product_id,v_qty,v_cogs,'return:'||btrim(p_return_ref)||':'||v_line_key,btrim(p_return_ref),v_original_ref,p_actor,p_device_id,p_reason);
    elsif v_cogs<>0 then raise exception 'service_return_cogs_must_be_zero' using errcode='23514'; end if;
    v_total_dpp:=v_total_dpp+v_dpp; v_total_vat:=v_total_vat+v_vat; v_total_cogs:=v_total_cogs+v_cogs;
    if v_first_tax='{}'::jsonb and v_orig_line.tax_snapshot<>'{}'::jsonb then v_first_tax:=v_orig_line.tax_snapshot; end if;
    v_return_evidence:=v_return_evidence||jsonb_build_array(jsonb_build_object('original_transaction_ref',v_original_ref,'line_key',v_line_key,'quantity',v_qty,'dpp_reversed',v_dpp,'vat_reversed',v_vat,'cogs_restored',v_cogs));
  end loop;
  if v_total_dpp<=0 then raise exception 'return_dpp_must_be_positive' using errcode='23514'; end if;
  if v_payment<>'1-1050' then perform private.assert_sufficient_liquid_funds(p_tenant_id,v_payment,v_total_dpp+v_total_vat); end if;
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','4-4030','debit',v_total_dpp,'credit',0,'memo','Retur penjualan'));
  if v_total_vat>0 then v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','2-2010','debit',v_total_vat,'credit',0,'memo','Pembalikan PPN penjualan')); end if;
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',v_payment,'debit',0,'credit',v_total_dpp+v_total_vat,'memo','Pengembalian pembayaran/piutang'));
  if v_total_cogs>0 then
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','1-1040','debit',v_total_cogs,'credit',0,'memo','Barang retur kembali ke stok'));
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','5-5010','debit',0,'credit',v_total_cogs,'memo','Pembalikan harga modal asli'));
  end if;
  return jsonb_build_object('journal_lines',v_journal,'return_lines',v_return_evidence,'original_transaction_ref',v_original_ref,'dpp',v_total_dpp,'vat_amount',v_total_vat,'gross_amount',v_total_dpp+v_total_vat,'cogs_restored',v_total_cogs,'tax_snapshot',v_first_tax);
end;
$function$


-- private.build_stock_opname_lines(p_tenant_id uuid, p_transaction_ref text, p_facts jsonb, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION private.build_stock_opname_lines(p_tenant_id uuid, p_transaction_ref text, p_facts jsonb, p_actor uuid, p_device_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lines jsonb:=coalesce(p_facts->'lines','[]'::jsonb); v_line jsonb; v_i int:=0; v_product uuid; v_counted bigint; v_zero_cost bigint; v_adj jsonb;
  v_qty_delta bigint; v_value_delta bigint; v_short bigint:=0; v_over bigint:=0; v_journal jsonb:='[]'::jsonb; v_evidence_count bigint;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if coalesce(p_facts->>'evidence_count','') !~ '^[1-9][0-9]*$' or coalesce((p_facts->>'approved')::boolean,false) is not true then raise exception 'stock_opname_approval_and_evidence_required' using errcode='22023'; end if;
  v_evidence_count:=(p_facts->>'evidence_count')::bigint;
  if jsonb_typeof(v_lines)<>'array' or jsonb_array_length(v_lines)<1 or jsonb_array_length(v_lines)>100 then raise exception 'stock_opname_lines_required' using errcode='22023'; end if;
  for v_line in select value from jsonb_array_elements(v_lines) loop
    v_i:=v_i+1;
    begin v_product:=(v_line->>'product_id')::uuid; exception when others then raise exception 'valid_product_id_required' using errcode='22023'; end;
    if coalesce(v_line->>'counted_qty','') !~ '^(0|[1-9][0-9]*)$' then raise exception 'counted_qty_must_be_nonnegative_integer' using errcode='22023'; end if;
    v_counted:=(v_line->>'counted_qty')::bigint;
    if coalesce(v_line->>'zero_stock_unit_cost','') ~ '^[1-9][0-9]*$' then v_zero_cost:=(v_line->>'zero_stock_unit_cost')::bigint; else v_zero_cost:=null; end if;
    v_adj:=inventory_private.average_adjust_to_count(p_tenant_id,v_product,v_counted,v_zero_cost,'opname:'||btrim(p_transaction_ref)||':'||v_i::text,btrim(p_transaction_ref),p_actor,p_device_id,p_reason);
    v_qty_delta:=(v_adj->>'quantity_delta')::bigint; v_value_delta:=(v_adj->>'value_delta')::bigint;
    if v_value_delta<0 then v_short:=v_short+(-v_value_delta); else v_over:=v_over+v_value_delta; end if;
  end loop;
  if v_short>0 then
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','6-6080','debit',v_short,'credit',0,'memo','Selisih stok kurang'));
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','1-1040','debit',0,'credit',v_short,'memo','Pengurangan persediaan opname'));
  end if;
  if v_over>0 then
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','1-1040','debit',v_over,'credit',0,'memo','Penambahan persediaan opname'));
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code','4-4060','debit',0,'credit',v_over,'memo','Selisih stok lebih'));
  end if;
  if jsonb_array_length(v_journal)<2 then raise exception 'stock_opname_has_no_adjustment' using errcode='22023'; end if;
  return jsonb_build_object('journal_lines',v_journal,'shortage_value',v_short,'overage_value',v_over,'evidence_count',v_evidence_count);
end;
$function$


-- private.build_supplier_payment_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
CREATE OR REPLACE FUNCTION private.build_supplier_payment_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_source_ref text:=nullif(btrim(coalesce(p_facts->>'source_purchase_ref','')),'');
  v_liability public.supplier_liabilities%rowtype;
  v_gross bigint;
  v_base bigint:=0;
  v_tax bigint:=0;
  v_net bigint;
  v_method text;
  v_party public.tax_parties%rowtype;
  v_object text;
  v_tax_code text;
  v_rate_object text;
  v_tax_rule jsonb:='{}'::jsonb;
  v_rate numeric:=0;
  v_payable_account text;
  v_payment_account text;
  v_journal jsonb:='[]'::jsonb;
  v_final_valid boolean:=false;
  v_claim_vendor uuid;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_business_date is null then raise exception 'business_date_required' using errcode='22023'; end if;
  if v_source_ref is null then raise exception 'source_purchase_ref_required' using errcode='22023'; end if;

  select * into strict v_liability
  from public.supplier_liabilities s
  where s.tenant_id=p_tenant_id and s.purchase_transaction_ref=v_source_ref
  for update;
  if p_business_date<v_liability.business_date then
    raise exception 'supplier_payment_before_source_liability_date' using errcode='23514';
  end if;
  if v_liability.remaining_amount<=0 then
    raise exception 'supplier_liability_already_settled' using errcode='23514';
  end if;

  if p_facts ? 'vendor_party_id' and nullif(btrim(p_facts->>'vendor_party_id'),'') is not null then
    begin v_claim_vendor:=(p_facts->>'vendor_party_id')::uuid;
    exception when others then raise exception 'invalid_vendor_party_id' using errcode='22023'; end;
    if v_claim_vendor<>v_liability.vendor_party_id then
      raise exception 'supplier_liability_vendor_mismatch' using errcode='23514';
    end if;
  end if;

  select * into strict v_party
  from public.tax_parties tp
  where tp.tenant_id=p_tenant_id and tp.party_id=v_liability.vendor_party_id and tp.party_kind='VENDOR'
    and tp.valid_from<=p_business_date and (tp.valid_to is null or tp.valid_to>=p_business_date);

  v_method:=upper(coalesce(p_facts->>'payment_method',''));
  if v_method='CASH' then v_payment_account:='1-1010';
  elsif v_method='BANK' then v_payment_account:='1-1030';
  else raise exception 'payment_method_must_be_cash_or_bank' using errcode='22023'; end if;

  v_object:=v_liability.tax_object_code;
  if p_facts ? 'tax_object' and upper(coalesce(nullif(btrim(p_facts->>'tax_object'),''),'NONE'))<>v_object then
    raise exception 'supplier_payment_tax_object_claim_mismatch' using errcode='23514';
  end if;

  if v_object='NONE' then
    if p_facts ? 'pph_base' and nullif(btrim(p_facts->>'pph_base'),'') is not null then
      raise exception 'pph_base_not_allowed_for_non_withholding_liability' using errcode='23514';
    end if;
    if p_facts ? 'gross_liability' then
      if coalesce(p_facts->>'gross_liability','') !~ '^[1-9][0-9]*$' then
        raise exception 'gross_liability_must_be_positive_integer' using errcode='22023';
      end if;
      v_gross:=(p_facts->>'gross_liability')::bigint;
    else
      v_gross:=v_liability.remaining_amount;
    end if;
    if v_gross>v_liability.remaining_amount then
      raise exception 'supplier_payment_exceeds_outstanding_liability' using errcode='23514';
    end if;
  else
    if v_liability.withholding_base_remaining<=0 then
      raise exception 'withholding_source_base_missing' using errcode='23514';
    end if;
    if p_facts ? 'gross_liability' and (p_facts->>'gross_liability')::bigint<>v_liability.remaining_amount then
      raise exception 'taxed_supplier_liability_requires_full_settlement' using errcode='23514';
    end if;
    if p_facts ? 'pph_base' and (p_facts->>'pph_base')::bigint<>v_liability.withholding_base_remaining then
      raise exception 'pph_base_claim_mismatch_source_liability' using errcode='23514';
    end if;
    v_gross:=v_liability.remaining_amount;
    v_base:=v_liability.withholding_base_remaining;

    if v_object='LAND_BUILDING_RENT' then
      v_tax_code:='PPH_FINAL_4_2'; v_rate_object:='LAND_BUILDING_RENT'; v_payable_account:='2-2060';
    elsif v_object in ('SERVICE','ASSET_RENT_NON_LAND_BUILDING') then
      if upper(v_party.tax_regime)='PPH_FINAL_UMKM' then
        v_final_valid:=private.is_pph_final_umkm_evidence_valid(
          v_party.tax_regime,v_party.taxpayer_type,v_party.turnover_eligibility,
          v_party.certificate_status,v_party.legal_basis,p_business_date
        );
        if not v_final_valid then raise exception 'vendor_final_tax_evidence_invalid' using errcode='23514'; end if;
        v_tax_code:='PPH_FINAL_UMKM'; v_rate_object:='TURNOVER'; v_payable_account:='2-2060';
      else
        v_tax_code:='PPH23'; v_rate_object:=v_object; v_payable_account:='2-2050';
      end if;
    else
      raise exception 'unsupported_source_liability_tax_object' using errcode='23514';
    end if;
    v_tax_rule:=private.resolve_tax_rate_snapshot(v_tax_code,v_rate_object,p_business_date,'DEFAULT');
    v_rate:=(v_tax_rule->>'effective_rate')::numeric;
    v_tax:=round(v_base::numeric*v_rate)::bigint;
    if v_tax<=0 or v_tax>=v_gross then raise exception 'invalid_withholding_amount' using errcode='23514'; end if;
  end if;

  v_net:=v_gross-v_tax;
  perform private.assert_sufficient_liquid_funds(p_tenant_id,v_payment_account,v_net);
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object(
    'account_code','2-2020','debit',v_gross,'credit',0,'memo','Pelunasan utang supplier'
  ));
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object(
    'account_code',v_payment_account,'debit',0,'credit',v_net,'memo','Pembayaran vendor'
  ));
  if v_tax>0 then
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object(
      'account_code',v_payable_account,'debit',0,'credit',v_tax,'memo','Pajak dipotong saat bayar'
    ));
  end if;
  return jsonb_build_object(
    'journal_lines',v_journal,
    'source_purchase_ref',v_source_ref,
    'vendor_party_id',v_liability.vendor_party_id,
    'gross_liability',v_gross,
    'cash_paid',v_net,
    'withholding_amount',v_tax,
    'withholding_base',v_base,
    'tax_code',v_tax_code,
    'tax_object',case when v_object='NONE' then null else v_rate_object end,
    'tax_snapshot',v_tax_rule,
    'withholding_account',v_payable_account
  );
exception when no_data_found then
  raise exception 'supplier_payment_source_dependency_missing' using errcode='23514';
end;
$function$


-- private.build_tax_remittance_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
CREATE OR REPLACE FUNCTION private.build_tax_remittance_lines(p_tenant_id uuid, p_business_date date, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ref_id uuid; v_ref public.tax_payment_refs%rowtype; v_account text; v_balance bigint; v_method text:=upper(coalesce(p_facts->>'payment_method','')); v_payment_account text; v_payment_reference text:=nullif(btrim(coalesce(p_facts->>'payment_reference','')),''); v_journal jsonb:='[]'::jsonb; v_is_asset boolean:=false;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_business_date is null then raise exception 'business_date_required' using errcode='22023'; end if;
  begin v_ref_id:=(p_facts->>'payment_ref_id')::uuid; exception when others then raise exception 'tax_payment_ref_id_required' using errcode='22023'; end;
  if v_payment_reference is null or length(v_payment_reference)<3 then raise exception 'tax_payment_confirmation_reference_required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':tax-payment:'||v_ref_id::text,7338));
  select * into strict v_ref from public.tax_payment_refs r where r.tenant_id=p_tenant_id and r.payment_ref_id=v_ref_id for update;
  if v_ref.status<>'CREATED' then raise exception 'tax_payment_reference_not_open' using errcode='23514'; end if;
  if v_ref.tax_code is null or v_ref.tax_period_start is null or v_ref.tax_period_end is null then raise exception 'legacy_tax_payment_reference_not_payable' using errcode='23514'; end if;
  if p_business_date<v_ref.tax_period_end then raise exception 'tax_payment_before_period_end' using errcode='23514'; end if;
  if v_method='CASH' then v_payment_account:='1-1010'; elsif v_method='BANK' then v_payment_account:='1-1030'; else raise exception 'tax_payment_method_must_be_cash_or_bank' using errcode='22023'; end if;
  v_account:=case v_ref.tax_code when 'PPN' then '2-2010' when 'PPH21' then '2-2040' when 'PPH23' then '2-2050' when 'PPH_FINAL' then '2-2060' when 'PPH25' then '1-1110' when 'PPH29' then '2-2070' else null end;
  if v_account is null then raise exception 'unsupported_tax_remittance_code' using errcode='23514'; end if;
  v_is_asset:=(v_ref.tax_code='PPH25');
  if not v_is_asset then
    select coalesce(sum(credit-debit),0)::bigint into v_balance from public.accounting_journal_lines where tenant_id=p_tenant_id and account_code=v_account;
    if v_balance<v_ref.amount then raise exception 'tax_payment_exceeds_current_tax_liability' using errcode='23514'; end if;
  end if;
  perform private.assert_sufficient_liquid_funds(p_tenant_id,v_payment_account,v_ref.amount);
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',v_account,'debit',v_ref.amount,'credit',0,'memo',case when v_is_asset then 'Angsuran PPh25' else 'Setor '||v_ref.tax_code end));
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object('account_code',v_payment_account,'debit',0,'credit',v_ref.amount,'memo','Pembayaran pajak via e-Billing'));
  return jsonb_build_object('journal_lines',v_journal,'tax_snapshot',jsonb_build_object('tax_code',v_ref.tax_code,'tax_period_start',v_ref.tax_period_start,'tax_period_end',v_ref.tax_period_end,'billing_code',v_ref.billing_code,'obligation_snapshot',v_ref.obligation_snapshot),'payment_ref_id',v_ref_id,'tax_code',v_ref.tax_code,'amount',v_ref.amount,'payment_reference',v_payment_reference,'settlement_account',v_account);
exception when no_data_found then raise exception 'tax_payment_reference_not_found' using errcode='P0002';
end; $function$


-- private.build_vendor_expense_accrual_lines(p_tenant_id uuid, p_transaction_ref text, p_business_date date, p_facts jsonb, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION private.build_vendor_expense_accrual_lines(p_tenant_id uuid, p_transaction_ref text, p_business_date date, p_facts jsonb, p_actor uuid, p_device_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_vendor uuid;
  v_party public.tax_parties%rowtype;
  v_object text;
  v_kind text;
  v_expense_account text;
  v_base bigint;
  v_withholding_base bigint;
  v_vat_mode text:=upper(coalesce(nullif(btrim(p_facts->>'vat_mode'),''),'NONE'));
  v_doc_id uuid;
  v_doc public.tax_documents%rowtype;
  v_tax bigint:=0;
  v_expense_debit bigint;
  v_liability bigint;
  v_journal jsonb:='[]'::jsonb;
begin
  perform private.assert_no_accounting_fields(p_facts);
  if p_transaction_ref is null or length(btrim(p_transaction_ref))=0 or p_business_date is null then
    raise exception 'vendor_expense_identity_required' using errcode='22023';
  end if;
  begin
    v_vendor:=(p_facts->>'vendor_party_id')::uuid;
  exception when others then
    raise exception 'vendor_tax_party_required' using errcode='22023';
  end;
  select * into strict v_party
  from public.tax_parties tp
  where tp.tenant_id=p_tenant_id and tp.party_id=v_vendor and tp.party_kind='VENDOR'
    and tp.valid_from<=p_business_date and (tp.valid_to is null or tp.valid_to>=p_business_date);

  v_object:=upper(coalesce(v_party.tax_object,''));
  if v_object='SERVICE' then
    v_kind:='SERVICE';
    v_expense_account:='6-6030';
  elsif v_object in ('LAND_BUILDING_RENT','ASSET_RENT_NON_LAND_BUILDING') then
    v_kind:='RENT';
    v_expense_account:='6-6040';
  else
    raise exception 'vendor_tax_object_not_supported_for_expense_accrual' using errcode='23514';
  end if;

  if coalesce(p_facts->>'expense_base','') !~ '^[1-9][0-9]*$' then
    raise exception 'expense_base_required' using errcode='22023';
  end if;
  if coalesce(p_facts->>'withholding_base','') !~ '^[1-9][0-9]*$' then
    raise exception 'withholding_base_required_separate_from_vat_dpp' using errcode='22023';
  end if;
  v_base:=(p_facts->>'expense_base')::bigint;
  v_withholding_base:=(p_facts->>'withholding_base')::bigint;
  if v_withholding_base>v_base then
    raise exception 'withholding_base_exceeds_expense_base' using errcode='23514';
  end if;
  if v_object='LAND_BUILDING_RENT' and v_withholding_base<>v_base then
    raise exception 'land_building_rent_withholding_base_must_equal_gross_rent' using errcode='23514';
  end if;
  if v_vat_mode not in ('NONE','CREDITABLE','NON_CREDITABLE') then
    raise exception 'invalid_vendor_expense_vat_mode' using errcode='22023';
  end if;

  if v_vat_mode<>'NONE' then
    begin
      v_doc_id:=(p_facts->>'input_tax_document_id')::uuid;
    exception when others then
      raise exception 'input_tax_document_id_required' using errcode='22023';
    end;
    select * into strict v_doc
    from public.tax_documents d
    where d.tax_document_id=v_doc_id
      and d.tenant_id=p_tenant_id
      and d.document_type='VAT_INPUT';
    if v_doc.counterparty_id is distinct from v_vendor then
      raise exception 'input_tax_invoice_vendor_mismatch' using errcode='23514';
    end if;
    if v_doc.status not in ('VALIDATED','ACCEPTED','REPORTED') then
      raise exception 'input_tax_invoice_not_validated' using errcode='23514';
    end if;
    if v_doc.dpp<>v_base then
      raise exception 'vendor_expense_dpp_does_not_match_input_tax_invoice' using errcode='23514';
    end if;
    if v_vat_mode='CREDITABLE' then
      if v_doc.invoice_status<>'VALID' or not v_doc.creditable_input_vat or v_doc.tax_amount<=0 then
        raise exception 'input_tax_invoice_not_creditable' using errcode='23514';
      end if;
    else
      if v_doc.creditable_input_vat then
        raise exception 'creditable_input_vat_cannot_be_capitalized_to_expense' using errcode='23514';
      end if;
    end if;
    v_tax:=v_doc.tax_amount;
  elsif p_facts ? 'input_tax_document_id' and nullif(btrim(p_facts->>'input_tax_document_id'),'') is not null then
    raise exception 'vat_mode_required_when_input_tax_document_present' using errcode='22023';
  end if;

  v_expense_debit:=v_base + case when v_vat_mode='NON_CREDITABLE' then v_tax else 0 end;
  v_liability:=v_base+v_tax;
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object(
    'account_code',v_expense_account,'debit',v_expense_debit,'credit',0,
    'memo',case when v_kind='RENT' then 'Beban sewa vendor' else 'Beban jasa vendor' end
  ));
  if v_vat_mode='CREDITABLE' and v_tax>0 then
    v_journal:=v_journal||jsonb_build_array(jsonb_build_object(
      'account_code','1-1090','debit',v_tax,'credit',0,'memo','PPN pembelian yang bisa diperhitungkan'
    ));
  end if;
  v_journal:=v_journal||jsonb_build_array(jsonb_build_object(
    'account_code','2-2020','debit',0,'credit',v_liability,'memo','Utang supplier jasa/sewa'
  ));

  return jsonb_build_object(
    'journal_lines',v_journal,
    'vendor_party_id',v_vendor,
    'liability_kind',v_kind,
    'tax_object',v_object,
    'expense_base',v_base,
    'withholding_base',v_withholding_base,
    'vat_mode',v_vat_mode,
    'input_tax_document_id',v_doc_id,
    'input_vat',case when v_vat_mode='CREDITABLE' then v_tax else 0 end,
    'liability',v_liability,
    'tax_snapshot',case when v_doc_id is null then '{}'::jsonb else v_doc.tax_rate_snapshot end
  );
exception when no_data_found then
  raise exception 'vendor_expense_tax_master_dependency_missing' using errcode='23514';
end;
$function$


-- private.can_export_coretax(p_tenant_id uuid, p_tax_document_id uuid)
CREATE OR REPLACE FUNCTION private.can_export_coretax(p_tenant_id uuid, p_tax_document_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_doc public.tax_documents%ROWTYPE;
  v_gate jsonb;
  v_expected_template text;
BEGIN
  IF p_tenant_id IS NULL OR p_tax_document_id IS NULL THEN
    RETURN false;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.accounting_tenants AS t WHERE t.tenant_id = p_tenant_id
  ) THEN
    RETURN false;
  END IF;

  SELECT d.* INTO v_doc
  FROM public.tax_documents AS d
  WHERE d.tax_document_id = p_tax_document_id
    AND d.tenant_id = p_tenant_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_doc.status <> 'VALIDATED' THEN
    RETURN false;
  END IF;

  -- all_zero is the conservative aggregate hard gate; it fails closed for any
  -- non-zero ledger/subledger delta as well as other accounting invariants.
  v_gate := private.compute_accounting_hard_gate(p_tenant_id);
  IF coalesce((v_gate ->> 'all_zero')::boolean, false) IS NOT TRUE THEN
    RETURN false;
  END IF;

  IF v_doc.tax_rate_snapshot IS NULL
     OR jsonb_typeof(v_doc.tax_rate_snapshot) <> 'object'
     OR v_doc.tax_rate_snapshot = '{}'::jsonb
     OR v_doc.legal_rule_snapshot IS NULL
     OR jsonb_typeof(v_doc.legal_rule_snapshot) <> 'object'
     OR v_doc.legal_rule_snapshot = '{}'::jsonb
     OR nullif(btrim(v_doc.legal_rule_snapshot ->> 'legal_basis'), '') IS NULL THEN
    RETURN false;
  END IF;

  v_expected_template := CASE v_doc.document_type
    WHEN 'VAT_OUTPUT' THEN 'FAKTUR_KELUARAN'
    WHEN 'VAT_REPLACEMENT' THEN 'FAKTUR_KELUARAN'
    WHEN 'PPH23_UNIFICATION' THEN 'BPPU'
    WHEN 'PPH21_26' THEN 'BPMP'
    ELSE NULL
  END;
  IF v_expected_template IS NULL OR NOT private.verify_coretax_template() THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.coretax_template_registry AS t
    WHERE t.template_code = v_expected_template
      AND t.is_active IS TRUE
      AND t.is_verified IS TRUE
      AND t.xml_template IS NOT NULL
      AND t.template_sha256 ~ '^[0-9a-f]{64}$'
      AND t.template_sha256 = encode(
        extensions.digest(convert_to(t.xml_template, 'UTF8'), 'sha256'),
        'hex'
      )
      AND coalesce(t.generator_spec ->> 'status', '') <> 'SOURCE_REGISTERED_NOT_PARSED'
  );
END;
$function$


-- private.can_read_client_status(p_device_id text)
CREATE OR REPLACE FUNCTION private.can_read_client_status(p_device_id text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_role text := lower(coalesce(auth.jwt()->>'role',''));
begin
  if v_role = 'service_role' or private.btp_is_super_admin() then
    return true;
  end if;
  if v_uid is null then
    return false;
  end if;

  return exists (
    select 1
    from public.devices d
    where d.device_id = p_device_id
      and (
        d.user_id = v_uid
        or exists (
          select 1
          from public.pos_memberships pm
          where pm.tenant_id = d.tenant_id
            and pm.user_id = v_uid
            and pm.is_active
            and pm.role in ('owner','manager')
        )
        or exists (
          select 1
          from public.pos_accounting_tenant_map m
          join public.accounting_memberships am
            on am.tenant_id = m.accounting_tenant_id
          where m.pos_tenant_id = d.tenant_id
            and m.is_active
            and am.user_id = v_uid
            and am.is_active
            and am.role in ('owner','admin')
        )
      )
  );
end;
$function$


-- private.can_read_final_pos_config(config_key text)
CREATE OR REPLACE FUNCTION private.can_read_final_pos_config(config_key text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text := lower(coalesce(auth.jwt()->>'role',''));
begin
  if v_role = 'service_role' or private.btp_is_super_admin() then
    return true;
  end if;
  return private.can_read_final_pos_config_strict(config_key);
end;
$function$


-- private.can_write_app_config(p_key text)
CREATE OR REPLACE FUNCTION private.can_write_app_config(p_key text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_role text := lower(coalesce(auth.jwt()->>'role',''));
  v_tenant text;
  v_device text;
begin
  if v_role='service_role' or private.btp_is_super_admin() then return true; end if;
  if v_uid is null then return false; end if;

  if p_key ~ '^tenant:[^:]+$' then
    v_tenant:=split_part(p_key,':',2);
    return exists(select 1 from public.pos_memberships m
      where m.tenant_id=v_tenant and m.user_id=v_uid and m.is_active and m.role='owner');
  elsif p_key ~ '^tenant:[^:]+:service:(pos|akuntansi)$' then
    v_tenant:=split_part(p_key,':',2);
    return exists(select 1 from public.pos_memberships m
      where m.tenant_id=v_tenant and m.user_id=v_uid and m.is_active and m.role in ('owner','manager'));
  elsif p_key ~ '^device:[^:]+$' then
    v_device:=split_part(p_key,':',2);
    return exists(select 1 from public.devices d where d.device_id=v_device and
      (d.user_id=v_uid or exists(select 1 from public.pos_memberships m where m.tenant_id=d.tenant_id
       and m.user_id=v_uid and m.is_active and m.role in ('owner','manager'))));
  end if;
  return false;
end;
$function$

