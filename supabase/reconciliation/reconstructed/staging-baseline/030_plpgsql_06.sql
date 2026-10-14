-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; generated from pg_get_functiondef.
-- NOT historical migration source. PL/pgSQL bodies are installed before SQL-language wrappers.

-- private.guard_corporate_tax_history_immutable()
CREATE OR REPLACE FUNCTION private.guard_corporate_tax_history_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ begin raise exception 'corporate tax history is immutable; post a correction/version instead' using errcode='55000'; end; $function$


-- private.guard_customer_withholding_credit_immutable()
CREATE OR REPLACE FUNCTION private.guard_customer_withholding_credit_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ begin raise exception 'customer withholding tax credit evidence is immutable' using errcode='55000'; end; $function$


-- private.guard_domain_journal_reversal()
CREATE OR REPLACE FUNCTION private.guard_domain_journal_reversal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_type text;
begin
  if new.source_type='reversal' and new.reversal_of is not null then
    select e.transaction_type into v_type
    from public.accounting_transaction_evidence e
    where e.tenant_id=new.tenant_id and e.journal_id=new.reversal_of;
    if found and v_type in (
      'JUAL_TUNAI','JUAL_QRIS','JUAL_TRANSFER','JUAL_KREDIT',
      'BELI_KREDIT','BEBAN_VENDOR_KREDIT','BAYAR_VENDOR','TERIMA_PIUTANG','TERIMA_PIUTANG_PPH23','PPH23_15_ACCRUAL','BAYAR_PPH23_15','GAJI_BULANAN','BAYAR_GAJI','SETOR_PAJAK','TUTUP_PPN_MASA','PPH_FINAL_UMKM_BULANAN','PPH_BADAN_TAHUNAN','SETOR_MODAL_OWNER','BELI_ASET_TUNAI','PENYUSUTAN_BULANAN','PRIVE_OWNER','ATUR_CADANGAN_PIUTANG','RETUR_PENJUALAN','STOCK_OPNAME'
    ) then
      raise exception 'domain_journal_requires_domain_specific_reversal' using errcode='55000';
    end if;
  end if;
  return new;
end;
$function$


-- private.guard_employee_tax_profile()
CREATE OR REPLACE FUNCTION private.guard_employee_tax_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_expected_category text;
  v_expected_ptkp bigint;
  v_expected_status text;
  v_effective_date date;
begin
  if tg_op='DELETE' then
    raise exception 'employee tax profile history is immutable; close with valid_to' using errcode='55000';
  end if;

  v_expected_category:=private.resolve_ter_category(new.marital_status,new.dependents);
  v_expected_ptkp:=private.pph21_ptkp_amount(new.marital_status,new.dependents);
  v_expected_status:=private.pph21_ptkp_status(new.marital_status,new.dependents);
  new.ter_category:=v_expected_category;
  new.ptkp_amount:=v_expected_ptkp;
  new.ptkp_status:=v_expected_status;
  new.updated_at:=now();

  if new.valid_to is not null and new.valid_to<new.valid_from then
    raise exception 'employee_tax_profile_invalid_period' using errcode='22023';
  end if;
  if not exists(
    select 1 from public.tax_parties tp
    where tp.tenant_id=new.tenant_id
      and tp.party_id=new.employee_party_id
      and tp.party_kind='EMPLOYEE'
      and tp.valid_from<=new.valid_from
      and (tp.valid_to is null or tp.valid_to>=coalesce(new.valid_to,new.valid_from))
  ) then
    raise exception 'employee_tax_party_evidence_not_effective_for_profile_period' using errcode='23514';
  end if;

  if tg_op='UPDATE' then
    if old.tenant_id is distinct from new.tenant_id
       or old.profile_id is distinct from new.profile_id
       or old.employee_party_id is distinct from new.employee_party_id
       or old.employment_type is distinct from new.employment_type
       or old.marital_status is distinct from new.marital_status
       or old.dependents is distinct from new.dependents
       or old.tax_method is distinct from new.tax_method
       or old.valid_from is distinct from new.valid_from
       or old.legal_basis is distinct from new.legal_basis
       or old.actor_user_id is distinct from new.actor_user_id
       or old.device_id is distinct from new.device_id
       or old.reason is distinct from new.reason
       or old.created_at is distinct from new.created_at then
      raise exception 'employee tax profile economics are immutable; close and insert a new version' using errcode='55000';
    end if;
    if old.valid_to is not null and new.valid_to is distinct from old.valid_to then
      raise exception 'closed employee tax profile is immutable' using errcode='55000';
    end if;
    if new.valid_to is not null and new.valid_to<current_date then
      raise exception 'employee tax profile cannot be closed retroactively' using errcode='23514';
    end if;
  end if;

  v_effective_date:=new.valid_from;
  if exists(
    select 1 from public.employee_tax_profiles p
    where p.tenant_id=new.tenant_id
      and p.employee_party_id=new.employee_party_id
      and (tg_op='INSERT' or p.profile_id<>new.profile_id)
      and daterange(p.valid_from,coalesce(p.valid_to+1,'infinity'::date),'[)')
          && daterange(new.valid_from,coalesce(new.valid_to+1,'infinity'::date),'[)')
  ) then
    raise exception 'employee_tax_profile_period_overlap' using errcode='23P01';
  end if;
  return new;
end;
$function$


-- private.guard_owner_turnover_tax_period_immutable()
CREATE OR REPLACE FUNCTION private.guard_owner_turnover_tax_period_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ begin raise exception 'owner turnover tax period is immutable' using errcode='55000'; end; $function$


-- private.guard_payroll_tax_evidence_immutable()
CREATE OR REPLACE FUNCTION private.guard_payroll_tax_evidence_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  raise exception 'payroll tax evidence is immutable' using errcode='55000';
end;
$function$


-- private.guard_pph25_authority_update()
CREATE OR REPLACE FUNCTION private.guard_pph25_authority_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op='DELETE' then raise exception 'PPh25 authority history is immutable' using errcode='55000'; end if;
  if (old.tenant_id,old.tax_year,old.source_annual_period_id,old.effective_from_month,old.effective_to_month,old.annual_installment_basis,old.monthly_amount,old.source_reference,old.source_filed_date,old.calculation_snapshot,old.actor_user_id,old.device_id,old.reason,old.created_at,old.supersedes_authority_id)
     is distinct from
     (new.tenant_id,new.tax_year,new.source_annual_period_id,new.effective_from_month,new.effective_to_month,new.annual_installment_basis,new.monthly_amount,new.source_reference,new.source_filed_date,new.calculation_snapshot,new.actor_user_id,new.device_id,new.reason,new.created_at,new.supersedes_authority_id) then
    raise exception 'PPh25 authority economics are immutable' using errcode='55000';
  end if;
  if old.superseded_from_month is not null and new.superseded_from_month is distinct from old.superseded_from_month then raise exception 'PPh25 authority supersession is immutable once set' using errcode='55000'; end if;
  if new.superseded_from_month is not null and (new.superseded_from_month<=old.effective_from_month or new.superseded_from_month>old.effective_to_month) then raise exception 'invalid PPh25 authority supersession month' using errcode='23514'; end if;
  return new;
end; $function$


-- private.guard_self_tax_party_period()
CREATE OR REPLACE FUNCTION private.guard_self_tax_party_period()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.party_kind='SELF' and exists(
    select 1
    from public.tax_parties tp
    where tp.tenant_id=new.tenant_id
      and tp.party_kind='SELF'
      and tp.party_id<>new.party_id
      and daterange(tp.valid_from,tp.valid_to,'[]') && daterange(new.valid_from,new.valid_to,'[]')
  ) then
    raise exception 'overlapping_self_tax_party_period' using errcode='23514';
  end if;
  return new;
end;
$function$


-- private.guard_service_tax_profile()
CREATE OR REPLACE FUNCTION private.guard_service_tax_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_overlap boolean;
begin
  if current_user<>'postgres' then
    raise exception 'service tax profile direct mutation denied' using errcode='42501';
  end if;
  if tg_op='DELETE' then
    raise exception 'service tax profile history is immutable; close with valid_to' using errcode='55000';
  end if;
  if new.valid_to is not null and new.valid_to<new.valid_from then
    raise exception 'invalid service tax profile period' using errcode='23514';
  end if;
  if tg_op='UPDATE' and old.valid_from<=current_date then
    if (old.tenant_id,old.service_profile_id,old.service_code,old.name_id,old.vat_exempt,old.vat_object_code,old.valid_from,old.legal_basis,old.actor_user_id,old.device_id,old.reason,old.created_at)
       is distinct from
       (new.tenant_id,new.service_profile_id,new.service_code,new.name_id,new.vat_exempt,new.vat_object_code,new.valid_from,new.legal_basis,new.actor_user_id,new.device_id,new.reason,new.created_at) then
      raise exception 'historical service tax profile is immutable' using errcode='55000';
    end if;
    if old.valid_to is not null and new.valid_to is distinct from old.valid_to then
      raise exception 'closed service tax profile is immutable' using errcode='55000';
    end if;
    if old.valid_to is null and new.valid_to is not null and new.valid_to<current_date then
      raise exception 'service tax profile cannot close retroactively' using errcode='55000';
    end if;
  end if;
  select exists(
    select 1 from public.service_tax_profiles s
    where s.tenant_id=new.tenant_id
      and s.service_code=new.service_code
      and s.service_profile_id<>new.service_profile_id
      and daterange(s.valid_from,coalesce(s.valid_to+1,'infinity'::date),'[)')
          && daterange(new.valid_from,coalesce(new.valid_to+1,'infinity'::date),'[)')
  ) into v_overlap;
  if v_overlap then raise exception 'overlapping service tax profiles' using errcode='23514'; end if;
  return new;
end;
$function$


-- private.guard_tax_document_update()
CREATE OR REPLACE FUNCTION private.guard_tax_document_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_economic_changed boolean; v_journal_link_invalid boolean;
begin
  if tg_op='DELETE' then raise exception 'tax document history is immutable' using errcode='55000'; end if;
  v_economic_changed := (
    old.tenant_id,old.document_type,old.document_number,old.transaction_ref,old.reference_document_id,
    old.counterparty_id,old.business_date,old.vat_transaction_code,old.facility_context,
    old.dpp,old.tax_amount,old.gross_amount,old.tax_rate_snapshot,old.legal_rule_snapshot,
    old.invoice_status,old.creditable_input_vat,old.actor_user_id,old.device_id,old.reason,old.created_at
  ) is distinct from (
    new.tenant_id,new.document_type,new.document_number,new.transaction_ref,new.reference_document_id,
    new.counterparty_id,new.business_date,new.vat_transaction_code,new.facility_context,
    new.dpp,new.tax_amount,new.gross_amount,new.tax_rate_snapshot,new.legal_rule_snapshot,
    new.invoice_status,new.creditable_input_vat,new.actor_user_id,new.device_id,new.reason,new.created_at
  );
  v_journal_link_invalid := old.journal_id is not null and new.journal_id is distinct from old.journal_id;
  if v_journal_link_invalid then raise exception 'tax document journal linkage is immutable once set' using errcode='55000'; end if;
  if old.status<>'DRAFT' and v_economic_changed then raise exception 'validated/submitted tax document economics are immutable' using errcode='55000'; end if;
  if old.status in ('SUBMITTED','ACCEPTED','REPORTED','CANCELLED','REPLACED') and (v_economic_changed or new.journal_id is distinct from old.journal_id) then raise exception 'submitted/reported tax document is locked' using errcode='55000'; end if;
  if new.status=old.status then null;
  elsif old.status='DRAFT' and new.status in ('VALIDATED','CANCELLED') then null;
  elsif old.status='VALIDATED' and new.status in ('SUBMITTED','CANCELLED') then null;
  elsif old.status='SUBMITTED' and new.status in ('ACCEPTED','REJECTED') then null;
  elsif old.status='ACCEPTED' and new.status in ('REPORTED','CANCELLED','REPLACED') then null;
  elsif old.status='REJECTED' and new.status='CANCELLED' then null;
  else raise exception 'invalid tax document status transition % -> %',old.status,new.status using errcode='23514';
  end if;
  new.updated_at:=now(); return new;
end;
$function$


-- private.guard_tax_rate()
CREATE OR REPLACE FUNCTION private.guard_tax_rate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_overlap boolean;
begin
  if current_user <> 'postgres' and not private.btp_is_super_admin() then
    raise exception 'tax rate mutation denied' using errcode='42501';
  end if;
  if tg_op='DELETE' then
    raise exception 'tax rate history is immutable; close with end_date and add new rule' using errcode='55000';
  end if;
  if new.effective_date is null
     or (new.end_date is not null and new.end_date < new.effective_date)
     or new.statutory_rate < 0 or new.statutory_rate > 1
     or new.dpp_multiplier <= 0 or new.dpp_multiplier > 1
     or length(btrim(new.legal_basis)) < 3 then
    raise exception 'invalid tax rate' using errcode='23514';
  end if;

  if tg_op='UPDATE' and old.effective_date <= current_date then
    if (
      old.tax_code,old.object_code,old.category,old.statutory_rate,old.dpp_multiplier,
      old.calculation_method,old.effective_date,old.legal_basis,old.metadata,old.created_by,old.created_at
    ) is distinct from (
      new.tax_code,new.object_code,new.category,new.statutory_rate,new.dpp_multiplier,
      new.calculation_method,new.effective_date,new.legal_basis,new.metadata,new.created_by,new.created_at
    ) then
      raise exception 'effective historical tax rule is immutable' using errcode='55000';
    end if;
    if old.end_date is not null and new.end_date is distinct from old.end_date then
      raise exception 'closed historical tax rule is immutable' using errcode='55000';
    end if;
    if old.end_date is null and new.end_date is not null and new.end_date < current_date then
      raise exception 'tax rule cannot be closed retroactively' using errcode='55000';
    end if;
  end if;

  select exists(
    select 1 from public.tax_rates r
    where r.tax_rate_id <> new.tax_rate_id
      and r.tax_code=new.tax_code and r.object_code=new.object_code and r.category=new.category
      and daterange(r.effective_date,coalesce(r.end_date+1,'infinity'::date),'[)')
          && daterange(new.effective_date,coalesce(new.end_date+1,'infinity'::date),'[)')
  ) into v_overlap;
  if v_overlap then
    raise exception 'overlapping tax rules' using errcode='23514';
  end if;

  new.created_by := coalesce(new.created_by, auth.uid());
  return new;
end;
$function$


-- private.guard_tax_rate_bracket()
CREATE OR REPLACE FUNCTION private.guard_tax_rate_bracket()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_overlap boolean;
begin
  if current_user <> 'postgres' and not private.btp_is_super_admin() then
    raise exception 'tax rate bracket mutation denied' using errcode='42501';
  end if;
  if tg_op='DELETE' then
    raise exception 'tax rate bracket history is immutable; close with end_date and add new rule' using errcode='55000';
  end if;
  if new.effective_date is null
     or (new.end_date is not null and new.end_date < new.effective_date)
     or new.lower_bound < 0
     or (new.upper_bound is not null and new.upper_bound < new.lower_bound)
     or new.rate < 0 or new.rate > 1
     or length(btrim(new.legal_basis)) < 3 then
    raise exception 'invalid tax rate bracket' using errcode='23514';
  end if;

  if tg_op='UPDATE' and old.effective_date <= current_date then
    if (
      old.tax_code,old.category,old.lower_bound,old.upper_bound,old.rate,
      old.effective_date,old.legal_basis,old.created_by,old.created_at
    ) is distinct from (
      new.tax_code,new.category,new.lower_bound,new.upper_bound,new.rate,
      new.effective_date,new.legal_basis,new.created_by,new.created_at
    ) then
      raise exception 'effective historical tax rate bracket is immutable' using errcode='55000';
    end if;
    if old.end_date is not null and new.end_date is distinct from old.end_date then
      raise exception 'closed historical tax rate bracket is immutable' using errcode='55000';
    end if;
    if old.end_date is null and new.end_date is not null and new.end_date < current_date then
      raise exception 'tax rate bracket cannot be closed retroactively' using errcode='55000';
    end if;
  end if;

  select exists(
    select 1 from public.tax_rate_brackets b
    where b.bracket_id<>new.bracket_id and b.tax_code=new.tax_code and b.category=new.category
      and int8range(b.lower_bound,coalesce(b.upper_bound+1,9223372036854775807::bigint),'[)')
          && int8range(new.lower_bound,coalesce(new.upper_bound+1,9223372036854775807::bigint),'[)')
      and daterange(b.effective_date,coalesce(b.end_date+1,'infinity'::date),'[)')
          && daterange(new.effective_date,coalesce(new.end_date+1,'infinity'::date),'[)')
  ) into v_overlap;
  if v_overlap then
    raise exception 'overlapping tax rate brackets' using errcode='23514';
  end if;

  new.created_by := coalesce(new.created_by,auth.uid());
  return new;
end;
$function$

