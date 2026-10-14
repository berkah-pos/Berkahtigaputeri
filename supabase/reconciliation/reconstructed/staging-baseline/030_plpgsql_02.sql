-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source. PL/pgSQL bodies are installed before SQL-language wrappers.

-- accounting_private.reverse_journal(p_tenant_id uuid, p_original_journal_id uuid, p_idempotency_key text, p_journal_date date, p_reason text, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION accounting_private.reverse_journal(p_tenant_id uuid, p_original_journal_id uuid, p_idempotency_key text, p_journal_date date, p_reason text, p_device_id text, p_app_version text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_original public.accounting_journals%rowtype;
  v_existing_id uuid;
  v_existing_fingerprint jsonb;
  v_fingerprint jsonb;
  v_reversal_id uuid;
  v_line public.accounting_journal_lines%rowtype;
begin
  perform accounting_private.require_bound_device(v_actor, p_device_id, p_app_version);
  perform accounting_private.require_member_role(
    p_tenant_id, v_actor, array['owner','admin','accountant']
  );

  if p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 200 then
    raise exception using errcode = '22023', message = 'invalid_idempotency_key';
  end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 500 then
    raise exception using errcode = '22023', message = 'reversal_reason_required';
  end if;
  if p_journal_date is null then
    raise exception using errcode = '22023', message = 'journal_date_required';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_tenant_id::text || ':' || btrim(p_idempotency_key), 411)
  );

  select * into v_original
  from public.accounting_journals j
  where j.journal_id = p_original_journal_id
    and j.tenant_id = p_tenant_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'original_journal_not_found';
  end if;
  if v_original.source_type = 'reversal' then
    raise exception using errcode = '55000', message = 'cannot_reverse_reversal';
  end if;

  v_fingerprint := jsonb_build_object(
    'original_journal_id', p_original_journal_id::text,
    'journal_date', p_journal_date::text,
    'reason', btrim(p_reason),
    'device_id', p_device_id,
    'app_version', p_app_version
  );

  select j.journal_id, j.request_fingerprint
    into v_existing_id, v_existing_fingerprint
  from public.accounting_journals j
  where j.tenant_id = p_tenant_id
    and j.idempotency_key = btrim(p_idempotency_key);

  if v_existing_id is not null then
    if v_existing_fingerprint = v_fingerprint
       and exists (
         select 1 from public.accounting_journals r
         where r.journal_id = v_existing_id
           and r.reversal_of = p_original_journal_id
       ) then
      return v_existing_id;
    end if;
    raise exception using errcode = '23505', message = 'idempotency_conflict';
  end if;

  if exists (
    select 1 from public.accounting_journals r
    where r.tenant_id = p_tenant_id
      and r.reversal_of = p_original_journal_id
  ) then
    raise exception using errcode = '23505', message = 'journal_already_reversed';
  end if;

  if exists (
    select 1 from public.accounting_periods p
    where p.tenant_id = p_tenant_id
      and p.status = 'closed'
      and p_journal_date between p.period_start and p.period_end
  ) then
    raise exception using errcode = '55000', message = 'accounting_period_closed';
  end if;

  insert into public.accounting_journals(
    tenant_id, idempotency_key, request_fingerprint, transaction_ref,
    journal_date, description, source_type, reversal_of,
    total_debit, total_credit, actor_user_id, actor_subject, device_id, app_version
  ) values (
    p_tenant_id, btrim(p_idempotency_key), v_fingerprint,
    'reversal:' || v_original.transaction_ref,
    p_journal_date, 'Reversal: ' || btrim(p_reason), 'reversal',
    p_original_journal_id, v_original.total_credit, v_original.total_debit,
    v_actor, v_actor::text, p_device_id, p_app_version
  )
  returning journal_id into v_reversal_id;

  for v_line in
    select * from public.accounting_journal_lines
    where journal_id = p_original_journal_id
    order by line_no
  loop
    insert into public.accounting_journal_lines(
      journal_id, tenant_id, line_no, account_code, debit, credit, memo
    ) values (
      v_reversal_id, p_tenant_id, v_line.line_no, v_line.account_code,
      v_line.credit, v_line.debit,
      case when length(v_line.memo) > 0 then 'Reversal: ' || v_line.memo else 'Reversal' end
    );
  end loop;

  insert into public.accounting_events(
    tenant_id, event_type, event_key, journal_id, entity_type, entity_id,
    actor_user_id, actor_subject, device_id, app_version, details
  ) values (
    p_tenant_id, 'journal_reversed',
    'journal:' || p_original_journal_id::text || ':reversed',
    v_reversal_id, 'journal', p_original_journal_id::text,
    v_actor, v_actor::text, p_device_id, p_app_version,
    jsonb_build_object(
      'original_journal_id', p_original_journal_id,
      'reversal_journal_id', v_reversal_id,
      'reason', btrim(p_reason)
    )
  );

  return v_reversal_id;
end;
$function$


-- inventory_private.average_adjust_to_count(p_tenant_id uuid, p_product_id uuid, p_counted_qty bigint, p_zero_stock_unit_cost bigint, p_event_id text, p_business_ref text, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION inventory_private.average_adjust_to_count(p_tenant_id uuid, p_product_id uuid, p_counted_qty bigint, p_zero_stock_unit_cost bigint, p_event_id text, p_business_ref text, p_actor uuid, p_device_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.inventory_average_projection%rowtype; v_delta bigint; v_value_delta bigint; v_num numeric; v_existing public.inventory_average_events%rowtype;
begin
  if p_counted_qty is null or p_counted_qty<0 then raise exception 'invalid_stock_count' using errcode='22023'; end if;
  if p_event_id is null or length(btrim(p_event_id))=0 or p_business_ref is null or length(btrim(p_business_ref))=0 then raise exception 'inventory_identity_required' using errcode='22023'; end if;
  if p_actor is null or p_device_id is null or length(btrim(p_device_id))=0 or p_reason is null or length(btrim(p_reason))<3 then raise exception 'inventory_audit_lineage_required' using errcode='22023'; end if;
  select * into v_existing from public.inventory_average_events where tenant_id=p_tenant_id and event_id=btrim(p_event_id);
  if found then
    if v_existing.product_id=p_product_id and v_existing.event_type='adjustment' and v_existing.business_ref=btrim(p_business_ref) then
      return jsonb_build_object('quantity_delta',v_existing.quantity_delta,'value_delta',v_existing.value_delta);
    end if;
    raise exception 'inventory_idempotency_conflict' using errcode='23505';
  end if;
  insert into public.inventory_average_projection(tenant_id,product_id,on_hand_qty,inventory_value,revision,last_event_id) values(p_tenant_id,p_product_id,0,0,1,null) on conflict do nothing;
  select * into v from public.inventory_average_projection where tenant_id=p_tenant_id and product_id=p_product_id for update;
  v_delta:=p_counted_qty-v.on_hand_qty;
  if v_delta=0 then raise exception 'stock_count_matches_system_no_adjustment' using errcode='22023'; end if;
  if v_delta<0 then
    if v.inventory_value<=0 or v.on_hand_qty<=0 then raise exception 'invalid_inventory_value_for_stock_shortage' using errcode='23514'; end if;
    if -v_delta=v.on_hand_qty then v_value_delta:=-v.inventory_value;
    else
      v_num:=round(v.inventory_value::numeric*(-v_delta)::numeric/v.on_hand_qty::numeric);
      if v_num<=0 or v_num>=v.inventory_value then raise exception 'invalid_moving_average_adjustment' using errcode='23514'; end if;
      v_value_delta:=-v_num::bigint;
    end if;
  else
    if v.on_hand_qty>0 then
      v_num:=round(v.inventory_value::numeric*v_delta::numeric/v.on_hand_qty::numeric);
      if v_num<=0 then raise exception 'invalid_moving_average_adjustment' using errcode='23514'; end if;
      v_value_delta:=v_num::bigint;
    else
      if p_zero_stock_unit_cost is null or p_zero_stock_unit_cost<=0 then raise exception 'unit_cost_required_for_positive_count_from_zero' using errcode='22023'; end if;
      v_num:=v_delta::numeric*p_zero_stock_unit_cost::numeric;
      if v_num>9223372036854775807::numeric then raise exception 'inventory_value_out_of_range' using errcode='22003'; end if;
      v_value_delta:=v_num::bigint;
    end if;
  end if;
  update public.inventory_average_projection set on_hand_qty=p_counted_qty,inventory_value=v.inventory_value+v_value_delta,revision=v.revision+1,last_event_id=btrim(p_event_id),updated_at=now() where tenant_id=p_tenant_id and product_id=p_product_id;
  insert into public.inventory_product_projection(tenant_id,product_id,on_hand_qty,revision,last_server_sequence) values(p_tenant_id,p_product_id,p_counted_qty,1,0)
  on conflict (tenant_id,product_id) do update set on_hand_qty=excluded.on_hand_qty,revision=public.inventory_product_projection.revision+1,updated_at=now();
  insert into public.inventory_average_events(tenant_id,event_id,product_id,event_type,quantity_delta,value_delta,business_ref,actor_user_id,device_id,reason)
  values(p_tenant_id,btrim(p_event_id),p_product_id,'adjustment',v_delta,v_value_delta,btrim(p_business_ref),p_actor,btrim(p_device_id),btrim(p_reason));
  return jsonb_build_object('quantity_delta',v_delta,'value_delta',v_value_delta);
end;
$function$


-- inventory_private.average_consume(p_tenant_id uuid, p_product_id uuid, p_qty bigint, p_event_id text, p_business_ref text, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION inventory_private.average_consume(p_tenant_id uuid, p_product_id uuid, p_qty bigint, p_event_id text, p_business_ref text, p_actor uuid, p_device_id text, p_reason text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.inventory_average_projection%rowtype; v_cogs bigint; v_num numeric; v_existing public.inventory_average_events%rowtype;
begin
  if p_qty is null or p_qty<=0 then raise exception 'invalid_inventory_sale_quantity' using errcode='22023'; end if;
  if p_event_id is null or length(btrim(p_event_id))=0 or p_business_ref is null or length(btrim(p_business_ref))=0 then
    raise exception 'inventory_identity_required' using errcode='22023';
  end if;
  if p_actor is null or p_device_id is null or length(btrim(p_device_id))=0 or p_reason is null or length(btrim(p_reason))<3 then
    raise exception 'inventory_audit_lineage_required' using errcode='22023';
  end if;
  select * into v_existing from public.inventory_average_events
  where tenant_id=p_tenant_id and event_id=btrim(p_event_id);
  if found then
    if v_existing.product_id=p_product_id and v_existing.event_type='sale'
       and v_existing.quantity_delta=-p_qty and v_existing.business_ref=btrim(p_business_ref) then
      return -v_existing.value_delta;
    end if;
    raise exception 'inventory_idempotency_conflict' using errcode='23505';
  end if;

  select * into v from public.inventory_average_projection
  where tenant_id=p_tenant_id and product_id=p_product_id for update;
  if not found or v.on_hand_qty<p_qty then raise exception 'insufficient_stock' using errcode='23514'; end if;
  if v.inventory_value<=0 then raise exception 'invalid_inventory_value_for_stocked_sale' using errcode='23514'; end if;

  if p_qty=v.on_hand_qty then
    v_cogs:=v.inventory_value;
  else
    v_num:=round(v.inventory_value::numeric*p_qty::numeric/v.on_hand_qty::numeric);
    if v_num<=0 or v_num>=v.inventory_value then raise exception 'invalid_moving_average_cogs' using errcode='23514'; end if;
    v_cogs:=v_num::bigint;
  end if;

  update public.inventory_average_projection
  set on_hand_qty=v.on_hand_qty-p_qty,
      inventory_value=v.inventory_value-v_cogs,
      revision=v.revision+1,last_event_id=btrim(p_event_id),updated_at=now()
  where tenant_id=p_tenant_id and product_id=p_product_id;

  update public.inventory_product_projection
  set on_hand_qty=v.on_hand_qty-p_qty,revision=revision+1,updated_at=now()
  where tenant_id=p_tenant_id and product_id=p_product_id;
  if not found then raise exception 'physical_inventory_projection_missing' using errcode='23514'; end if;

  insert into public.inventory_average_events(tenant_id,event_id,product_id,event_type,quantity_delta,value_delta,business_ref,actor_user_id,device_id,reason)
  values(p_tenant_id,btrim(p_event_id),p_product_id,'sale',-p_qty,-v_cogs,btrim(p_business_ref),p_actor,btrim(p_device_id),btrim(p_reason));
  return v_cogs;
end;
$function$


-- inventory_private.average_receive(p_tenant_id uuid, p_product_id uuid, p_qty bigint, p_unit_cost bigint, p_event_id text, p_business_ref text, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION inventory_private.average_receive(p_tenant_id uuid, p_product_id uuid, p_qty bigint, p_unit_cost bigint, p_event_id text, p_business_ref text, p_actor uuid, p_device_id text, p_reason text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.inventory_average_projection%rowtype; v_add numeric; v_existing public.inventory_average_events%rowtype;
begin
  if p_qty is null or p_qty<=0 or p_unit_cost is null or p_unit_cost<=0 then
    raise exception 'invalid_inventory_receipt' using errcode='22023';
  end if;
  if p_event_id is null or length(btrim(p_event_id))=0 or p_business_ref is null or length(btrim(p_business_ref))=0 then raise exception 'inventory_identity_required' using errcode='22023'; end if;
  if p_actor is null or p_device_id is null or length(btrim(p_device_id))=0 or p_reason is null or length(btrim(p_reason))<3 then raise exception 'inventory_audit_lineage_required' using errcode='22023'; end if;
  if not exists(select 1 from public.product_master p where p.tenant_id=p_tenant_id and p.product_id=p_product_id and p.is_active) then raise exception 'inventory_product_not_active' using errcode='23503'; end if;
  select * into v_existing from public.inventory_average_events where tenant_id=p_tenant_id and event_id=btrim(p_event_id);
  if found then
    if v_existing.product_id=p_product_id and v_existing.event_type='receipt' and v_existing.quantity_delta=p_qty and v_existing.business_ref=btrim(p_business_ref) then return v_existing.value_delta; end if;
    raise exception 'inventory_idempotency_conflict' using errcode='23505';
  end if;
  v_add:=p_qty::numeric*p_unit_cost::numeric;
  if v_add>9223372036854775807::numeric then raise exception 'inventory_value_out_of_range' using errcode='22003'; end if;
  insert into public.inventory_average_projection(tenant_id,product_id,on_hand_qty,inventory_value,revision,last_event_id) values(p_tenant_id,p_product_id,0,0,1,null) on conflict do nothing;
  select * into v from public.inventory_average_projection where tenant_id=p_tenant_id and product_id=p_product_id for update;
  if v.inventory_value::numeric+v_add>9223372036854775807::numeric then raise exception 'inventory_value_out_of_range' using errcode='22003'; end if;
  update public.inventory_average_projection set on_hand_qty=v.on_hand_qty+p_qty,inventory_value=v.inventory_value+v_add::bigint,revision=v.revision+1,last_event_id=btrim(p_event_id),updated_at=now() where tenant_id=p_tenant_id and product_id=p_product_id;
  insert into public.inventory_product_projection(tenant_id,product_id,on_hand_qty,revision,last_server_sequence) values(p_tenant_id,p_product_id,v.on_hand_qty+p_qty,1,0)
  on conflict (tenant_id,product_id) do update set on_hand_qty=excluded.on_hand_qty,revision=public.inventory_product_projection.revision+1,updated_at=now();
  insert into public.inventory_average_events(tenant_id,event_id,product_id,event_type,quantity_delta,value_delta,business_ref,actor_user_id,device_id,reason)
  values(p_tenant_id,btrim(p_event_id),p_product_id,'receipt',p_qty,v_add::bigint,btrim(p_business_ref),p_actor,btrim(p_device_id),btrim(p_reason));
  return v_add::bigint;
end;
$function$


-- inventory_private.average_receive_value(p_tenant_id uuid, p_product_id uuid, p_qty bigint, p_total_value bigint, p_event_id text, p_business_ref text, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION inventory_private.average_receive_value(p_tenant_id uuid, p_product_id uuid, p_qty bigint, p_total_value bigint, p_event_id text, p_business_ref text, p_actor uuid, p_device_id text, p_reason text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.inventory_average_projection%rowtype; v_existing public.inventory_average_events%rowtype;
begin
  if p_qty is null or p_qty<=0 or p_total_value is null or p_total_value<=0 then raise exception 'invalid_inventory_receipt_value' using errcode='22023'; end if;
  if p_event_id is null or length(btrim(p_event_id))=0 or p_business_ref is null or length(btrim(p_business_ref))=0 then raise exception 'inventory_identity_required' using errcode='22023'; end if;
  if p_actor is null or p_device_id is null or length(btrim(p_device_id))=0 or p_reason is null or length(btrim(p_reason))<3 then raise exception 'inventory_audit_lineage_required' using errcode='22023'; end if;
  if not exists(select 1 from public.product_master p where p.tenant_id=p_tenant_id and p.product_id=p_product_id and p.is_active) then raise exception 'inventory_product_not_active' using errcode='23503'; end if;
  select * into v_existing from public.inventory_average_events where tenant_id=p_tenant_id and event_id=btrim(p_event_id);
  if found then
    if v_existing.product_id=p_product_id and v_existing.event_type='receipt' and v_existing.quantity_delta=p_qty and v_existing.value_delta=p_total_value and v_existing.business_ref=btrim(p_business_ref) then return p_total_value; end if;
    raise exception 'inventory_idempotency_conflict' using errcode='23505';
  end if;
  insert into public.inventory_average_projection(tenant_id,product_id,on_hand_qty,inventory_value,revision,last_event_id) values(p_tenant_id,p_product_id,0,0,1,null) on conflict do nothing;
  select * into v from public.inventory_average_projection where tenant_id=p_tenant_id and product_id=p_product_id for update;
  if v.inventory_value::numeric+p_total_value::numeric>9223372036854775807::numeric then raise exception 'inventory_value_out_of_range' using errcode='22003'; end if;
  update public.inventory_average_projection set on_hand_qty=v.on_hand_qty+p_qty,inventory_value=v.inventory_value+p_total_value,revision=v.revision+1,last_event_id=btrim(p_event_id),updated_at=now() where tenant_id=p_tenant_id and product_id=p_product_id;
  insert into public.inventory_product_projection(tenant_id,product_id,on_hand_qty,revision,last_server_sequence) values(p_tenant_id,p_product_id,v.on_hand_qty+p_qty,1,0)
  on conflict (tenant_id,product_id) do update set on_hand_qty=excluded.on_hand_qty,revision=public.inventory_product_projection.revision+1,updated_at=now();
  insert into public.inventory_average_events(tenant_id,event_id,product_id,event_type,quantity_delta,value_delta,business_ref,actor_user_id,device_id,reason)
  values(p_tenant_id,btrim(p_event_id),p_product_id,'receipt',p_qty,p_total_value,btrim(p_business_ref),p_actor,btrim(p_device_id),btrim(p_reason));
  return p_total_value;
end;
$function$


-- inventory_private.average_restore_original(p_tenant_id uuid, p_product_id uuid, p_qty bigint, p_original_value bigint, p_event_id text, p_business_ref text, p_original_business_ref text, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION inventory_private.average_restore_original(p_tenant_id uuid, p_product_id uuid, p_qty bigint, p_original_value bigint, p_event_id text, p_business_ref text, p_original_business_ref text, p_actor uuid, p_device_id text, p_reason text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v public.inventory_average_projection%rowtype; v_existing public.inventory_average_events%rowtype;
begin
  if p_qty is null or p_qty<=0 or p_original_value is null or p_original_value<=0 then
    raise exception 'invalid_inventory_return' using errcode='22023';
  end if;
  if p_event_id is null or length(btrim(p_event_id))=0 or p_business_ref is null or length(btrim(p_business_ref))=0
     or p_original_business_ref is null or length(btrim(p_original_business_ref))=0 then
    raise exception 'inventory_return_identity_required' using errcode='22023';
  end if;
  if p_actor is null or p_device_id is null or length(btrim(p_device_id))=0 or p_reason is null or length(btrim(p_reason))<3 then
    raise exception 'inventory_audit_lineage_required' using errcode='22023';
  end if;
  select * into v_existing from public.inventory_average_events
  where tenant_id=p_tenant_id and event_id=btrim(p_event_id);
  if found then
    if v_existing.product_id=p_product_id and v_existing.event_type='return'
       and v_existing.quantity_delta=p_qty and v_existing.value_delta=p_original_value
       and v_existing.original_business_ref=btrim(p_original_business_ref) then return p_original_value; end if;
    raise exception 'inventory_idempotency_conflict' using errcode='23505';
  end if;
  insert into public.inventory_average_projection(tenant_id,product_id,on_hand_qty,inventory_value,revision,last_event_id)
  values(p_tenant_id,p_product_id,0,0,1,null) on conflict do nothing;
  select * into v from public.inventory_average_projection
  where tenant_id=p_tenant_id and product_id=p_product_id for update;
  if v.inventory_value::numeric+p_original_value::numeric>9223372036854775807::numeric then
    raise exception 'inventory_value_out_of_range' using errcode='22003';
  end if;
  update public.inventory_average_projection
  set on_hand_qty=v.on_hand_qty+p_qty,inventory_value=v.inventory_value+p_original_value,
      revision=v.revision+1,last_event_id=btrim(p_event_id),updated_at=now()
  where tenant_id=p_tenant_id and product_id=p_product_id;
  insert into public.inventory_product_projection(tenant_id,product_id,on_hand_qty,revision,last_server_sequence)
  values(p_tenant_id,p_product_id,v.on_hand_qty+p_qty,1,0)
  on conflict (tenant_id,product_id) do update
  set on_hand_qty=excluded.on_hand_qty,revision=public.inventory_product_projection.revision+1,updated_at=now();
  insert into public.inventory_average_events(tenant_id,event_id,product_id,event_type,quantity_delta,value_delta,business_ref,original_business_ref,actor_user_id,device_id,reason)
  values(p_tenant_id,btrim(p_event_id),p_product_id,'return',p_qty,p_original_value,btrim(p_business_ref),btrim(p_original_business_ref),p_actor,btrim(p_device_id),btrim(p_reason));
  return p_original_value;
end;
$function$


-- inventory_private.ingest_inventory_component_event(p_tenant_id uuid, p_event_id text, p_event_type text, p_component text, p_product_id uuid, p_lot_id text, p_cost_layer_id text, p_quantity_delta bigint, p_unit_cost bigint, p_business_ref text, p_occurred_at timestamp with time zone, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION inventory_private.ingest_inventory_component_event(p_tenant_id uuid, p_event_id text, p_event_type text, p_component text, p_product_id uuid, p_lot_id text, p_cost_layer_id text, p_quantity_delta bigint, p_unit_cost bigint, p_business_ref text, p_occurred_at timestamp with time zone, p_device_id text, p_app_version text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid(); v_fingerprint jsonb; v_existing_fingerprint jsonb;
  v_existing_sequence bigint; v_sequence bigint;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant','cashier']);
  if p_event_id is null or length(btrim(p_event_id))=0
     or p_business_ref is null or length(btrim(p_business_ref))=0 then
    raise exception using errcode='22023',message='inventory_identity_required';
  end if;
  if p_event_type is null or p_event_type not in ('receipt','sale','adjustment','reversal') then
    raise exception using errcode='22023',message='invalid_inventory_event_type';
  end if;
  if p_component not in ('physical','valuation') then
    raise exception using errcode='22023',message='invalid_inventory_event_component';
  end if;
  if p_component='physical' and (p_lot_id is null or length(btrim(p_lot_id))=0 or p_cost_layer_id is not null) then
    raise exception using errcode='22023',message='invalid_physical_inventory_identity';
  end if;
  if p_component='valuation' and (p_cost_layer_id is null or length(btrim(p_cost_layer_id))=0 or p_lot_id is not null) then
    raise exception using errcode='22023',message='invalid_valuation_inventory_identity';
  end if;
  if p_quantity_delta is null or p_quantity_delta=0 then
    raise exception using errcode='22023',message='inventory_delta_required';
  end if;
  if p_unit_cost is null or p_unit_cost<0 then
    raise exception using errcode='22023',message='invalid_inventory_unit_cost';
  end if;
  if p_occurred_at is null then
    raise exception using errcode='22023',message='inventory_occurred_at_required';
  end if;
  if not exists(select 1 from public.product_master p
    where p.tenant_id=p_tenant_id and p.product_id=p_product_id and p.is_active) then
    raise exception using errcode='23503',message='inventory_product_not_active';
  end if;

  v_fingerprint:=jsonb_build_object(
    'event_type',p_event_type,'component',p_component,'product_id',p_product_id,
    'lot_id',case when p_lot_id is null then null else btrim(p_lot_id) end,
    'cost_layer_id',case when p_cost_layer_id is null then null else btrim(p_cost_layer_id) end,
    'quantity_delta',p_quantity_delta,'unit_cost',p_unit_cost,
    'business_ref',btrim(p_business_ref),'occurred_at',p_occurred_at);
  select e.request_fingerprint,e.server_sequence into v_existing_fingerprint,v_existing_sequence
  from public.inventory_events e where e.tenant_id=p_tenant_id and e.event_id=btrim(p_event_id);
  if found then
    if v_existing_fingerprint<>v_fingerprint then
      raise exception using errcode='23505',message='inventory_idempotency_conflict';
    end if;
    return v_existing_sequence;
  end if;

  insert into public.inventory_events(
    tenant_id,event_id,event_type,event_component,product_id,lot_id,cost_layer_id,
    quantity_delta,unit_cost,business_ref,request_fingerprint,actor_user_id,
    actor_subject,device_id,app_version,occurred_at)
  values(
    p_tenant_id,btrim(p_event_id),p_event_type,p_component,p_product_id,
    case when p_lot_id is null then null else btrim(p_lot_id) end,
    case when p_cost_layer_id is null then null else btrim(p_cost_layer_id) end,
    p_quantity_delta,p_unit_cost,btrim(p_business_ref),v_fingerprint,v_actor,
    v_actor::text,btrim(p_device_id),btrim(p_app_version),p_occurred_at)
  returning server_sequence into v_sequence;

  if p_component='physical' then
    update public.inventory_product_projection
      set on_hand_qty=on_hand_qty+p_quantity_delta,revision=revision+1,
          last_server_sequence=v_sequence,updated_at=now()
      where tenant_id=p_tenant_id and product_id=p_product_id;
    if not found then
      insert into public.inventory_product_projection(tenant_id,product_id,on_hand_qty,revision,last_server_sequence)
      values(p_tenant_id,p_product_id,p_quantity_delta,1,v_sequence);
    end if;

    update public.inventory_lot_projection
      set on_hand_qty=on_hand_qty+p_quantity_delta,revision=revision+1,
          last_server_sequence=v_sequence,updated_at=now()
      where tenant_id=p_tenant_id and lot_id=btrim(p_lot_id) and product_id=p_product_id;
    if not found then
      if exists(select 1 from public.inventory_lot_projection
        where tenant_id=p_tenant_id and lot_id=btrim(p_lot_id)) then
        raise exception using errcode='23514',message='inventory_lot_identity_conflict';
      end if;
      insert into public.inventory_lot_projection(tenant_id,lot_id,product_id,on_hand_qty,revision,last_server_sequence)
      values(p_tenant_id,btrim(p_lot_id),p_product_id,p_quantity_delta,1,v_sequence);
    end if;
  else
    update public.inventory_cost_layer_projection
      set remaining_qty=remaining_qty+p_quantity_delta,revision=revision+1,
          last_server_sequence=v_sequence,updated_at=now()
      where tenant_id=p_tenant_id and cost_layer_id=btrim(p_cost_layer_id)
        and product_id=p_product_id and unit_cost=p_unit_cost;
    if not found then
      if exists(select 1 from public.inventory_cost_layer_projection
        where tenant_id=p_tenant_id and cost_layer_id=btrim(p_cost_layer_id)) then
        raise exception using errcode='23514',message='inventory_cost_layer_identity_conflict';
      end if;
      insert into public.inventory_cost_layer_projection(
        tenant_id,cost_layer_id,lot_id,product_id,remaining_qty,unit_cost,revision,last_server_sequence)
      values(p_tenant_id,btrim(p_cost_layer_id),null,p_product_id,p_quantity_delta,p_unit_cost,1,v_sequence);
    end if;
  end if;
  return v_sequence;
end; $function$


-- inventory_private.ingest_inventory_event(p_tenant_id uuid, p_event_id text, p_event_type text, p_product_id uuid, p_lot_id text, p_cost_layer_id text, p_quantity_delta bigint, p_unit_cost bigint, p_business_ref text, p_occurred_at timestamp with time zone, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION inventory_private.ingest_inventory_event(p_tenant_id uuid, p_event_id text, p_event_type text, p_product_id uuid, p_lot_id text, p_cost_layer_id text, p_quantity_delta bigint, p_unit_cost bigint, p_business_ref text, p_occurred_at timestamp with time zone, p_device_id text, p_app_version text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid:=auth.uid(); v_fingerprint jsonb; v_existing_fingerprint jsonb;
  v_existing_sequence bigint; v_sequence bigint;
begin
  perform accounting_private.require_bound_device(v_actor,p_device_id,p_app_version);
  perform accounting_private.require_member_role(p_tenant_id,v_actor,array['owner','admin','accountant','cashier']);
  if p_event_id is null or length(btrim(p_event_id))=0
     or p_lot_id is null or length(btrim(p_lot_id))=0
     or p_cost_layer_id is null or length(btrim(p_cost_layer_id))=0
     or p_business_ref is null or length(btrim(p_business_ref))=0 then
    raise exception using errcode='22023',message='inventory_identity_required';
  end if;
  if p_event_type is null or p_event_type not in ('receipt','sale','adjustment','reversal') then
    raise exception using errcode='22023',message='invalid_inventory_event_type';
  end if;
  if p_quantity_delta is null or p_quantity_delta=0 then
    raise exception using errcode='22023',message='inventory_delta_required';
  end if;
  if p_unit_cost is null or p_unit_cost<0 then
    raise exception using errcode='22023',message='invalid_inventory_unit_cost';
  end if;
  if p_occurred_at is null then
    raise exception using errcode='22023',message='inventory_occurred_at_required';
  end if;
  if not exists(select 1 from public.product_master p
    where p.tenant_id=p_tenant_id and p.product_id=p_product_id and p.is_active) then
    raise exception using errcode='23503',message='inventory_product_not_active';
  end if;
  v_fingerprint:=jsonb_build_object(
    'event_type',p_event_type,'product_id',p_product_id,'lot_id',btrim(p_lot_id),
    'cost_layer_id',btrim(p_cost_layer_id),'quantity_delta',p_quantity_delta,
    'unit_cost',p_unit_cost,'business_ref',btrim(p_business_ref),'occurred_at',p_occurred_at);
  select e.request_fingerprint,e.server_sequence into v_existing_fingerprint,v_existing_sequence
  from public.inventory_events e where e.tenant_id=p_tenant_id and e.event_id=btrim(p_event_id);
  if found then
    if v_existing_fingerprint<>v_fingerprint then
      raise exception using errcode='23505',message='inventory_idempotency_conflict';
    end if;
    return v_existing_sequence;
  end if;
  insert into public.inventory_events(
    tenant_id,event_id,event_type,product_id,lot_id,cost_layer_id,quantity_delta,unit_cost,
    business_ref,request_fingerprint,actor_user_id,actor_subject,device_id,app_version,occurred_at)
  values(p_tenant_id,btrim(p_event_id),p_event_type,p_product_id,btrim(p_lot_id),btrim(p_cost_layer_id),
    p_quantity_delta,p_unit_cost,btrim(p_business_ref),v_fingerprint,v_actor,v_actor::text,
    btrim(p_device_id),btrim(p_app_version),p_occurred_at)
  returning server_sequence into v_sequence;
  update public.inventory_product_projection
  set on_hand_qty=on_hand_qty+p_quantity_delta,
      revision=revision+1,last_server_sequence=v_sequence,updated_at=now()
  where tenant_id=p_tenant_id and product_id=p_product_id;
  if not found then
    insert into public.inventory_product_projection(
      tenant_id,product_id,on_hand_qty,revision,last_server_sequence)
    values(p_tenant_id,p_product_id,p_quantity_delta,1,v_sequence);
  end if;

  update public.inventory_lot_projection
  set on_hand_qty=on_hand_qty+p_quantity_delta,
      revision=revision+1,last_server_sequence=v_sequence,updated_at=now()
  where tenant_id=p_tenant_id and lot_id=btrim(p_lot_id) and product_id=p_product_id;
  if not found then
    if exists(select 1 from public.inventory_lot_projection
      where tenant_id=p_tenant_id and lot_id=btrim(p_lot_id)) then
      raise exception using errcode='23514',message='inventory_lot_identity_conflict';
    end if;
    insert into public.inventory_lot_projection(
      tenant_id,lot_id,product_id,on_hand_qty,revision,last_server_sequence)
    values(p_tenant_id,btrim(p_lot_id),p_product_id,p_quantity_delta,1,v_sequence);
  end if;

  update public.inventory_cost_layer_projection
  set remaining_qty=remaining_qty+p_quantity_delta,
      revision=revision+1,last_server_sequence=v_sequence,updated_at=now()
  where tenant_id=p_tenant_id and cost_layer_id=btrim(p_cost_layer_id)
    and product_id=p_product_id and lot_id=btrim(p_lot_id) and unit_cost=p_unit_cost;
  if not found then
    if exists(select 1 from public.inventory_cost_layer_projection
      where tenant_id=p_tenant_id and cost_layer_id=btrim(p_cost_layer_id)) then
      raise exception using errcode='23514',message='inventory_cost_layer_identity_conflict';
    end if;
    insert into public.inventory_cost_layer_projection(
      tenant_id,cost_layer_id,lot_id,product_id,remaining_qty,unit_cost,revision,last_server_sequence)
    values(p_tenant_id,btrim(p_cost_layer_id),btrim(p_lot_id),p_product_id,p_quantity_delta,p_unit_cost,1,v_sequence);
  end if;
  return v_sequence;
end; $function$


-- inventory_private.reject_event_mutation()
CREATE OR REPLACE FUNCTION inventory_private.reject_event_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception using errcode='55000', message='immutable_inventory_event';
end; $function$


-- private.assert_accounting_hard_gate(p_tenant_id uuid)
CREATE OR REPLACE FUNCTION private.assert_accounting_hard_gate(p_tenant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  v:=private.compute_accounting_hard_gate(p_tenant_id);
  if coalesce((v->>'all_zero')::boolean,false) is not true then
    raise exception 'accounting_tax_hard_gate_failed: %',v using errcode='23514';
  end if;
end;
$function$


-- private.assert_app_config_inventory()
CREATE OR REPLACE FUNCTION private.assert_app_config_inventory()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_count integer;
  v_digest text;
begin
  select count(*)::integer, md5(string_agg(key, E'\n' order by key))
    into v_count, v_digest
  from public.app_config;

  if v_count <> 352 or v_digest <> '1fd3d64219ecc7c333453c20da80e295' then
    raise exception 'app_config inventory mismatch: count %, digest %', v_count, v_digest
      using errcode = '23514';
  end if;
end;
$function$


-- private.assert_no_accounting_fields(p_value jsonb)
CREATE OR REPLACE FUNCTION private.assert_no_accounting_fields(p_value jsonb)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_key text;
  v_child jsonb;
begin
  if p_value is null then
    raise exception 'facts_must_be_object' using errcode='22023';
  end if;

  if jsonb_typeof(p_value)='object' then
    for v_key,v_child in select key,value from jsonb_each(p_value)
    loop
      if lower(v_key) in ('account_code','debit','cogs','tax_amount') then
        raise exception 'economic_fact_injection_blocked' using errcode='42501';
      end if;
      if lower(v_key) in (
        'credit','journal_lines','lines_accounting',
        'tax_rate','ppn_rate','pph_rate','statutory_rate','effective_rate','dpp_multiplier'
      ) then
        raise exception 'operator facts cannot contain account/debit/credit/rate overrides'
          using errcode='42501';
      end if;
      if jsonb_typeof(v_child) in ('object','array') then
        perform private.assert_no_accounting_fields(v_child);
      end if;
    end loop;
  elsif jsonb_typeof(p_value)='array' then
    for v_child in select value from jsonb_array_elements(p_value)
    loop
      if jsonb_typeof(v_child) in ('object','array') then
        perform private.assert_no_accounting_fields(v_child);
      end if;
    end loop;
  else
    raise exception 'facts_must_be_object' using errcode='22023';
  end if;
end;
$function$

