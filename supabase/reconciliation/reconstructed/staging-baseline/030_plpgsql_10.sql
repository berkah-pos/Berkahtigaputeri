-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source. PL/pgSQL bodies are installed before SQL-language wrappers.

-- public.create_self_tax_party_for_config_tenant(p_config_tenant_id text, p_display_name text, p_npwp text, p_nik text, p_nitku text, p_is_pkp boolean, p_tax_regime text, p_legal_basis text, p_taxpayer_type text, p_valid_from date, p_valid_to date, p_certificate_status text, p_turnover_eligibility boolean, p_tax_object text, p_metadata jsonb, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.create_self_tax_party_for_config_tenant(p_config_tenant_id text, p_display_name text, p_npwp text, p_nik text, p_nitku text, p_is_pkp boolean, p_tax_regime text, p_legal_basis text, p_taxpayer_type text, p_valid_from date, p_valid_to date, p_certificate_status text, p_turnover_eligibility boolean, p_tax_object text, p_metadata jsonb, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_accounting_tenant uuid;
begin
  if p_config_tenant_id is null or length(btrim(p_config_tenant_id))=0 then
    raise exception 'config_tenant_id_required' using errcode='22023';
  end if;
  if p_valid_from is null then
    raise exception 'valid_from_required' using errcode='22023';
  end if;

  v_accounting_tenant := public.resolve_accounting_tenant(
    btrim(p_config_tenant_id),
    p_valid_from,
    p_device_id,
    p_app_version
  );

  return public.create_tax_party_evidence(
    v_accounting_tenant,
    'SELF',
    p_display_name,
    p_npwp,
    p_nik,
    p_nitku,
    p_is_pkp,
    p_tax_regime,
    p_legal_basis,
    p_taxpayer_type,
    p_valid_from,
    p_valid_to,
    p_certificate_status,
    p_turnover_eligibility,
    p_tax_object,
    p_metadata,
    p_device_id,
    p_app_version,
    p_reason
  );
end;
$function$


-- public.create_service_tax_profile(p_tenant_id uuid, p_service_code text, p_name_id text, p_unit_price bigint, p_vat_exempt boolean, p_vat_object_code text, p_valid_from date, p_valid_to date, p_legal_basis text, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.create_service_tax_profile(p_tenant_id uuid, p_service_code text, p_name_id text, p_unit_price bigint, p_vat_exempt boolean, p_vat_object_code text, p_valid_from date, p_valid_to date, p_legal_basis text, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_service_code is null or length(btrim(p_service_code))<1 or p_name_id is null or length(btrim(p_name_id))<1 then raise exception 'service_identity_required' using errcode='22023'; end if;
  if p_unit_price is null or p_unit_price<=0 then raise exception 'service_unit_price_must_be_positive_integer_rupiah' using errcode='22023'; end if;
  if p_vat_object_code not in ('NON_LUXURY','LUXURY_CONSUMER') then raise exception 'invalid_vat_object_code' using errcode='22023'; end if;
  if p_valid_from is null or (p_valid_to is not null and p_valid_to<p_valid_from) then raise exception 'invalid_service_tax_profile_period' using errcode='22023'; end if;
  if p_legal_basis is null or length(btrim(p_legal_basis))<3 or p_reason is null or length(btrim(p_reason))<3 then raise exception 'service_tax_evidence_required' using errcode='22023'; end if;
  insert into public.service_tax_profiles(tenant_id,service_code,name_id,unit_price,vat_exempt,vat_object_code,valid_from,valid_to,legal_basis,actor_user_id,device_id,reason)
  values(p_tenant_id,upper(btrim(p_service_code)),btrim(p_name_id),p_unit_price,coalesce(p_vat_exempt,false),p_vat_object_code,p_valid_from,p_valid_to,btrim(p_legal_basis),v_actor,btrim(p_device_id),btrim(p_reason))
  returning service_profile_id into v_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values(p_tenant_id::text,v_actor,btrim(p_device_id),'service_tax_profile:create:'||v_id::text,btrim(p_reason),'success');
  return v_id;
end;
$function$


-- public.create_service_tax_profile_v2(p_tenant_id uuid, p_service_code text, p_name_id text, p_unit_price bigint, p_vat_exempt boolean, p_vat_object_code text, p_pph23_object_code text, p_valid_from date, p_valid_to date, p_legal_basis text, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.create_service_tax_profile_v2(p_tenant_id uuid, p_service_code text, p_name_id text, p_unit_price bigint, p_vat_exempt boolean, p_vat_object_code text, p_pph23_object_code text, p_valid_from date, p_valid_to date, p_legal_basis text, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_id uuid; v_pph text:=upper(btrim(coalesce(p_pph23_object_code,'NONE')));
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_service_code is null or length(btrim(p_service_code))<1 or p_name_id is null or length(btrim(p_name_id))<1 then raise exception 'service_identity_required' using errcode='22023'; end if;
  if p_unit_price is null or p_unit_price<=0 then raise exception 'service_unit_price_must_be_positive_integer_rupiah' using errcode='22023'; end if;
  if p_vat_object_code not in ('NON_LUXURY','LUXURY_CONSUMER') or v_pph not in ('NONE','SERVICE') then raise exception 'invalid_service_tax_object' using errcode='22023'; end if;
  if p_valid_from is null or (p_valid_to is not null and p_valid_to<p_valid_from) then raise exception 'invalid_service_tax_profile_period' using errcode='22023'; end if;
  if p_legal_basis is null or length(btrim(p_legal_basis))<3 or p_reason is null or length(btrim(p_reason))<3 then raise exception 'service_tax_evidence_required' using errcode='22023'; end if;
  insert into public.service_tax_profiles(tenant_id,service_code,name_id,unit_price,vat_exempt,vat_object_code,pph23_object_code,valid_from,valid_to,legal_basis,actor_user_id,device_id,reason)
  values(p_tenant_id,upper(btrim(p_service_code)),btrim(p_name_id),p_unit_price,coalesce(p_vat_exempt,false),p_vat_object_code,v_pph,p_valid_from,p_valid_to,btrim(p_legal_basis),v_actor,btrim(p_device_id),btrim(p_reason)) returning service_profile_id into v_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action) values(p_tenant_id::text,v_actor,btrim(p_device_id),'service_tax_profile_v2:create:'||v_id::text,btrim(p_reason),'success');
  return v_id;
end; $function$


-- public.create_service_tax_profile_v3(p_tenant_id uuid, p_service_code text, p_name_id text, p_unit_price bigint, p_vat_exempt boolean, p_vat_object_code text, p_pph23_object_code text, p_umkm_final_eligible boolean, p_valid_from date, p_valid_to date, p_legal_basis text, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.create_service_tax_profile_v3(p_tenant_id uuid, p_service_code text, p_name_id text, p_unit_price bigint, p_vat_exempt boolean, p_vat_object_code text, p_pph23_object_code text, p_umkm_final_eligible boolean, p_valid_from date, p_valid_to date, p_legal_basis text, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_id uuid; v_pph text:=upper(btrim(coalesce(p_pph23_object_code,'NONE')));
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_service_code is null or length(btrim(p_service_code))<1 or p_name_id is null or length(btrim(p_name_id))<1 then raise exception 'service_identity_required' using errcode='22023'; end if;
  if p_unit_price is null or p_unit_price<=0 then raise exception 'service_unit_price_must_be_positive_integer_rupiah' using errcode='22023'; end if;
  if p_vat_object_code not in ('NON_LUXURY','LUXURY_CONSUMER') or v_pph not in ('NONE','SERVICE') then raise exception 'invalid_service_tax_object' using errcode='22023'; end if;
  if p_valid_from is null or (p_valid_to is not null and p_valid_to<p_valid_from) then raise exception 'invalid_service_tax_profile_period' using errcode='22023'; end if;
  if p_legal_basis is null or length(btrim(p_legal_basis))<3 or p_reason is null or length(btrim(p_reason))<3 then raise exception 'service_tax_evidence_required' using errcode='22023'; end if;
  insert into public.service_tax_profiles(tenant_id,service_code,name_id,unit_price,vat_exempt,vat_object_code,pph23_object_code,umkm_final_eligible,valid_from,valid_to,legal_basis,actor_user_id,device_id,reason)
  values(p_tenant_id,upper(btrim(p_service_code)),btrim(p_name_id),p_unit_price,coalesce(p_vat_exempt,false),p_vat_object_code,v_pph,coalesce(p_umkm_final_eligible,false),p_valid_from,p_valid_to,btrim(p_legal_basis),v_actor,btrim(p_device_id),btrim(p_reason)) returning service_profile_id into v_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action) values(p_tenant_id::text,v_actor,btrim(p_device_id),'service_tax_profile_v3:create:'||v_id::text,btrim(p_reason),'success');
  return v_id;
end; $function$


-- public.create_tax_party_evidence(p_tenant_id uuid, p_party_kind text, p_display_name text, p_npwp text, p_nik text, p_nitku text, p_is_pkp boolean, p_tax_regime text, p_legal_basis text, p_taxpayer_type text, p_valid_from date, p_valid_to date, p_certificate_status text, p_turnover_eligibility boolean, p_tax_object text, p_metadata jsonb, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.create_tax_party_evidence(p_tenant_id uuid, p_party_kind text, p_display_name text, p_npwp text, p_nik text, p_nitku text, p_is_pkp boolean, p_tax_regime text, p_legal_basis text, p_taxpayer_type text, p_valid_from date, p_valid_to date, p_certificate_status text, p_turnover_eligibility boolean, p_tax_object text, p_metadata jsonb, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_party_kind not in ('SELF','CUSTOMER','VENDOR','EMPLOYEE','SHAREHOLDER') or p_display_name is null or length(btrim(p_display_name))=0 then raise exception 'invalid_tax_party' using errcode='22023'; end if;
  if p_reason is null or length(btrim(p_reason))<3 or p_legal_basis is null or length(btrim(p_legal_basis))<3 then raise exception 'tax_party_evidence_required' using errcode='22023'; end if;
  if p_valid_from is null or (p_valid_to is not null and p_valid_to<p_valid_from) then raise exception 'invalid_tax_party_period' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'tax_party_metadata_must_be_object' using errcode='22023'; end if;
  insert into public.tax_parties(
    tenant_id,party_kind,display_name,npwp,nik,nitku,is_pkp,tax_regime,legal_basis,taxpayer_type,
    valid_from,valid_to,certificate_status,turnover_eligibility,tax_object,metadata,actor_user_id,device_id,reason
  ) values(
    p_tenant_id,p_party_kind,btrim(p_display_name),nullif(btrim(coalesce(p_npwp,'')),''),nullif(btrim(coalesce(p_nik,'')),''),nullif(btrim(coalesce(p_nitku,'')),''),
    coalesce(p_is_pkp,false),upper(btrim(p_tax_regime)),btrim(p_legal_basis),upper(btrim(p_taxpayer_type)),p_valid_from,p_valid_to,
    upper(btrim(p_certificate_status)),p_turnover_eligibility,nullif(upper(btrim(coalesce(p_tax_object,''))),''),p_metadata,v_actor,btrim(p_device_id),btrim(p_reason)
  ) returning party_id into v_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values(p_tenant_id::text,v_actor,btrim(p_device_id),'tax_party_evidence',btrim(p_reason),'success');
  return v_id;
end;
$function$


-- public.create_tax_party_evidence_v2(p_tenant_id uuid, p_party_kind text, p_display_name text, p_npwp text, p_nik text, p_nitku text, p_is_pkp boolean, p_tax_regime text, p_legal_basis text, p_taxpayer_type text, p_valid_from date, p_valid_to date, p_certificate_status text, p_turnover_eligibility boolean, p_tax_object text, p_is_withholding_agent boolean, p_metadata jsonb, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.create_tax_party_evidence_v2(p_tenant_id uuid, p_party_kind text, p_display_name text, p_npwp text, p_nik text, p_nitku text, p_is_pkp boolean, p_tax_regime text, p_legal_basis text, p_taxpayer_type text, p_valid_from date, p_valid_to date, p_certificate_status text, p_turnover_eligibility boolean, p_tax_object text, p_is_withholding_agent boolean, p_metadata jsonb, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']);
  if p_party_kind not in ('SELF','CUSTOMER','VENDOR','EMPLOYEE','SHAREHOLDER') or p_display_name is null or length(btrim(p_display_name))=0 then raise exception 'invalid_tax_party' using errcode='22023'; end if;
  if p_reason is null or length(btrim(p_reason))<3 or p_legal_basis is null or length(btrim(p_legal_basis))<3 then raise exception 'tax_party_evidence_required' using errcode='22023'; end if;
  if p_valid_from is null or (p_valid_to is not null and p_valid_to<p_valid_from) then raise exception 'invalid_tax_party_period' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'tax_party_metadata_must_be_object' using errcode='22023'; end if;
  if coalesce(p_is_withholding_agent,false) and p_party_kind<>'CUSTOMER' then raise exception 'withholding_agent_flag_only_valid_for_customer' using errcode='23514'; end if;
  insert into public.tax_parties(tenant_id,party_kind,display_name,npwp,nik,nitku,is_pkp,tax_regime,legal_basis,taxpayer_type,valid_from,valid_to,certificate_status,turnover_eligibility,tax_object,is_withholding_agent,metadata,actor_user_id,device_id,reason)
  values(p_tenant_id,p_party_kind,btrim(p_display_name),nullif(btrim(coalesce(p_npwp,'')),''),nullif(btrim(coalesce(p_nik,'')),''),nullif(btrim(coalesce(p_nitku,'')),''),coalesce(p_is_pkp,false),upper(btrim(p_tax_regime)),btrim(p_legal_basis),upper(btrim(p_taxpayer_type)),p_valid_from,p_valid_to,upper(btrim(p_certificate_status)),p_turnover_eligibility,nullif(upper(btrim(coalesce(p_tax_object,''))),''),coalesce(p_is_withholding_agent,false),p_metadata,v_actor,btrim(p_device_id),btrim(p_reason)) returning party_id into v_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action) values(p_tenant_id::text,v_actor,btrim(p_device_id),'tax_party_evidence_v2',btrim(p_reason),'success');
  return v_id;
end; $function$


-- public.create_tax_rate_bracket_version(p_category text, p_lower_bound bigint, p_upper_bound bigint, p_rate numeric, p_effective_date date, p_end_date date, p_legal_basis text, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.create_tax_rate_bracket_version(p_category text, p_lower_bound bigint, p_upper_bound bigint, p_rate numeric, p_effective_date date, p_end_date date, p_legal_basis text, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  if not private.btp_is_super_admin() then raise exception 'canonical super_admin required' using errcode='42501'; end if;
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  insert into public.tax_rate_brackets(tax_code,category,lower_bound,upper_bound,rate,effective_date,end_date,legal_basis,created_by)
  values('PPH21_TER',p_category,p_lower_bound,p_upper_bound,p_rate,p_effective_date,p_end_date,btrim(p_legal_basis),v_actor)
  returning bracket_id into v_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values('GLOBAL',v_actor,btrim(p_device_id),'tax_rate_bracket:create:'||v_id::text,btrim(p_reason),'success');
  return v_id;
end;
$function$


-- public.create_tax_rate_version(p_tax_code text, p_object_code text, p_category text, p_statutory_rate numeric, p_dpp_multiplier numeric, p_calculation_method text, p_effective_date date, p_end_date date, p_legal_basis text, p_metadata jsonb, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.create_tax_rate_version(p_tax_code text, p_object_code text, p_category text, p_statutory_rate numeric, p_dpp_multiplier numeric, p_calculation_method text, p_effective_date date, p_end_date date, p_legal_basis text, p_metadata jsonb, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  if not private.btp_is_super_admin() then raise exception 'canonical super_admin required' using errcode='42501'; end if;
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  if exists(select 1 from public.tax_rates r where r.tax_code=p_tax_code and r.object_code=p_object_code and r.category=coalesce(nullif(p_category,''),'DEFAULT') and r.effective_date<=p_effective_date and (r.end_date is null or r.end_date>=p_effective_date)) then
    raise exception 'close existing tax rule with end_date before inserting successor' using errcode='23514';
  end if;
  insert into public.tax_rates(tax_code,object_code,category,statutory_rate,dpp_multiplier,calculation_method,effective_date,end_date,legal_basis,metadata,created_by)
  values(p_tax_code,p_object_code,coalesce(nullif(p_category,''),'DEFAULT'),p_statutory_rate,p_dpp_multiplier,p_calculation_method,p_effective_date,p_end_date,btrim(p_legal_basis),coalesce(p_metadata,'{}'::jsonb),v_actor)
  returning tax_rate_id into v_id;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values('GLOBAL',v_actor,btrim(p_device_id),'tax_rate:create:'||v_id::text,btrim(p_reason),'success');
  return v_id;
end;
$function$


-- public.create_tenant_accounting_link(p_config_tenant_id text, p_accounting_tenant_id uuid, p_valid_from date, p_valid_to date, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.create_tenant_accounting_link(p_config_tenant_id text, p_accounting_tenant_id uuid, p_valid_from date, p_valid_to date, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid();
  v_link uuid;
  v_device_tenant text;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_accounting_tenant_id,v_actor,array['owner','admin']);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  if p_valid_from is null or (p_valid_to is not null and p_valid_to<p_valid_from) then raise exception 'invalid_link_period' using errcode='22023'; end if;

  select d.tenant_id into strict v_device_tenant
  from public.devices d
  where d.device_id=btrim(p_device_id) and d.user_id=v_actor;
  if v_device_tenant<>p_config_tenant_id then raise exception 'device_config_tenant_mismatch' using errcode='42501'; end if;
  if not exists(select 1 from public.tenants t where t.tenant_id=p_config_tenant_id and t.status='active' and not t.is_blocked) then
    raise exception 'config_tenant_not_active' using errcode='23514';
  end if;
  if not exists(select 1 from public.accounting_tenants t where t.tenant_id=p_accounting_tenant_id and t.status='active') then
    raise exception 'accounting_tenant_not_active' using errcode='23514';
  end if;

  insert into private.tenant_accounting_links(config_tenant_id,accounting_tenant_id,valid_from,valid_to,actor_user_id,device_id,reason)
  values(p_config_tenant_id,p_accounting_tenant_id,p_valid_from,p_valid_to,v_actor,btrim(p_device_id),btrim(p_reason))
  returning link_id into v_link;

  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values(p_accounting_tenant_id::text,v_actor,btrim(p_device_id),'tenant_accounting_link:create:'||v_link::text,btrim(p_reason),'success');
  return v_link;
end;
$function$


-- public.get_accounting_hard_gate(p_tenant_id uuid)
CREATE OR REPLACE FUNCTION public.get_accounting_hard_gate(p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_role text:=lower(coalesce(auth.jwt()->>'role',''));
begin
  if v_role<>'service_role' then perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant']); end if;
  return private.compute_accounting_hard_gate(p_tenant_id);
end;
$function$


-- public.get_compliance_readiness(p_tenant_id uuid, p_business_date date, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.get_compliance_readiness(p_tenant_id uuid, p_business_date date, p_device_id text, p_app_version text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid();
  v_gate jsonb;
  v_self_row_count bigint;
  v_self_count bigint;
  v_coretax_self_count bigint;
  v_template_count bigint;
  v_templates jsonb;
  v_blockers jsonb:='[]'::jsonb;
  v_accounting_ready boolean;
  v_sale_tax_ready boolean;
  v_coretax_ready boolean;
  v_pph21_payroll_ready boolean;
  v_pph21_coretax_ready boolean;
  v_vendor_withholding_source_ready boolean;
  v_extended_pph23_source_ready boolean;
  v_inbound_withholding_credit_ready boolean;
  v_owner_adjustment_intents_ready boolean;
  v_tax_remittance_ready boolean; v_vat_period_settlement_ready boolean;
  v_owner_turnover_tax_ready boolean;
  v_corporate_income_tax_ready boolean;
  v_full_compliance_ready boolean;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant','cashier']);
  if p_business_date is null then raise exception 'business_date_required' using errcode='22023'; end if;

  v_gate:=private.compute_accounting_hard_gate(p_tenant_id);
  v_accounting_ready:=coalesce((v_gate->>'all_zero')::boolean,false);

  select count(*)::bigint into v_self_row_count from public.tax_parties tp
  where tp.tenant_id=p_tenant_id and tp.party_kind='SELF' and tp.valid_from<=p_business_date and (tp.valid_to is null or tp.valid_to>=p_business_date);

  select count(*)::bigint into v_self_count from public.tax_parties tp
  where tp.tenant_id=p_tenant_id and tp.party_kind='SELF' and tp.valid_from<=p_business_date and (tp.valid_to is null or tp.valid_to>=p_business_date)
    and ((tp.is_pkp and tp.certificate_status='VALID') or (not tp.is_pkp and tp.certificate_status in ('VALID','NOT_REQUIRED')));

  select count(*)::bigint into v_coretax_self_count from public.tax_parties tp
  where tp.tenant_id=p_tenant_id and tp.party_kind='SELF' and tp.valid_from<=p_business_date and (tp.valid_to is null or tp.valid_to>=p_business_date) and tp.certificate_status='VALID';

  select count(*)::bigint,
         coalesce(jsonb_object_agg(template_code,jsonb_build_object(
           'verified',is_verified,'active',is_active,'has_xml',xml_template is not null,
           'has_sha256',template_sha256 is not null,'version',template_version,
           'official_source_url',official_source_url,'generator_status',coalesce(generator_spec->>'status','')
         )),'{}'::jsonb)
  into v_template_count,v_templates
  from public.coretax_template_registry
  where template_code in ('FAKTUR_KELUARAN','BPPU','BPMP')
    and is_verified and is_active and xml_template is not null
    and template_sha256 ~ '^[0-9a-f]{64}$'
    and coalesce(generator_spec->>'status','')<>'SOURCE_REGISTERED_NOT_PARSED';

  v_sale_tax_ready:=v_accounting_ready and v_self_count=1;

  v_pph21_payroll_ready:=
    to_regclass('public.employee_tax_profiles') is not null
    and to_regclass('public.payroll_tax_evidence') is not null
    and to_regprocedure('private.build_payroll_lines(uuid,date,jsonb,uuid,text,text)') is not null;
  v_pph21_coretax_ready:=
    to_regprocedure('private.build_pph21_coretax_document(uuid,text,date)') is not null;
  v_vendor_withholding_source_ready:=
    to_regprocedure('private.build_vendor_expense_accrual_lines(uuid,text,date,jsonb,uuid,text,text)') is not null;
  v_extended_pph23_source_ready:=
    to_regprocedure('private.build_extended_withholding_source_lines(uuid,text,date,jsonb,uuid,text,text)') is not null;
  v_inbound_withholding_credit_ready:=
    to_regprocedure('private.build_customer_withholding_receipt_lines(uuid,date,jsonb)') is not null;
  v_owner_adjustment_intents_ready:=
    to_regprocedure('private.build_owner_draw_lines(uuid,date,jsonb)') is not null
    and to_regprocedure('private.build_depreciation_lines(uuid,date,jsonb)') is not null
    and to_regprocedure('private.build_bad_debt_allowance_lines(uuid,date,jsonb)') is not null;
  v_tax_remittance_ready:=
    to_regprocedure('private.build_tax_remittance_lines(uuid,date,jsonb)') is not null;
  v_vat_period_settlement_ready:=
    to_regprocedure('public.close_vat_period(uuid,date,text,text,text)') is not null
    and to_regclass('public.vat_period_settlements') is not null;
  v_owner_turnover_tax_ready:=
    to_regprocedure('private.build_owner_turnover_tax_lines(uuid,date,jsonb)') is not null;
  v_corporate_income_tax_ready:=
    to_regprocedure('private.build_corporate_income_tax_close_lines(uuid,date,jsonb)') is not null
    and to_regprocedure('private.build_pph25_installment_lines(uuid,date,jsonb)') is not null;

  v_coretax_ready:=v_accounting_ready and v_coretax_self_count=1 and v_template_count=3 and v_pph21_coretax_ready;

  v_full_compliance_ready:=
    v_accounting_ready and v_sale_tax_ready and v_coretax_ready
    and v_pph21_payroll_ready and v_pph21_coretax_ready
    and v_vendor_withholding_source_ready and v_extended_pph23_source_ready
    and v_inbound_withholding_credit_ready and v_owner_adjustment_intents_ready
    and v_tax_remittance_ready and v_vat_period_settlement_ready and v_owner_turnover_tax_ready and v_corporate_income_tax_ready;

  if not v_accounting_ready then v_blockers:=v_blockers||jsonb_build_array('ACCOUNTING_HARD_GATE_NOT_ZERO'); end if;
  if v_self_count<>1 then v_blockers:=v_blockers||jsonb_build_array('EXACTLY_ONE_EFFECTIVE_SELF_TAX_PROFILE_REQUIRED'); end if;
  if v_coretax_self_count<>1 then v_blockers:=v_blockers||jsonb_build_array('EXACTLY_ONE_VALID_SELF_TAX_PROFILE_REQUIRED_FOR_CORETAX'); end if;
  if v_template_count<>3 then v_blockers:=v_blockers||jsonb_build_array('CORETAX_OFFICIAL_TEMPLATES_NOT_VERIFIED'); end if;
  if not v_pph21_payroll_ready then v_blockers:=v_blockers||jsonb_build_array('PPH21_PAYROLL_EVIDENCE_ENGINE_NOT_READY'); end if;
  if not v_pph21_coretax_ready then v_blockers:=v_blockers||jsonb_build_array('PPH21_CORETAX_DOCUMENT_FLOW_NOT_READY'); end if;
  if not v_vendor_withholding_source_ready then v_blockers:=v_blockers||jsonb_build_array('VENDOR_WITHHOLDING_SOURCE_ACCRUAL_NOT_READY'); end if;
  if not v_extended_pph23_source_ready then v_blockers:=v_blockers||jsonb_build_array('PPH23_15PCT_SOURCE_OBJECTS_NOT_READY'); end if;
  if not v_inbound_withholding_credit_ready then v_blockers:=v_blockers||jsonb_build_array('INBOUND_PPH23_TAX_CREDIT_NOT_READY'); end if;
  if not v_owner_adjustment_intents_ready then v_blockers:=v_blockers||jsonb_build_array('OWNER_ACCOUNTING_ADJUSTMENT_INTENTS_NOT_READY'); end if;
  if not v_tax_remittance_ready then v_blockers:=v_blockers||jsonb_build_array('TAX_REMITTANCE_EBILLING_JOURNAL_FLOW_NOT_READY'); end if;
  if not v_vat_period_settlement_ready then v_blockers:=v_blockers||jsonb_build_array('VAT_PERIOD_SETTLEMENT_NOT_READY'); end if;
  if not v_owner_turnover_tax_ready then v_blockers:=v_blockers||jsonb_build_array('OWNER_UMKM_FINAL_TURNOVER_TAX_ENGINE_NOT_READY'); end if;
  if not v_corporate_income_tax_ready then v_blockers:=v_blockers||jsonb_build_array('CORPORATE_PPH25_PPH29_FISCAL_ENGINE_NOT_READY'); end if;

  return jsonb_build_object(
    'business_date',p_business_date,
    'accounting_ready',v_accounting_ready,
    'sale_tax_ready',v_sale_tax_ready,
    'coretax_ready',v_coretax_ready,
    'full_compliance_ready',v_full_compliance_ready,
    'capabilities',jsonb_build_object(
      'pph21_payroll_engine_ready',v_pph21_payroll_ready,
      'pph21_coretax_document_flow_ready',v_pph21_coretax_ready,
      'vendor_withholding_source_ready',v_vendor_withholding_source_ready,
      'extended_pph23_source_ready',v_extended_pph23_source_ready,
      'inbound_withholding_credit_ready',v_inbound_withholding_credit_ready,
      'owner_adjustment_intents_ready',v_owner_adjustment_intents_ready,
      'tax_remittance_ready',v_tax_remittance_ready,
      'vat_period_settlement_ready',v_vat_period_settlement_ready,
      'owner_turnover_tax_ready',v_owner_turnover_tax_ready,
      'corporate_income_tax_ready',v_corporate_income_tax_ready
    ),
    'effective_self_tax_profile_row_count',v_self_row_count,
    'effective_self_tax_profile_count',v_self_count,
    'effective_coretax_self_tax_profile_count',v_coretax_self_count,
    'verified_active_coretax_template_count',v_template_count,
    'required_coretax_template_count',3,
    'coretax_templates',v_templates,
    'accounting_gate',v_gate,
    'blockers',v_blockers
  );
end;
$function$


-- public.get_config_tenant_compliance_readiness(p_config_tenant_id text, p_business_date date, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.get_config_tenant_compliance_readiness(p_config_tenant_id text, p_business_date date, p_device_id text, p_app_version text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_accounting_tenant uuid;
  v_readiness jsonb;
begin
  if p_config_tenant_id is null or length(btrim(p_config_tenant_id))=0 then
    raise exception 'config_tenant_id_required' using errcode='22023';
  end if;
  if p_business_date is null then
    raise exception 'business_date_required' using errcode='22023';
  end if;

  v_accounting_tenant := public.resolve_accounting_tenant(
    btrim(p_config_tenant_id),
    p_business_date,
    p_device_id,
    p_app_version
  );

  v_readiness := public.get_compliance_readiness(
    v_accounting_tenant,
    p_business_date,
    p_device_id,
    p_app_version
  );

  return jsonb_build_object(
    'config_tenant_id', btrim(p_config_tenant_id)
  ) || v_readiness;
end;
$function$

