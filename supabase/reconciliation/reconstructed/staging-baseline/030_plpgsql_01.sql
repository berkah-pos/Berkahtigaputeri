-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source. PL/pgSQL bodies are installed before SQL-language wrappers.

-- accounting_private.assert_journal_balanced()
CREATE OR REPLACE FUNCTION accounting_private.assert_journal_balanced()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_journal_id uuid;
  v_expected_debit bigint;
  v_expected_credit bigint;
  v_debit numeric;
  v_credit numeric;
  v_count bigint;
begin
  v_journal_id := coalesce(new.journal_id, old.journal_id);

  select j.total_debit, j.total_credit
    into v_expected_debit, v_expected_credit
  from public.accounting_journals j
  where j.journal_id = v_journal_id;

  if not found then
    return null;
  end if;

  select coalesce(sum(l.debit),0), coalesce(sum(l.credit),0), count(*)
    into v_debit, v_credit, v_count
  from public.accounting_journal_lines l
  where l.journal_id = v_journal_id;

  if v_count < 2
     or v_debit <= 0
     or v_debit <> v_credit
     or v_debit <> v_expected_debit
     or v_credit <> v_expected_credit then
    raise exception using errcode = '23514', message = 'journal_not_balanced';
  end if;

  return null;
end;
$function$


-- accounting_private.close_period(p_tenant_id uuid, p_period_start date, p_period_end date, p_reason text, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION accounting_private.close_period(p_tenant_id uuid, p_period_start date, p_period_end date, p_reason text, p_device_id text, p_app_version text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid();
  v_period public.accounting_periods%rowtype;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin']);
  if p_period_start is null or p_period_end is null or p_period_end<p_period_start then raise exception 'invalid_period_dates' using errcode='22023'; end if;
  if p_reason is null or length(btrim(p_reason))<3 or length(btrim(p_reason))>500 then raise exception 'close_reason_required' using errcode='22023'; end if;

  -- Hard blocker before close. No warning/waiver path.
  perform private.assert_accounting_hard_gate(p_tenant_id);
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text,412));

  if exists(select 1 from public.accounting_periods p where p.tenant_id=p_tenant_id
            and not (p.period_end<p_period_start or p.period_start>p_period_end)
            and not (p.period_start=p_period_start and p.period_end=p_period_end)) then
    raise exception 'accounting_period_overlap' using errcode='23P01';
  end if;

  select * into v_period from public.accounting_periods p
  where p.tenant_id=p_tenant_id and p.period_start=p_period_start and p.period_end=p_period_end for update;
  if found and v_period.status='closed' then return v_period.period_id; end if;

  if not found then
    insert into public.accounting_periods(tenant_id,period_start,period_end,status,close_reason,closed_at,closed_by,closed_subject)
    values(p_tenant_id,p_period_start,p_period_end,'closed',btrim(p_reason),now(),v_actor,v_actor::text)
    returning * into v_period;
  else
    update public.accounting_periods set status='closed',close_reason=btrim(p_reason),closed_at=now(),closed_by=v_actor,closed_subject=v_actor::text
    where period_id=v_period.period_id returning * into v_period;
  end if;

  insert into public.accounting_events(tenant_id,event_type,event_key,entity_type,entity_id,actor_user_id,actor_subject,device_id,app_version,details)
  values(p_tenant_id,'period_closed','period:'||v_period.period_id::text||':closed:'||txid_current()::text,'accounting_period',v_period.period_id::text,
         v_actor,v_actor::text,btrim(p_device_id),btrim(p_app_version),jsonb_build_object('period_start',p_period_start::text,'period_end',p_period_end::text,'reason',btrim(p_reason),'hard_gate','PASS'));
  return v_period.period_id;
end;
$function$


-- accounting_private.create_tenant(p_name text, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION accounting_private.create_tenant(p_name text, p_device_id text, p_app_version text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid;
begin
  perform accounting_private.require_bound_device(v_actor, p_device_id, p_app_version);
  if p_name is null or length(btrim(p_name)) not between 1 and 120 then
    raise exception using errcode = '22023', message = 'invalid_tenant_name';
  end if;

  insert into public.accounting_tenants(name, owner_user_id, owner_subject)
  values (btrim(p_name), v_actor, v_actor::text)
  returning tenant_id into v_tenant;

  insert into public.accounting_memberships(tenant_id, user_id, role)
  values (v_tenant, v_actor, 'owner');

  insert into public.accounting_events(
    tenant_id, event_type, event_key, entity_type, entity_id,
    actor_user_id, actor_subject, device_id, app_version, details
  ) values (
    v_tenant, 'tenant_created', 'tenant:' || v_tenant::text || ':created',
    'tenant', v_tenant::text,
    v_actor, v_actor::text, p_device_id, p_app_version,
    jsonb_build_object('name', btrim(p_name))
  );

  return v_tenant;
end;
$function$


-- accounting_private.guard_line_creation_tx()
CREATE OR REPLACE FUNCTION accounting_private.guard_line_creation_tx()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_txid bigint;
begin
  select j.write_txid into v_txid
  from public.accounting_journals j
  where j.journal_id = new.journal_id
    and j.tenant_id = new.tenant_id;

  if v_txid is null then
    raise exception using errcode = '23503', message = 'journal_not_found';
  end if;
  if v_txid <> txid_current() then
    raise exception using errcode = '55000', message = 'immutable_posted_journal';
  end if;
  return new;
end;
$function$


-- accounting_private.post_journal(p_tenant_id uuid, p_idempotency_key text, p_transaction_ref text, p_journal_date date, p_description text, p_source_type text, p_lines jsonb, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION accounting_private.post_journal(p_tenant_id uuid, p_idempotency_key text, p_transaction_ref text, p_journal_date date, p_description text, p_source_type text, p_lines jsonb, p_device_id text, p_app_version text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_existing_id uuid;
  v_existing_fingerprint jsonb;
  v_fingerprint jsonb;
  v_journal_id uuid;
  v_line jsonb;
  v_line_no integer := 0;
  v_account_code text;
  v_debit_text text;
  v_credit_text text;
  v_memo text;
  v_debit numeric;
  v_credit numeric;
  v_total_debit numeric := 0;
  v_total_credit numeric := 0;
begin
  perform accounting_private.require_bound_device(v_actor, p_device_id, p_app_version);
  perform accounting_private.require_member_role(p_tenant_id, v_actor, null);

  if p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid_idempotency_key';
  end if;
  if p_transaction_ref is null or length(btrim(p_transaction_ref)) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid_transaction_ref';
  end if;
  if p_journal_date is null then
    raise exception using errcode = '22023', message = 'journal_date_required';
  end if;
  if p_source_type not in ('pos_sale','sale_return','shift_close','qris_settlement','purchase_receipt','supplier_payment','ar_invoice','ar_receipt','fixed_asset_acquisition','fixed_asset_depreciation','payroll_accrual','payroll_payment','manual') then
    raise exception using errcode = '22023', message = 'invalid_source_type';
  end if;
  if p_description is not null and length(p_description) > 500 then
    raise exception using errcode = '22023', message = 'description_too_long';
  end if;
  if jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) < 2
     or jsonb_array_length(p_lines) > 100 then
    raise exception using errcode = '22023', message = 'invalid_journal_lines';
  end if;

  v_fingerprint := jsonb_build_object(
    'transaction_ref', btrim(p_transaction_ref),
    'journal_date', p_journal_date::text,
    'description', coalesce(p_description,''),
    'source_type', p_source_type,
    'lines', p_lines,
    'device_id', p_device_id,
    'app_version', p_app_version
  );

  perform pg_advisory_xact_lock(
    hashtextextended(p_tenant_id::text || ':' || btrim(p_idempotency_key), 411)
  );

  select j.journal_id, j.request_fingerprint
    into v_existing_id, v_existing_fingerprint
  from public.accounting_journals j
  where j.tenant_id = p_tenant_id
    and j.idempotency_key = btrim(p_idempotency_key);

  if v_existing_id is not null then
    if v_existing_fingerprint = v_fingerprint then
      return v_existing_id;
    end if;
    raise exception using errcode = '23505', message = 'idempotency_conflict';
  end if;

  if exists (
    select 1 from public.accounting_periods p
    where p.tenant_id = p_tenant_id
      and p.status = 'closed'
      and p_journal_date between p.period_start and p.period_end
  ) then
    raise exception using errcode = '55000', message = 'accounting_period_closed';
  end if;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_line_no := v_line_no + 1;
    v_account_code := v_line->>'account_code';
    v_debit_text := coalesce(v_line->>'debit','0');
    v_credit_text := coalesce(v_line->>'credit','0');
    v_memo := coalesce(v_line->>'memo','');

    if v_account_code is null or not exists (
      select 1 from public.accounting_coa c where c.account_code = v_account_code
    ) then
      raise exception using errcode = '23503', message = 'unknown_account_code';
    end if;
    if v_debit_text !~ '^(0|[1-9][0-9]*)$'
       or v_credit_text !~ '^(0|[1-9][0-9]*)$' then
      raise exception using errcode = '22023', message = 'amount_must_be_integer_rupiah';
    end if;

    v_debit := v_debit_text::numeric;
    v_credit := v_credit_text::numeric;

    if (v_debit > 0 and v_credit > 0) or (v_debit = 0 and v_credit = 0) then
      raise exception using errcode = '23514', message = 'line_requires_one_side';
    end if;
    if v_debit > 9223372036854775807::numeric
       or v_credit > 9223372036854775807::numeric then
      raise exception using errcode = '22003', message = 'amount_out_of_range';
    end if;
    if length(v_memo) > 500 then
      raise exception using errcode = '22023', message = 'line_memo_too_long';
    end if;

    v_total_debit := v_total_debit + v_debit;
    v_total_credit := v_total_credit + v_credit;
  end loop;

  if v_total_debit <= 0 or v_total_debit <> v_total_credit then
    raise exception using errcode = '23514', message = 'journal_not_balanced';
  end if;
  if v_total_debit > 9223372036854775807::numeric then
    raise exception using errcode = '22003', message = 'journal_total_out_of_range';
  end if;

  insert into public.accounting_journals(
    tenant_id, idempotency_key, request_fingerprint, transaction_ref,
    journal_date, description, source_type, total_debit, total_credit,
    actor_user_id, actor_subject, device_id, app_version
  ) values (
    p_tenant_id, btrim(p_idempotency_key), v_fingerprint, btrim(p_transaction_ref),
    p_journal_date, coalesce(p_description,''), p_source_type,
    v_total_debit::bigint, v_total_credit::bigint,
    v_actor, v_actor::text, p_device_id, p_app_version
  )
  returning journal_id into v_journal_id;

  v_line_no := 0;
  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_line_no := v_line_no + 1;
    insert into public.accounting_journal_lines(
      journal_id, tenant_id, line_no, account_code, debit, credit, memo
    ) values (
      v_journal_id, p_tenant_id, v_line_no, v_line->>'account_code',
      coalesce(v_line->>'debit','0')::bigint,
      coalesce(v_line->>'credit','0')::bigint,
      coalesce(v_line->>'memo','')
    );
  end loop;

  insert into public.accounting_events(
    tenant_id, event_type, event_key, journal_id, entity_type, entity_id,
    actor_user_id, actor_subject, device_id, app_version, details
  ) values (
    p_tenant_id, 'journal_posted', 'journal:' || v_journal_id::text || ':posted',
    v_journal_id, 'journal', v_journal_id::text,
    v_actor, v_actor::text, p_device_id, p_app_version,
    jsonb_build_object(
      'idempotency_key', btrim(p_idempotency_key),
      'transaction_ref', btrim(p_transaction_ref),
      'source_type', p_source_type,
      'journal_date', p_journal_date::text,
      'total_debit', v_total_debit
    )
  );

  return v_journal_id;
end;
$function$


-- accounting_private.reject_locked_coa_insert()
CREATE OR REPLACE FUNCTION accounting_private.reject_locked_coa_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception using errcode = '55000', message = 'locked_coa_contract';
end;
$function$


-- accounting_private.reject_mutation()
CREATE OR REPLACE FUNCTION accounting_private.reject_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception using errcode = '55000', message = 'immutable_accounting_record';
end;
$function$


-- accounting_private.reopen_period(p_tenant_id uuid, p_period_id uuid, p_reason text, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION accounting_private.reopen_period(p_tenant_id uuid, p_period_id uuid, p_reason text, p_device_id text, p_app_version text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_period public.accounting_periods%rowtype;
begin
  perform accounting_private.require_bound_device(v_actor, p_device_id, p_app_version);
  perform accounting_private.require_member_role(
    p_tenant_id, v_actor, array['owner','admin']
  );

  if p_reason is null or length(btrim(p_reason)) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'reopen_reason_required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text, 412));

  select * into v_period
  from public.accounting_periods p
  where p.period_id = p_period_id
    and p.tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'accounting_period_not_found';
  end if;
  if v_period.status = 'open' then
    return v_period.period_id;
  end if;

  update public.accounting_periods
  set status = 'open',
      reopen_reason = btrim(p_reason),
      reopened_at = now(),
      reopened_by = v_actor,
      reopened_subject = v_actor::text
  where period_id = p_period_id
  returning * into v_period;

  insert into public.accounting_events(
    tenant_id, event_type, event_key, entity_type, entity_id,
    actor_user_id, actor_subject, device_id, app_version, details
  ) values (
    p_tenant_id, 'period_reopened',
    'period:' || v_period.period_id::text || ':reopened:' || txid_current()::text,
    'accounting_period', v_period.period_id::text,
    v_actor, v_actor::text, p_device_id, p_app_version,
    jsonb_build_object('reason', btrim(p_reason))
  );

  return v_period.period_id;
end;
$function$


-- accounting_private.require_bound_device(p_actor uuid, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION accounting_private.require_bound_device(p_actor uuid, p_device_id text, p_app_version text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_actor is null then
    raise exception using errcode = '28000', message = 'authentication_required';
  end if;
  if p_device_id is null or length(btrim(p_device_id)) = 0 then
    raise exception using errcode = '22023', message = 'device_id_required';
  end if;
  if p_app_version is null or length(btrim(p_app_version)) = 0 then
    raise exception using errcode = '22023', message = 'app_version_required';
  end if;
  if not exists (
    select 1 from public.devices d
    where d.device_id = p_device_id and d.user_id = p_actor
  ) then
    raise exception using errcode = '42501', message = 'device_not_bound_to_actor';
  end if;
end;
$function$


-- accounting_private.require_member_role(p_tenant_id uuid, p_actor uuid, p_allowed_roles text[])
CREATE OR REPLACE FUNCTION accounting_private.require_member_role(p_tenant_id uuid, p_actor uuid, p_allowed_roles text[] DEFAULT NULL::text[])
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text;
begin
  select m.role into v_role
  from public.accounting_memberships m
  join public.accounting_tenants t on t.tenant_id = m.tenant_id
  where m.tenant_id = p_tenant_id
    and m.user_id = p_actor
    and m.is_active
    and t.status = 'active';

  if v_role is null then
    raise exception using errcode = '42501', message = 'tenant_access_denied';
  end if;
  if p_allowed_roles is not null and not (v_role = any(p_allowed_roles)) then
    raise exception using errcode = '42501', message = 'accounting_role_denied';
  end if;
  return v_role;
end;
$function$


-- accounting_private.require_open_period(p_tenant_id uuid, p_business_date date)
CREATE OR REPLACE FUNCTION accounting_private.require_open_period(p_tenant_id uuid, p_business_date date)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF p_tenant_id IS NULL OR p_business_date IS NULL THEN
    RAISE EXCEPTION 'accounting_period_identity_required' USING ERRCODE='22023';
  END IF;

  -- The period table is a close-register: no row means the date remains open.
  -- Any matching persisted row must explicitly be status=open to allow posting.
  IF EXISTS (
    SELECT 1
    FROM public.accounting_periods p
    WHERE p.tenant_id=p_tenant_id
      AND p_business_date BETWEEN p.period_start AND p.period_end
      AND p.status IS DISTINCT FROM 'open'
  ) THEN
    RAISE EXCEPTION 'accounting_period_closed' USING ERRCODE='55000';
  END IF;
END;
$function$


-- accounting_private.resolve_pos_accounting_tenant(p_pos_tenant_id text, p_device_id text)
CREATE OR REPLACE FUNCTION accounting_private.resolve_pos_accounting_tenant(p_pos_tenant_id text, p_device_id text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid:=auth.uid(); v_accounting uuid;
begin
  if v_actor is null then raise exception using errcode='28000',message='authentication_required'; end if;
  if p_pos_tenant_id is null or btrim(p_pos_tenant_id)='' then raise exception using errcode='22023',message='pos_tenant_required'; end if;
  if not exists(select 1 from public.devices d where d.device_id=p_device_id and d.user_id=v_actor and d.tenant_id=p_pos_tenant_id) then raise exception using errcode='42501',message='pos_device_tenant_mismatch'; end if;
  if not exists(select 1 from public.pos_memberships m where m.tenant_id=p_pos_tenant_id and m.user_id=v_actor and m.is_active) then raise exception using errcode='42501',message='pos_membership_required'; end if;
  select m.accounting_tenant_id into v_accounting from public.pos_accounting_tenant_map m where m.pos_tenant_id=p_pos_tenant_id and m.is_active;
  if v_accounting is null then raise exception using errcode='55000',message='accounting_tenant_mapping_missing'; end if;
  perform accounting_private.require_member_role(v_accounting,v_actor,null);
  return v_accounting;
end; $function$

