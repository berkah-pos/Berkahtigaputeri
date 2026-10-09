-- Atomic journal/evidence posting and retry conflict detection.
-- Targeted first at the isolated Supabase staging clone; validate against the deployed schema before any production rollout.
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
  -- Serialize all writes for a transaction_ref. The lock is held until transaction end.
  perform pg_advisory_xact_lock(hashtext(btrim(p_transaction_ref)));

  -- Evidence is authoritative for retry identity. A conflicting payload is never
  -- allowed to fall through to a new journal or inventory write.
  select * into v_existing
  from public.accounting_transaction_evidence
  where tenant_id=p_tenant_id and transaction_ref=btrim(p_transaction_ref);
  if found then
    if v_existing.request_fingerprint is distinct from v_fingerprint then
      raise exception 'transaction_idempotency_conflict' using errcode='23505';
    end if;

    select j.journal_id into v_journal
    from public.accounting_journals j
    where j.journal_id=v_existing.journal_id
      and j.tenant_id=p_tenant_id
      and j.transaction_ref=btrim(p_transaction_ref);
    if not found then
      raise exception 'transaction_evidence_journal_mismatch' using errcode='23514';
    end if;

    return v_journal;
  end if;

  -- A journal without its immutable evidence is inconsistent. Fail closed; never
  -- treat it as a successful retry and never create a second journal.
  select j.journal_id into v_journal
  from public.accounting_journals j
  where j.tenant_id=p_tenant_id and j.transaction_ref=btrim(p_transaction_ref);
  if found then
    raise exception 'journal_evidence_missing' using errcode='23514';
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

-- Evidence is mandatory and must link a journal in the same tenant.
ALTER TABLE public.accounting_transaction_evidence
  ALTER COLUMN journal_id SET NOT NULL;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.accounting_transaction_evidence'::regclass
      AND conname = 'accounting_transaction_evidence_journal_tenant_fkey'
  ) THEN
    ALTER TABLE public.accounting_transaction_evidence
      ADD CONSTRAINT accounting_transaction_evidence_journal_tenant_fkey
      FOREIGN KEY (journal_id, tenant_id)
      REFERENCES public.accounting_journals (journal_id, tenant_id)
      ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'public.accounting_transaction_evidence'::regclass
      AND NOT t.tgisinternal AND (t.tgtype & 16) <> 0
      AND t.tgfoid = 'private.reject_tax_evidence_mutation()'::regprocedure
  ) THEN
    CREATE TRIGGER accounting_transaction_evidence_atomic_immutable_update
      BEFORE UPDATE ON public.accounting_transaction_evidence
      FOR EACH ROW EXECUTE FUNCTION private.reject_tax_evidence_mutation();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'public.accounting_transaction_evidence'::regclass
      AND NOT t.tgisinternal AND (t.tgtype & 8) <> 0
      AND t.tgfoid = 'private.reject_tax_evidence_mutation()'::regprocedure
  ) THEN
    CREATE TRIGGER accounting_transaction_evidence_atomic_immutable_delete
      BEFORE DELETE ON public.accounting_transaction_evidence
      FOR EACH ROW EXECUTE FUNCTION private.reject_tax_evidence_mutation();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'public.inventory_events'::regclass
      AND NOT t.tgisinternal AND (t.tgtype & 16) <> 0
      AND t.tgfoid = 'inventory_private.reject_event_mutation()'::regprocedure
  ) THEN
    CREATE TRIGGER inventory_events_atomic_append_only_update
      BEFORE UPDATE ON public.inventory_events
      FOR EACH ROW EXECUTE FUNCTION inventory_private.reject_event_mutation();
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid = 'public.inventory_events'::regclass
      AND NOT t.tgisinternal AND (t.tgtype & 8) <> 0
      AND t.tgfoid = 'inventory_private.reject_event_mutation()'::regprocedure
  ) THEN
    CREATE TRIGGER inventory_events_atomic_append_only_delete
      BEFORE DELETE ON public.inventory_events
      FOR EACH ROW EXECUTE FUNCTION inventory_private.reject_event_mutation();
  END IF;
END
$migration$;

CREATE OR REPLACE FUNCTION public.validate_journal_consistency()
RETURNS TABLE (
  issue_code text,
  tenant_id uuid,
  transaction_ref text,
  journal_id uuid,
  details jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    'auto_journal_missing_evidence'::text,
    j.tenant_id,
    j.transaction_ref,
    j.journal_id,
    jsonb_build_object('idempotency_key', j.idempotency_key)
  FROM public.accounting_journals j
  WHERE j.idempotency_key LIKE 'auto:%'
    AND NOT EXISTS (
      SELECT 1
      FROM public.accounting_transaction_evidence e
      WHERE e.tenant_id=j.tenant_id
        AND e.transaction_ref=j.transaction_ref
        AND e.journal_id=j.journal_id
    )

  UNION ALL

  SELECT
    'evidence_journal_link_mismatch'::text,
    e.tenant_id,
    e.transaction_ref,
    e.journal_id,
    jsonb_build_object('evidence_id', e.evidence_id)
  FROM public.accounting_transaction_evidence e
  LEFT JOIN public.accounting_journals j
    ON j.journal_id=e.journal_id
   AND j.tenant_id=e.tenant_id
   AND j.transaction_ref=e.transaction_ref
  WHERE j.journal_id IS NULL

  UNION ALL

  SELECT
    'evidence_fingerprint_mismatch'::text,
    e.tenant_id,
    e.transaction_ref,
    e.journal_id,
    jsonb_build_object('evidence_id', e.evidence_id)
  FROM public.accounting_transaction_evidence e
  WHERE e.request_fingerprint IS DISTINCT FROM jsonb_build_object(
    'transaction_type', e.transaction_type,
    'transaction_ref', e.transaction_ref,
    'business_date', e.business_date::text,
    'facts', e.facts_snapshot,
    'actor_user_id', e.actor_user_id::text,
    'device_id', btrim(e.device_id),
    'app_version', btrim(e.app_version),
    'reason', btrim(e.reason)
  )

  UNION ALL

  SELECT
    'journal_lines_summary_mismatch'::text,
    j.tenant_id,
    j.transaction_ref,
    j.journal_id,
    jsonb_build_object(
      'journal_total_debit', j.total_debit,
      'lines_total_debit', coalesce(l.total_debit, 0),
      'journal_total_credit', j.total_credit,
      'lines_total_credit', coalesce(l.total_credit, 0),
      'line_count', coalesce(l.line_count, 0)
    )
  FROM public.accounting_journals j
  LEFT JOIN LATERAL (
    SELECT
      count(*)::bigint AS line_count,
      coalesce(sum(x.debit), 0) AS total_debit,
      coalesce(sum(x.credit), 0) AS total_credit
    FROM public.accounting_journal_lines x
    WHERE x.journal_id=j.journal_id
      AND x.tenant_id=j.tenant_id
  ) l ON true
  WHERE coalesce(l.line_count, 0) < 2
     OR j.total_debit <> coalesce(l.total_debit, 0)
     OR j.total_credit <> coalesce(l.total_credit, 0)
$function$;

REVOKE ALL ON FUNCTION public.validate_journal_consistency() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.validate_journal_consistency() TO service_role;
