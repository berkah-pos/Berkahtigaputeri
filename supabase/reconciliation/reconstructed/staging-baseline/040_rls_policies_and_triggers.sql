-- RECONSTRUCTED STAGING CATALOG SNAPSHOT; not historical migration source.
-- Application schema RLS flags and policy bodies are reconstructed from pg_catalog/pg_policies.
-- Policies are created after their referenced helper functions and all tables exist.

-- Row-level security flags.
ALTER TABLE "private"."audit_logs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "private"."manager_pins" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "private"."pos_memberships" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."accounting_coa" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."accounting_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."accounting_journal_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."accounting_journals" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."accounting_memberships" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."accounting_periods" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."accounting_tenants" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."accounting_transaction_evidence" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."app_config" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."client_status" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."config_history" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."coretax_outbox" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."coretax_template_registry" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."corporate_annual_tax_periods" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."corporate_fiscal_adjustments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."corporate_fiscal_loss_applications" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."corporate_fiscal_loss_carryforwards" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."corporate_pph25_authorities" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."customer_receivable_allocations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."customer_receivables" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."customer_withholding_tax_credits" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."devices" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."employee_payables" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."employee_tax_profiles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."extended_withholding_liabilities" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."extended_withholding_payments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."fixed_asset_depreciation_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."fixed_assets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."inventory_average_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."inventory_average_projection" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."inventory_cost_layer_projection" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."inventory_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."inventory_lot_projection" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."inventory_product_projection" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."licences" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."owner_turnover_tax_periods" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."payroll_payment_allocations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."payroll_tax_evidence" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."plans" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."pos_accounting_tenant_map" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."pos_manager_pins" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."pos_memberships" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."pos_pin_audit" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."product_master" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."receivable_allowance_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."receivable_allowances" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."sale_line_evidence" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."sale_return_line_evidence" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."service_tax_profiles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."subscription_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."subscriptions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."supplier_liabilities" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."supplier_payment_allocations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tax_document_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tax_document_lines" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tax_documents" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tax_parties" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tax_payment_refs" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tax_rate_brackets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tax_rates" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tenant_services" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."tenants" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."vat_period_settlements" ENABLE ROW LEVEL SECURITY;

-- Policies.
CREATE POLICY "accounting_coa_read_member" ON "public"."accounting_coa" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((private.btp_is_super_admin() OR (EXISTS ( SELECT 1
   FROM accounting_memberships m
  WHERE ((m.user_id = auth.uid()) AND m.is_active)))));

CREATE POLICY "accounting_events_read_member" ON "public"."accounting_events" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM accounting_memberships m
  WHERE ((m.tenant_id = accounting_events.tenant_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.is_active))));

CREATE POLICY "accounting_journal_lines_read_member" ON "public"."accounting_journal_lines" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM accounting_memberships m
  WHERE ((m.tenant_id = accounting_journal_lines.tenant_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.is_active))));

CREATE POLICY "accounting_journals_read_member" ON "public"."accounting_journals" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM accounting_memberships m
  WHERE ((m.tenant_id = accounting_journals.tenant_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.is_active))));

CREATE POLICY "accounting_memberships_read_self" ON "public"."accounting_memberships" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "accounting_periods_read_member" ON "public"."accounting_periods" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM accounting_memberships m
  WHERE ((m.tenant_id = accounting_periods.tenant_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.is_active))));

CREATE POLICY "accounting_tenants_read_member" ON "public"."accounting_tenants" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM accounting_memberships m
  WHERE ((m.tenant_id = accounting_tenants.tenant_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.is_active))));

CREATE POLICY "authenticated read own app_config - device only own" ON "public"."app_config" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (private.can_read_final_pos_config_strict(key));

CREATE POLICY "super admin all app_config - canonical" ON "public"."app_config" AS PERMISSIVE FOR ALL TO "authenticated"
  USING (private.btp_is_super_admin())
  WITH CHECK (private.btp_is_super_admin());

CREATE POLICY "client_status_tenant_bound" ON "public"."client_status" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (private.can_read_client_status(device_id));

CREATE POLICY "super admin insert history" ON "public"."config_history" AS PERMISSIVE FOR INSERT TO "authenticated"
  WITH CHECK (private.btp_is_super_admin());

CREATE POLICY "super admin read history" ON "public"."config_history" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (private.btp_is_super_admin());

CREATE POLICY "coretax_template_insert_super_admin" ON "public"."coretax_template_registry" AS PERMISSIVE FOR INSERT TO "authenticated"
  WITH CHECK (private.btp_is_super_admin());

CREATE POLICY "coretax_template_read_authenticated" ON "public"."coretax_template_registry" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (true);

CREATE POLICY "coretax_template_update_super_admin" ON "public"."coretax_template_registry" AS PERMISSIVE FOR UPDATE TO "authenticated"
  USING (private.btp_is_super_admin())
  WITH CHECK (private.btp_is_super_admin());

CREATE POLICY "authenticated read own devices" ON "public"."devices" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "super admin all devices" ON "public"."devices" AS PERMISSIVE FOR ALL TO "authenticated"
  USING (private.btp_is_super_admin())
  WITH CHECK (private.btp_is_super_admin());

CREATE POLICY "inventory_average_events_member_read" ON "public"."inventory_average_events" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (((auth.uid() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM accounting_memberships m
  WHERE ((m.tenant_id = inventory_average_events.tenant_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.is_active)))));

CREATE POLICY "inventory_average_projection_member_read" ON "public"."inventory_average_projection" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (((auth.uid() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM accounting_memberships m
  WHERE ((m.tenant_id = inventory_average_projection.tenant_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.is_active)))));

CREATE POLICY "inventory_cost_projection_member_read" ON "public"."inventory_cost_layer_projection" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM accounting_memberships m
  WHERE ((m.tenant_id = inventory_cost_layer_projection.tenant_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.is_active)))));

CREATE POLICY "inventory_events_member_read" ON "public"."inventory_events" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM accounting_memberships m
  WHERE ((m.tenant_id = inventory_events.tenant_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.is_active)))));

CREATE POLICY "inventory_lot_projection_member_read" ON "public"."inventory_lot_projection" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM accounting_memberships m
  WHERE ((m.tenant_id = inventory_lot_projection.tenant_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.is_active)))));

CREATE POLICY "inventory_product_projection_member_read" ON "public"."inventory_product_projection" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM accounting_memberships m
  WHERE ((m.tenant_id = inventory_product_projection.tenant_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.is_active)))));

CREATE POLICY "authenticated read own licences" ON "public"."licences" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM devices d
  WHERE ((d.device_id = licences.device_id) AND (d.tenant_id = licences.tenant_id) AND (d.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "super admin all licences" ON "public"."licences" AS PERMISSIVE FOR ALL TO "authenticated"
  USING (private.btp_is_super_admin())
  WITH CHECK (private.btp_is_super_admin());

CREATE POLICY "plans_read_active" ON "public"."plans" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((is_active = true));

CREATE POLICY "pos_memberships_owner_manage" ON "public"."pos_memberships" AS PERMISSIVE FOR ALL TO "authenticated"
  USING (private.is_pos_owner(tenant_id))
  WITH CHECK (private.is_pos_owner(tenant_id));

CREATE POLICY "pos_memberships_self_read" ON "public"."pos_memberships" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "pos_pin_audit_owner_read" ON "public"."pos_pin_audit" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (private.is_pos_owner(tenant_id));

CREATE POLICY "pos_pin_audit_self_read" ON "public"."pos_pin_audit" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((actor_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "product_master_read_active_membership" ON "public"."product_master" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (((( SELECT auth.uid() AS uid) IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM accounting_memberships membership
  WHERE ((membership.tenant_id = product_master.tenant_id) AND (membership.user_id = ( SELECT auth.uid() AS uid)) AND membership.is_active)))));

CREATE POLICY "service_tax_profiles_member_read" ON "public"."service_tax_profiles" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (((auth.uid() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM accounting_memberships m
  WHERE ((m.tenant_id = service_tax_profiles.tenant_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND m.is_active)))));

CREATE POLICY "tax_rate_brackets_insert_super_admin" ON "public"."tax_rate_brackets" AS PERMISSIVE FOR INSERT TO "authenticated"
  WITH CHECK (private.btp_is_super_admin());

CREATE POLICY "tax_rate_brackets_read_authenticated" ON "public"."tax_rate_brackets" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (true);

CREATE POLICY "tax_rate_brackets_update_super_admin" ON "public"."tax_rate_brackets" AS PERMISSIVE FOR UPDATE TO "authenticated"
  USING (private.btp_is_super_admin())
  WITH CHECK (private.btp_is_super_admin());

CREATE POLICY "tax_rates_insert_super_admin" ON "public"."tax_rates" AS PERMISSIVE FOR INSERT TO "authenticated"
  WITH CHECK (private.btp_is_super_admin());

CREATE POLICY "tax_rates_read_authenticated" ON "public"."tax_rates" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING (true);

CREATE POLICY "tax_rates_update_super_admin" ON "public"."tax_rates" AS PERMISSIVE FOR UPDATE TO "authenticated"
  USING (private.btp_is_super_admin())
  WITH CHECK (private.btp_is_super_admin());

CREATE POLICY "authenticated read own tenant_services" ON "public"."tenant_services" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM devices d
  WHERE ((d.tenant_id = tenant_services.tenant_id) AND (d.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "super admin all tenant_services" ON "public"."tenant_services" AS PERMISSIVE FOR ALL TO "authenticated"
  USING (private.btp_is_super_admin())
  WITH CHECK (private.btp_is_super_admin());

CREATE POLICY "authenticated read own tenants" ON "public"."tenants" AS PERMISSIVE FOR SELECT TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM devices d
  WHERE ((d.tenant_id = tenants.tenant_id) AND (d.user_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "super admin all tenants" ON "public"."tenants" AS PERMISSIVE FOR ALL TO "authenticated"
  USING (private.btp_is_super_admin())
  WITH CHECK (private.btp_is_super_admin());

-- Triggers and trigger enablement.
CREATE TRIGGER tenant_accounting_links_guard BEFORE INSERT OR DELETE OR UPDATE ON private.tenant_accounting_links FOR EACH ROW EXECUTE FUNCTION private.guard_tenant_accounting_link();

CREATE TRIGGER accounting_coa_no_insert BEFORE INSERT ON accounting_coa FOR EACH ROW EXECUTE FUNCTION accounting_private.reject_locked_coa_insert();

CREATE TRIGGER accounting_coa_no_mutation BEFORE DELETE OR UPDATE ON accounting_coa FOR EACH ROW EXECUTE FUNCTION accounting_private.reject_mutation();

CREATE TRIGGER accounting_events_no_mutation BEFORE DELETE OR UPDATE ON accounting_events FOR EACH ROW EXECUTE FUNCTION accounting_private.reject_mutation();

CREATE CONSTRAINT TRIGGER accounting_journal_lines_balance AFTER INSERT OR DELETE OR UPDATE ON accounting_journal_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION accounting_private.assert_journal_balanced();

CREATE TRIGGER accounting_journal_lines_creation_tx BEFORE INSERT ON accounting_journal_lines FOR EACH ROW EXECUTE FUNCTION accounting_private.guard_line_creation_tx();

CREATE TRIGGER accounting_journal_lines_no_mutation BEFORE DELETE OR UPDATE ON accounting_journal_lines FOR EACH ROW EXECUTE FUNCTION accounting_private.reject_mutation();

CREATE CONSTRAINT TRIGGER accounting_journal_parent_balance AFTER INSERT ON accounting_journals DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION accounting_private.assert_journal_balanced();

CREATE TRIGGER accounting_journals_domain_reversal_guard BEFORE INSERT ON accounting_journals FOR EACH ROW EXECUTE FUNCTION private.guard_domain_journal_reversal();

CREATE TRIGGER accounting_journals_no_mutation BEFORE DELETE OR UPDATE ON accounting_journals FOR EACH ROW EXECUTE FUNCTION accounting_private.reject_mutation();

CREATE TRIGGER accounting_transaction_customer_receivable_guard AFTER INSERT ON accounting_transaction_evidence FOR EACH ROW WHEN (new.transaction_type = ANY (ARRAY['JUAL_KREDIT'::text, 'TERIMA_PIUTANG'::text, 'TERIMA_PIUTANG_PPH23'::text, 'RETUR_PENJUALAN'::text])) EXECUTE FUNCTION private.enforce_customer_receivable_evidence();

CREATE TRIGGER accounting_transaction_evidence_immutable BEFORE DELETE OR UPDATE ON accounting_transaction_evidence FOR EACH ROW EXECUTE FUNCTION private.reject_tax_evidence_mutation();

CREATE TRIGGER accounting_transaction_extended_withholding_guard AFTER INSERT ON accounting_transaction_evidence FOR EACH ROW WHEN (new.transaction_type = ANY (ARRAY['PPH23_15_ACCRUAL'::text, 'BAYAR_PPH23_15'::text])) EXECUTE FUNCTION private.enforce_extended_withholding_evidence();

CREATE TRIGGER accounting_transaction_owner_adjustment_guard AFTER INSERT ON accounting_transaction_evidence FOR EACH ROW WHEN (new.transaction_type = ANY (ARRAY['BELI_ASET_TUNAI'::text, 'PENYUSUTAN_BULANAN'::text, 'ATUR_CADANGAN_PIUTANG'::text])) EXECUTE FUNCTION private.enforce_owner_adjustment_evidence();

CREATE TRIGGER accounting_transaction_payroll_guard AFTER INSERT ON accounting_transaction_evidence FOR EACH ROW WHEN (new.transaction_type = ANY (ARRAY['GAJI_BULANAN'::text, 'BAYAR_GAJI'::text])) EXECUTE FUNCTION private.enforce_payroll_evidence();

CREATE TRIGGER accounting_transaction_supplier_liability_guard AFTER INSERT ON accounting_transaction_evidence FOR EACH ROW WHEN (new.transaction_type = ANY (ARRAY['BELI_KREDIT'::text, 'BEBAN_VENDOR_KREDIT'::text, 'BAYAR_VENDOR'::text])) EXECUTE FUNCTION private.enforce_supplier_liability_evidence();

CREATE TRIGGER accounting_transaction_tax_remittance_guard AFTER INSERT ON accounting_transaction_evidence FOR EACH ROW WHEN (new.transaction_type = 'SETOR_PAJAK'::text) EXECUTE FUNCTION private.enforce_tax_remittance_evidence();

CREATE TRIGGER app_config_inventory_key_guard AFTER INSERT OR DELETE OR UPDATE OF key ON app_config FOR EACH STATEMENT EXECUTE FUNCTION private.guard_app_config_inventory();

CREATE TRIGGER app_config_inventory_truncate_guard AFTER TRUNCATE ON app_config FOR EACH STATEMENT EXECUTE FUNCTION private.guard_app_config_inventory();

CREATE TRIGGER trg_app_config_audit AFTER INSERT OR UPDATE ON app_config FOR EACH ROW EXECUTE FUNCTION log_config_change();

CREATE TRIGGER coretax_outbox_export_gate BEFORE INSERT ON coretax_outbox FOR EACH ROW EXECUTE FUNCTION private.guard_coretax_export_gate();

CREATE TRIGGER coretax_outbox_no_delete BEFORE DELETE ON coretax_outbox FOR EACH ROW EXECUTE FUNCTION private.reject_tax_evidence_mutation();

CREATE TRIGGER coretax_template_guard BEFORE INSERT OR DELETE OR UPDATE ON coretax_template_registry FOR EACH ROW EXECUTE FUNCTION private.guard_coretax_template();

CREATE TRIGGER corporate_annual_tax_periods_immutable BEFORE DELETE OR UPDATE ON corporate_annual_tax_periods FOR EACH ROW EXECUTE FUNCTION private.guard_corporate_tax_history_immutable();

CREATE TRIGGER corporate_fiscal_adjustments_immutable BEFORE DELETE OR UPDATE ON corporate_fiscal_adjustments FOR EACH ROW EXECUTE FUNCTION private.guard_corporate_tax_history_immutable();

CREATE TRIGGER corporate_fiscal_loss_applications_immutable BEFORE DELETE OR UPDATE ON corporate_fiscal_loss_applications FOR EACH ROW EXECUTE FUNCTION private.guard_corporate_tax_history_immutable();

CREATE TRIGGER corporate_fiscal_loss_carryforwards_immutable BEFORE DELETE OR UPDATE ON corporate_fiscal_loss_carryforwards FOR EACH ROW EXECUTE FUNCTION private.guard_corporate_tax_history_immutable();

CREATE TRIGGER corporate_pph25_authorities_guard BEFORE DELETE OR UPDATE ON corporate_pph25_authorities FOR EACH ROW EXECUTE FUNCTION private.guard_pph25_authority_update();

CREATE TRIGGER customer_withholding_tax_credits_immutable BEFORE DELETE OR UPDATE ON customer_withholding_tax_credits FOR EACH ROW EXECUTE FUNCTION private.guard_customer_withholding_credit_immutable();

CREATE TRIGGER trg_devices_updated_at BEFORE UPDATE ON devices FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER employee_tax_profiles_guard BEFORE INSERT OR DELETE OR UPDATE ON employee_tax_profiles FOR EACH ROW EXECUTE FUNCTION private.guard_employee_tax_profile();

CREATE TRIGGER inventory_events_no_mutation BEFORE DELETE OR UPDATE ON inventory_events FOR EACH ROW EXECUTE FUNCTION inventory_private.reject_event_mutation();

CREATE TRIGGER owner_turnover_tax_periods_immutable BEFORE DELETE OR UPDATE ON owner_turnover_tax_periods FOR EACH ROW EXECUTE FUNCTION private.guard_owner_turnover_tax_period_immutable();

CREATE TRIGGER payroll_tax_evidence_immutable_guard BEFORE DELETE OR UPDATE ON payroll_tax_evidence FOR EACH ROW EXECUTE FUNCTION private.guard_payroll_tax_evidence_immutable();

CREATE TRIGGER trg_plans_updated_at BEFORE UPDATE ON plans FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER sale_line_evidence_immutable BEFORE DELETE OR UPDATE ON sale_line_evidence FOR EACH ROW EXECUTE FUNCTION private.reject_tax_evidence_mutation();

CREATE TRIGGER sale_return_line_evidence_immutable BEFORE DELETE OR UPDATE ON sale_return_line_evidence FOR EACH ROW EXECUTE FUNCTION private.reject_tax_evidence_mutation();

CREATE TRIGGER service_tax_profiles_guard BEFORE INSERT OR DELETE OR UPDATE ON service_tax_profiles FOR EACH ROW EXECUTE FUNCTION private.guard_service_tax_profile();

CREATE TRIGGER trg_subscriptions_updated_at BEFORE UPDATE ON subscriptions FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER tax_document_events_immutable BEFORE DELETE OR UPDATE ON tax_document_events FOR EACH ROW EXECUTE FUNCTION private.reject_tax_evidence_mutation();

CREATE TRIGGER tax_document_lines_immutable BEFORE DELETE OR UPDATE ON tax_document_lines FOR EACH ROW EXECUTE FUNCTION private.reject_tax_evidence_mutation();

CREATE TRIGGER tax_documents_guard BEFORE DELETE OR UPDATE ON tax_documents FOR EACH ROW EXECUTE FUNCTION private.guard_tax_document_update();

CREATE TRIGGER tax_documents_populate_lines AFTER INSERT ON tax_documents FOR EACH ROW EXECUTE FUNCTION private.populate_tax_document_lines();

CREATE TRIGGER tax_documents_seal BEFORE INSERT OR UPDATE ON tax_documents FOR EACH ROW EXECUTE FUNCTION private.seal_tax_document();

CREATE TRIGGER tax_documents_vat_closed_period_insert_guard BEFORE INSERT ON tax_documents FOR EACH ROW EXECUTE FUNCTION private.guard_vat_document_closed_period_insert();

CREATE TRIGGER tax_parties_self_period_guard BEFORE INSERT OR UPDATE ON tax_parties FOR EACH ROW EXECUTE FUNCTION private.guard_self_tax_party_period();

CREATE TRIGGER tax_rate_brackets_guard BEFORE INSERT OR DELETE OR UPDATE ON tax_rate_brackets FOR EACH ROW EXECUTE FUNCTION private.guard_tax_rate_bracket();

CREATE TRIGGER tax_rates_guard BEFORE INSERT OR DELETE OR UPDATE ON tax_rates FOR EACH ROW EXECUTE FUNCTION private.guard_tax_rate();

CREATE TRIGGER vat_period_settlements_immutable BEFORE DELETE OR UPDATE ON vat_period_settlements FOR EACH ROW EXECUTE FUNCTION private.guard_vat_period_settlement_immutable();
