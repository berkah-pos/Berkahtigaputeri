-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source. PL/pgSQL bodies are installed before SQL-language wrappers.

-- public.close_corporate_tax_year(p_tenant_id uuid, p_tax_year integer, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.close_corporate_tax_year(p_tenant_id uuid, p_tax_year integer, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid(); v_start date; v_end date; v_existing uuid; v_self_count int; v_self public.tax_parties%rowtype;
  v_commercial bigint; v_pos bigint; v_neg bigint; v_fiscal bigint; v_remaining_income bigint; v_loss_applied bigint:=0; v_loss_created bigint:=0;
  v_loss public.corporate_fiscal_loss_carryforwards%rowtype; v_loss_available bigint; v_apply bigint;
  v_pkp bigint; v_gross bigint; v_rule jsonb; v_rate numeric; v_method text; v_facility_pkp bigint:=0; v_general_pkp bigint:=0; v_tax_due bigint:=0;
  v_pph23_avail bigint:=0; v_pph25_avail bigint:=0; v_pph23_apply bigint:=0; v_pph25_apply bigint:=0; v_pph29 bigint:=0; v_overpay bigint:=0;
  v_lines jsonb:='[]'::jsonb; v_journal uuid; v_period uuid; v_ref text; v_fingerprint jsonb;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  if p_tax_year is null or p_tax_year<2020 or p_tax_year>=extract(year from current_date)::integer then raise exception 'corporate_tax_year_must_be_completed' using errcode='23514'; end if;
  v_start:=make_date(p_tax_year,1,1); v_end:=make_date(p_tax_year,12,31);
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':corporate-tax:'||p_tax_year::text,7346));
  select annual_period_id into v_existing from public.corporate_annual_tax_periods where tenant_id=p_tenant_id and tax_year=p_tax_year;
  if v_existing is not null then return v_existing; end if;

  select count(*) into v_self_count from public.tax_parties p
  where p.tenant_id=p_tenant_id and p.party_kind='SELF' and p.valid_from<=v_start and (p.valid_to is null or p.valid_to>=v_end)
    and p.taxpayer_type in ('BADAN','PT_PERORANGAN','KOPERASI') and upper(p.tax_regime)<>'PPH_FINAL_UMKM'
    and p.certificate_status in ('VALID','NOT_REQUIRED')
    and coalesce((p.metadata->>'corporate_all_turnover_captured')::boolean,false)
    and coalesce((p.metadata->>'corporate_fiscal_scope_verified')::boolean,false)
    and coalesce((p.metadata->>'corporate_no_pph22_pph24_credits')::boolean,false)
    and upper(coalesce(p.metadata->>'corporate_special_rate','NONE'))='NONE';
  if v_self_count<>1 then raise exception 'exactly_one_verified_ordinary_corporate_self_profile_required' using errcode='23514'; end if;
  select * into strict v_self from public.tax_parties p
  where p.tenant_id=p_tenant_id and p.party_kind='SELF' and p.valid_from<=v_start and (p.valid_to is null or p.valid_to>=v_end)
    and p.taxpayer_type in ('BADAN','PT_PERORANGAN','KOPERASI') and upper(p.tax_regime)<>'PPH_FINAL_UMKM'
    and p.certificate_status in ('VALID','NOT_REQUIRED')
    and coalesce((p.metadata->>'corporate_all_turnover_captured')::boolean,false)
    and coalesce((p.metadata->>'corporate_fiscal_scope_verified')::boolean,false)
    and coalesce((p.metadata->>'corporate_no_pph22_pph24_credits')::boolean,false)
    and upper(coalesce(p.metadata->>'corporate_special_rate','NONE'))='NONE';

  v_commercial:=private.corporate_commercial_profit_before_tax(p_tenant_id,p_tax_year);
  select coalesce(sum(amount) filter(where direction='POSITIVE'),0)::bigint,coalesce(sum(amount) filter(where direction='NEGATIVE'),0)::bigint
    into v_pos,v_neg from public.corporate_fiscal_adjustments where tenant_id=p_tenant_id and tax_year=p_tax_year;
  v_fiscal:=v_commercial+v_pos-v_neg;
  v_remaining_income:=greatest(v_fiscal,0);
  if v_remaining_income>0 then
    for v_loss in
      select l.* from public.corporate_fiscal_loss_carryforwards l
      where l.tenant_id=p_tenant_id and l.origin_tax_year between p_tax_year-5 and p_tax_year-1 and l.expires_after_tax_year>=p_tax_year
      order by l.origin_tax_year
    loop
      select greatest(v_loss.original_loss-coalesce(sum(a.amount_applied),0),0)::bigint into v_loss_available
      from public.corporate_fiscal_loss_applications a where a.loss_id=v_loss.loss_id;
      v_apply:=least(v_remaining_income,v_loss_available);
      if v_apply>0 then v_loss_applied:=v_loss_applied+v_apply; v_remaining_income:=v_remaining_income-v_apply; end if;
      exit when v_remaining_income=0;
    end loop;
  else
    v_loss_created:=greatest(-v_fiscal,0);
  end if;
  v_pkp:=(floor(v_remaining_income::numeric/1000)*1000)::bigint;
  v_gross:=private.corporate_gross_turnover_between(p_tenant_id,v_start,v_end);
  if v_pkp>0 and v_gross<=0 then raise exception 'corporate_gross_turnover_evidence_missing' using errcode='23514'; end if;
  v_rule:=private.resolve_tax_rate_snapshot('PPH_BADAN','GENERAL',v_end,'DEFAULT');
  v_rate:=(v_rule->>'effective_rate')::numeric;
  if v_pkp=0 then
    v_method:='LOSS_OR_NIL';
  elsif v_gross<=4800000000 then
    v_method:='ARTICLE_31E_FULL'; v_facility_pkp:=v_pkp; v_tax_due:=round(v_pkp::numeric*v_rate*0.5)::bigint;
  elsif v_gross<=50000000000 then
    v_method:='ARTICLE_31E_PARTIAL';
    v_facility_pkp:=floor(v_pkp::numeric*4800000000::numeric/v_gross::numeric)::bigint;
    v_general_pkp:=v_pkp-v_facility_pkp;
    v_tax_due:=round(v_facility_pkp::numeric*v_rate*0.5+v_general_pkp::numeric*v_rate)::bigint;
  else
    v_method:='GENERAL_22'; v_general_pkp:=v_pkp; v_tax_due:=round(v_pkp::numeric*v_rate)::bigint;
  end if;

  select coalesce(sum(c.tax_amount),0)::bigint into v_pph23_avail from public.customer_withholding_tax_credits c where c.tenant_id=p_tenant_id and c.business_date between v_start and v_end;
  select coalesce(sum(r.amount),0)::bigint into v_pph25_avail from public.tax_payment_refs r where r.tenant_id=p_tenant_id and r.tax_code='PPH25' and r.status='PAID' and r.tax_period_start between v_start and v_end;
  v_pph23_apply:=least(v_pph23_avail,v_tax_due);
  v_pph25_apply:=least(v_pph25_avail,greatest(v_tax_due-v_pph23_apply,0));
  v_pph29:=greatest(v_tax_due-v_pph23_apply-v_pph25_apply,0);
  v_overpay:=greatest(v_pph23_avail+v_pph25_avail-v_tax_due,0);
  v_ref:='PPH_BADAN:'||p_tax_year::text;
  if v_tax_due>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_code','6-6120','debit',v_tax_due,'credit',0,'memo','Beban PPh Badan '||p_tax_year));
    if v_pph23_apply>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_code','1-1100','debit',0,'credit',v_pph23_apply,'memo','Pemakaian kredit PPh23')); end if;
    if v_pph25_apply>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_code','1-1110','debit',0,'credit',v_pph25_apply,'memo','Pemakaian angsuran PPh25')); end if;
    if v_pph29>0 then v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_code','2-2070','debit',0,'credit',v_pph29,'memo','Utang PPh29 '||p_tax_year)); end if;
    v_journal:=accounting_private.post_journal(p_tenant_id,'auto:'||v_ref,v_ref,v_end,'PPH_BADAN_TAHUNAN','manual',v_lines,p_device_id,p_app_version);
    v_fingerprint:=jsonb_build_object('transaction_type','PPH_BADAN_TAHUNAN','tax_year',p_tax_year,'actor_user_id',v_actor,'device_id',btrim(p_device_id),'app_version',btrim(p_app_version),'reason',btrim(p_reason));
    insert into public.accounting_transaction_evidence(tenant_id,transaction_ref,transaction_type,business_date,request_fingerprint,facts_snapshot,tax_snapshot,journal_id,actor_user_id,device_id,app_version,reason)
    values(p_tenant_id,v_ref,'PPH_BADAN_TAHUNAN',v_end,v_fingerprint,jsonb_build_object('tax_year',p_tax_year),v_rule||jsonb_build_object('rate_method',v_method,'gross_turnover',v_gross,'facility_taxable_income',v_facility_pkp,'general_taxable_income',v_general_pkp),v_journal,v_actor,btrim(p_device_id),btrim(p_app_version),btrim(p_reason));
  end if;

  insert into public.corporate_annual_tax_periods(
    tenant_id,tax_year,taxpayer_type,commercial_profit_before_tax,fiscal_positive_adjustments,fiscal_negative_adjustments,fiscal_income_before_losses,
    fiscal_loss_applied,fiscal_loss_created,taxable_income,gross_turnover,rate_method,facility_taxable_income,general_taxable_income,corporate_tax_due,
    pph23_credit_available,pph23_credit_applied,pph25_credit_available,pph25_credit_applied,pph29_payable,overpayment_remaining,tax_rule_snapshot,
    annual_journal_id,self_tax_party_id,actor_user_id,device_id,app_version,reason
  ) values(
    p_tenant_id,p_tax_year,v_self.taxpayer_type,v_commercial,v_pos,v_neg,v_fiscal,v_loss_applied,v_loss_created,v_pkp,v_gross,v_method,v_facility_pkp,v_general_pkp,v_tax_due,
    v_pph23_avail,v_pph23_apply,v_pph25_avail,v_pph25_apply,v_pph29,v_overpay,
    v_rule||jsonb_build_object('rate_method',v_method,'article_31e_turnover_limit',50000000000,'article_31e_facility_turnover',4800000000,'fiscal_loss_compensation_years',5),
    v_journal,v_self.party_id,v_actor,btrim(p_device_id),btrim(p_app_version),btrim(p_reason)
  ) returning annual_period_id into v_period;

  if v_loss_applied>0 then
    v_remaining_income:=v_loss_applied;
    for v_loss in
      select l.* from public.corporate_fiscal_loss_carryforwards l
      where l.tenant_id=p_tenant_id and l.origin_tax_year between p_tax_year-5 and p_tax_year-1 and l.expires_after_tax_year>=p_tax_year
      order by l.origin_tax_year
    loop
      select greatest(v_loss.original_loss-coalesce(sum(a.amount_applied),0),0)::bigint into v_loss_available from public.corporate_fiscal_loss_applications a where a.loss_id=v_loss.loss_id;
      v_apply:=least(v_remaining_income,v_loss_available);
      if v_apply>0 then
        insert into public.corporate_fiscal_loss_applications(tenant_id,loss_id,target_annual_period_id,target_tax_year,amount_applied) values(p_tenant_id,v_loss.loss_id,v_period,p_tax_year,v_apply);
        v_remaining_income:=v_remaining_income-v_apply;
      end if;
      exit when v_remaining_income=0;
    end loop;
  end if;
  if v_loss_created>0 then
    insert into public.corporate_fiscal_loss_carryforwards(tenant_id,origin_tax_year,original_loss,expires_after_tax_year,source_annual_period_id)
    values(p_tenant_id,p_tax_year,v_loss_created,p_tax_year+5,v_period);
  end if;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action) values(p_tenant_id::text,v_actor,btrim(p_device_id),'corporate_tax_year_close:'||p_tax_year::text,btrim(p_reason),'success');
  return v_period;
end; $function$


-- public.close_employee_tax_profile(p_tenant_id uuid, p_profile_id uuid, p_valid_to date, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.close_employee_tax_profile(p_tenant_id uuid, p_profile_id uuid, p_valid_to date, p_device_id text, p_app_version text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid();
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_valid_to is null or p_valid_to<current_date then
    raise exception 'valid_to_must_be_today_or_future' using errcode='22023';
  end if;
  if p_reason is null or length(btrim(p_reason))<3 then
    raise exception 'audit_reason_required' using errcode='22023';
  end if;
  update public.employee_tax_profiles
    set valid_to=p_valid_to
  where tenant_id=p_tenant_id and profile_id=p_profile_id and valid_to is null;
  if not found then raise exception 'open_employee_tax_profile_not_found' using errcode='P0002'; end if;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values(p_tenant_id::text,v_actor,btrim(p_device_id),'employee_tax_profile:close:'||p_profile_id::text,btrim(p_reason),'success');
end;
$function$


-- public.close_owner_turnover_tax_period(p_tenant_id uuid, p_period_start date, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.close_owner_turnover_tax_period(p_tenant_id uuid, p_period_start date, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid(); v_end date; v_build jsonb; v_existing uuid; v_journal uuid; v_doc uuid; v_id uuid; v_ref text; v_fingerprint jsonb;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  if p_period_start is null or p_period_start<>date_trunc('month',p_period_start)::date then raise exception 'owner_turnover_tax_period_start_must_be_first_day' using errcode='22023'; end if;
  v_end:=(date_trunc('month',p_period_start)+interval '1 month - 1 day')::date;
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':umkm-final:'||p_period_start::text,7344));
  select period_id into v_existing from public.owner_turnover_tax_periods where tenant_id=p_tenant_id and period_start=p_period_start;
  if v_existing is not null then return v_existing; end if;
  if exists(select 1 from public.owner_turnover_tax_periods p where p.tenant_id=p_tenant_id and p.period_end<p_period_start and p.period_end<>(p_period_start-1)) then null; end if;
  v_build:=private.build_owner_turnover_tax_lines(p_tenant_id,v_end,'{}'::jsonb);
  v_ref:='UMKM_FINAL:'||to_char(p_period_start,'YYYY-MM');
  if (v_build->>'tax_amount')::bigint>0 then
    v_journal:=accounting_private.post_journal(p_tenant_id,'auto:'||v_ref,v_ref,v_end,'PPH_FINAL_UMKM_BULANAN','manual',v_build->'journal_lines',p_device_id,p_app_version);
    v_fingerprint:=jsonb_build_object('transaction_type','PPH_FINAL_UMKM_BULANAN','period_start',p_period_start,'period_end',v_end,'actor_user_id',v_actor,'device_id',btrim(p_device_id),'app_version',btrim(p_app_version),'reason',btrim(p_reason));
    insert into public.accounting_transaction_evidence(tenant_id,transaction_ref,transaction_type,business_date,request_fingerprint,facts_snapshot,tax_snapshot,journal_id,actor_user_id,device_id,app_version,reason)
    values(p_tenant_id,v_ref,'PPH_FINAL_UMKM_BULANAN',v_end,v_fingerprint,jsonb_build_object('period_start',p_period_start,'period_end',v_end),v_build->'tax_snapshot',v_journal,v_actor,btrim(p_device_id),btrim(p_app_version),btrim(p_reason));
    v_doc:=private.create_tax_document_internal(p_tenant_id,'PPH_FINAL',v_ref,v_end,null,null,v_build->'tax_snapshot',(v_build->>'taxable_turnover_month')::bigint,(v_build->>'tax_amount')::bigint,(v_build->>'taxable_turnover_month')::bigint,v_journal,'VALID',false,null,v_actor,p_device_id,p_reason);
  end if;
  insert into public.owner_turnover_tax_periods(tenant_id,period_start,period_end,taxpayer_type,gross_turnover_month,gross_turnover_ytd_before,gross_turnover_ytd_after,exempt_turnover_month,taxable_turnover_month,tax_amount,tax_rule_snapshot,tax_journal_id,tax_document_id,actor_user_id,device_id,app_version,reason)
  values(p_tenant_id,p_period_start,v_end,v_build->>'taxpayer_type',(v_build->>'gross_turnover_month')::bigint,(v_build->>'gross_turnover_ytd_before')::bigint,(v_build->>'gross_turnover_ytd_after')::bigint,(v_build->>'exempt_turnover_month')::bigint,(v_build->>'taxable_turnover_month')::bigint,(v_build->>'tax_amount')::bigint,v_build->'tax_snapshot',v_journal,v_doc,v_actor,btrim(p_device_id),btrim(p_app_version),btrim(p_reason)) returning period_id into v_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action) values(p_tenant_id::text,v_actor,btrim(p_device_id),'owner_umkm_final:'||to_char(p_period_start,'YYYY-MM'),btrim(p_reason),'success');
  return v_id;
end; $function$


-- public.close_self_tax_party_for_config_tenant(p_config_tenant_id text, p_valid_to date, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.close_self_tax_party_for_config_tenant(p_config_tenant_id text, p_valid_to date, p_device_id text, p_app_version text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid();
  v_accounting_tenant uuid;
  v_party_id uuid;
  v_count bigint;
begin
  if p_config_tenant_id is null or length(btrim(p_config_tenant_id))=0 then
    raise exception 'config_tenant_id_required' using errcode='22023';
  end if;
  if p_valid_to is null then
    raise exception 'valid_to_required' using errcode='22023';
  end if;

  v_accounting_tenant := public.resolve_accounting_tenant(
    btrim(p_config_tenant_id),
    current_date,
    p_device_id,
    p_app_version
  );
  perform accounting_private.require_member_role(
    v_accounting_tenant,
    v_actor,
    array['owner','admin','accountant']
  );

  select count(*)::bigint into v_count
  from public.tax_parties tp
  where tp.tenant_id=v_accounting_tenant
    and tp.party_kind='SELF'
    and tp.valid_to is null
    and tp.valid_from<=current_date;

  if v_count=0 then
    raise exception 'open_effective_self_tax_profile_not_found' using errcode='P0002';
  end if;
  if v_count<>1 then
    raise exception 'open_self_tax_profile_ambiguity' using errcode='23514';
  end if;

  select tp.party_id into strict v_party_id
  from public.tax_parties tp
  where tp.tenant_id=v_accounting_tenant
    and tp.party_kind='SELF'
    and tp.valid_to is null
    and tp.valid_from<=current_date
  for update;

  perform public.close_tax_party_evidence(
    v_accounting_tenant,
    v_party_id,
    p_valid_to,
    p_device_id,
    p_app_version,
    p_reason
  );
end;
$function$


-- public.close_service_tax_profile(p_tenant_id uuid, p_service_profile_id uuid, p_valid_to date, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.close_service_tax_profile(p_tenant_id uuid, p_service_profile_id uuid, p_valid_to date, p_device_id text, p_app_version text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_old public.service_tax_profiles%rowtype;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  select * into strict v_old from public.service_tax_profiles
  where tenant_id=p_tenant_id and service_profile_id=p_service_profile_id for update;
  if v_old.valid_to is not null then raise exception 'service_tax_profile_already_closed' using errcode='55000'; end if;
  if p_valid_to is null or p_valid_to<v_old.valid_from or p_valid_to<current_date then raise exception 'service_tax_profile_cannot_close_retroactively' using errcode='55000'; end if;
  update public.service_tax_profiles set valid_to=p_valid_to
  where tenant_id=p_tenant_id and service_profile_id=p_service_profile_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values(p_tenant_id::text,v_actor,btrim(p_device_id),'service_tax_profile:close:'||p_service_profile_id::text,btrim(p_reason),'success');
end;
$function$


-- public.close_tax_party_evidence(p_tenant_id uuid, p_party_id uuid, p_valid_to date, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.close_tax_party_evidence(p_tenant_id uuid, p_party_id uuid, p_valid_to date, p_device_id text, p_app_version text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_old public.tax_parties%rowtype;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  select * into strict v_old from public.tax_parties where tenant_id=p_tenant_id and party_id=p_party_id for update;
  if v_old.valid_to is not null then raise exception 'tax_party_evidence_already_closed' using errcode='55000'; end if;
  if p_valid_to is null or p_valid_to<v_old.valid_from or p_valid_to<current_date then raise exception 'tax_party_evidence_cannot_close_retroactively' using errcode='55000'; end if;
  update public.tax_parties set valid_to=p_valid_to,updated_at=now() where tenant_id=p_tenant_id and party_id=p_party_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values(p_tenant_id::text,v_actor,btrim(p_device_id),'tax_party_evidence_close',btrim(p_reason),'success');
end;
$function$


-- public.close_tax_rate_bracket_version(p_bracket_id uuid, p_end_date date, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.close_tax_rate_bracket_version(p_bracket_id uuid, p_end_date date, p_device_id text, p_app_version text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_old public.tax_rate_brackets%rowtype;
begin
  if not private.btp_is_super_admin() then raise exception 'canonical super_admin required' using errcode='42501'; end if;
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  select * into strict v_old from public.tax_rate_brackets where bracket_id=p_bracket_id for update;
  if v_old.end_date is not null then raise exception 'tax rate bracket already closed' using errcode='55000'; end if;
  if p_end_date is null or p_end_date<v_old.effective_date or p_end_date<current_date then raise exception 'tax rate bracket cannot be closed retroactively' using errcode='55000'; end if;
  update public.tax_rate_brackets set end_date=p_end_date where bracket_id=p_bracket_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values('GLOBAL',v_actor,btrim(p_device_id),'tax_rate_bracket:close:'||p_bracket_id::text,btrim(p_reason),'success');
end;
$function$


-- public.close_tax_rate_version(p_tax_rate_id uuid, p_end_date date, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.close_tax_rate_version(p_tax_rate_id uuid, p_end_date date, p_device_id text, p_app_version text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_old public.tax_rates%rowtype;
begin
  if not private.btp_is_super_admin() then raise exception 'canonical super_admin required' using errcode='42501'; end if;
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  select * into strict v_old from public.tax_rates where tax_rate_id=p_tax_rate_id for update;
  if v_old.end_date is not null then raise exception 'tax rule already closed' using errcode='55000'; end if;
  if p_end_date is null or p_end_date<v_old.effective_date or p_end_date<current_date then raise exception 'tax rule cannot be closed retroactively' using errcode='55000'; end if;
  update public.tax_rates set end_date=p_end_date where tax_rate_id=p_tax_rate_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values('GLOBAL',v_actor,btrim(p_device_id),'tax_rate:close:'||p_tax_rate_id::text,btrim(p_reason),'success');
end;
$function$


-- public.close_tenant_accounting_link(p_link_id uuid, p_valid_to date, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.close_tenant_accounting_link(p_link_id uuid, p_valid_to date, p_device_id text, p_app_version text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid();
  v_link private.tenant_accounting_links%rowtype;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  select * into strict v_link from private.tenant_accounting_links where link_id=p_link_id for update;
  perform accounting_private.require_member_role(v_link.accounting_tenant_id,v_actor,array['owner','admin']);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  if v_link.valid_to is not null then raise exception 'tenant_accounting_link_already_closed' using errcode='55000'; end if;
  if p_valid_to is null or p_valid_to<v_link.valid_from or p_valid_to<current_date then raise exception 'tenant_accounting_link_cannot_close_retroactively' using errcode='55000'; end if;
  update private.tenant_accounting_links set valid_to=p_valid_to where link_id=p_link_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values(v_link.accounting_tenant_id::text,v_actor,btrim(p_device_id),'tenant_accounting_link:close:'||p_link_id::text,btrim(p_reason),'success');
end;
$function$


-- public.close_vat_period(p_tenant_id uuid, p_period_start date, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.close_vat_period(p_tenant_id uuid, p_period_start date, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid(); v_period_end date; v_prev public.vat_period_settlements%rowtype; v_existing uuid;
  v_output bigint:=0; v_returns bigint:=0; v_input bigint:=0; v_carry bigint:=0; v_offset bigint:=0; v_reclass bigint:=0; v_payable bigint:=0; v_carry_out bigint:=0;
  v_lines jsonb:='[]'::jsonb; v_journal uuid; v_settlement uuid; v_ref text; v_fingerprint jsonb;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  if p_period_start is null or p_period_start<>date_trunc('month',p_period_start)::date then raise exception 'vat_period_start_must_be_first_day_of_month' using errcode='22023'; end if;
  v_period_end:=(date_trunc('month',p_period_start)+interval '1 month - 1 day')::date;
  if v_period_end>=current_date then raise exception 'vat_period_must_be_completed_before_close' using errcode='23514'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':vat-close:'||p_period_start::text,7341));
  select settlement_id into v_existing from public.vat_period_settlements where tenant_id=p_tenant_id and period_start=p_period_start;
  if v_existing is not null then return v_existing; end if;

  select * into v_prev from public.vat_period_settlements where tenant_id=p_tenant_id order by period_end desc limit 1;
  if found then
    if p_period_start<>v_prev.period_end+1 then raise exception 'vat_periods_must_be_closed_contiguously' using errcode='23514'; end if;
    v_carry:=v_prev.carry_out;
  else
    if exists(select 1 from public.tax_documents d where d.tenant_id=p_tenant_id and d.document_type like 'VAT_%' and d.business_date<p_period_start) then
      raise exception 'earlier_vat_period_must_be_settled_first' using errcode='23514';
    end if;
  end if;

  if exists(select 1 from public.tax_documents d where d.tenant_id=p_tenant_id and d.document_type='VAT_CANCELLATION' and d.business_date between p_period_start and v_period_end) then
    raise exception 'vat_cancellation_period_requires_explicit_correction_semantics' using errcode='23514';
  end if;

  select coalesce(sum(d.tax_amount),0)::bigint into v_output from public.tax_documents d
   where d.tenant_id=p_tenant_id and d.document_type in ('VAT_OUTPUT','VAT_REPLACEMENT')
     and d.business_date between p_period_start and v_period_end
     and d.status in ('VALIDATED','SUBMITTED','ACCEPTED','REPORTED');
  select coalesce(sum(d.tax_amount),0)::bigint into v_returns from public.tax_documents d
   where d.tenant_id=p_tenant_id and d.document_type='VAT_RETURN'
     and d.business_date between p_period_start and v_period_end
     and d.status in ('VALIDATED','SUBMITTED','ACCEPTED','REPORTED');
  select coalesce(sum(d.tax_amount),0)::bigint into v_input from public.tax_documents d
   where d.tenant_id=p_tenant_id and d.document_type='VAT_INPUT'
     and d.business_date between p_period_start and v_period_end
     and d.status in ('VALIDATED','ACCEPTED','REPORTED') and d.invoice_status='VALID' and d.creditable_input_vat and d.journal_id is not null;

  v_reclass:=greatest(v_returns-v_output,0);
  v_offset:=least(greatest(v_output-v_returns,0),v_input+v_carry);
  v_payable:=greatest(v_output-v_returns,0)-v_offset;
  v_carry_out:=v_input+v_carry+v_reclass-v_offset;
  v_ref:='VAT_CLOSE:'||to_char(p_period_start,'YYYY-MM');

  if v_offset>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_code','2-2010','debit',v_offset,'credit',0,'memo','Kompensasi PPN Masukan masa '||to_char(p_period_start,'YYYY-MM')));
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_code','1-1090','debit',0,'credit',v_offset,'memo','Pemakaian kredit PPN Masukan masa '||to_char(p_period_start,'YYYY-MM')));
  end if;
  if v_reclass>0 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_code','1-1090','debit',v_reclass,'credit',0,'memo','Kredit PPN dari retur melebihi PPN Keluaran'));
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object('account_code','2-2010','debit',0,'credit',v_reclass,'memo','Reklasifikasi saldo debit PPN Keluaran'));
  end if;
  if jsonb_array_length(v_lines)>0 then
    v_journal:=accounting_private.post_journal(p_tenant_id,'auto:'||v_ref,v_ref,v_period_end,'TUTUP_PPN_MASA','manual',v_lines,p_device_id,p_app_version);
    v_fingerprint:=jsonb_build_object('transaction_type','TUTUP_PPN_MASA','period_start',p_period_start,'period_end',v_period_end,'actor_user_id',v_actor,'device_id',btrim(p_device_id),'app_version',btrim(p_app_version),'reason',btrim(p_reason));
    insert into public.accounting_transaction_evidence(tenant_id,transaction_ref,transaction_type,business_date,request_fingerprint,facts_snapshot,tax_snapshot,journal_id,actor_user_id,device_id,app_version,reason)
    values(p_tenant_id,v_ref,'TUTUP_PPN_MASA',v_period_end,v_fingerprint,jsonb_build_object('period_start',p_period_start,'period_end',v_period_end),jsonb_build_object('output_vat_charged',v_output,'output_vat_reductions',v_returns,'input_vat_current',v_input,'carry_in',v_carry,'offset_used',v_offset,'return_credit_reclass',v_reclass,'net_payable',v_payable,'carry_out',v_carry_out),v_journal,v_actor,btrim(p_device_id),btrim(p_app_version),btrim(p_reason));
  end if;

  insert into public.vat_period_settlements(tenant_id,period_start,period_end,output_vat_charged,output_vat_reductions,input_vat_current,carry_in,offset_used,return_credit_reclass,net_payable,carry_out,settlement_journal_id,actor_user_id,device_id,app_version,reason)
  values(p_tenant_id,p_period_start,v_period_end,v_output,v_returns,v_input,v_carry,v_offset,v_reclass,v_payable,v_carry_out,v_journal,v_actor,btrim(p_device_id),btrim(p_app_version),btrim(p_reason)) returning settlement_id into v_settlement;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action) values(p_tenant_id::text,v_actor,btrim(p_device_id),'vat_period_close:'||to_char(p_period_start,'YYYY-MM'),btrim(p_reason),'success');
  return v_settlement;
end; $function$


-- public.create_auto_journal(p_tenant_id uuid, p_transaction_type text, p_transaction_ref text, p_business_date date, p_facts jsonb, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.create_auto_journal(p_tenant_id uuid, p_transaction_type text, p_transaction_ref text, p_business_date date, p_facts jsonb, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid(); v_member_role text; v_type text:=upper(btrim(coalesce(p_transaction_type,'')));
  v_fingerprint jsonb; v_existing public.accounting_transaction_evidence%rowtype; v_build jsonb; v_lines jsonb;
  v_source text; v_payment text; v_journal uuid; v_item jsonb; v_counterparty uuid; v_tax_doc uuid; v_original_tax public.tax_documents%rowtype;
  v_input_doc uuid; v_withholding bigint; v_tax_code text; v_required_bad int;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  v_member_role:=accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant','cashier']);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  if p_business_date is null or p_transaction_ref is null or length(btrim(p_transaction_ref))=0 then raise exception 'transaction_identity_required' using errcode='22023'; end if;
  if v_type not in ('JUAL_TUNAI','JUAL_QRIS','JUAL_TRANSFER','JUAL_KREDIT','BELI_KREDIT','BEBAN_VENDOR_KREDIT','BAYAR_VENDOR','TERIMA_PIUTANG','TERIMA_PIUTANG_PPH23','PPH23_15_ACCRUAL','BAYAR_PPH23_15','GAJI_BULANAN','BAYAR_GAJI','SETOR_PAJAK','SETOR_MODAL_OWNER','BELI_ASET_TUNAI','PENYUSUTAN_BULANAN','PRIVE_OWNER','ATUR_CADANGAN_PIUTANG','RETUR_PENJUALAN','STOCK_OPNAME') then raise exception 'unsupported_transaction_template' using errcode='22023'; end if;
  if v_type in ('RETUR_PENJUALAN','STOCK_OPNAME','PPH23_15_ACCRUAL','BAYAR_PPH23_15','GAJI_BULANAN','BAYAR_GAJI','SETOR_PAJAK','BELI_ASET_TUNAI','PENYUSUTAN_BULANAN','PRIVE_OWNER','ATUR_CADANGAN_PIUTANG') and v_member_role='cashier' then raise exception 'sensitive_transaction_requires_accounting_supervisor' using errcode='42501'; end if;
  if v_type in ('PRIVE_OWNER','SETOR_MODAL_OWNER') and v_member_role<>'owner' then raise exception 'owner_capital_or_draw_requires_owner_role' using errcode='42501'; end if;
  if jsonb_typeof(p_facts)='object'
     and exists (
       select 1 from jsonb_object_keys(p_facts) as k(key)
       where lower(k.key) in ('account_code','debit','cogs','tax_amount')
     ) then
    raise exception 'economic_fact_injection_blocked' using errcode='42501';
  end if;
  perform private.assert_no_accounting_fields(p_facts);
  select count(*) into v_required_bad from (values
    ('1-1010','Aset Lancar','debit'),('1-1020','Aset Lancar','debit'),('1-1030','Aset Lancar','debit'),('1-1040','Aset Lancar','debit'),('1-1050','Aset Lancar','debit'),('1-1090','Aset Lancar','debit'),('2-2010','Kewajiban','credit'),('2-2020','Kewajiban','credit'),('2-2050','Kewajiban','credit'),('2-2060','Kewajiban','credit'),('4-4010','Pendapatan','credit'),('4-4030','Pendapatan','debit'),('4-4050','Pendapatan','credit'),('4-4060','Pendapatan','credit'),('5-5010','HPP','debit'),('6-6080','Beban','debit')
  ) x(code,typ,bal) where not exists(select 1 from public.accounting_coa c where c.account_code=x.code and c.account_type=x.typ and c.normal_balance=x.bal);
  if v_required_bad<>0 then raise exception 'canonical COA mapping missing or semantically invalid' using errcode='23514'; end if;
  v_fingerprint:=jsonb_build_object('transaction_type',v_type,'transaction_ref',btrim(p_transaction_ref),'business_date',p_business_date::text,'facts',p_facts,'actor_user_id',v_actor::text,'device_id',btrim(p_device_id),'app_version',btrim(p_app_version),'reason',btrim(p_reason));
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||btrim(p_transaction_ref),7331));
  select j.journal_id into v_journal
  from public.accounting_journals j
  where j.tenant_id=p_tenant_id and j.transaction_ref=btrim(p_transaction_ref);
  if found then return v_journal; end if;

  select * into v_existing from public.accounting_transaction_evidence
  where tenant_id=p_tenant_id and transaction_ref=btrim(p_transaction_ref);
  if found then
    if v_existing.request_fingerprint=v_fingerprint then return v_existing.journal_id; end if;
    raise exception 'transaction_idempotency_conflict' using errcode='23505';
  end if;

  perform accounting_private.require_open_period(p_tenant_id,p_business_date);
  case v_type
    when 'JUAL_TUNAI' then v_payment:='1-1010'; v_source:='pos_sale'; v_build:=private.build_sale_lines(p_tenant_id,p_transaction_ref,p_business_date,p_facts,v_payment,v_actor,p_device_id,p_reason);
    when 'JUAL_QRIS' then v_payment:='1-1020'; v_source:='pos_sale'; v_build:=private.build_sale_lines(p_tenant_id,p_transaction_ref,p_business_date,p_facts,v_payment,v_actor,p_device_id,p_reason);
    when 'JUAL_TRANSFER' then v_payment:='1-1030'; v_source:='pos_sale'; v_build:=private.build_sale_lines(p_tenant_id,p_transaction_ref,p_business_date,p_facts,v_payment,v_actor,p_device_id,p_reason);
    when 'JUAL_KREDIT' then if nullif(btrim(coalesce(p_facts->>'customer_id','')),'') is null then raise exception 'customer_required_for_credit_sale' using errcode='22023'; end if; v_payment:='1-1050'; v_source:='pos_sale'; v_build:=private.build_sale_lines(p_tenant_id,p_transaction_ref,p_business_date,p_facts,v_payment,v_actor,p_device_id,p_reason);
    when 'BELI_KREDIT' then if nullif(btrim(coalesce(p_facts->>'supplier_id','')),'') is null then raise exception 'supplier_required_for_credit_purchase' using errcode='22023'; end if; v_source:='purchase_receipt'; v_build:=private.build_purchase_lines(p_tenant_id,p_transaction_ref,p_business_date,p_facts,v_actor,p_device_id,p_reason);
    when 'BEBAN_VENDOR_KREDIT' then if nullif(btrim(coalesce(p_facts->>'supplier_id','')),'') is null then raise exception 'supplier_required_for_vendor_expense' using errcode='22023'; end if; v_source:='purchase_receipt'; v_build:=private.build_vendor_expense_accrual_lines(p_tenant_id,p_transaction_ref,p_business_date,p_facts,v_actor,p_device_id,p_reason);
    when 'BAYAR_VENDOR' then v_source:='supplier_payment'; v_build:=private.build_supplier_payment_lines(p_tenant_id,p_business_date,p_facts);
    when 'TERIMA_PIUTANG' then v_source:='ar_receipt'; v_build:=private.build_customer_receipt_lines(p_tenant_id,p_business_date,p_facts);
    when 'TERIMA_PIUTANG_PPH23' then v_source:='ar_receipt'; v_build:=private.build_customer_withholding_receipt_lines(p_tenant_id,p_business_date,p_facts);
    when 'PPH23_15_ACCRUAL' then v_source:='manual'; v_build:=private.build_extended_withholding_source_lines(p_tenant_id,p_transaction_ref,p_business_date,p_facts,v_actor,p_device_id,p_reason);
    when 'BAYAR_PPH23_15' then v_source:='supplier_payment'; v_build:=private.build_extended_withholding_payment_lines(p_tenant_id,p_business_date,p_facts);
    when 'GAJI_BULANAN' then v_source:='payroll_accrual'; v_build:=private.build_payroll_lines(p_tenant_id,p_business_date,p_facts,v_actor,p_device_id,p_reason);
    when 'BAYAR_GAJI' then v_source:='payroll_payment'; v_build:=private.build_salary_payment_lines(p_tenant_id,p_business_date,p_facts);
    when 'SETOR_PAJAK' then v_source:='manual'; v_build:=private.build_tax_remittance_lines(p_tenant_id,p_business_date,p_facts);
    when 'SETOR_MODAL_OWNER' then v_source:='manual'; v_build:=private.build_owner_capital_lines(p_tenant_id,p_business_date,p_facts);
    when 'BELI_ASET_TUNAI' then v_source:='fixed_asset_acquisition'; v_build:=private.build_fixed_asset_acquisition_lines(p_tenant_id,p_business_date,p_facts);
    when 'PENYUSUTAN_BULANAN' then v_source:='fixed_asset_depreciation'; v_build:=private.build_depreciation_lines(p_tenant_id,p_business_date,p_facts);
    when 'PRIVE_OWNER' then v_source:='manual'; v_build:=private.build_owner_draw_lines(p_tenant_id,p_business_date,p_facts);
    when 'ATUR_CADANGAN_PIUTANG' then v_source:='manual'; v_build:=private.build_bad_debt_allowance_lines(p_tenant_id,p_business_date,p_facts);
    when 'RETUR_PENJUALAN' then v_source:='sale_return'; v_build:=private.build_sale_return_lines(p_tenant_id,p_transaction_ref,p_business_date,p_facts,v_actor,p_device_id,p_reason);
    when 'STOCK_OPNAME' then v_source:='manual'; v_build:=private.build_stock_opname_lines(p_tenant_id,p_transaction_ref,p_facts,v_actor,p_device_id,p_reason);
  end case;
  v_lines:=v_build->'journal_lines'; if jsonb_typeof(v_lines)<>'array' or jsonb_array_length(v_lines)<2 then raise exception 'auto_journal_builder_failed' using errcode='23514'; end if;
  v_journal:=accounting_private.post_journal(p_tenant_id,'auto:'||btrim(p_transaction_ref),btrim(p_transaction_ref),p_business_date,v_type,v_source,v_lines,p_device_id,p_app_version);
  insert into public.accounting_transaction_evidence(tenant_id,transaction_ref,transaction_type,business_date,request_fingerprint,facts_snapshot,tax_snapshot,journal_id,actor_user_id,device_id,app_version,reason)
  values(p_tenant_id,btrim(p_transaction_ref),v_type,p_business_date,v_fingerprint,p_facts,coalesce(v_build->'tax_snapshot','{}'::jsonb),v_journal,v_actor,btrim(p_device_id),btrim(p_app_version),btrim(p_reason));
  if v_type in ('JUAL_TUNAI','JUAL_QRIS','JUAL_TRANSFER','JUAL_KREDIT') then
    for v_item in select value from jsonb_array_elements(v_build->'sale_lines') loop
      insert into public.sale_line_evidence(tenant_id,transaction_ref,line_key,product_id,service_profile_id,line_kind,item_code,item_name,quantity,unit_price,list_amount,discount_amount,revenue_account,dpp,vat_amount,gross_amount,original_cogs,taxable,tax_object_code,tax_snapshot)
      values(p_tenant_id,btrim(p_transaction_ref),v_item->>'line_key',nullif(v_item->>'product_id','')::uuid,nullif(v_item->>'service_profile_id','')::uuid,v_item->>'line_kind',v_item->>'item_code',v_item->>'item_name',(v_item->>'quantity')::bigint,(v_item->>'unit_price')::bigint,(v_item->>'list_amount')::bigint,(v_item->>'discount_amount')::bigint,v_item->>'revenue_account',(v_item->>'dpp')::bigint,(v_item->>'vat_amount')::bigint,(v_item->>'gross_amount')::bigint,(v_item->>'original_cogs')::bigint,(v_item->>'taxable')::boolean,v_item->>'tax_object_code',coalesce(v_item->'tax_snapshot','{}'::jsonb));
    end loop;
    if coalesce((v_build->>'tax_document_required')::boolean,false) then
      if p_facts ? 'customer_tax_party_id' and nullif(btrim(p_facts->>'customer_tax_party_id'),'') is not null then begin v_counterparty:=(p_facts->>'customer_tax_party_id')::uuid; exception when others then raise exception 'invalid_customer_tax_party_id' using errcode='22023'; end; if not exists(select 1 from public.tax_parties tp where tp.tenant_id=p_tenant_id and tp.party_id=v_counterparty and tp.party_kind='CUSTOMER' and tp.valid_from<=p_business_date and (tp.valid_to is null or tp.valid_to>=p_business_date)) then raise exception 'customer_tax_party_evidence_invalid' using errcode='23514'; end if; end if;
      v_tax_doc:=private.create_tax_document_internal(p_tenant_id,'VAT_OUTPUT',p_transaction_ref,p_business_date,v_counterparty,coalesce(v_build->'tax_snapshot'->>'facility_context','NORMAL'),v_build->'tax_snapshot',(v_build->>'taxable_dpp')::bigint,(v_build->>'vat_amount')::bigint,(v_build->>'taxable_gross')::bigint,v_journal,'VALID',false,null,v_actor,p_device_id,p_reason);
    end if;
  elsif v_type in ('BELI_KREDIT','BEBAN_VENDOR_KREDIT') then
    if nullif(v_build->>'input_tax_document_id','') is not null then v_input_doc:=(v_build->>'input_tax_document_id')::uuid; update public.tax_documents set journal_id=v_journal,updated_at=now() where tax_document_id=v_input_doc and tenant_id=p_tenant_id and journal_id is null; if not found then raise exception 'input_tax_document_journal_link_failed' using errcode='23514'; end if; insert into public.tax_document_events(tax_document_id,tenant_id,event_type,details,actor_user_id,device_id,reason) values(v_input_doc,p_tenant_id,'JOURNAL_LINKED',jsonb_build_object('journal_id',v_journal),v_actor,btrim(p_device_id),btrim(p_reason)); end if;
  elsif v_type in ('BAYAR_VENDOR','BAYAR_PPH23_15') then
    v_withholding:=coalesce((v_build->>'withholding_amount')::bigint,0); if v_withholding>0 then v_tax_code:=v_build->>'tax_code'; v_tax_doc:=private.create_tax_document_internal(p_tenant_id,case when v_tax_code='PPH23' then 'PPH23_UNIFICATION' else 'PPH_FINAL' end,p_transaction_ref,p_business_date,(v_build->>'vendor_party_id')::uuid,null,v_build->'tax_snapshot',(v_build->>'withholding_base')::bigint,v_withholding,(v_build->>'withholding_base')::bigint,v_journal,'VALID',false,null,v_actor,p_device_id,p_reason); end if;
  elsif v_type='RETUR_PENJUALAN' then
    for v_item in select value from jsonb_array_elements(v_build->'return_lines') loop insert into public.sale_return_line_evidence(tenant_id,return_transaction_ref,original_transaction_ref,line_key,quantity,dpp_reversed,vat_reversed,cogs_restored) values(p_tenant_id,btrim(p_transaction_ref),v_item->>'original_transaction_ref',v_item->>'line_key',(v_item->>'quantity')::bigint,(v_item->>'dpp_reversed')::bigint,(v_item->>'vat_reversed')::bigint,(v_item->>'cogs_restored')::bigint); end loop;
    select * into v_original_tax from public.tax_documents where tenant_id=p_tenant_id and document_type='VAT_OUTPUT' and transaction_ref=v_build->>'original_transaction_ref'; if found then v_tax_doc:=private.create_tax_document_internal(p_tenant_id,'VAT_RETURN',p_transaction_ref,p_business_date,v_original_tax.counterparty_id,v_original_tax.facility_context,v_original_tax.tax_rate_snapshot,(v_build->>'dpp')::bigint,(v_build->>'vat_amount')::bigint,(v_build->>'gross_amount')::bigint,v_journal,'VALID',false,v_original_tax.tax_document_id,v_actor,p_device_id,p_reason); elsif (v_build->>'vat_amount')::bigint>0 then raise exception 'taxable_return_requires_original_tax_document' using errcode='23514'; end if;
  end if;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action) values(p_tenant_id::text,v_actor,btrim(p_device_id),'auto_journal:'||lower(v_type),btrim(p_reason),'success');
  return v_journal;
end;
$function$


-- public.create_employee_tax_profile(p_tenant_id uuid, p_employee_party_id uuid, p_marital_status text, p_dependents integer, p_tax_method text, p_valid_from date, p_valid_to date, p_legal_basis text, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.create_employee_tax_profile(p_tenant_id uuid, p_employee_party_id uuid, p_marital_status text, p_dependents integer, p_tax_method text, p_valid_from date, p_valid_to date, p_legal_basis text, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid();
  v_id uuid;
  v_method text:=upper(btrim(coalesce(p_tax_method,'')));
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_employee_party_id is null or p_valid_from is null then
    raise exception 'employee_profile_identity_and_valid_from_required' using errcode='22023';
  end if;
  if v_method not in ('EMPLOYEE_BORNE','GROSS_UP') then
    raise exception 'invalid_pph21_tax_method' using errcode='22023';
  end if;
  if p_legal_basis is null or length(btrim(p_legal_basis))<3 then
    raise exception 'employee_tax_profile_legal_basis_required' using errcode='22023';
  end if;
  if p_reason is null or length(btrim(p_reason))<3 then
    raise exception 'audit_reason_required' using errcode='22023';
  end if;

  insert into public.employee_tax_profiles(
    tenant_id,employee_party_id,employment_type,marital_status,dependents,
    ptkp_status,ptkp_amount,ter_category,tax_method,valid_from,valid_to,legal_basis,
    actor_user_id,device_id,reason
  ) values(
    p_tenant_id,p_employee_party_id,'PERMANENT',upper(btrim(p_marital_status)),p_dependents,
    private.pph21_ptkp_status(p_marital_status,p_dependents),
    private.pph21_ptkp_amount(p_marital_status,p_dependents),
    private.resolve_ter_category(p_marital_status,p_dependents),
    v_method,p_valid_from,p_valid_to,btrim(p_legal_basis),
    v_actor,btrim(p_device_id),btrim(p_reason)
  ) returning profile_id into v_id;

  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values(p_tenant_id::text,v_actor,btrim(p_device_id),'employee_tax_profile:create:'||v_id::text,btrim(p_reason),'success');
  return v_id;
end;
$function$

