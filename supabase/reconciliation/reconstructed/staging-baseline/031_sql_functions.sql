-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source. SQL-language functions are dependency-sorted using pg_depend.

-- private.apply_sale_avg(p_tenant_id uuid, p_product_id uuid, p_qty bigint, p_event_id text, p_business_ref text, p_actor uuid, p_device_id text, p_reason text)
CREATE OR REPLACE FUNCTION private.apply_sale_avg(p_tenant_id uuid, p_product_id uuid, p_qty bigint, p_event_id text, p_business_ref text, p_actor uuid, p_device_id text, p_reason text)
 RETURNS bigint
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  SELECT inventory_private.average_consume(
    p_tenant_id, p_product_id, p_qty, p_event_id, p_business_ref,
    p_actor, p_device_id, p_reason
  );
$function$;
-- private.btp_is_super_admin()
CREATE OR REPLACE FUNCTION private.btp_is_super_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    auth.uid() = '49abb5d4-8616-45d3-b2cb-8e0dcb72f100'::uuid
    and lower(coalesce(auth.jwt()->>'email','')) = 'berkahtigaputeri@gmail.com';
$function$;
-- private.can_read_final_pos_config_strict(config_key text)
CREATE OR REPLACE FUNCTION private.can_read_final_pos_config_strict(config_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    config_key ~ '^device:[^:]+$'
    and auth.uid() is not null
    and exists (
      select 1
      from public.devices d
      where d.device_id = split_part(config_key, ':', 2)
        and d.user_id = auth.uid()
    );
$function$;
-- private.corporate_commercial_profit_before_tax(p_tenant_id uuid, p_tax_year integer)
CREATE OR REPLACE FUNCTION private.corporate_commercial_profit_before_tax(p_tenant_id uuid, p_tax_year integer)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(sum(case
    when c.account_type='Pendapatan' then l.credit-l.debit
    when c.account_type in ('HPP','Beban') and l.account_code not in ('6-6110','6-6120') then -(l.debit-l.credit)
    else 0 end),0)::bigint
  from public.accounting_journal_lines l
  join public.accounting_journals j on j.tenant_id=l.tenant_id and j.journal_id=l.journal_id
  join public.accounting_coa c on c.account_code=l.account_code
  where l.tenant_id=p_tenant_id and extract(year from j.journal_date)::integer=p_tax_year;
$function$;
-- private.corporate_gross_turnover_between(p_tenant_id uuid, p_from date, p_to date)
CREATE OR REPLACE FUNCTION private.corporate_gross_turnover_between(p_tenant_id uuid, p_from date, p_to date)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with base_lines as (
    select s.tenant_id,s.transaction_ref,s.line_key,s.quantity,s.list_amount,s.taxable,s.tax_snapshot,e.business_date,e.facts_snapshot,
      case when s.taxable and coalesce((e.facts_snapshot->>'prices_include_vat')::boolean,false)
        then round(s.list_amount::numeric/(1+coalesce((s.tax_snapshot->>'effective_rate')::numeric,0)))::bigint
        else s.list_amount end as gross_before_discount_ex_vat
    from public.sale_line_evidence s
    join public.accounting_transaction_evidence e on e.tenant_id=s.tenant_id and e.transaction_ref=s.transaction_ref
    where s.tenant_id=p_tenant_id and e.transaction_type in ('JUAL_TUNAI','JUAL_QRIS','JUAL_TRANSFER','JUAL_KREDIT')
  ), sales_period as (
    select * from base_lines where business_date between p_from and p_to
  ), returns_period as (
    select r.tenant_id,r.original_transaction_ref,r.line_key,er.business_date as return_date,
      round(bl.gross_before_discount_ex_vat::numeric*r.quantity::numeric/bl.quantity::numeric)::bigint as gross_reversed
    from public.sale_return_line_evidence r
    join public.accounting_transaction_evidence er on er.tenant_id=r.tenant_id and er.transaction_ref=r.return_transaction_ref
    join base_lines bl on bl.tenant_id=r.tenant_id and bl.transaction_ref=r.original_transaction_ref and bl.line_key=r.line_key
    where r.tenant_id=p_tenant_id and er.business_date between p_from and p_to
  )
  select greatest(coalesce((select sum(gross_before_discount_ex_vat) from sales_period),0)-coalesce((select sum(gross_reversed) from returns_period),0),0)::bigint;
$function$;
-- private.is_pos_owner(p_tenant_id text)
CREATE OR REPLACE FUNCTION private.is_pos_owner(p_tenant_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1
    from public.pos_memberships m
    where m.tenant_id = p_tenant_id
      and m.user_id = (select auth.uid())
      and m.role = 'owner'
      and m.is_active = true
  );
$function$;
-- private.is_pph_final_umkm_evidence_valid(p_tax_regime text, p_taxpayer_type text, p_turnover_eligibility boolean, p_certificate_status text, p_legal_basis text, p_business_date date)
CREATE OR REPLACE FUNCTION private.is_pph_final_umkm_evidence_valid(p_tax_regime text, p_taxpayer_type text, p_turnover_eligibility boolean, p_certificate_status text, p_legal_basis text, p_business_date date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select
    upper(coalesce(p_tax_regime,''))='PPH_FINAL_UMKM'
    and p_business_date >= date '2026-04-22'
    and upper(coalesce(p_taxpayer_type,'')) in ('OP','PT_PERORANGAN','KOPERASI')
    and coalesce(p_turnover_eligibility,false)
    and upper(coalesce(p_certificate_status,''))='VALID'
    and length(btrim(coalesce(p_legal_basis,'')))>=3;
$function$;
-- private.strip_legacy_tax_config(p_value jsonb)
CREATE OR REPLACE FUNCTION private.strip_legacy_tax_config(p_value jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
  from jsonb_each(coalesce(p_value, '{}'::jsonb)) e
  where lower(e.key) not in (
    'ppn', 'ppn rate %', 'ppn account', 'dpp',
    'pph21', 'pph 21', 'pph23', 'pph 23', 'pph final', 'tax rate', 'tax_rate'
  );
$function$;
-- private.umkm_gross_turnover_between(p_tenant_id uuid, p_from date, p_to date)
CREATE OR REPLACE FUNCTION private.umkm_gross_turnover_between(p_tenant_id uuid, p_from date, p_to date)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with base_lines as (
    select
      s.tenant_id,s.transaction_ref,s.line_key,s.line_kind,s.service_profile_id,s.quantity,s.list_amount,s.taxable,s.tax_snapshot,
      e.business_date,e.facts_snapshot,
      case when s.line_kind='SERVICE' then coalesce(sp.umkm_final_eligible,false) else true end as umkm_eligible,
      case
        when s.taxable and coalesce((e.facts_snapshot->>'prices_include_vat')::boolean,false)
          then round(s.list_amount::numeric/(1+coalesce((s.tax_snapshot->>'effective_rate')::numeric,0)))::bigint
        else s.list_amount
      end as gross_before_discount_ex_vat
    from public.sale_line_evidence s
    join public.accounting_transaction_evidence e on e.tenant_id=s.tenant_id and e.transaction_ref=s.transaction_ref
    left join public.service_tax_profiles sp on sp.tenant_id=s.tenant_id and sp.service_profile_id=s.service_profile_id
    where s.tenant_id=p_tenant_id and e.transaction_type in ('JUAL_TUNAI','JUAL_QRIS','JUAL_TRANSFER','JUAL_KREDIT')
  ), sales_period as (
    select * from base_lines where business_date between p_from and p_to
  ), returns_period as (
    select r.tenant_id,r.original_transaction_ref,r.line_key,er.business_date as return_date,
           round(bl.gross_before_discount_ex_vat::numeric*r.quantity::numeric/bl.quantity::numeric)::bigint as gross_reversed,
           bl.umkm_eligible
    from public.sale_return_line_evidence r
    join public.accounting_transaction_evidence er on er.tenant_id=r.tenant_id and er.transaction_ref=r.return_transaction_ref
    join base_lines bl on bl.tenant_id=r.tenant_id and bl.transaction_ref=r.original_transaction_ref and bl.line_key=r.line_key
    where r.tenant_id=p_tenant_id and er.business_date between p_from and p_to
  )
  select greatest(
    coalesce((select sum(gross_before_discount_ex_vat) from sales_period where umkm_eligible),0)
    - coalesce((select sum(gross_reversed) from returns_period where umkm_eligible),0),0
  )::bigint;
$function$;
-- private.verify_coretax_template()
CREATE OR REPLACE FUNCTION private.verify_coretax_template()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT (
    SELECT count(*) = 3
    FROM (VALUES ('FAKTUR_KELUARAN'), ('BPPU'), ('BPMP')) AS required(template_code)
    WHERE EXISTS (
      SELECT 1
      FROM public.coretax_template_registry AS t
      WHERE t.template_code = required.template_code
        AND t.is_active IS TRUE
        AND t.is_verified IS TRUE
        AND t.xml_template IS NOT NULL
        AND length(btrim(t.xml_template)) >= 20
        AND t.template_sha256 ~ '^[0-9a-f]{64}$'
        AND t.template_sha256 = encode(
          extensions.digest(convert_to(t.xml_template, 'UTF8'), 'sha256'),
          'hex'
        )
        AND coalesce(t.generator_spec ->> 'status', '') <> 'SOURCE_REGISTERED_NOT_PARSED'
    )
  );
$function$;
-- public.close_accounting_period(p_tenant_id uuid, p_period_start date, p_period_end date, p_reason text, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.close_accounting_period(p_tenant_id uuid, p_period_start date, p_period_end date, p_reason text, p_device_id text, p_app_version text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select accounting_private.close_period(
    p_tenant_id, p_period_start, p_period_end,
    p_reason, p_device_id, p_app_version
  );
$function$;
-- public.create_accounting_tenant(p_name text, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.create_accounting_tenant(p_name text, p_device_id text, p_app_version text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select accounting_private.create_tenant(p_name, p_device_id, p_app_version);
$function$;
-- public.get_compliance_readiness(p_tenant_id uuid, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.get_compliance_readiness(p_tenant_id uuid, p_device_id text, p_app_version text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select public.get_compliance_readiness(
    p_tenant_id,
    current_date,
    p_device_id,
    p_app_version
  );
$function$;
-- public.get_hardening_migration_manifest()
CREATE OR REPLACE FUNCTION public.get_hardening_migration_manifest()
 RETURNS TABLE(version text, name text, sql_bytes bigint, sql_sha256 text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select m.version::text,
         m.name::text,
         octet_length(array_to_string(m.statements,E'\n\n'))::bigint,
         encode(extensions.digest(convert_to(array_to_string(m.statements,E'\n\n'),'UTF8'),'sha256'),'hex')::text
  from supabase_migrations.schema_migrations m
  where m.version >= '20261008231304'
  order by m.version;
$function$;
-- public.get_license_private_key()
CREATE OR REPLACE FUNCTION public.get_license_private_key()
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select decrypted_secret
  from vault.decrypted_secrets
  where name = 'berkahtigaputeri_license_private_key'
  order by updated_at desc
  limit 1
$function$;
-- public.get_pos_role(p_device_id text)
CREATE OR REPLACE FUNCTION public.get_pos_role(p_device_id text)
 RETURNS text
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.get_pos_role_internal(p_device_id); $function$;
-- public.ingest_inventory_component_event(p_tenant_id uuid, p_event_id text, p_event_type text, p_component text, p_product_id uuid, p_lot_id text, p_cost_layer_id text, p_quantity_delta bigint, p_unit_cost bigint, p_business_ref text, p_occurred_at timestamp with time zone, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.ingest_inventory_component_event(p_tenant_id uuid, p_event_id text, p_event_type text, p_component text, p_product_id uuid, p_lot_id text, p_cost_layer_id text, p_quantity_delta bigint, p_unit_cost bigint, p_business_ref text, p_occurred_at timestamp with time zone, p_device_id text, p_app_version text)
 RETURNS bigint
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select inventory_private.ingest_inventory_component_event(
    p_tenant_id,p_event_id,p_event_type,p_component,p_product_id,p_lot_id,p_cost_layer_id,
    p_quantity_delta,p_unit_cost,p_business_ref,p_occurred_at,p_device_id,p_app_version);
$function$;
-- public.ingest_inventory_event(p_tenant_id uuid, p_event_id text, p_event_type text, p_product_id uuid, p_lot_id text, p_cost_layer_id text, p_quantity_delta bigint, p_unit_cost bigint, p_business_ref text, p_occurred_at timestamp with time zone, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.ingest_inventory_event(p_tenant_id uuid, p_event_id text, p_event_type text, p_product_id uuid, p_lot_id text, p_cost_layer_id text, p_quantity_delta bigint, p_unit_cost bigint, p_business_ref text, p_occurred_at timestamp with time zone, p_device_id text, p_app_version text)
 RETURNS bigint
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select inventory_private.ingest_inventory_event(
    p_tenant_id,p_event_id,p_event_type,p_product_id,p_lot_id,p_cost_layer_id,
    p_quantity_delta,p_unit_cost,p_business_ref,p_occurred_at,p_device_id,p_app_version);
$function$;
-- public.post_accounting_journal(p_tenant_id uuid, p_idempotency_key text, p_transaction_ref text, p_journal_date date, p_description text, p_source_type text, p_lines jsonb, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.post_accounting_journal(p_tenant_id uuid, p_idempotency_key text, p_transaction_ref text, p_journal_date date, p_description text, p_source_type text, p_lines jsonb, p_device_id text, p_app_version text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select accounting_private.post_journal(
    p_tenant_id, p_idempotency_key, p_transaction_ref, p_journal_date,
    p_description, p_source_type, p_lines, p_device_id, p_app_version
  );
$function$;
-- public.reopen_accounting_period(p_tenant_id uuid, p_period_id uuid, p_reason text, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.reopen_accounting_period(p_tenant_id uuid, p_period_id uuid, p_reason text, p_device_id text, p_app_version text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select accounting_private.reopen_period(
    p_tenant_id, p_period_id, p_reason, p_device_id, p_app_version
  );
$function$;
-- public.reverse_accounting_journal(p_tenant_id uuid, p_original_journal_id uuid, p_idempotency_key text, p_journal_date date, p_reason text, p_device_id text, p_app_version text)
CREATE OR REPLACE FUNCTION public.reverse_accounting_journal(p_tenant_id uuid, p_original_journal_id uuid, p_idempotency_key text, p_journal_date date, p_reason text, p_device_id text, p_app_version text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select accounting_private.reverse_journal(
    p_tenant_id, p_original_journal_id, p_idempotency_key, p_journal_date,
    p_reason, p_device_id, p_app_version
  );
$function$;
-- public.verify_manager_pin(p_device_id text, p_outlet_id text, p_pin text, p_required_action text)
CREATE OR REPLACE FUNCTION public.verify_manager_pin(p_device_id text, p_outlet_id text, p_pin text, p_required_action text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.verify_manager_pin_internal(p_device_id, p_outlet_id, p_pin, p_required_action); $function$;