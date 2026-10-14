-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source. PL/pgSQL bodies are installed before SQL-language wrappers.

-- public.prepare_coretax_export_package(p_tax_document_id uuid, p_template_code text, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.prepare_coretax_export_package(p_tax_document_id uuid, p_template_code text, p_device_id text, p_app_version text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid(); v_doc public.tax_documents%rowtype; v_template public.coretax_template_registry%rowtype;
  v_self_count int; v_self public.tax_parties%rowtype; v_counter public.tax_parties%rowtype; v_expected_template text; v_lines jsonb;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role((select tenant_id from public.tax_documents where tax_document_id=p_tax_document_id),v_actor,array['owner','admin','accountant']);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  select * into strict v_doc from public.tax_documents where tax_document_id=p_tax_document_id;
  perform private.assert_accounting_hard_gate(v_doc.tenant_id);
  if v_doc.status<>'VALIDATED' then raise exception 'tax_document_must_be_validated_before_export' using errcode='55000'; end if;
  if jsonb_typeof(v_doc.legal_rule_snapshot)<>'object' or nullif(btrim(v_doc.legal_rule_snapshot->>'legal_basis'),'') is null then raise exception 'tax_document_legal_snapshot_missing' using errcode='23514'; end if;
  v_expected_template:=case v_doc.document_type when 'VAT_OUTPUT' then 'FAKTUR_KELUARAN' when 'VAT_REPLACEMENT' then 'FAKTUR_KELUARAN' when 'PPH23_UNIFICATION' then 'BPPU' when 'PPH21_26' then 'BPMP' else null end;
  if v_expected_template is null or p_template_code<>v_expected_template then raise exception 'unsupported_or_mismatched_coretax_template' using errcode='23514'; end if;
  select * into strict v_template from public.coretax_template_registry where template_code=p_template_code and is_active and is_verified;
  if v_template.xml_template is null or v_template.template_sha256 is null or coalesce(v_template.generator_spec->>'status','')='SOURCE_REGISTERED_NOT_PARSED' then raise exception 'official_coretax_template_not_verified' using errcode='23514'; end if;
  select count(*) into v_self_count from public.tax_parties p where p.tenant_id=v_doc.tenant_id and p.party_kind='SELF' and p.valid_from<=v_doc.business_date and (p.valid_to is null or p.valid_to>=v_doc.business_date) and p.certificate_status='VALID';
  if v_self_count<>1 then raise exception 'exactly_one_valid_self_tax_identity_required' using errcode='23514'; end if;
  select * into strict v_self from public.tax_parties p where p.tenant_id=v_doc.tenant_id and p.party_kind='SELF' and p.valid_from<=v_doc.business_date and (p.valid_to is null or p.valid_to>=v_doc.business_date) and p.certificate_status='VALID';
  if v_doc.counterparty_id is not null then select * into strict v_counter from public.tax_parties where tenant_id=v_doc.tenant_id and party_id=v_doc.counterparty_id; end if;
  select coalesce(jsonb_agg(to_jsonb(l) order by l.line_key),'[]'::jsonb) into v_lines from public.tax_document_lines l where l.tax_document_id=p_tax_document_id;
  if v_doc.document_type in ('VAT_OUTPUT','VAT_REPLACEMENT') and jsonb_array_length(v_lines)=0 then raise exception 'coretax_tax_document_lines_required' using errcode='23514'; end if;
  return jsonb_build_object(
    'template',jsonb_build_object('template_id',v_template.template_id,'template_code',v_template.template_code,'template_version',v_template.template_version,'xml_template',v_template.xml_template,'generator_spec',v_template.generator_spec,'template_sha256',v_template.template_sha256,'official_source_url',v_template.official_source_url),
    'data',jsonb_build_object('document',to_jsonb(v_doc),'lines',v_lines,'self',to_jsonb(v_self),'counterparty',case when v_doc.counterparty_id is null then null else to_jsonb(v_counter) end),
    'actor_user_id',v_actor,'device_id',btrim(p_device_id),'reason',btrim(p_reason)
  );
exception when no_data_found then raise exception 'coretax_export_dependency_missing' using errcode='23514';
end;
$function$


-- public.reconcile_subscription_expiry()
CREATE OR REPLACE FUNCTION public.reconcile_subscription_expiry()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_past_due integer; v_expired integer;
begin
  update public.subscriptions set status = 'past_due'
  where payment_provider = 'midtrans' and paid_at is not null and status = 'active'
    and now() >= current_period_end and now() < grace_period_end;
  get diagnostics v_past_due = row_count;
  update public.subscriptions set status = 'expired', auto_renewing = false
  where status in ('pending','active','past_due','cancelled') and (
    (payment_provider = 'play_billing' and now() >= current_period_end) or
    (payment_provider = 'midtrans' and (status = 'cancelled' or now() >= coalesce(grace_period_end,current_period_end)))
  );
  get diagnostics v_expired = row_count;
  return jsonb_build_object('past_due',v_past_due,'expired',v_expired);
end $function$


-- public.record_coretax_result(p_outbox_id uuid, p_result text, p_reference text, p_details jsonb, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.record_coretax_result(p_outbox_id uuid, p_result text, p_reference text, p_details jsonb, p_device_id text, p_app_version text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_o public.coretax_outbox%rowtype; v_doc public.tax_documents%rowtype; v_result text:=upper(btrim(coalesce(p_result,'')));
begin
  if v_result not in ('ACK','REJECTED') or p_details is null or jsonb_typeof(p_details)<>'object' or p_reason is null or length(btrim(p_reason))<3 then raise exception 'invalid_coretax_result' using errcode='22023'; end if;
  select * into strict v_o from public.coretax_outbox where outbox_id=p_outbox_id for update;
  select * into strict v_doc from public.tax_documents where tax_document_id=v_o.tax_document_id for update;
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(v_doc.tenant_id,v_actor,array['owner','admin','accountant']);
  if v_o.status<>'SENT' or v_doc.status<>'SUBMITTED' then raise exception 'coretax_result_state_invalid' using errcode='55000'; end if;
  if v_result='ACK' then
    update public.coretax_outbox set status='ACK',ack_reference=coalesce(nullif(btrim(coalesce(p_reference,'')),''),ack_reference),rejection_detail='{}'::jsonb,updated_at=now() where outbox_id=p_outbox_id;
    update public.tax_documents set status='ACCEPTED',coretax_reference=coalesce(nullif(btrim(coalesce(p_reference,'')),''),coretax_reference),updated_at=now() where tax_document_id=v_doc.tax_document_id;
  else
    update public.coretax_outbox set status='REJECTED',rejection_detail=p_details,updated_at=now() where outbox_id=p_outbox_id;
    update public.tax_documents set status='REJECTED',updated_at=now() where tax_document_id=v_doc.tax_document_id;
  end if;
  insert into public.tax_document_events(tax_document_id,tenant_id,event_type,details,actor_user_id,device_id,reason)
  values(v_doc.tax_document_id,v_doc.tenant_id,'CORETAX_'||v_result,p_details||jsonb_build_object('outbox_id',p_outbox_id,'reference',p_reference),v_actor,btrim(p_device_id),btrim(p_reason));
end;
$function$


-- public.record_corporate_fiscal_adjustment(p_tenant_id uuid, p_tax_year integer, p_adjustment_ref text, p_direction text, p_category text, p_amount bigint, p_legal_basis text, p_evidence jsonb, p_reverses_adjustment_id uuid, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.record_corporate_fiscal_adjustment(p_tenant_id uuid, p_tax_year integer, p_adjustment_ref text, p_direction text, p_category text, p_amount bigint, p_legal_basis text, p_evidence jsonb, p_reverses_adjustment_id uuid, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_id uuid; v_dir text:=upper(btrim(coalesce(p_direction,''))); v_cat text:=upper(btrim(coalesce(p_category,''))); v_old public.corporate_fiscal_adjustments%rowtype;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if exists(select 1 from public.corporate_annual_tax_periods p where p.tenant_id=p_tenant_id and p.tax_year=p_tax_year) then raise exception 'corporate_tax_year_already_closed' using errcode='55000'; end if;
  if p_adjustment_ref is null or length(btrim(p_adjustment_ref))<3 or v_dir not in ('POSITIVE','NEGATIVE') or v_cat not in ('NON_DEDUCTIBLE_EXPENSE','TAXABLE_INCOME_ADDITION','NON_TAXABLE_INCOME','DEDUCTIBLE_EXPENSE','TIMING_DIFFERENCE','OTHER_STATUTORY') or p_amount is null or p_amount<=0 then raise exception 'invalid_fiscal_adjustment' using errcode='22023'; end if;
  if p_legal_basis is null or length(btrim(p_legal_basis))<3 or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or p_evidence='{}'::jsonb or p_reason is null or length(btrim(p_reason))<3 then raise exception 'fiscal_adjustment_evidence_required' using errcode='22023'; end if;
  if p_reverses_adjustment_id is not null then
    select * into strict v_old from public.corporate_fiscal_adjustments a where a.tenant_id=p_tenant_id and a.adjustment_id=p_reverses_adjustment_id and a.tax_year=p_tax_year;
    if v_old.direction=v_dir or v_old.amount<>p_amount then raise exception 'fiscal_adjustment_reversal_must_exactly_offset_original' using errcode='23514'; end if;
  end if;
  insert into public.corporate_fiscal_adjustments(tenant_id,tax_year,adjustment_ref,direction,category,amount,legal_basis,evidence,reverses_adjustment_id,actor_user_id,device_id,reason)
  values(p_tenant_id,p_tax_year,btrim(p_adjustment_ref),v_dir,v_cat,p_amount,btrim(p_legal_basis),p_evidence,p_reverses_adjustment_id,v_actor,btrim(p_device_id),btrim(p_reason)) returning adjustment_id into v_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action) values(p_tenant_id::text,v_actor,btrim(p_device_id),'corporate_fiscal_adjustment:'||v_id::text,btrim(p_reason),'success');
  return v_id;
exception when no_data_found then raise exception 'fiscal_adjustment_reversal_source_not_found' using errcode='P0002';
end; $function$


-- public.register_input_tax_invoice(p_tenant_id uuid, p_transaction_ref text, p_business_date date, p_counterparty_id uuid, p_facility_context text, p_tax_object_code text, p_dpp bigint, p_tax_amount bigint, p_gross_amount bigint, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.register_input_tax_invoice(p_tenant_id uuid, p_transaction_ref text, p_business_date date, p_counterparty_id uuid, p_facility_context text, p_tax_object_code text, p_dpp bigint, p_tax_amount bigint, p_gross_amount bigint, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  raise exception 'input_tax_invoice_number_required_use_numbered_api' using errcode='55000';
end;
$function$


-- public.register_input_tax_invoice(p_tenant_id uuid, p_transaction_ref text, p_document_number text, p_business_date date, p_counterparty_id uuid, p_facility_context text, p_tax_object_code text, p_dpp bigint, p_tax_amount bigint, p_gross_amount bigint, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.register_input_tax_invoice(p_tenant_id uuid, p_transaction_ref text, p_document_number text, p_business_date date, p_counterparty_id uuid, p_facility_context text, p_tax_object_code text, p_dpp bigint, p_tax_amount bigint, p_gross_amount bigint, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_tax jsonb; v_rate numeric; v_expected bigint; v_id uuid; v_code text; v_number text:=nullif(upper(btrim(coalesce(p_document_number,''))),'');
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  if v_number is null or length(v_number)<3 then raise exception 'input_tax_invoice_number_required' using errcode='22023'; end if;
  if p_transaction_ref is null or length(btrim(p_transaction_ref))<1 then raise exception 'input_tax_transaction_ref_required' using errcode='22023'; end if;
  if p_business_date is null then raise exception 'business_date_required' using errcode='22023'; end if;
  if p_counterparty_id is null or not exists(
    select 1 from public.tax_parties tp
    where tp.tenant_id=p_tenant_id and tp.party_id=p_counterparty_id and tp.party_kind='VENDOR'
      and p_business_date between tp.valid_from and coalesce(tp.valid_to,date '9999-12-31')
  ) then raise exception 'valid_vendor_tax_party_required' using errcode='23514'; end if;
  v_tax:=private.resolve_tax_rate_snapshot('PPN',upper(coalesce(nullif(btrim(p_tax_object_code),''),'NON_LUXURY')),p_business_date,'DEFAULT');
  v_code:=private.resolve_vat_transaction_code(p_facility_context);
  v_rate:=(v_tax->>'effective_rate')::numeric;
  v_expected:=case when v_code in ('07','08') then 0 else round(p_dpp::numeric*v_rate)::bigint end;
  if p_dpp<=0 or p_tax_amount<>v_expected or p_gross_amount<>p_dpp+p_tax_amount then raise exception 'input_tax_invoice_amount_mismatch' using errcode='23514'; end if;
  insert into public.tax_documents(
    tenant_id,document_type,document_number,transaction_ref,counterparty_id,business_date,vat_transaction_code,facility_context,
    dpp,tax_amount,gross_amount,tax_rate_snapshot,legal_rule_snapshot,invoice_status,creditable_input_vat,status,
    actor_user_id,device_id,reason
  ) values(
    p_tenant_id,'VAT_INPUT',v_number,btrim(p_transaction_ref),p_counterparty_id,p_business_date,v_code,upper(coalesce(p_facility_context,'NORMAL')),
    p_dpp,p_tax_amount,p_gross_amount,v_tax,
    jsonb_build_object('legal_basis',v_tax->>'legal_basis','tax_rate_id',v_tax->>'tax_rate_id','vat_transaction_code',v_code,'facility_context',upper(coalesce(p_facility_context,'NORMAL')),'snapshot_at',now()),
    'PENDING',false,'DRAFT',v_actor,btrim(p_device_id),btrim(p_reason)
  ) returning tax_document_id into v_id;
  insert into public.tax_document_events(tax_document_id,tenant_id,event_type,details,actor_user_id,device_id,reason)
  values(v_id,p_tenant_id,'REGISTERED',jsonb_build_object('invoice_status','PENDING','document_number',v_number),v_actor,btrim(p_device_id),btrim(p_reason));
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values(p_tenant_id::text,v_actor,btrim(p_device_id),'tax_input_invoice:'||v_id::text,btrim(p_reason),'success');
  return v_id;
exception when unique_violation then
  raise exception 'duplicate_input_tax_invoice_number_or_transaction_ref' using errcode='23505';
end;
$function$


-- public.register_tax_payment_reference(p_tenant_id uuid, p_tax_document_id uuid, p_billing_code text, p_amount bigint, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.register_tax_payment_reference(p_tenant_id uuid, p_tax_document_id uuid, p_billing_code text, p_amount bigint, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_billing_code is null or length(btrim(p_billing_code))<3 or p_amount is null or p_amount<=0 or p_reason is null or length(btrim(p_reason))<3 then raise exception 'billing_reference_fields_required' using errcode='22023'; end if;
  if p_tax_document_id is not null and not exists(select 1 from public.tax_documents where tax_document_id=p_tax_document_id and tenant_id=p_tenant_id) then raise exception 'tax_document_not_found' using errcode='P0002'; end if;
  insert into public.tax_payment_refs(tenant_id,tax_document_id,billing_code,amount,status,actor_user_id,device_id,reason)
  values(p_tenant_id,p_tax_document_id,btrim(p_billing_code),p_amount,'CREATED',v_actor,btrim(p_device_id),btrim(p_reason)) returning payment_ref_id into v_id;
  return v_id;
end;
$function$


-- public.register_tax_payment_reference_v2(p_tenant_id uuid, p_tax_code text, p_tax_period_start date, p_tax_period_end date, p_billing_code text, p_amount bigint, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.register_tax_payment_reference_v2(p_tenant_id uuid, p_tax_code text, p_tax_period_start date, p_tax_period_end date, p_billing_code text, p_amount bigint, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid();
  v_code text:=upper(btrim(coalesce(p_tax_code,'')));
  v_obligation bigint;
  v_reserved bigint;
  v_id uuid;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if v_code not in ('PPN','PPH21','PPH23','PPH_FINAL','PPH25','PPH29') then raise exception 'unsupported_tax_remittance_code' using errcode='22023'; end if;
  if p_tax_period_start is null or p_tax_period_end is null or p_tax_period_end<p_tax_period_start then raise exception 'invalid_tax_period' using errcode='22023'; end if;
  if v_code='PPH29' then
    if p_tax_period_start<>make_date(extract(year from p_tax_period_start)::int,1,1) or p_tax_period_end<>make_date(extract(year from p_tax_period_start)::int,12,31) then raise exception 'PPh29_period_must_be_full_calendar_year' using errcode='22023'; end if;
  else
    if p_tax_period_start<>date_trunc('month',p_tax_period_start)::date or p_tax_period_end<>(date_trunc('month',p_tax_period_start)+interval '1 month - 1 day')::date then raise exception 'tax_period_must_be_full_calendar_month' using errcode='22023'; end if;
  end if;
  if p_billing_code is null or length(btrim(p_billing_code))<3 or p_amount is null or p_amount<=0 then raise exception 'billing_code_and_amount_required' using errcode='22023'; end if;
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':tax-billing:'||v_code||':'||p_tax_period_start::text||':'||p_tax_period_end::text,7337));
  v_obligation:=private.tax_period_obligation(p_tenant_id,v_code,p_tax_period_start,p_tax_period_end);
  select coalesce(sum(amount),0)::bigint into v_reserved
  from public.tax_payment_refs
  where tenant_id=p_tenant_id and tax_code=v_code
    and tax_period_start=p_tax_period_start and tax_period_end=p_tax_period_end
    and status in ('CREATED','PAID');
  if v_obligation<=0 then raise exception 'tax_period_has_no_payable_obligation' using errcode='23514'; end if;
  if p_amount>v_obligation-v_reserved then raise exception 'billing_amount_exceeds_unreserved_tax_obligation' using errcode='23514'; end if;

  insert into public.tax_payment_refs(
    tenant_id,tax_document_id,billing_code,amount,status,actor_user_id,device_id,reason,
    tax_code,tax_period_start,tax_period_end,obligation_snapshot,updated_at
  ) values(
    p_tenant_id,null,btrim(p_billing_code),p_amount,'CREATED',v_actor,btrim(p_device_id),btrim(p_reason),
    v_code,p_tax_period_start,p_tax_period_end,v_obligation,now()
  ) returning payment_ref_id into v_id;
  return v_id;
end;
$function$


-- public.resolve_accounting_tenant(p_config_tenant_id text, p_business_date date, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.resolve_accounting_tenant(p_config_tenant_id text, p_business_date date, p_device_id text, p_app_version text)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid();
  v_device_tenant text;
  v_count bigint;
  v_accounting_tenant uuid;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  if p_business_date is null then raise exception 'business_date_required' using errcode='22023'; end if;

  select d.tenant_id into strict v_device_tenant
  from public.devices d
  where d.device_id=btrim(p_device_id) and d.user_id=v_actor;
  if v_device_tenant<>p_config_tenant_id then raise exception 'device_config_tenant_mismatch' using errcode='42501'; end if;
  if not exists(select 1 from public.tenants t where t.tenant_id=p_config_tenant_id and t.status='active' and not t.is_blocked) then
    raise exception 'config_tenant_not_active' using errcode='23514';
  end if;

  select count(*) into v_count
  from private.tenant_accounting_links l
  where l.config_tenant_id=p_config_tenant_id
    and l.valid_from<=p_business_date
    and (l.valid_to is null or l.valid_to>=p_business_date);
  if v_count<>1 then raise exception 'exactly_one_effective_accounting_tenant_link_required' using errcode='23514'; end if;

  select l.accounting_tenant_id into strict v_accounting_tenant
  from private.tenant_accounting_links l
  where l.config_tenant_id=p_config_tenant_id
    and l.valid_from<=p_business_date
    and (l.valid_to is null or l.valid_to>=p_business_date);

  perform accounting_private.require_member_role(v_accounting_tenant,v_actor,array['owner','admin','accountant','cashier']);
  if not exists(select 1 from public.accounting_tenants t where t.tenant_id=v_accounting_tenant and t.status='active') then
    raise exception 'accounting_tenant_not_active' using errcode='23514';
  end if;
  return v_accounting_tenant;
exception when no_data_found then
  raise exception 'tenant_accounting_link_dependency_missing' using errcode='23514';
end;
$function$


-- public.rpc_get_my_pos_role(p_tenant_id text)
CREATE OR REPLACE FUNCTION public.rpc_get_my_pos_role(p_tenant_id text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_tenant text := nullif(trim(coalesce(p_tenant_id, '')), '');
  v_role text;
begin
  if v_actor is null then
    raise exception 'authenticated session required' using errcode = '42501';
  end if;
  if v_tenant is null then
    raise exception 'tenant is required' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.devices d
    where d.tenant_id = v_tenant
      and d.user_id = v_actor
  ) then
    raise exception 'caller has no bound device in tenant' using errcode = '42501';
  end if;

  select m.role
    into v_role
  from public.pos_memberships m
  where m.tenant_id = v_tenant
    and m.user_id = v_actor
    and m.is_active = true;

  if v_role is null then
    raise exception 'active POS membership required' using errcode = '42501';
  end if;

  return v_role;
end;
$function$


-- public.rpc_verify_manager_pin(p_tenant_id text, p_pin text, p_required_action text, p_device_id text)
CREATE OR REPLACE FUNCTION public.rpc_verify_manager_pin(p_tenant_id text, p_pin text, p_required_action text, p_device_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_tenant text := nullif(trim(coalesce(p_tenant_id, '')), '');
  v_device text := nullif(trim(coalesce(p_device_id, '')), '');
  v_action text := lower(trim(coalesce(p_required_action, '')));
  v_pin_hash text;
  v_is_active boolean;
  v_attempts integer;
  v_locked_until timestamptz;
  v_now timestamptz := now();
  v_ok boolean := false;
begin
  if v_actor is null then
    raise exception 'authenticated session required' using errcode = '42501';
  end if;
  if v_tenant is null or v_device is null or nullif(coalesce(p_pin, ''), '') is null then
    raise exception 'tenant, device and pin are required' using errcode = '22023';
  end if;
  if v_action not in ('return_sale','void_sale','close_shift_variance') then
    raise exception 'unsupported manager pin action' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.devices d
    where d.device_id = v_device
      and d.tenant_id = v_tenant
      and d.user_id = v_actor
  ) then
    raise exception 'device is not bound to actor and tenant' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.pos_memberships m
    where m.tenant_id = v_tenant
      and m.user_id = v_actor
      and m.is_active = true
  ) then
    raise exception 'active POS membership required' using errcode = '42501';
  end if;

  select p.pin_hash, p.is_active, p.failed_attempts, p.locked_until
    into v_pin_hash, v_is_active, v_attempts, v_locked_until
  from public.pos_manager_pins p
  where p.tenant_id = v_tenant
  for update;

  if v_pin_hash is null or not coalesce(v_is_active, false) then
    insert into public.pos_pin_audit (
      tenant_id, actor_id, device_id, required_action, success,
      failure_reason, attempt_count, locked_until
    ) values (
      v_tenant, v_actor, v_device, v_action, false,
      'pin_not_configured_or_inactive', coalesce(v_attempts, 0), v_locked_until
    );
    return jsonb_build_object(
      'ok', false,
      'is_active', coalesce(v_is_active, false),
      'attempts', coalesce(v_attempts, 0),
      'locked_until', v_locked_until
    );
  end if;

  if v_locked_until is not null and v_locked_until > v_now then
    insert into public.pos_pin_audit (
      tenant_id, actor_id, device_id, required_action, success,
      failure_reason, attempt_count, locked_until
    ) values (
      v_tenant, v_actor, v_device, v_action, false,
      'locked', v_attempts, v_locked_until
    );
    return jsonb_build_object(
      'ok', false,
      'is_active', true,
      'attempts', v_attempts,
      'locked_until', v_locked_until
    );
  end if;

  if v_locked_until is not null and v_locked_until <= v_now then
    v_attempts := 0;
    v_locked_until := null;
  end if;

  v_ok := extensions.crypt(p_pin, v_pin_hash) = v_pin_hash;

  if v_ok then
    v_attempts := 0;
    v_locked_until := null;
    update public.pos_manager_pins
       set failed_attempts = 0,
           locked_until = null,
           updated_at = v_now
     where tenant_id = v_tenant;
  else
    v_attempts := least(coalesce(v_attempts, 0) + 1, 3);
    if v_attempts >= 3 then
      v_locked_until := v_now + interval '5 minutes';
    else
      v_locked_until := null;
    end if;
    update public.pos_manager_pins
       set failed_attempts = v_attempts,
           locked_until = v_locked_until,
           updated_at = v_now
     where tenant_id = v_tenant;
  end if;

  insert into public.pos_pin_audit (
    tenant_id, actor_id, device_id, required_action, success,
    failure_reason, attempt_count, locked_until
  ) values (
    v_tenant, v_actor, v_device, v_action, v_ok,
    case when v_ok then null else 'invalid_pin' end,
    v_attempts, v_locked_until
  );

  return jsonb_build_object(
    'ok', v_ok,
    'is_active', true,
    'attempts', v_attempts,
    'locked_until', v_locked_until
  );
end;
$function$


-- public.save_coretax_export_internal(p_tax_document_id uuid, p_template_id uuid, p_xml_payload text, p_actor_user_id uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION public.save_coretax_export_internal(p_tax_document_id uuid, p_template_id uuid, p_xml_payload text, p_actor_user_id uuid, p_device_id text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text:=lower(coalesce(auth.jwt()->>'role',''));
  v_doc public.tax_documents%rowtype;
  v_template public.coretax_template_registry%rowtype;
  v_outbox uuid;
  v_sha text;
  v_expected_template text;
  v_config_tenant text;
  v_link_count bigint;
begin
  if v_role<>'service_role' then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if p_actor_user_id is null
     or nullif(btrim(coalesce(p_device_id,'')),'') is null
     or p_reason is null or length(btrim(p_reason))<3 then
    raise exception 'coretax_export_actor_device_reason_required' using errcode='22023';
  end if;

  select * into strict v_doc
  from public.tax_documents
  where tax_document_id=p_tax_document_id
  for update;

  perform private.assert_accounting_hard_gate(v_doc.tenant_id);
  if v_doc.status<>'VALIDATED' then
    raise exception 'tax_document_must_be_validated_before_export' using errcode='55000';
  end if;

  if not exists(
    select 1 from public.accounting_memberships m
    where m.tenant_id=v_doc.tenant_id
      and m.user_id=p_actor_user_id
      and m.is_active
      and m.role in ('owner','admin','accountant')
  ) then
    raise exception 'coretax_export_actor_not_authorized' using errcode='42501';
  end if;

  select d.tenant_id into strict v_config_tenant
  from public.devices d
  where d.device_id=btrim(p_device_id)
    and d.user_id=p_actor_user_id;

  if not exists(
    select 1 from public.tenants t
    where t.tenant_id=v_config_tenant
      and t.status='active'
      and not t.is_blocked
  ) then
    raise exception 'coretax_export_config_tenant_not_active' using errcode='23514';
  end if;

  select count(*) into v_link_count
  from private.tenant_accounting_links l
  where l.config_tenant_id=v_config_tenant
    and l.accounting_tenant_id=v_doc.tenant_id
    and l.valid_from<=current_date
    and (l.valid_to is null or l.valid_to>=current_date);
  if v_link_count<>1 then
    raise exception 'coretax_export_device_tenant_link_invalid' using errcode='23514';
  end if;

  v_expected_template:=case v_doc.document_type
    when 'VAT_OUTPUT' then 'FAKTUR_KELUARAN'
    when 'VAT_REPLACEMENT' then 'FAKTUR_KELUARAN'
    when 'PPH23_UNIFICATION' then 'BPPU'
    when 'PPH21_26' then 'BPMP'
    else null
  end;
  if v_expected_template is null then
    raise exception 'unsupported_coretax_document_type' using errcode='23514';
  end if;

  select * into strict v_template
  from public.coretax_template_registry
  where template_id=p_template_id and is_active and is_verified;
  if v_template.template_code<>v_expected_template then
    raise exception 'coretax_template_document_type_mismatch' using errcode='23514';
  end if;
  if v_template.xml_template is null
     or v_template.template_sha256 is null
     or v_template.template_sha256 !~ '^[0-9a-f]{64}$'
     or coalesce(v_template.generator_spec->>'status','')='SOURCE_REGISTERED_NOT_PARSED' then
    raise exception 'official_coretax_template_not_verified' using errcode='23514';
  end if;

  if p_xml_payload is null or length(p_xml_payload)<20 then
    raise exception 'invalid_coretax_export_payload' using errcode='22023';
  end if;
  if position('{{' in p_xml_payload)>0 or position('}}' in p_xml_payload)>0 then
    raise exception 'unresolved_coretax_xml_placeholder' using errcode='23514';
  end if;
  if exists(select 1 from public.coretax_outbox o where o.tax_document_id=p_tax_document_id) then
    raise exception 'coretax_export_already_exists_for_tax_document' using errcode='23505';
  end if;

  v_sha:=encode(extensions.digest(convert_to(p_xml_payload,'UTF8'),'sha256'),'hex');
  insert into public.coretax_outbox(
    tax_document_id,tenant_id,xml_template_code,xml_payload,payload_sha256,status
  ) values(
    p_tax_document_id,v_doc.tenant_id,v_template.template_code,p_xml_payload,v_sha,'EXPORTED'
  ) returning outbox_id into v_outbox;

  insert into public.tax_document_events(
    tax_document_id,tenant_id,event_type,details,actor_user_id,device_id,reason
  ) values(
    p_tax_document_id,v_doc.tenant_id,'XML_EXPORTED',
    jsonb_build_object(
      'outbox_id',v_outbox,
      'template_code',v_template.template_code,
      'template_version',v_template.template_version,
      'payload_sha256',v_sha
    ),
    p_actor_user_id,btrim(p_device_id),btrim(p_reason)
  );
  return v_outbox;
exception when no_data_found then
  raise exception 'coretax_export_dependency_missing' using errcode='23514';
end;
$function$

