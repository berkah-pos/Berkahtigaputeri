-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source. PL/pgSQL bodies are installed before SQL-language wrappers.

-- private.resolve_vat_transaction_code(p_facility_context text)
CREATE OR REPLACE FUNCTION private.resolve_vat_transaction_code(p_facility_context text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
  case upper(coalesce(btrim(p_facility_context),'NORMAL'))
    when 'NORMAL' then return '01';
    when 'NOT_COLLECTED' then return '07';
    when 'GOVERNMENT_BORNE' then return '07';
    when 'EXEMPT' then return '08';
    when 'ASSET_16D' then return '09';
    else raise exception 'invalid_vat_facility_context' using errcode='22023';
  end case;
end;
$function$;
-- private.seal_tax_document()
CREATE OR REPLACE FUNCTION private.seal_tax_document()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status in ('SUBMITTED','ACCEPTED','REPORTED','CANCELLED','REPLACED') and new.sealed_hash is null then
    new.sealed_hash:=encode(extensions.digest(convert_to(concat_ws('|',
      new.tenant_id::text,new.tax_document_id::text,new.document_type,new.transaction_ref,new.business_date::text,
      coalesce(new.vat_transaction_code,''),new.dpp::text,new.tax_amount::text,new.gross_amount::text,
      new.tax_rate_snapshot::text,new.legal_rule_snapshot::text,coalesce(new.journal_id::text,'')
    ),'UTF8'),'sha256'),'hex');
  end if;
  return new;
end;
$function$;
-- private.tax_period_obligation(p_tenant_id uuid, p_tax_code text, p_period_start date, p_period_end date)
CREATE OR REPLACE FUNCTION private.tax_period_obligation(p_tenant_id uuid, p_tax_code text, p_period_start date, p_period_end date)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_code text:=upper(btrim(coalesce(p_tax_code,''))); v_amount bigint; v_count int;
begin
  if p_period_start is null or p_period_end is null or p_period_end<p_period_start then raise exception 'invalid_tax_period' using errcode='22023'; end if;
  if v_code='PPN' then
    select s.net_payable into v_amount from public.vat_period_settlements s where s.tenant_id=p_tenant_id and s.period_start=p_period_start and s.period_end=p_period_end;
    if v_amount is null then raise exception 'vat_period_must_be_settled_before_billing' using errcode='23514'; end if;
  elsif v_code='PPH21' then
    select greatest(coalesce(sum(withholding_adjustment),0),0)::bigint into v_amount from public.payroll_tax_evidence where tenant_id=p_tenant_id and business_date between p_period_start and p_period_end;
  elsif v_code='PPH23' then
    select coalesce(sum(tax_amount),0)::bigint into v_amount from public.tax_documents where tenant_id=p_tenant_id and document_type='PPH23_UNIFICATION' and business_date between p_period_start and p_period_end and status in ('VALIDATED','SUBMITTED','ACCEPTED','REPORTED');
  elsif v_code='PPH_FINAL' then
    select coalesce(sum(tax_amount),0)::bigint into v_amount from public.tax_documents where tenant_id=p_tenant_id and document_type='PPH_FINAL' and business_date between p_period_start and p_period_end and status in ('VALIDATED','SUBMITTED','ACCEPTED','REPORTED');
  elsif v_code='PPH25' then
    select count(*) into v_count from public.corporate_pph25_authorities a
    where a.tenant_id=p_tenant_id and a.tax_year=extract(year from p_period_start)::int
      and p_period_start between a.effective_from_month and a.effective_to_month
      and (a.superseded_from_month is null or p_period_start<a.superseded_from_month);
    if v_count<>1 then raise exception 'exactly_one_effective_PPh25_authority_required' using errcode='23514'; end if;
    select a.monthly_amount into strict v_amount from public.corporate_pph25_authorities a
    where a.tenant_id=p_tenant_id and a.tax_year=extract(year from p_period_start)::int
      and p_period_start between a.effective_from_month and a.effective_to_month
      and (a.superseded_from_month is null or p_period_start<a.superseded_from_month);
  elsif v_code='PPH29' then
    select p.pph29_payable into v_amount from public.corporate_annual_tax_periods p
    where p.tenant_id=p_tenant_id and p.tax_year=extract(year from p_period_start)::int
      and p_period_start=make_date(p.tax_year,1,1) and p_period_end=make_date(p.tax_year,12,31);
    if v_amount is null then raise exception 'corporate_annual_tax_must_be_closed_before_PPh29_billing' using errcode='23514'; end if;
  else raise exception 'unsupported_tax_remittance_code' using errcode='22023'; end if;
  return coalesce(v_amount,0);
end; $function$;
-- private.verify_manager_pin_internal(p_device_id text, p_outlet_id text, p_pin text, p_required_action text)
CREATE OR REPLACE FUNCTION private.verify_manager_pin_internal(p_device_id text, p_outlet_id text, p_pin text, p_required_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_tenant text;
  v_role text;
  v_hash text;
  v_active boolean;
  v_attempts integer;
  v_locked timestamptz;
  v_now timestamptz := now();
  v_ok boolean := false;
begin
  if v_actor is null then raise exception 'authenticated session required' using errcode='42501'; end if;
  if trim(p_device_id) = '' or trim(p_outlet_id) = '' or coalesce(p_pin,'') = '' then
    raise exception 'device, outlet and pin are required' using errcode='22023';
  end if;
  if p_required_action not in ('return_sale','void_sale','close_shift_variance') then
    raise exception 'unsupported manager pin action' using errcode='22023';
  end if;
  select d.tenant_id into v_tenant
  from public.devices d
  where d.device_id = trim(p_device_id) and d.user_id = v_actor;
  if v_tenant is null then raise exception 'device is not bound to actor' using errcode='42501'; end if;

  select role, pin_hash, is_active, attempts, locked_until
    into v_role, v_hash, v_active, v_attempts, v_locked
  from private.manager_pins
  where tenant_id = v_tenant and outlet_id = trim(p_outlet_id)
  for update;

  if v_hash is null or not coalesce(v_active,false) then
    insert into private.audit_logs(tenant_id, actor_id, device_id, source, reason, action)
    values (v_tenant, v_actor, trim(p_device_id), 'pos_pin', p_required_action, 'fail');
    return jsonb_build_object('ok',false,'role',v_role,'isActive',coalesce(v_active,false),'attempts',coalesce(v_attempts,0),'lockedUntil',v_locked);
  end if;

  if v_locked is not null and v_locked > v_now then
    insert into private.audit_logs(tenant_id, actor_id, device_id, source, reason, action)
    values (v_tenant, v_actor, trim(p_device_id), 'pos_pin', p_required_action, 'fail');
    return jsonb_build_object('ok',false,'role',v_role,'isActive',true,'attempts',v_attempts,'lockedUntil',v_locked);
  end if;

  v_ok := extensions.crypt(p_pin, v_hash) = v_hash;
  if v_ok then
    update private.manager_pins
       set attempts = 0, locked_until = null, updated_at = v_now
     where tenant_id = v_tenant and outlet_id = trim(p_outlet_id);
  else
    v_attempts := case when v_locked is not null and v_locked <= v_now then 1 else least(v_attempts + 1, 3) end;
    v_locked := case when v_attempts >= 3 then v_now + interval '5 minutes' else null end;
    update private.manager_pins
       set attempts = v_attempts, locked_until = v_locked, updated_at = v_now
     where tenant_id = v_tenant and outlet_id = trim(p_outlet_id);
  end if;

  insert into private.audit_logs(tenant_id, actor_id, device_id, source, reason, action)
  values (v_tenant, v_actor, trim(p_device_id), 'pos_pin', p_required_action, case when v_ok then 'success' else 'fail' end);

  return jsonb_build_object('ok',v_ok,'role',v_role,'isActive',true,'attempts',case when v_ok then 0 else v_attempts end,'lockedUntil',case when v_ok then null else v_locked end);
end;
$function$;
-- public.activate_pph25_authority(p_tenant_id uuid, p_source_annual_period_id uuid, p_effective_from_month date, p_source_reference text, p_source_filed_date date, p_supersedes_authority_id uuid, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.activate_pph25_authority(p_tenant_id uuid, p_source_annual_period_id uuid, p_effective_from_month date, p_source_reference text, p_source_filed_date date, p_supersedes_authority_id uuid, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid(); v_ann public.corporate_annual_tax_periods%rowtype; v_target_year int; v_to date; v_basis bigint; v_monthly bigint; v_id uuid; v_old public.corporate_pph25_authorities%rowtype;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_reason is null or length(btrim(p_reason))<3 or p_source_reference is null or length(btrim(p_source_reference))<3 or p_source_filed_date is null then raise exception 'PPh25 authority source evidence required' using errcode='22023'; end if;
  select * into strict v_ann from public.corporate_annual_tax_periods where tenant_id=p_tenant_id and annual_period_id=p_source_annual_period_id;
  v_target_year:=v_ann.tax_year+1;
  v_to:=make_date(v_target_year,12,1);
  if p_effective_from_month is null or p_effective_from_month<>date_trunc('month',p_effective_from_month)::date or extract(year from p_effective_from_month)::int<>v_target_year then raise exception 'PPh25 effective month must be a month in the following tax year' using errcode='22023'; end if;
  if p_effective_from_month<date_trunc('month',p_source_filed_date)::date then raise exception 'PPh25 authority cannot be effective before source filing month' using errcode='23514'; end if;
  v_basis:=greatest(v_ann.corporate_tax_due-v_ann.pph23_credit_available,0);
  v_monthly:=round(v_basis::numeric/12)::bigint;
  if p_supersedes_authority_id is null then
    if exists(select 1 from public.corporate_pph25_authorities a where a.tenant_id=p_tenant_id and a.tax_year=v_target_year and a.superseded_from_month is null) then raise exception 'active PPh25 authority already exists; use supersession' using errcode='23505'; end if;
  else
    select * into strict v_old from public.corporate_pph25_authorities a where a.tenant_id=p_tenant_id and a.authority_id=p_supersedes_authority_id for update;
    if v_old.tax_year<>v_target_year or v_old.superseded_from_month is not null or p_effective_from_month<=v_old.effective_from_month then raise exception 'invalid PPh25 authority supersession source' using errcode='23514'; end if;
  end if;
  insert into public.corporate_pph25_authorities(tenant_id,tax_year,source_annual_period_id,effective_from_month,effective_to_month,annual_installment_basis,monthly_amount,source_reference,source_filed_date,calculation_snapshot,actor_user_id,device_id,reason,supersedes_authority_id)
  values(p_tenant_id,v_target_year,p_source_annual_period_id,p_effective_from_month,v_to,v_basis,v_monthly,btrim(p_source_reference),p_source_filed_date,
    jsonb_build_object('formula','(prior_year_corporate_tax_due - prior_year_PPh23_credit)/12','prior_year_tax_due',v_ann.corporate_tax_due,'prior_year_pph23_credit',v_ann.pph23_credit_available,'annual_installment_basis',v_basis,'monthly_amount',v_monthly,'rounding','nearest_full_rupiah','legal_basis','Pasal 25 UU PPh jo. UU HPP'),
    v_actor,btrim(p_device_id),btrim(p_reason),p_supersedes_authority_id) returning authority_id into v_id;
  if p_supersedes_authority_id is not null then update public.corporate_pph25_authorities set superseded_from_month=p_effective_from_month where authority_id=p_supersedes_authority_id; end if;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action) values(p_tenant_id::text,v_actor,btrim(p_device_id),'pph25_authority:'||v_id::text,btrim(p_reason),'success');
  return v_id;
exception when no_data_found then raise exception 'PPh25 authority dependency missing' using errcode='P0002';
end; $function$;
-- public.apply_midtrans_payment(p_sub_id uuid, p_status text, p_transaction_id text, p_amount numeric, p_order_id text, p_checked_at timestamp with time zone)
CREATE OR REPLACE FUNCTION public.apply_midtrans_payment(p_sub_id uuid, p_status text, p_transaction_id text, p_amount numeric, p_order_id text, p_checked_at timestamp with time zone)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  s public.subscriptions;
  owner_id uuid;
  start_at timestamptz;
  end_at timestamptz;
begin
  if p_status not in ('pending','active','cancelled','expired') or p_checked_at is null then
    raise exception 'invalid_payment_state';
  end if;

  select user_id into strict owner_id
  from public.subscriptions
  where sub_id = p_sub_id;

  perform pg_advisory_xact_lock(hashtextextended(owner_id::text, 17));

  select * into strict s
  from public.subscriptions
  where sub_id = p_sub_id
  for update;

  if s.payment_provider <> 'midtrans'
     or s.midtrans_order_id is distinct from p_order_id then
    raise exception 'payment_order_mismatch';
  end if;

  if s.provider_checked_at is not null
     and p_checked_at <= s.provider_checked_at then
    return s.status;
  end if;

  if s.midtrans_amount_idr is null or s.midtrans_duration_days is null then
    raise exception 'legacy_order_requires_verified_snapshot';
  end if;

  if p_amount is null or p_amount <> s.midtrans_amount_idr then
    raise exception 'payment_amount_mismatch';
  end if;

  if p_transaction_id is null or length(p_transaction_id) = 0 then
    raise exception 'missing_transaction_id';
  end if;

  if s.midtrans_transaction_id is not null
     and s.midtrans_transaction_id <> p_transaction_id then
    raise exception 'payment_transaction_mismatch';
  end if;

  if p_status = 'active' then
    if s.paid_at is null then
      select greatest(now(), coalesce(max(current_period_end), now()))
      into start_at
      from public.subscriptions
      where user_id = owner_id
        and sub_id <> p_sub_id
        and payment_provider = 'midtrans'
        and plan_id = s.plan_id
        and paid_at is not null
        and status in ('active','past_due');

      end_at := start_at + make_interval(days => s.midtrans_duration_days);

      update public.subscriptions
      set status = 'active',
          paid_at = now(),
          current_period_start = start_at,
          current_period_end = end_at,
          grace_period_end = end_at + interval '3 days',
          auto_renewing = false,
          cancelled_at = null,
          midtrans_transaction_id = p_transaction_id,
          provider_checked_at = p_checked_at
      where sub_id = p_sub_id;

      return 'active';
    end if;

    -- The order has already purchased its one period. Do not extend it again,
    -- but do advance the provider-read watermark so an older in-flight read
    -- cannot overwrite this newer reconciliation.
    update public.subscriptions
    set provider_checked_at = p_checked_at,
        midtrans_transaction_id =
          coalesce(midtrans_transaction_id, p_transaction_id)
    where sub_id = p_sub_id;

    return s.status;
  end if;

  if p_status = 'pending' and s.paid_at is not null then
    -- A paid order never rolls back to pending, but this is still a newer
    -- authoritative provider read and must advance the ordering watermark.
    update public.subscriptions
    set provider_checked_at = p_checked_at,
        midtrans_transaction_id =
          coalesce(midtrans_transaction_id, p_transaction_id)
    where sub_id = p_sub_id;

    return s.status;
  end if;

  update public.subscriptions
  set status = case when p_status = 'cancelled' then 'expired' else p_status end,
      midtrans_transaction_id = p_transaction_id,
      provider_checked_at = p_checked_at,
      auto_renewing = false
  where sub_id = p_sub_id;

  return case when p_status = 'cancelled' then 'expired' else p_status end;
end
$function$;
-- public.apply_play_subscription(p_user_id uuid, p_token text, p_plan_id text, p_state jsonb, p_checked_at timestamp with time zone, p_linked_token text)
CREATE OR REPLACE FUNCTION public.apply_play_subscription(p_user_id uuid, p_token text, p_plan_id text, p_state jsonb, p_checked_at timestamp with time zone, p_linked_token text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  result_id uuid;
  owner_id uuid;
begin
  if p_checked_at is null then raise exception 'missing_provider_check_time'; end if;
  -- User lock serializes linked-token replacement; unique token handles
  -- competing users atomically through the conflict predicate below.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 18));
  if p_linked_token is not null then
    select user_id into owner_id from public.subscriptions where play_purchase_token = p_linked_token;
    if owner_id is not null and owner_id <> p_user_id then raise exception 'linked_token_owner_mismatch'; end if;
  end if;
  insert into public.subscriptions as existing (
    user_id, plan_id, status, payment_provider, play_purchase_token, play_order_id,
    current_period_start, current_period_end, grace_period_end, auto_renewing, provider_checked_at
  ) values (
    p_user_id, p_plan_id, p_state->>'status', 'play_billing', p_token, p_state->>'playOrderId',
    (p_state->>'currentPeriodStart')::timestamptz, (p_state->>'currentPeriodEnd')::timestamptz,
    (p_state->>'currentPeriodEnd')::timestamptz, (p_state->>'autoRenewing')::boolean, p_checked_at
  ) on conflict (play_purchase_token) do update set
    plan_id = excluded.plan_id, status = excluded.status, play_order_id = excluded.play_order_id,
    current_period_start = excluded.current_period_start, current_period_end = excluded.current_period_end,
    grace_period_end = excluded.grace_period_end, auto_renewing = excluded.auto_renewing,
    provider_checked_at = excluded.provider_checked_at
  where existing.user_id = p_user_id
    and (existing.provider_checked_at is null or existing.provider_checked_at < p_checked_at)
  returning sub_id into result_id;
  if result_id is null then
    select sub_id into result_id from public.subscriptions where play_purchase_token = p_token and user_id = p_user_id;
    if result_id is null then raise exception 'purchase_token_already_bound'; end if;
    return result_id;
  end if;
  if p_linked_token is not null and p_state->>'status' in ('active','past_due','cancelled') then
    update public.subscriptions set status = 'expired', auto_renewing = false
    where play_purchase_token = p_linked_token and user_id = p_user_id and sub_id <> result_id;
  end if;
  return result_id;
end $function$;
-- public.assert_config_contract()
CREATE OR REPLACE FUNCTION public.assert_config_contract()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_count int; v_digest text;
begin
  perform private.assert_app_config_inventory();
  select count(*)::int,md5(string_agg(key,E'\n' order by key)) into v_count,v_digest from public.app_config;
  if v_count<>352 or v_digest<>'1fd3d64219ecc7c333453c20da80e295' then
    raise exception 'app_config_contract_mismatch' using errcode='23514';
  end if;
  return jsonb_build_object('count',v_count,'keyset_md5',v_digest,'expected_count',352,'expected_keyset_md5','1fd3d64219ecc7c333453c20da80e295');
end;
$function$;
-- public.assert_financial_report_ready(p_tenant_id uuid)
CREATE OR REPLACE FUNCTION public.assert_financial_report_ready(p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_gate jsonb;
begin
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  v_gate:=private.compute_accounting_hard_gate(p_tenant_id);
  if coalesce((v_gate->>'all_zero')::boolean,false) is not true then
    raise exception 'financial_report_blocked: %',v_gate using errcode='23514';
  end if;
  return v_gate;
end;
$function$;
-- public.bind_license_device(p_user_id uuid, p_device_id text, p_platform text, p_app_version text, p_plan_id text)
CREATE OR REPLACE FUNCTION public.bind_license_device(p_user_id uuid, p_device_id text, p_platform text, p_app_version text, p_plan_id text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_max_devices integer;
  v_count integer;
  v_owner uuid;
begin
  if p_platform not in ('android_play','android_direct') then
    raise exception using errcode = '22023', message = 'invalid_platform';
  end if;

  -- Serialize device enrollment per user.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  select user_id into v_owner
  from public.devices
  where device_id = p_device_id;

  if v_owner is not null and v_owner <> p_user_id then
    raise exception using errcode = 'P0001', message = 'device_bound_to_other_user';
  end if;

  if v_owner = p_user_id then
    update public.devices
    set platform = p_platform,
        app_version = p_app_version,
        last_license_check = now()
    where device_id = p_device_id;
    return;
  end if;

  select max_devices into v_max_devices
  from public.plans
  where plan_id = p_plan_id;

  if v_max_devices is null then
    raise exception using errcode = 'P0001', message = 'plan_not_found';
  end if;

  select count(*)::integer into v_count
  from public.devices
  where user_id = p_user_id;

  if v_count >= v_max_devices then
    raise exception using errcode = 'P0001', message = 'device_limit_exceeded';
  end if;

  insert into public.devices (
    device_id,
    user_id,
    platform,
    app_version,
    last_license_check
  ) values (
    p_device_id,
    p_user_id,
    p_platform,
    p_app_version,
    now()
  );
end;
$function$;
-- public.calculate_pph21_final_period(p_annual_taxable_income bigint, p_withheld_before_final_period bigint)
CREATE OR REPLACE FUNCTION public.calculate_pph21_final_period(p_annual_taxable_income bigint, p_withheld_before_final_period bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pkp bigint:=greatest(coalesce(p_annual_taxable_income,0),0); v_tax numeric:=0; v_remaining bigint; v_final bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if p_annual_taxable_income is null or p_annual_taxable_income<0 or p_withheld_before_final_period is null or p_withheld_before_final_period<0 then raise exception 'invalid_final_period_input' using errcode='22023'; end if;
  v_remaining:=v_pkp;
  v_tax:=v_tax+least(v_remaining,60000000)::numeric*0.05; v_remaining:=greatest(v_remaining-60000000,0);
  v_tax:=v_tax+least(v_remaining,190000000)::numeric*0.15; v_remaining:=greatest(v_remaining-190000000,0);
  v_tax:=v_tax+least(v_remaining,250000000)::numeric*0.25; v_remaining:=greatest(v_remaining-250000000,0);
  v_tax:=v_tax+least(v_remaining,4500000000)::numeric*0.30; v_remaining:=greatest(v_remaining-4500000000,0);
  v_tax:=v_tax+v_remaining::numeric*0.35;
  v_final:=round(v_tax)::bigint-p_withheld_before_final_period;
  return jsonb_build_object('annual_taxable_income',v_pkp,'annual_pph21',round(v_tax)::bigint,'withheld_before_final_period',p_withheld_before_final_period,'final_period_adjustment',v_final,'method','ARTICLE_17_FINAL_PERIOD','legal_basis','UU PPh jo. UU HPP; PMK 168/2023');
end;
$function$;
-- public.calculate_pph21_ter(p_marital_status text, p_dependents integer, p_monthly_gross bigint, p_business_date date)
CREATE OR REPLACE FUNCTION public.calculate_pph21_ter(p_marital_status text, p_dependents integer, p_monthly_gross bigint, p_business_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_category text; v_rule jsonb; v_tax bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if p_monthly_gross is null or p_monthly_gross<0 or p_business_date is null then raise exception 'invalid_pph21_input' using errcode='22023'; end if;
  v_category:=private.resolve_ter_category(p_marital_status,p_dependents);
  v_rule:=private.resolve_pph21_ter(v_category,p_monthly_gross,p_business_date);
  v_tax:=round(p_monthly_gross::numeric*(v_rule->>'rate')::numeric)::bigint;
  return jsonb_build_object('category',v_category,'monthly_gross',p_monthly_gross,'withholding',v_tax,'rule',v_rule,'method','TER_PERIODIC');
end;
$function$;