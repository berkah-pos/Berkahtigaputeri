-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source. PL/pgSQL bodies are installed before SQL-language wrappers.

-- public.get_config_tenant_self_tax_profile_status(p_config_tenant_id text, p_business_date date, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.get_config_tenant_self_tax_profile_status(p_config_tenant_id text, p_business_date date, p_device_id text, p_app_version text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid();
  v_accounting_tenant uuid;
  v_row public.tax_parties%rowtype;
  v_count bigint;
  v_sale_usable boolean:=false;
  v_coretax_usable boolean:=false;
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
  perform accounting_private.require_member_role(
    v_accounting_tenant,
    v_actor,
    array['owner','admin','accountant','cashier']
  );

  select count(*)::bigint into v_count
  from public.tax_parties tp
  where tp.tenant_id=v_accounting_tenant
    and tp.party_kind='SELF'
    and tp.valid_from<=p_business_date
    and (tp.valid_to is null or tp.valid_to>=p_business_date);

  if v_count=0 then
    return jsonb_build_object(
      'config_tenant_id',btrim(p_config_tenant_id),
      'business_date',p_business_date,
      'effective_row_count',0,
      'exists',false,
      'sale_usable',false,
      'coretax_usable',false
    );
  end if;

  if v_count<>1 then
    raise exception 'self_tax_profile_period_ambiguity' using errcode='23514';
  end if;

  select * into strict v_row
  from public.tax_parties tp
  where tp.tenant_id=v_accounting_tenant
    and tp.party_kind='SELF'
    and tp.valid_from<=p_business_date
    and (tp.valid_to is null or tp.valid_to>=p_business_date);

  v_sale_usable :=
    (v_row.is_pkp and v_row.certificate_status='VALID')
    or (not v_row.is_pkp and v_row.certificate_status in ('VALID','NOT_REQUIRED'));
  v_coretax_usable := v_row.certificate_status='VALID';

  return jsonb_build_object(
    'config_tenant_id',btrim(p_config_tenant_id),
    'business_date',p_business_date,
    'effective_row_count',1,
    'exists',true,
    'sale_usable',v_sale_usable,
    'coretax_usable',v_coretax_usable,
    'is_pkp',v_row.is_pkp,
    'certificate_status',v_row.certificate_status,
    'taxpayer_type',v_row.taxpayer_type,
    'tax_regime',v_row.tax_regime,
    'legal_basis',v_row.legal_basis,
    'valid_from',v_row.valid_from,
    'valid_to',v_row.valid_to,
    'turnover_eligibility',v_row.turnover_eligibility,
    'tax_object',v_row.tax_object,
    'has_npwp',v_row.npwp is not null,
    'has_nik',v_row.nik is not null,
    'has_nitku',v_row.nitku is not null
  );
end;
$function$;
-- public.get_coretax_export_capability(p_tax_document_id uuid, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.get_coretax_export_capability(p_tax_document_id uuid, p_device_id text, p_app_version text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_doc public.tax_documents%ROWTYPE;
  v_gate jsonb;
  v_templates_verified boolean;
  v_snapshot_ready boolean;
  v_can_export boolean;
  v_expected_template text;
  v_blockers jsonb := '[]'::jsonb;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING errcode = '42501';
  END IF;

  SELECT d.* INTO STRICT v_doc
  FROM public.tax_documents AS d
  WHERE d.tax_document_id = p_tax_document_id;

  PERFORM accounting_private.require_bound_device(v_actor, p_device_id, p_app_version);
  PERFORM accounting_private.require_member_role(
    v_doc.tenant_id,
    v_actor,
    ARRAY['owner', 'admin', 'accountant']
  );

  v_gate := private.compute_accounting_hard_gate(v_doc.tenant_id);
  v_templates_verified := private.verify_coretax_template();
  v_snapshot_ready :=
    v_doc.tax_rate_snapshot IS NOT NULL
    AND jsonb_typeof(v_doc.tax_rate_snapshot) = 'object'
    AND v_doc.tax_rate_snapshot <> '{}'::jsonb
    AND v_doc.legal_rule_snapshot IS NOT NULL
    AND jsonb_typeof(v_doc.legal_rule_snapshot) = 'object'
    AND v_doc.legal_rule_snapshot <> '{}'::jsonb
    AND nullif(btrim(v_doc.legal_rule_snapshot ->> 'legal_basis'), '') IS NOT NULL;

  v_expected_template := CASE v_doc.document_type
    WHEN 'VAT_OUTPUT' THEN 'FAKTUR_KELUARAN'
    WHEN 'VAT_REPLACEMENT' THEN 'FAKTUR_KELUARAN'
    WHEN 'PPH23_UNIFICATION' THEN 'BPPU'
    WHEN 'PPH21_26' THEN 'BPMP'
    ELSE NULL
  END;

  v_can_export := private.can_export_coretax(v_doc.tenant_id, v_doc.tax_document_id);

  IF coalesce((v_gate ->> 'all_zero')::boolean, false) IS NOT TRUE THEN
    v_blockers := v_blockers || jsonb_build_array('ACCOUNTING_HARD_GATE_NOT_ZERO');
  END IF;
  IF NOT v_snapshot_ready THEN
    v_blockers := v_blockers || jsonb_build_array('TAX_SNAPSHOT_MISSING_OR_EMPTY');
  END IF;
  IF NOT v_templates_verified THEN
    v_blockers := v_blockers || jsonb_build_array('CORETAX_REQUIRED_TEMPLATES_NOT_VERIFIED');
  END IF;
  IF v_doc.status <> 'VALIDATED' THEN
    v_blockers := v_blockers || jsonb_build_array('TAX_DOCUMENT_NOT_VALIDATED');
  END IF;
  IF v_expected_template IS NULL THEN
    v_blockers := v_blockers || jsonb_build_array('UNSUPPORTED_TAX_DOCUMENT_TYPE');
  END IF;

  RETURN jsonb_build_object(
    'can_export_coretax', coalesce(v_can_export, false),
    'accounting_all_zero', coalesce((v_gate ->> 'all_zero')::boolean, false),
    'accounting_gate', v_gate,
    'snapshot_ready', coalesce(v_snapshot_ready, false),
    'required_templates_verified', coalesce(v_templates_verified, false),
    'expected_template_code', v_expected_template,
    'blockers', v_blockers
  );
EXCEPTION
  WHEN no_data_found THEN
    RAISE EXCEPTION 'tax_document_not_found' USING errcode = 'P0002';
END;
$function$;
-- public.get_coretax_status(p_tax_document_id uuid)
CREATE OR REPLACE FUNCTION public.get_coretax_status(p_tax_document_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_doc public.tax_documents%rowtype; v_out jsonb; v_pay jsonb;
begin
  select * into strict v_doc from public.tax_documents where tax_document_id=p_tax_document_id;
  perform accounting_private.require_member_role(v_doc.tenant_id,v_actor,array['owner','admin','accountant']);
  select coalesce(jsonb_agg(to_jsonb(o) order by o.created_at desc),'[]'::jsonb) into v_out from public.coretax_outbox o where o.tax_document_id=p_tax_document_id;
  select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc),'[]'::jsonb) into v_pay from public.tax_payment_refs p where p.tax_document_id=p_tax_document_id;
  return jsonb_build_object('document_status',v_doc.status,'invoice_status',v_doc.invoice_status,'coretax_reference',v_doc.coretax_reference,'sealed_hash',v_doc.sealed_hash,'outbox',v_out,'payments',v_pay);
end;
$function$;
-- public.get_effective_config(p_tenant text, p_device text, p_service text)
CREATE OR REPLACE FUNCTION public.get_effective_config(p_tenant text, p_device text, p_service text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  g jsonb;
  t jsonb;
  x jsonb;
  s jsonb;
  d jsonb;
  tid text;
  svc text := lower(trim(coalesce(p_service, '')));
  uid uuid := auth.uid();
  role_name text := lower(coalesce(auth.jwt()->>'role', ''));
begin
  perform private.assert_app_config_inventory();

  if nullif(trim(coalesce(p_tenant, '')), '') is null
     or nullif(trim(coalesce(p_device, '')), '') is null
     or svc not in ('pos', 'akuntansi') then
    raise exception 'invalid tenant/device/service' using errcode = '22023';
  end if;

  if role_name <> 'service_role' and uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  -- First prove the device is a member of the requested tenant.
  if not exists (
    select 1
    from public.devices z
    where z.device_id = p_device
      and z.tenant_id = p_tenant
  ) then
    raise exception 'device does not belong to tenant' using errcode = '42501';
  end if;

  -- Service-role is server-only. Other callers must own the device or be the
  -- canonical super-admin; caller-supplied tenant/device strings are not authority.
  if role_name <> 'service_role'
     and not private.btp_is_super_admin()
     and not exists (
       select 1 from public.devices z
       where z.device_id = p_device
         and z.tenant_id = p_tenant
         and z.user_id = uid
     ) then
    raise exception 'caller is not authorized for device' using errcode = '42501';
  end if;

  select value into strict g from public.app_config where key = 'global';
  select value into strict t from public.app_config where key = 'tenant:' || p_tenant;

  tid := upper(trim(coalesce(t->>'template_id', t->>'template', '')));
  if tid = '' then
    raise exception 'tenant template assignment missing' using errcode = '23514';
  end if;

  select value into strict x from public.app_config where key = 'template:' || tid;
  select value into strict s
    from public.app_config
    where key = 'tenant:' || p_tenant || ':service:' || svc;
  select value into strict d from public.app_config where key = 'device:' || p_device;

  if nullif(trim(coalesce(s->>'inherited_from_template', '')), '') is not null then
    s := s - 'mdr' - 'mdr_pos' - 'qris_mdr' - 'mdr_%';
  end if;

  return private.strip_legacy_tax_config(g || x || t || s || d);
exception
  when no_data_found then
    raise exception 'missing canonical five-layer app_config row' using errcode = '23514';
end;
$function$;
-- public.get_runtime_tax_snapshot(p_business_date date)
CREATE OR REPLACE FUNCTION public.get_runtime_tax_snapshot(p_business_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rules jsonb; v_ter jsonb; v_missing int;
begin
  if p_business_date is null then raise exception 'business_date_required' using errcode='22023'; end if;
  with active as (
    select tax_code,object_code,category,statutory_rate,dpp_multiplier,effective_rate,calculation_method,effective_date,end_date,legal_basis,metadata,
           count(*) over(partition by tax_code,object_code,category) as active_count
    from public.tax_rates
    where effective_date<=p_business_date and (end_date is null or end_date>=p_business_date)
  )
  select count(*) into v_missing from active where active_count<>1;
  if v_missing<>0 then raise exception 'effective_tax_rule_ambiguity' using errcode='23514'; end if;

  select coalesce(jsonb_object_agg(tax_code||':'||object_code||':'||category,
    jsonb_build_object('tax_code',tax_code,'object_code',object_code,'category',category,
      'statutory_rate',statutory_rate,'dpp_multiplier',dpp_multiplier,'effective_rate',effective_rate,
      'calculation_method',calculation_method,'effective_date',effective_date,'end_date',end_date,
      'legal_basis',legal_basis,'metadata',metadata)
    order by tax_code,object_code,category),'{}'::jsonb)
  into v_rules
  from public.tax_rates
  where effective_date<=p_business_date and (end_date is null or end_date>=p_business_date);

  select coalesce(jsonb_object_agg(category,jsonb_build_object('category',category,'effective_date',effective_date,'end_date',end_date,'legal_basis',legal_basis)),'{}'::jsonb)
  into v_ter
  from (
    select category,min(effective_date) effective_date,max(end_date) end_date,min(legal_basis) legal_basis
    from public.tax_rate_brackets
    where tax_code='PPH21_TER' and effective_date<=p_business_date and (end_date is null or end_date>=p_business_date)
    group by category
  ) q;

  if not (v_rules ? 'PPN:NON_LUXURY:DEFAULT') or not (v_rules ? 'PPN:LUXURY_CONSUMER:DEFAULT')
     or not (v_ter ? 'A') or not (v_ter ? 'B') or not (v_ter ? 'C') then
    raise exception 'required_runtime_tax_rule_missing' using errcode='23514';
  end if;
  return jsonb_build_object('business_date',p_business_date,'tax_rates',v_rules,'pph21_ter_categories',v_ter,'authority','public.tax_rates + public.tax_rate_brackets');
end;
$function$;
-- public.install_coretax_template(p_template_code text, p_template_version text, p_official_source_url text, p_official_last_update date, p_xml_template text, p_generator_spec jsonb, p_expected_sha256 text)
CREATE OR REPLACE FUNCTION public.install_coretax_template(p_template_code text, p_template_version text, p_official_source_url text, p_official_last_update date, p_xml_template text, p_generator_spec jsonb, p_expected_sha256 text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  raise exception 'legacy_coretax_template_installer_disabled_use_audited_overload'
    using errcode='42501';
end;
$function$;
-- public.install_coretax_template(p_template_code text, p_template_version text, p_official_source_url text, p_official_last_update date, p_xml_template text, p_generator_spec jsonb, p_expected_sha256 text, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.install_coretax_template(p_template_code text, p_template_version text, p_official_source_url text, p_official_last_update date, p_xml_template text, p_generator_spec jsonb, p_expected_sha256 text, p_device_id text, p_app_version text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_sha text; v_id uuid;
begin
  if not private.btp_is_super_admin() then raise exception 'canonical super_admin required' using errcode='42501'; end if;
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  if p_reason is null or length(btrim(p_reason))<3 then raise exception 'audit_reason_required' using errcode='22023'; end if;
  if p_template_code not in ('FAKTUR_KELUARAN','BPPU','BPMP') or p_template_version is null or length(btrim(p_template_version))<3 then raise exception 'invalid_coretax_template_identity' using errcode='22023'; end if;
  if p_official_source_url not like 'https://pajak.go.id/%' and p_official_source_url not like 'https://www.pajak.go.id/%' then raise exception 'official_djp_source_required' using errcode='23514'; end if;
  if p_xml_template is null or length(p_xml_template)<20 or p_generator_spec is null or jsonb_typeof(p_generator_spec)<>'object' then raise exception 'verified_xml_template_and_generator_spec_required' using errcode='22023'; end if;
  v_sha:=encode(extensions.digest(convert_to(p_xml_template,'UTF8'),'sha256'),'hex');
  if lower(coalesce(p_expected_sha256,''))<>v_sha then raise exception 'coretax_template_sha256_mismatch' using errcode='23514'; end if;

  update public.coretax_template_registry set is_active=false where template_code=p_template_code and is_active;
  update public.coretax_template_registry
  set official_source_url=p_official_source_url,official_last_update=p_official_last_update,
      xml_template=p_xml_template,generator_spec=p_generator_spec,template_sha256=v_sha,
      is_verified=true,is_active=true,verified_by=v_actor,verified_at=now()
  where template_code=p_template_code and template_version=p_template_version and not is_verified
  returning template_id into v_id;
  if v_id is null then
    insert into public.coretax_template_registry(template_code,template_version,official_source_url,official_last_update,xml_template,generator_spec,template_sha256,is_verified,is_active,verified_by,verified_at)
    values(p_template_code,p_template_version,p_official_source_url,p_official_last_update,p_xml_template,p_generator_spec,v_sha,true,true,v_actor,now()) returning template_id into v_id;
  end if;
  insert into private.audit_logs(tenant_id,actor_id,device_id,source,reason,action)
  values('GLOBAL',v_actor,btrim(p_device_id),'coretax_template:install:'||v_id::text,btrim(p_reason),'success');
  return v_id;
end;
$function$;
-- public.log_config_change()
CREATE OR REPLACE FUNCTION public.log_config_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  insert into public.config_history (key, old_value, new_value, changed_by, version)
  values (
    coalesce(new.key, old.key),
    case when tg_op='INSERT' then null else old.value end,
    new.value,
    auth.jwt() ->> 'email',
    coalesce((new.value->>'version')::int, case when tg_op='INSERT' then null else (old.value->>'version')::int end, 1)
  );
  return new;
end;
$function$;
-- public.mark_coretax_submitted(p_outbox_id uuid, p_coretax_reference text, p_device_id text, p_app_version text, p_reason text)
CREATE OR REPLACE FUNCTION public.mark_coretax_submitted(p_outbox_id uuid, p_coretax_reference text, p_device_id text, p_app_version text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_o public.coretax_outbox%rowtype; v_doc public.tax_documents%rowtype;
begin
  select * into strict v_o from public.coretax_outbox where outbox_id=p_outbox_id for update;
  select * into strict v_doc from public.tax_documents where tax_document_id=v_o.tax_document_id for update;
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(v_doc.tenant_id,v_actor,array['owner','admin','accountant']);
  perform private.assert_accounting_hard_gate(v_doc.tenant_id);
  if v_o.status<>'EXPORTED' or v_doc.status<>'VALIDATED' then
    raise exception 'coretax_submission_state_invalid' using errcode='55000';
  end if;
  if p_coretax_reference is null or length(btrim(p_coretax_reference))<3 or p_reason is null or length(btrim(p_reason))<3 then
    raise exception 'coretax_reference_and_reason_required' using errcode='22023';
  end if;
  update public.coretax_outbox
    set status='SENT',ack_reference=btrim(p_coretax_reference),attempt_count=attempt_count+1,updated_at=now()
    where outbox_id=p_outbox_id;
  update public.tax_documents
    set status='SUBMITTED',coretax_reference=btrim(p_coretax_reference),updated_at=now()
    where tax_document_id=v_doc.tax_document_id;
  insert into public.tax_document_events(tax_document_id,tenant_id,event_type,details,actor_user_id,device_id,reason)
  values(v_doc.tax_document_id,v_doc.tenant_id,'SUBMITTED',jsonb_build_object('outbox_id',p_outbox_id,'coretax_reference',btrim(p_coretax_reference)),v_actor,btrim(p_device_id),btrim(p_reason));
end;
$function$;
-- public.post_pos_accounting_event(p_pos_tenant_id text, p_event_id text, p_fingerprint text, p_event_type text, p_entity_type text, p_entity_id text, p_details jsonb, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.post_pos_accounting_event(p_pos_tenant_id text, p_event_id text, p_fingerprint text, p_event_type text, p_entity_type text, p_entity_id text, p_details jsonb, p_device_id text, p_app_version text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_tenant uuid; v_actor uuid:=auth.uid(); v_id uuid; v_old record; v_key text;
begin
  v_tenant:=accounting_private.resolve_pos_accounting_tenant(p_pos_tenant_id,p_device_id); perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  if p_event_type not in ('sale_posted','return_posted','shift_closed','qris_settled') then raise exception using errcode='22023',message='invalid_pos_accounting_event_type'; end if;
  if p_event_id is null or length(btrim(p_event_id)) not between 1 and 200 or p_fingerprint is null or length(p_fingerprint) not between 1 and 2000 then raise exception using errcode='22023',message='invalid_event_identity'; end if;
  v_key:='pos:'||p_pos_tenant_id||':'||btrim(p_event_id);
  select e.event_id,e.event_type,e.entity_type,e.entity_id,e.details into v_old from public.accounting_events e where e.tenant_id=v_tenant and e.event_key=v_key;
  if v_old.event_id is not null then
    if v_old.event_type=p_event_type and v_old.entity_type=p_entity_type and v_old.entity_id=p_entity_id and v_old.details->>'fingerprint'=p_fingerprint then return v_old.event_id; end if;
    raise exception using errcode='23505',message='event_idempotency_conflict';
  end if;
  insert into public.accounting_events(tenant_id,event_type,event_key,entity_type,entity_id,actor_user_id,actor_subject,device_id,app_version,details)
  values(v_tenant,p_event_type,v_key,p_entity_type,p_entity_id,v_actor,v_actor::text,p_device_id,p_app_version,coalesce(p_details,'{}'::jsonb)||jsonb_build_object('fingerprint',p_fingerprint,'pos_tenant_id',p_pos_tenant_id)) returning event_id into v_id;
  return v_id;
end $function$;
-- public.post_pos_accounting_journal(p_pos_tenant_id text, p_idempotency_key text, p_transaction_ref text, p_journal_date date, p_description text, p_source_type text, p_lines jsonb, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.post_pos_accounting_journal(p_pos_tenant_id text, p_idempotency_key text, p_transaction_ref text, p_journal_date date, p_description text, p_source_type text, p_lines jsonb, p_device_id text, p_app_version text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_tenant uuid;
begin
  v_tenant:=accounting_private.resolve_pos_accounting_tenant(p_pos_tenant_id,p_device_id);
  return accounting_private.post_journal(v_tenant,p_idempotency_key,p_transaction_ref,p_journal_date,p_description,p_source_type,p_lines,p_device_id,p_app_version);
end $function$;
-- public.post_pos_accounting_journal(p_pos_tenant_id text, p_idempotency_key text, p_transaction_ref text, p_journal_date date, p_description text, p_source_type text, p_lines jsonb, p_device_id text, p_app_version text, p_client_actor_id text, p_reason text)
CREATE OR REPLACE FUNCTION public.post_pos_accounting_journal(p_pos_tenant_id text, p_idempotency_key text, p_transaction_ref text, p_journal_date date, p_description text, p_source_type text, p_lines jsonb, p_device_id text, p_app_version text, p_client_actor_id text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tenant uuid;
  v_actor uuid := auth.uid();
  v_journal_id uuid;
  v_event_key text;
  v_old record;
begin
  if p_client_actor_id is null
     or length(btrim(p_client_actor_id)) not between 1 and 200 then
    raise exception using errcode='22023', message='client_actor_required';
  end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 500 then
    raise exception using errcode='22023', message='journal_reason_required';
  end if;

  v_tenant := accounting_private.resolve_pos_accounting_tenant(
    p_pos_tenant_id,
    p_device_id
  );
  v_journal_id := accounting_private.post_journal(
    v_tenant,
    p_idempotency_key,
    p_transaction_ref,
    p_journal_date,
    p_description,
    p_source_type,
    p_lines,
    p_device_id,
    p_app_version
  );

  v_event_key := 'journal:' || v_journal_id::text || ':pos-audit-lineage';
  select e.event_id, e.actor_user_id, e.device_id, e.app_version, e.details
    into v_old
  from public.accounting_events e
  where e.tenant_id = v_tenant
    and e.event_key = v_event_key;

  if v_old.event_id is not null then
    if v_old.actor_user_id is not distinct from v_actor
       and v_old.device_id = p_device_id
       and v_old.app_version = p_app_version
       and v_old.details->>'client_actor_id' = btrim(p_client_actor_id)
       and v_old.details->>'reason' = btrim(p_reason)
       and v_old.details->>'source_type' = p_source_type
       and v_old.details->>'pos_tenant_id' = p_pos_tenant_id then
      return v_journal_id;
    end if;
    raise exception using errcode='23505', message='journal_audit_idempotency_conflict';
  end if;

  insert into public.accounting_events(
    tenant_id,
    event_type,
    event_key,
    journal_id,
    entity_type,
    entity_id,
    actor_user_id,
    actor_subject,
    device_id,
    app_version,
    details
  ) values (
    v_tenant,
    'journal_audit_retained',
    v_event_key,
    v_journal_id,
    'journal',
    v_journal_id::text,
    v_actor,
    v_actor::text,
    p_device_id,
    p_app_version,
    jsonb_build_object(
      'client_actor_id', btrim(p_client_actor_id),
      'reason', btrim(p_reason),
      'source_type', p_source_type,
      'pos_tenant_id', p_pos_tenant_id
    )
  );

  return v_journal_id;
end;
$function$;