-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source.

-- public.set_input_tax_invoice_validation(p_tax_document_id uuid, p_invoice_status text, p_creditable boolean, p_external_reference text, p_reason text)
CREATE OR REPLACE FUNCTION public.set_input_tax_invoice_validation(p_tax_document_id uuid, p_invoice_status text, p_creditable boolean, p_external_reference text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_doc public.tax_documents%rowtype; v_actor uuid:=auth.uid(); v_role text:=lower(coalesce(auth.jwt()->>'role',''));
begin
  if v_role<>'service_role' and not private.btp_is_super_admin() then raise exception 'tax invoice validation authority denied' using errcode='42501'; end if;
  if p_invoice_status not in ('VALID','INVALID') or p_reason is null or length(btrim(p_reason))<3 then raise exception 'invalid_tax_invoice_validation' using errcode='22023'; end if;
  select * into strict v_doc from public.tax_documents where tax_document_id=p_tax_document_id and document_type='VAT_INPUT' for update;
  if v_doc.status<>'DRAFT' or v_doc.invoice_status<>'PENDING' then raise exception 'tax_invoice_already_validated' using errcode='55000'; end if;
  if p_invoice_status='INVALID' and p_creditable then raise exception 'invalid_invoice_cannot_be_creditable' using errcode='23514'; end if;
  update public.tax_documents set invoice_status=p_invoice_status,creditable_input_vat=(p_invoice_status='VALID' and p_creditable),status='VALIDATED',coretax_reference=nullif(btrim(coalesce(p_external_reference,'')),''),updated_at=now() where tax_document_id=p_tax_document_id;
  insert into public.tax_document_events(tax_document_id,tenant_id,event_type,details,actor_user_id,device_id,reason)
  values(p_tax_document_id,v_doc.tenant_id,'INPUT_INVOICE_VALIDATED',jsonb_build_object('invoice_status',p_invoice_status,'creditable',p_creditable,'external_reference',p_external_reference),coalesce(v_actor,v_doc.actor_user_id),v_doc.device_id,btrim(p_reason));
end;
$function$


-- public.set_updated_at()
CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$


-- public.update_app_config_atomic(p_key text, p_new_value jsonb, p_expected_version integer)
CREATE OR REPLACE FUNCTION public.update_app_config_atomic(p_key text, p_new_value jsonb, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_current jsonb;
  v_version int;
  v_device_tenant text;
  v_role text:=lower(coalesce(auth.jwt()->>'role',''));
begin
  perform private.assert_app_config_inventory();

  if v_role='service_role' and (p_key='global' or p_key ~ '^template:[^:]+$') then
    raise exception 'service_role cannot mutate protected config' using errcode='42501';
  end if;

  if (p_key='global' or p_key ~ '^template:[^:]+$') and not private.btp_is_super_admin() then
    raise exception 'GLOBAL/TEMPLATE mutation requires canonical super_admin berkahtigaputeri@gmail.com'
      using errcode='42501';
  end if;

  if not private.can_write_app_config(p_key) then
    raise exception 'not authorized to update app_config key %',p_key using errcode='42501';
  end if;
  if p_new_value is null or jsonb_typeof(p_new_value)<>'object' then
    raise exception 'new value must be a JSON object' using errcode='22023';
  end if;
  if exists(
    select 1 from jsonb_object_keys(p_new_value) k
    where lower(k) in (
      'ppn','ppn rate %','ppn account','dpp',
      'pph21','pph 21','pph23','pph 23','pph final','tax rate','tax_rate'
    )
  ) then
    raise exception 'regulatory tax values are read-only; use tax_rates' using errcode='42501';
  end if;
  if p_expected_version is null or p_expected_version<1 then
    raise exception 'expected version must be >= 1' using errcode='22023';
  end if;

  select value into v_current from public.app_config where key=p_key for update;
  if not found then raise exception 'key not found %',p_key using errcode='P0002'; end if;
  if coalesce(v_current->>'version','') !~ '^[1-9][0-9]*$' then
    raise exception 'invalid current version for key %',p_key using errcode='22023';
  end if;
  v_version:=(v_current->>'version')::int;
  if v_version<>p_expected_version then
    raise sqlstate '40001' using message=format('version conflict: expected %s got %s',p_expected_version,v_version);
  end if;

  if p_key ~ '^tenant:[^:]+$'
     and v_role<>'service_role'
     and not private.btp_is_super_admin()
     and coalesce(p_new_value->>'template_id',p_new_value->>'template','')
         <>coalesce(v_current->>'template_id',v_current->>'template','') then
    raise exception 'tenant role cannot change template assignment' using errcode='42501';
  end if;

  if p_key ~ '^device:[^:]+$' then
    if p_new_value?'device_id' and p_new_value->>'device_id'<>split_part(p_key,':',2) then
      raise exception 'device_id must match app_config key' using errcode='23514';
    end if;
    select tenant_id into strict v_device_tenant from public.devices where device_id=split_part(p_key,':',2);
    if p_new_value?'tenant_id' and p_new_value->>'tenant_id'<>v_device_tenant then
      raise exception 'device tenant cannot be reassigned' using errcode='23514';
    end if;
  end if;

  p_new_value:=jsonb_set(private.strip_legacy_tax_config(p_new_value),'{version}',to_jsonb(v_version+1),true);
  update public.app_config set value=p_new_value,updated_at=now()
  where key=p_key and (value->>'version')::int=p_expected_version;
  if not found then raise sqlstate '40001' using message='concurrent update'; end if;

  if p_key ~ '^tenant:[^:]+$' then
    update public.tenants set
      toko_name=case when p_new_value?'toko_name' then p_new_value->>'toko_name' else toko_name end,
      alamat=case when p_new_value?'address' then p_new_value->>'address' else alamat end,
      max_user=case when p_new_value?'max_user' then (p_new_value->>'max_user')::int else max_user end,
      expiry=case when p_new_value?'expiry' then nullif(p_new_value->>'expiry','')::date else expiry end,
      is_blocked=case when p_new_value?'blocked' then (p_new_value->>'blocked')::boolean else is_blocked end,
      features=case when p_new_value?'features' then p_new_value->'features' else features end,
      template_id=case when p_new_value?'template_id' then upper(p_new_value->>'template_id') else template_id end,
      updated_at=now()
    where tenant_id=split_part(p_key,':',2);
    if not found then raise exception 'tenant projection missing' using errcode='23514'; end if;
  elsif p_key ~ '^device:[^:]+$' then
    update public.devices set
      package_id=case when p_new_value?'package_id' then p_new_value->>'package_id' else package_id end,
      hardware_mode=case when p_new_value?'hardware_mode' then p_new_value->>'hardware_mode' else hardware_mode end,
      printer_type=case when p_new_value?'printer_type' then p_new_value->>'printer_type' else printer_type end,
      updated_at=now()
    where device_id=split_part(p_key,':',2);
    if not found then raise exception 'device projection missing' using errcode='23514'; end if;
  end if;
  return p_new_value;
exception when no_data_found then
  raise exception 'device projection missing' using errcode='23514';
end;
$function$

