-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source. PL/pgSQL bodies are installed before SQL-language wrappers.

-- private.guard_tenant_accounting_link()
CREATE OR REPLACE FUNCTION private.guard_tenant_accounting_link()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_overlap boolean;
begin
  if current_user<>'postgres' then
    raise exception 'tenant accounting link direct mutation denied' using errcode='42501';
  end if;
  if tg_op='DELETE' then
    raise exception 'tenant accounting link history is immutable; close with valid_to' using errcode='55000';
  end if;
  if new.valid_to is not null and new.valid_to<new.valid_from then
    raise exception 'invalid tenant accounting link period' using errcode='23514';
  end if;
  if tg_op='UPDATE' and old.valid_from<=current_date then
    if (old.link_id,old.config_tenant_id,old.accounting_tenant_id,old.valid_from,old.actor_user_id,old.device_id,old.reason,old.created_at)
       is distinct from
       (new.link_id,new.config_tenant_id,new.accounting_tenant_id,new.valid_from,new.actor_user_id,new.device_id,new.reason,new.created_at) then
      raise exception 'historical tenant accounting link is immutable' using errcode='55000';
    end if;
    if old.valid_to is not null and new.valid_to is distinct from old.valid_to then
      raise exception 'closed tenant accounting link is immutable' using errcode='55000';
    end if;
    if old.valid_to is null and new.valid_to is not null and new.valid_to<current_date then
      raise exception 'tenant accounting link cannot close retroactively' using errcode='55000';
    end if;
  end if;

  select exists(
    select 1 from private.tenant_accounting_links l
    where l.link_id<>new.link_id
      and (l.config_tenant_id=new.config_tenant_id or l.accounting_tenant_id=new.accounting_tenant_id)
      and daterange(l.valid_from,coalesce(l.valid_to+1,'infinity'::date),'[)')
          && daterange(new.valid_from,coalesce(new.valid_to+1,'infinity'::date),'[)')
  ) into v_overlap;
  if v_overlap then
    raise exception 'overlapping tenant accounting link' using errcode='23514';
  end if;
  return new;
end;
$function$;
-- private.guard_vat_document_closed_period_insert()
CREATE OR REPLACE FUNCTION private.guard_vat_document_closed_period_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.document_type in ('VAT_OUTPUT','VAT_INPUT','VAT_RETURN','VAT_REPLACEMENT','VAT_CANCELLATION')
     and exists(select 1 from public.vat_period_settlements s where s.tenant_id=new.tenant_id and new.business_date between s.period_start and s.period_end) then
    raise exception 'vat_period_already_settled_use_period_correction_workflow' using errcode='55000';
  end if;
  return new;
end; $function$;
-- private.guard_vat_period_settlement_immutable()
CREATE OR REPLACE FUNCTION private.guard_vat_period_settlement_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ begin raise exception 'VAT period settlement is immutable' using errcode='55000'; end; $function$;
-- private.populate_tax_document_lines()
CREATE OR REPLACE FUNCTION private.populate_tax_document_lines()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.document_type in ('VAT_OUTPUT','VAT_REPLACEMENT') then
    insert into public.tax_document_lines(
      tax_document_id,tenant_id,line_key,line_kind,item_code,item_name,quantity,unit_price,list_amount,discount_amount,
      dpp,tax_amount,gross_amount,tax_object_code,tax_rule_snapshot
    )
    select new.tax_document_id,s.tenant_id,s.line_key,s.line_kind,s.item_code,s.item_name,s.quantity,s.unit_price,s.list_amount,s.discount_amount,
           s.dpp,s.vat_amount,s.gross_amount,coalesce(s.tax_object_code,'NON_LUXURY'),s.tax_snapshot
    from public.sale_line_evidence s
    where s.tenant_id=new.tenant_id and s.transaction_ref=new.transaction_ref and s.taxable;
  elsif new.document_type='VAT_RETURN' and new.reference_document_id is not null then
    insert into public.tax_document_lines(
      tax_document_id,tenant_id,line_key,line_kind,item_code,item_name,quantity,unit_price,list_amount,discount_amount,
      dpp,tax_amount,gross_amount,tax_object_code,tax_rule_snapshot
    )
    select new.tax_document_id,o.tenant_id,r.line_key,o.line_kind,o.item_code,o.item_name,r.quantity,o.unit_price,
           round(o.list_amount::numeric*r.quantity::numeric/o.quantity::numeric)::bigint,
           greatest(round(o.discount_amount::numeric*r.quantity::numeric/o.quantity::numeric)::bigint,0),
           r.dpp_reversed,r.vat_reversed,r.dpp_reversed+r.vat_reversed,coalesce(o.tax_object_code,'NON_LUXURY'),o.tax_snapshot
    from public.sale_return_line_evidence r
    join public.sale_line_evidence o
      on o.tenant_id=r.tenant_id and o.transaction_ref=r.original_transaction_ref and o.line_key=r.line_key
    where r.tenant_id=new.tenant_id and r.return_transaction_ref=new.transaction_ref and o.taxable;
  end if;
  return new;
end;
$function$;
-- private.pph21_article17_tax(p_taxable_income bigint)
CREATE OR REPLACE FUNCTION private.pph21_article17_tax(p_taxable_income bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_remaining bigint:=greatest(coalesce(p_taxable_income,0),0);
  v_tax numeric:=0;
begin
  v_tax:=v_tax+least(v_remaining,60000000)::numeric*0.05;
  v_remaining:=greatest(v_remaining-60000000,0);
  v_tax:=v_tax+least(v_remaining,190000000)::numeric*0.15;
  v_remaining:=greatest(v_remaining-190000000,0);
  v_tax:=v_tax+least(v_remaining,250000000)::numeric*0.25;
  v_remaining:=greatest(v_remaining-250000000,0);
  v_tax:=v_tax+least(v_remaining,4500000000)::numeric*0.30;
  v_remaining:=greatest(v_remaining-4500000000,0);
  v_tax:=v_tax+v_remaining::numeric*0.35;
  return round(v_tax)::bigint;
end;
$function$;
-- private.pph21_periodic_calc(p_category text, p_cash_compensation bigint, p_tax_method text, p_business_date date)
CREATE OR REPLACE FUNCTION private.pph21_periodic_calc(p_category text, p_cash_compensation bigint, p_tax_method text, p_business_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_method text:=upper(btrim(coalesce(p_tax_method,'')));
  v_allowance bigint:=0;
  v_new_allowance bigint:=0;
  v_gross bigint;
  v_tax bigint;
  v_rule jsonb;
  v_i integer;
begin
  if p_cash_compensation is null or p_cash_compensation<=0 or p_business_date is null then
    raise exception 'invalid_periodic_payroll_input' using errcode='22023';
  end if;
  if v_method='EMPLOYEE_BORNE' then
    v_gross:=p_cash_compensation;
    v_rule:=private.resolve_pph21_ter(p_category,v_gross,p_business_date);
    v_tax:=round(v_gross::numeric*(v_rule->>'rate')::numeric)::bigint;
    return jsonb_build_object(
      'taxable_gross',v_gross,'tax_allowance',0,'withholding_adjustment',v_tax,
      'rule',v_rule,'method','TER_PERIODIC_EMPLOYEE_BORNE'
    );
  elsif v_method<>'GROSS_UP' then
    raise exception 'invalid_pph21_tax_method' using errcode='22023';
  end if;

  for v_i in 1..100 loop
    if p_cash_compensation::numeric+v_allowance::numeric>9223372036854775807::numeric then
      raise exception 'payroll_value_out_of_range' using errcode='22003';
    end if;
    v_gross:=p_cash_compensation+v_allowance;
    v_rule:=private.resolve_pph21_ter(p_category,v_gross,p_business_date);
    v_new_allowance:=round(v_gross::numeric*(v_rule->>'rate')::numeric)::bigint;
    if v_new_allowance=v_allowance then
      return jsonb_build_object(
        'taxable_gross',v_gross,'tax_allowance',v_allowance,'withholding_adjustment',v_allowance,
        'rule',v_rule,'method','TER_PERIODIC_GROSS_UP','iterations',v_i
      );
    end if;
    v_allowance:=v_new_allowance;
  end loop;
  raise exception 'pph21_gross_up_did_not_converge' using errcode='23514';
end;
$function$;
-- private.pph21_ptkp_amount(p_marital_status text, p_dependents integer)
CREATE OR REPLACE FUNCTION private.pph21_ptkp_amount(p_marital_status text, p_dependents integer)
 RETURNS bigint
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v_status text:=upper(btrim(coalesce(p_marital_status,'')));
begin
  if v_status not in ('TK','K') or p_dependents is null or p_dependents<0 or p_dependents>3 then
    raise exception 'invalid_ptkp_status' using errcode='22023';
  end if;
  return 54000000
    + case when v_status='K' then 4500000 else 0 end
    + (p_dependents::bigint*4500000);
end;
$function$;
-- private.pph21_ptkp_status(p_marital_status text, p_dependents integer)
CREATE OR REPLACE FUNCTION private.pph21_ptkp_status(p_marital_status text, p_dependents integer)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v_status text:=upper(btrim(coalesce(p_marital_status,'')));
begin
  if v_status not in ('TK','K') or p_dependents is null or p_dependents<0 or p_dependents>3 then
    raise exception 'invalid_ptkp_status' using errcode='22023';
  end if;
  return v_status||'/'||p_dependents::text;
end;
$function$;
-- private.reject_tax_evidence_mutation()
CREATE OR REPLACE FUNCTION private.reject_tax_evidence_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$ begin raise exception 'immutable_tax_or_transaction_evidence' using errcode='55000'; end $function$;
-- private.resolve_pph21_ter(p_category text, p_monthly_gross bigint, p_business_date date)
CREATE OR REPLACE FUNCTION private.resolve_pph21_ter(p_category text, p_monthly_gross bigint, p_business_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_count int; v public.tax_rate_brackets%rowtype;
begin
  if p_category not in ('A','B','C') or p_monthly_gross is null or p_monthly_gross<0 or p_business_date is null then
    raise exception 'invalid_pph21_ter_input' using errcode='22023';
  end if;
  select count(*) into v_count from public.tax_rate_brackets b
  where b.tax_code='PPH21_TER' and b.category=p_category
    and b.lower_bound<=p_monthly_gross and (b.upper_bound is null or b.upper_bound>=p_monthly_gross)
    and b.effective_date<=p_business_date and (b.end_date is null or b.end_date>=p_business_date);
  if v_count<>1 then raise exception 'effective_pph21_ter_rule_ambiguity' using errcode='23514'; end if;
  select * into strict v from public.tax_rate_brackets b
  where b.tax_code='PPH21_TER' and b.category=p_category
    and b.lower_bound<=p_monthly_gross and (b.upper_bound is null or b.upper_bound>=p_monthly_gross)
    and b.effective_date<=p_business_date and (b.end_date is null or b.end_date>=p_business_date);
  return jsonb_build_object(
    'tax_code','PPH21_TER','category',v.category,'lower_bound',v.lower_bound,'upper_bound',v.upper_bound,
    'rate',v.rate,'effective_date',v.effective_date,'end_date',v.end_date,'legal_basis',v.legal_basis
  );
end;
$function$;
-- private.resolve_tax_rate_snapshot(p_tax_code text, p_object_code text, p_business_date date, p_category text)
CREATE OR REPLACE FUNCTION private.resolve_tax_rate_snapshot(p_tax_code text, p_object_code text, p_business_date date, p_category text DEFAULT 'DEFAULT'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_count int; v_id uuid; v_row public.tax_rates%rowtype;
begin
  if p_business_date is null then raise exception 'business_date_required' using errcode='22023'; end if;
  select count(*) into v_count
  from public.tax_rates
  where tax_code=p_tax_code and object_code=p_object_code and category=p_category
    and effective_date<=p_business_date and (end_date is null or end_date>=p_business_date);
  if v_count<>1 then raise exception 'effective_tax_rule_ambiguity' using errcode='23514'; end if;
  select tax_rate_id into strict v_id
  from public.tax_rates
  where tax_code=p_tax_code and object_code=p_object_code and category=p_category
    and effective_date<=p_business_date and (end_date is null or end_date>=p_business_date);
  select * into strict v_row from public.tax_rates where tax_rate_id=v_id;
  return jsonb_build_object(
    'tax_rate_id',v_row.tax_rate_id,'tax_code',v_row.tax_code,'object_code',v_row.object_code,
    'category',v_row.category,'statutory_rate',v_row.statutory_rate,'dpp_multiplier',v_row.dpp_multiplier,
    'effective_rate',v_row.effective_rate,'calculation_method',v_row.calculation_method,
    'effective_date',v_row.effective_date,'end_date',v_row.end_date,'legal_basis',v_row.legal_basis,
    'metadata',v_row.metadata
  );
end;
$function$;
-- private.resolve_ter_category(p_marital_status text, p_dependents integer)
CREATE OR REPLACE FUNCTION private.resolve_ter_category(p_marital_status text, p_dependents integer)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v text:=upper(btrim(coalesce(p_marital_status,'')));
begin
  if p_dependents is null or p_dependents<0 or p_dependents>3 or v not in ('TK','K') then raise exception 'invalid_ptkp_status' using errcode='22023'; end if;
  if (v='TK' and p_dependents in (0,1)) or (v='K' and p_dependents=0) then return 'A'; end if;
  if (v='TK' and p_dependents in (2,3)) or (v='K' and p_dependents in (1,2)) then return 'B'; end if;
  if v='K' and p_dependents=3 then return 'C'; end if;
  raise exception 'invalid_ptkp_status' using errcode='22023';
end;
$function$;