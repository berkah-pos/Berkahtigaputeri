-- Reconstructed from staging catalog. Constraints/indexes only; not historical migration SQL.
ALTER SEQUENCE public.config_history_id_seq OWNED BY public.config_history.id;
-- Constraints in dependency order; all table definitions exist before this section.

-- private.audit_logs.audit_logs_pkey
ALTER TABLE ONLY private.audit_logs ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);

-- private.manager_pins.manager_pins_pkey
ALTER TABLE ONLY private.manager_pins ADD CONSTRAINT manager_pins_pkey PRIMARY KEY (tenant_id, outlet_id);

-- private.pos_memberships.pos_memberships_pkey
ALTER TABLE ONLY private.pos_memberships ADD CONSTRAINT pos_memberships_pkey PRIMARY KEY (tenant_id, user_id);

-- private.tenant_accounting_links.tenant_accounting_links_pkey
ALTER TABLE ONLY private.tenant_accounting_links ADD CONSTRAINT tenant_accounting_links_pkey PRIMARY KEY (link_id);

-- public.accounting_coa.accounting_coa_pkey
ALTER TABLE ONLY public.accounting_coa ADD CONSTRAINT accounting_coa_pkey PRIMARY KEY (account_code);

-- public.accounting_events.accounting_events_pkey
ALTER TABLE ONLY public.accounting_events ADD CONSTRAINT accounting_events_pkey PRIMARY KEY (event_id);

-- public.accounting_journal_lines.accounting_journal_lines_pkey
ALTER TABLE ONLY public.accounting_journal_lines ADD CONSTRAINT accounting_journal_lines_pkey PRIMARY KEY (line_id);

-- public.accounting_journals.accounting_journals_pkey
ALTER TABLE ONLY public.accounting_journals ADD CONSTRAINT accounting_journals_pkey PRIMARY KEY (journal_id);

-- public.accounting_memberships.accounting_memberships_pkey
ALTER TABLE ONLY public.accounting_memberships ADD CONSTRAINT accounting_memberships_pkey PRIMARY KEY (tenant_id, user_id);

-- public.accounting_periods.accounting_periods_pkey
ALTER TABLE ONLY public.accounting_periods ADD CONSTRAINT accounting_periods_pkey PRIMARY KEY (period_id);

-- public.accounting_tenants.accounting_tenants_pkey
ALTER TABLE ONLY public.accounting_tenants ADD CONSTRAINT accounting_tenants_pkey PRIMARY KEY (tenant_id);

-- public.accounting_transaction_evidence.accounting_transaction_evidence_pkey
ALTER TABLE ONLY public.accounting_transaction_evidence ADD CONSTRAINT accounting_transaction_evidence_pkey PRIMARY KEY (evidence_id);

-- public.app_config.app_config_pkey
ALTER TABLE ONLY public.app_config ADD CONSTRAINT app_config_pkey PRIMARY KEY (key);

-- public.client_status.client_status_pkey
ALTER TABLE ONLY public.client_status ADD CONSTRAINT client_status_pkey PRIMARY KEY (device_id);

-- public.config_history.config_history_pkey
ALTER TABLE ONLY public.config_history ADD CONSTRAINT config_history_pkey PRIMARY KEY (id);

-- public.coretax_outbox.coretax_outbox_pkey
ALTER TABLE ONLY public.coretax_outbox ADD CONSTRAINT coretax_outbox_pkey PRIMARY KEY (outbox_id);

-- public.coretax_template_registry.coretax_template_registry_pkey
ALTER TABLE ONLY public.coretax_template_registry ADD CONSTRAINT coretax_template_registry_pkey PRIMARY KEY (template_id);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_pkey
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_pkey PRIMARY KEY (annual_period_id);

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_pkey
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_pkey PRIMARY KEY (adjustment_id);

-- public.corporate_fiscal_loss_applications.corporate_fiscal_loss_applications_pkey
ALTER TABLE ONLY public.corporate_fiscal_loss_applications ADD CONSTRAINT corporate_fiscal_loss_applications_pkey PRIMARY KEY (application_id);

-- public.corporate_fiscal_loss_carryforwards.corporate_fiscal_loss_carryforwards_pkey
ALTER TABLE ONLY public.corporate_fiscal_loss_carryforwards ADD CONSTRAINT corporate_fiscal_loss_carryforwards_pkey PRIMARY KEY (loss_id);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_pkey
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_pkey PRIMARY KEY (authority_id);

-- public.customer_receivable_allocations.customer_receivable_allocations_pkey
ALTER TABLE ONLY public.customer_receivable_allocations ADD CONSTRAINT customer_receivable_allocations_pkey PRIMARY KEY (tenant_id, receipt_transaction_ref);

-- public.customer_receivables.customer_receivables_pkey
ALTER TABLE ONLY public.customer_receivables ADD CONSTRAINT customer_receivables_pkey PRIMARY KEY (tenant_id, sale_transaction_ref);

-- public.customer_withholding_tax_credits.customer_withholding_tax_credits_pkey
ALTER TABLE ONLY public.customer_withholding_tax_credits ADD CONSTRAINT customer_withholding_tax_credits_pkey PRIMARY KEY (credit_id);

-- public.devices.devices_pkey
ALTER TABLE ONLY public.devices ADD CONSTRAINT devices_pkey PRIMARY KEY (device_id);

-- public.employee_payables.employee_payables_pkey
ALTER TABLE ONLY public.employee_payables ADD CONSTRAINT employee_payables_pkey PRIMARY KEY (tenant_id, payroll_ref);

-- public.employee_tax_profiles.employee_tax_profiles_pkey
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_pkey PRIMARY KEY (tenant_id, profile_id);

-- public.extended_withholding_liabilities.extended_withholding_liabilities_pkey
ALTER TABLE ONLY public.extended_withholding_liabilities ADD CONSTRAINT extended_withholding_liabilities_pkey PRIMARY KEY (tenant_id, source_transaction_ref);

-- public.extended_withholding_payments.extended_withholding_payments_pkey
ALTER TABLE ONLY public.extended_withholding_payments ADD CONSTRAINT extended_withholding_payments_pkey PRIMARY KEY (tenant_id, payment_transaction_ref);

-- public.fixed_asset_depreciation_events.fixed_asset_depreciation_events_pkey
ALTER TABLE ONLY public.fixed_asset_depreciation_events ADD CONSTRAINT fixed_asset_depreciation_events_pkey PRIMARY KEY (tenant_id, asset_id, depreciation_month);

-- public.fixed_assets.fixed_assets_pkey
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_pkey PRIMARY KEY (tenant_id, asset_id);

-- public.inventory_average_events.inventory_average_events_pkey
ALTER TABLE ONLY public.inventory_average_events ADD CONSTRAINT inventory_average_events_pkey PRIMARY KEY (tenant_id, event_id);

-- public.inventory_average_projection.inventory_average_projection_pkey
ALTER TABLE ONLY public.inventory_average_projection ADD CONSTRAINT inventory_average_projection_pkey PRIMARY KEY (tenant_id, product_id);

-- public.inventory_cost_layer_projection.inventory_cost_layer_projection_pkey
ALTER TABLE ONLY public.inventory_cost_layer_projection ADD CONSTRAINT inventory_cost_layer_projection_pkey PRIMARY KEY (tenant_id, cost_layer_id);

-- public.inventory_events.inventory_events_pkey
ALTER TABLE ONLY public.inventory_events ADD CONSTRAINT inventory_events_pkey PRIMARY KEY (tenant_id, event_id);

-- public.inventory_lot_projection.inventory_lot_projection_pkey
ALTER TABLE ONLY public.inventory_lot_projection ADD CONSTRAINT inventory_lot_projection_pkey PRIMARY KEY (tenant_id, lot_id);

-- public.inventory_product_projection.inventory_product_projection_pkey
ALTER TABLE ONLY public.inventory_product_projection ADD CONSTRAINT inventory_product_projection_pkey PRIMARY KEY (tenant_id, product_id);

-- public.licences.licences_pkey
ALTER TABLE ONLY public.licences ADD CONSTRAINT licences_pkey PRIMARY KEY (device_id);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_pkey
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_pkey PRIMARY KEY (period_id);

-- public.payroll_payment_allocations.payroll_payment_allocations_pkey
ALTER TABLE ONLY public.payroll_payment_allocations ADD CONSTRAINT payroll_payment_allocations_pkey PRIMARY KEY (tenant_id, payment_transaction_ref);

-- public.payroll_tax_evidence.payroll_tax_evidence_pkey
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_pkey PRIMARY KEY (tenant_id, payroll_ref);

-- public.plans.plans_pkey
ALTER TABLE ONLY public.plans ADD CONSTRAINT plans_pkey PRIMARY KEY (plan_id);

-- public.pos_accounting_tenant_map.pos_accounting_tenant_map_pkey
ALTER TABLE ONLY public.pos_accounting_tenant_map ADD CONSTRAINT pos_accounting_tenant_map_pkey PRIMARY KEY (pos_tenant_id);

-- public.pos_manager_pins.pos_manager_pins_pkey
ALTER TABLE ONLY public.pos_manager_pins ADD CONSTRAINT pos_manager_pins_pkey PRIMARY KEY (tenant_id);

-- public.pos_pin_audit.pos_pin_audit_pkey
ALTER TABLE ONLY public.pos_pin_audit ADD CONSTRAINT pos_pin_audit_pkey PRIMARY KEY (id);

-- public.product_master.product_master_pkey
ALTER TABLE ONLY public.product_master ADD CONSTRAINT product_master_pkey PRIMARY KEY (product_id);

-- public.receivable_allowance_events.receivable_allowance_events_pkey
ALTER TABLE ONLY public.receivable_allowance_events ADD CONSTRAINT receivable_allowance_events_pkey PRIMARY KEY (tenant_id, adjustment_transaction_ref);

-- public.receivable_allowances.receivable_allowances_pkey
ALTER TABLE ONLY public.receivable_allowances ADD CONSTRAINT receivable_allowances_pkey PRIMARY KEY (tenant_id, sale_transaction_ref);

-- public.sale_line_evidence.sale_line_evidence_pkey
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_pkey PRIMARY KEY (tenant_id, transaction_ref, line_key);

-- public.sale_return_line_evidence.sale_return_line_evidence_pkey
ALTER TABLE ONLY public.sale_return_line_evidence ADD CONSTRAINT sale_return_line_evidence_pkey PRIMARY KEY (tenant_id, return_transaction_ref, line_key);

-- public.service_tax_profiles.service_tax_profiles_pkey
ALTER TABLE ONLY public.service_tax_profiles ADD CONSTRAINT service_tax_profiles_pkey PRIMARY KEY (tenant_id, service_profile_id);

-- public.subscription_events.subscription_events_pkey
ALTER TABLE ONLY public.subscription_events ADD CONSTRAINT subscription_events_pkey PRIMARY KEY (event_id);

-- public.subscriptions.subscriptions_pkey
ALTER TABLE ONLY public.subscriptions ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (sub_id);

-- public.supplier_liabilities.supplier_liabilities_pkey
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_pkey PRIMARY KEY (tenant_id, purchase_transaction_ref);

-- public.supplier_payment_allocations.supplier_payment_allocations_pkey
ALTER TABLE ONLY public.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_pkey PRIMARY KEY (tenant_id, payment_transaction_ref);

-- public.tax_document_events.tax_document_events_pkey
ALTER TABLE ONLY public.tax_document_events ADD CONSTRAINT tax_document_events_pkey PRIMARY KEY (event_id);

-- public.tax_document_lines.tax_document_lines_pkey
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_pkey PRIMARY KEY (tax_document_id, line_key);

-- public.tax_documents.tax_documents_pkey
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_pkey PRIMARY KEY (tax_document_id);

-- public.tax_parties.tax_parties_pkey
ALTER TABLE ONLY public.tax_parties ADD CONSTRAINT tax_parties_pkey PRIMARY KEY (tenant_id, party_id);

-- public.tax_payment_refs.tax_payment_refs_pkey
ALTER TABLE ONLY public.tax_payment_refs ADD CONSTRAINT tax_payment_refs_pkey PRIMARY KEY (payment_ref_id);

-- public.tax_rate_brackets.tax_rate_brackets_pkey
ALTER TABLE ONLY public.tax_rate_brackets ADD CONSTRAINT tax_rate_brackets_pkey PRIMARY KEY (bracket_id);

-- public.tax_rates.tax_rates_pkey
ALTER TABLE ONLY public.tax_rates ADD CONSTRAINT tax_rates_pkey PRIMARY KEY (tax_rate_id);

-- public.tenant_services.tenant_services_pkey
ALTER TABLE ONLY public.tenant_services ADD CONSTRAINT tenant_services_pkey PRIMARY KEY (tenant_id, service);

-- public.tenants.tenants_pkey
ALTER TABLE ONLY public.tenants ADD CONSTRAINT tenants_pkey PRIMARY KEY (tenant_id);

-- public.vat_period_settlements.vat_period_settlements_pkey
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_pkey PRIMARY KEY (settlement_id);

-- public.accounting_events.accounting_event_key_unique
ALTER TABLE ONLY public.accounting_events ADD CONSTRAINT accounting_event_key_unique UNIQUE (tenant_id, event_key);

-- public.accounting_journal_lines.accounting_line_unique_no
ALTER TABLE ONLY public.accounting_journal_lines ADD CONSTRAINT accounting_line_unique_no UNIQUE (journal_id, line_no);

-- public.accounting_journals.accounting_journal_id_tenant_unique
ALTER TABLE ONLY public.accounting_journals ADD CONSTRAINT accounting_journal_id_tenant_unique UNIQUE (journal_id, tenant_id);

-- public.accounting_journals.accounting_journal_tenant_idempotency
ALTER TABLE ONLY public.accounting_journals ADD CONSTRAINT accounting_journal_tenant_idempotency UNIQUE (tenant_id, idempotency_key);

-- public.accounting_journals.accounting_journal_tenant_transaction_ref_unique
ALTER TABLE ONLY public.accounting_journals ADD CONSTRAINT accounting_journal_tenant_transaction_ref_unique UNIQUE (tenant_id, transaction_ref);

-- public.accounting_periods.accounting_period_unique
ALTER TABLE ONLY public.accounting_periods ADD CONSTRAINT accounting_period_unique UNIQUE (tenant_id, period_start, period_end);

-- public.accounting_transaction_evidence.accounting_transaction_evidence_tenant_id_transaction_ref_key
ALTER TABLE ONLY public.accounting_transaction_evidence ADD CONSTRAINT accounting_transaction_evidence_tenant_id_transaction_ref_key UNIQUE (tenant_id, transaction_ref);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_tenant_id_tax_year_key
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_tenant_id_tax_year_key UNIQUE (tenant_id, tax_year);

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_tenant_id_tax_year_adjustment__key
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_tenant_id_tax_year_adjustment__key UNIQUE (tenant_id, tax_year, adjustment_ref);

-- public.corporate_fiscal_loss_applications.corporate_fiscal_loss_applica_loss_id_target_annual_period__key
ALTER TABLE ONLY public.corporate_fiscal_loss_applications ADD CONSTRAINT corporate_fiscal_loss_applica_loss_id_target_annual_period__key UNIQUE (loss_id, target_annual_period_id);

-- public.corporate_fiscal_loss_carryforwards.corporate_fiscal_loss_carryforwar_tenant_id_origin_tax_year_key
ALTER TABLE ONLY public.corporate_fiscal_loss_carryforwards ADD CONSTRAINT corporate_fiscal_loss_carryforwar_tenant_id_origin_tax_year_key UNIQUE (tenant_id, origin_tax_year);

-- public.customer_withholding_tax_credits.customer_withholding_tax_credi_tenant_id_certificate_number_key
ALTER TABLE ONLY public.customer_withholding_tax_credits ADD CONSTRAINT customer_withholding_tax_credi_tenant_id_certificate_number_key UNIQUE (tenant_id, certificate_number);

-- public.customer_withholding_tax_credits.customer_withholding_tax_credits_tenant_id_source_sale_ref_key
ALTER TABLE ONLY public.customer_withholding_tax_credits ADD CONSTRAINT customer_withholding_tax_credits_tenant_id_source_sale_ref_key UNIQUE (tenant_id, source_sale_ref);

-- public.extended_withholding_payments.extended_withholding_payments_tenant_id_source_transaction__key
ALTER TABLE ONLY public.extended_withholding_payments ADD CONSTRAINT extended_withholding_payments_tenant_id_source_transaction__key UNIQUE (tenant_id, source_transaction_ref);

-- public.fixed_asset_depreciation_events.fixed_asset_depreciation_events_tenant_id_transaction_ref_key
ALTER TABLE ONLY public.fixed_asset_depreciation_events ADD CONSTRAINT fixed_asset_depreciation_events_tenant_id_transaction_ref_key UNIQUE (tenant_id, transaction_ref);

-- public.fixed_assets.fixed_assets_tenant_id_asset_ref_key
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_tenant_id_asset_ref_key UNIQUE (tenant_id, asset_ref);

-- public.inventory_events.inventory_events_tenant_sequence_unique
ALTER TABLE ONLY public.inventory_events ADD CONSTRAINT inventory_events_tenant_sequence_unique UNIQUE (tenant_id, server_sequence);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_tenant_id_period_end_key
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_tenant_id_period_end_key UNIQUE (tenant_id, period_end);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_tenant_id_period_start_key
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_tenant_id_period_start_key UNIQUE (tenant_id, period_start);

-- public.payroll_tax_evidence.payroll_tax_evidence_tenant_id_employee_party_id_payroll_mo_key
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_tenant_id_employee_party_id_payroll_mo_key UNIQUE (tenant_id, employee_party_id, payroll_month);

-- public.plans.plans_play_product_id_key
ALTER TABLE ONLY public.plans ADD CONSTRAINT plans_play_product_id_key UNIQUE (play_product_id);

-- public.pos_accounting_tenant_map.pos_accounting_tenant_map_accounting_tenant_id_key
ALTER TABLE ONLY public.pos_accounting_tenant_map ADD CONSTRAINT pos_accounting_tenant_map_accounting_tenant_id_key UNIQUE (accounting_tenant_id);

-- public.pos_memberships.pos_memberships_tenant_user_key
ALTER TABLE ONLY public.pos_memberships ADD CONSTRAINT pos_memberships_tenant_user_key UNIQUE (tenant_id, user_id);

-- public.product_master.product_master_tenant_product_unique
ALTER TABLE ONLY public.product_master ADD CONSTRAINT product_master_tenant_product_unique UNIQUE (tenant_id, product_id);

-- public.product_master.product_master_tenant_sku_unique
ALTER TABLE ONLY public.product_master ADD CONSTRAINT product_master_tenant_sku_unique UNIQUE (tenant_id, sku);

-- public.service_tax_profiles.service_tax_profiles_tenant_id_service_code_valid_from_key
ALTER TABLE ONLY public.service_tax_profiles ADD CONSTRAINT service_tax_profiles_tenant_id_service_code_valid_from_key UNIQUE (tenant_id, service_code, valid_from);

-- public.subscription_events.subscription_events_event_key_key
ALTER TABLE ONLY public.subscription_events ADD CONSTRAINT subscription_events_event_key_key UNIQUE (event_key);

-- public.subscriptions.subscriptions_midtrans_order_id_key
ALTER TABLE ONLY public.subscriptions ADD CONSTRAINT subscriptions_midtrans_order_id_key UNIQUE (midtrans_order_id);

-- public.subscriptions.subscriptions_play_purchase_token_key
ALTER TABLE ONLY public.subscriptions ADD CONSTRAINT subscriptions_play_purchase_token_key UNIQUE (play_purchase_token);

-- public.tax_documents.tax_documents_tenant_id_document_type_transaction_ref_key
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_tenant_id_document_type_transaction_ref_key UNIQUE (tenant_id, document_type, transaction_ref);

-- public.tenant_services.tenant_services_app_config_key_key
ALTER TABLE ONLY public.tenant_services ADD CONSTRAINT tenant_services_app_config_key_key UNIQUE (app_config_key);

-- public.vat_period_settlements.vat_period_settlements_tenant_id_period_end_key
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_tenant_id_period_end_key UNIQUE (tenant_id, period_end);

-- public.vat_period_settlements.vat_period_settlements_tenant_id_period_start_key
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_tenant_id_period_start_key UNIQUE (tenant_id, period_start);

-- private.audit_logs.audit_logs_action_check
ALTER TABLE ONLY private.audit_logs ADD CONSTRAINT audit_logs_action_check CHECK (action = ANY (ARRAY['success'::text, 'fail'::text]));

-- private.manager_pins.manager_pins_attempts_check
ALTER TABLE ONLY private.manager_pins ADD CONSTRAINT manager_pins_attempts_check CHECK (attempts >= 0 AND attempts <= 3);

-- private.manager_pins.manager_pins_role_check
ALTER TABLE ONLY private.manager_pins ADD CONSTRAINT manager_pins_role_check CHECK (role = ANY (ARRAY['manager'::text, 'owner'::text]));

-- private.pos_memberships.pos_memberships_role_check
ALTER TABLE ONLY private.pos_memberships ADD CONSTRAINT pos_memberships_role_check CHECK (role = ANY (ARRAY['cashier'::text, 'manager'::text, 'owner'::text]));

-- private.tenant_accounting_links.tenant_accounting_links_check
ALTER TABLE ONLY private.tenant_accounting_links ADD CONSTRAINT tenant_accounting_links_check CHECK (valid_to IS NULL OR valid_to >= valid_from);

-- private.tenant_accounting_links.tenant_accounting_links_device_id_check
ALTER TABLE ONLY private.tenant_accounting_links ADD CONSTRAINT tenant_accounting_links_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- private.tenant_accounting_links.tenant_accounting_links_reason_check
ALTER TABLE ONLY private.tenant_accounting_links ADD CONSTRAINT tenant_accounting_links_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.accounting_coa.accounting_coa_normal_balance_check
ALTER TABLE ONLY public.accounting_coa ADD CONSTRAINT accounting_coa_normal_balance_check CHECK (normal_balance = ANY (ARRAY['debit'::text, 'credit'::text]));

-- public.accounting_journal_lines.accounting_journal_lines_credit_check
ALTER TABLE ONLY public.accounting_journal_lines ADD CONSTRAINT accounting_journal_lines_credit_check CHECK (credit >= 0);

-- public.accounting_journal_lines.accounting_journal_lines_debit_check
ALTER TABLE ONLY public.accounting_journal_lines ADD CONSTRAINT accounting_journal_lines_debit_check CHECK (debit >= 0);

-- public.accounting_journal_lines.accounting_journal_lines_line_no_check
ALTER TABLE ONLY public.accounting_journal_lines ADD CONSTRAINT accounting_journal_lines_line_no_check CHECK (line_no > 0);

-- public.accounting_journal_lines.accounting_line_one_side
ALTER TABLE ONLY public.accounting_journal_lines ADD CONSTRAINT accounting_line_one_side CHECK (debit > 0 AND credit = 0 OR credit > 0 AND debit = 0);

-- public.accounting_journals.accounting_journal_balanced_summary
ALTER TABLE ONLY public.accounting_journals ADD CONSTRAINT accounting_journal_balanced_summary CHECK (total_debit = total_credit);

-- public.accounting_journals.accounting_journal_reversal_shape
ALTER TABLE ONLY public.accounting_journals ADD CONSTRAINT accounting_journal_reversal_shape CHECK (source_type = 'reversal'::text AND reversal_of IS NOT NULL OR source_type <> 'reversal'::text AND reversal_of IS NULL);

-- public.accounting_journals.accounting_journals_source_type_check
ALTER TABLE ONLY public.accounting_journals ADD CONSTRAINT accounting_journals_source_type_check CHECK (source_type = ANY (ARRAY['pos_sale'::text, 'sale_return'::text, 'shift_close'::text, 'qris_settlement'::text, 'purchase_receipt'::text, 'supplier_payment'::text, 'ar_invoice'::text, 'ar_receipt'::text, 'fixed_asset_acquisition'::text, 'fixed_asset_depreciation'::text, 'payroll_accrual'::text, 'payroll_payment'::text, 'manual'::text, 'reversal'::text]));

-- public.accounting_journals.accounting_journals_total_credit_check
ALTER TABLE ONLY public.accounting_journals ADD CONSTRAINT accounting_journals_total_credit_check CHECK (total_credit > 0);

-- public.accounting_journals.accounting_journals_total_debit_check
ALTER TABLE ONLY public.accounting_journals ADD CONSTRAINT accounting_journals_total_debit_check CHECK (total_debit > 0);

-- public.accounting_memberships.accounting_memberships_role_check
ALTER TABLE ONLY public.accounting_memberships ADD CONSTRAINT accounting_memberships_role_check CHECK (role = ANY (ARRAY['owner'::text, 'admin'::text, 'accountant'::text, 'cashier'::text]));

-- public.accounting_periods.accounting_period_dates
ALTER TABLE ONLY public.accounting_periods ADD CONSTRAINT accounting_period_dates CHECK (period_end >= period_start);

-- public.accounting_periods.accounting_periods_status_check
ALTER TABLE ONLY public.accounting_periods ADD CONSTRAINT accounting_periods_status_check CHECK (status = ANY (ARRAY['open'::text, 'closed'::text]));

-- public.accounting_tenants.accounting_tenants_name_check
ALTER TABLE ONLY public.accounting_tenants ADD CONSTRAINT accounting_tenants_name_check CHECK (length(btrim(name)) >= 1 AND length(btrim(name)) <= 120);

-- public.accounting_tenants.accounting_tenants_status_check
ALTER TABLE ONLY public.accounting_tenants ADD CONSTRAINT accounting_tenants_status_check CHECK (status = ANY (ARRAY['active'::text, 'suspended'::text]));

-- public.accounting_transaction_evidence.accounting_transaction_evidence_app_version_check
ALTER TABLE ONLY public.accounting_transaction_evidence ADD CONSTRAINT accounting_transaction_evidence_app_version_check CHECK (length(btrim(app_version)) >= 1);

-- public.accounting_transaction_evidence.accounting_transaction_evidence_device_id_check
ALTER TABLE ONLY public.accounting_transaction_evidence ADD CONSTRAINT accounting_transaction_evidence_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.accounting_transaction_evidence.accounting_transaction_evidence_facts_snapshot_check
ALTER TABLE ONLY public.accounting_transaction_evidence ADD CONSTRAINT accounting_transaction_evidence_facts_snapshot_check CHECK (jsonb_typeof(facts_snapshot) = 'object'::text);

-- public.accounting_transaction_evidence.accounting_transaction_evidence_reason_check
ALTER TABLE ONLY public.accounting_transaction_evidence ADD CONSTRAINT accounting_transaction_evidence_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.accounting_transaction_evidence.accounting_transaction_evidence_request_fingerprint_check
ALTER TABLE ONLY public.accounting_transaction_evidence ADD CONSTRAINT accounting_transaction_evidence_request_fingerprint_check CHECK (jsonb_typeof(request_fingerprint) = 'object'::text);

-- public.accounting_transaction_evidence.accounting_transaction_evidence_tax_snapshot_check
ALTER TABLE ONLY public.accounting_transaction_evidence ADD CONSTRAINT accounting_transaction_evidence_tax_snapshot_check CHECK (jsonb_typeof(tax_snapshot) = 'object'::text);

-- public.accounting_transaction_evidence.accounting_transaction_evidence_transaction_type_check
ALTER TABLE ONLY public.accounting_transaction_evidence ADD CONSTRAINT accounting_transaction_evidence_transaction_type_check CHECK (transaction_type = ANY (ARRAY['JUAL_TUNAI'::text, 'JUAL_QRIS'::text, 'JUAL_TRANSFER'::text, 'JUAL_KREDIT'::text, 'BELI_KREDIT'::text, 'BEBAN_VENDOR_KREDIT'::text, 'BAYAR_VENDOR'::text, 'TERIMA_PIUTANG'::text, 'TERIMA_PIUTANG_PPH23'::text, 'PPH23_15_ACCRUAL'::text, 'BAYAR_PPH23_15'::text, 'GAJI_BULANAN'::text, 'BAYAR_GAJI'::text, 'SETOR_PAJAK'::text, 'TUTUP_PPN_MASA'::text, 'PPH_FINAL_UMKM_BULANAN'::text, 'PPH_BADAN_TAHUNAN'::text, 'SETOR_MODAL_OWNER'::text, 'BELI_ASET_TUNAI'::text, 'PENYUSUTAN_BULANAN'::text, 'PRIVE_OWNER'::text, 'ATUR_CADANGAN_PIUTANG'::text, 'RETUR_PENJUALAN'::text, 'STOCK_OPNAME'::text]));

-- public.client_status.client_status_hardware_mode_check
ALTER TABLE ONLY public.client_status ADD CONSTRAINT client_status_hardware_mode_check CHECK (hardware_mode = ANY (ARRAY['SIMULATED'::text, 'REAL'::text]));

-- public.client_status.client_status_sales_today_check
ALTER TABLE ONLY public.client_status ADD CONSTRAINT client_status_sales_today_check CHECK (sales_today >= 0);

-- public.coretax_outbox.coretax_outbox_attempt_count_check
ALTER TABLE ONLY public.coretax_outbox ADD CONSTRAINT coretax_outbox_attempt_count_check CHECK (attempt_count >= 0);

-- public.coretax_outbox.coretax_outbox_rejection_detail_check
ALTER TABLE ONLY public.coretax_outbox ADD CONSTRAINT coretax_outbox_rejection_detail_check CHECK (jsonb_typeof(rejection_detail) = 'object'::text);

-- public.coretax_outbox.coretax_outbox_status_check
ALTER TABLE ONLY public.coretax_outbox ADD CONSTRAINT coretax_outbox_status_check CHECK (status = ANY (ARRAY['PENDING'::text, 'EXPORTED'::text, 'SENT'::text, 'ACK'::text, 'REJECTED'::text]));

-- public.coretax_template_registry.coretax_template_registry_check
ALTER TABLE ONLY public.coretax_template_registry ADD CONSTRAINT coretax_template_registry_check CHECK (NOT is_active OR is_verified AND xml_template IS NOT NULL AND length(xml_template) > 0 AND template_sha256 ~ '^[0-9a-f]{64}$'::text AND verified_by IS NOT NULL AND verified_at IS NOT NULL);

-- public.coretax_template_registry.coretax_template_registry_generator_spec_check
ALTER TABLE ONLY public.coretax_template_registry ADD CONSTRAINT coretax_template_registry_generator_spec_check CHECK (jsonb_typeof(generator_spec) = 'object'::text);

-- public.coretax_template_registry.coretax_template_registry_official_source_url_check
ALTER TABLE ONLY public.coretax_template_registry ADD CONSTRAINT coretax_template_registry_official_source_url_check CHECK (official_source_url ~~ 'https://pajak.go.id/%'::text OR official_source_url ~~ 'https://www.pajak.go.id/%'::text);

-- public.coretax_template_registry.coretax_template_registry_template_code_check
ALTER TABLE ONLY public.coretax_template_registry ADD CONSTRAINT coretax_template_registry_template_code_check CHECK (template_code = ANY (ARRAY['FAKTUR_KELUARAN'::text, 'BPPU'::text, 'BPMP'::text]));

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_app_version_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_app_version_check CHECK (length(btrim(app_version)) >= 1);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_check CHECK (pph23_credit_applied >= 0 AND pph23_credit_applied <= pph23_credit_available);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_check1
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_check1 CHECK (pph25_credit_applied >= 0 AND pph25_credit_applied <= pph25_credit_available);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_check2
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_check2 CHECK ((facility_taxable_income + general_taxable_income) = taxable_income);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_check3
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_check3 CHECK (pph29_payable = GREATEST(corporate_tax_due - pph23_credit_applied - pph25_credit_applied, 0::bigint));

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_check4
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_check4 CHECK (overpayment_remaining = GREATEST(pph23_credit_available + pph25_credit_available - corporate_tax_due, 0::bigint));

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_check5
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_check5 CHECK (corporate_tax_due = 0 AND annual_journal_id IS NULL OR corporate_tax_due > 0 AND annual_journal_id IS NOT NULL);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_corporate_tax_due_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_corporate_tax_due_check CHECK (corporate_tax_due >= 0);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_device_id_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_facility_taxable_income_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_facility_taxable_income_check CHECK (facility_taxable_income >= 0);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_fiscal_loss_applied_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_fiscal_loss_applied_check CHECK (fiscal_loss_applied >= 0);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_fiscal_loss_created_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_fiscal_loss_created_check CHECK (fiscal_loss_created >= 0);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_fiscal_negative_adjustments_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_fiscal_negative_adjustments_check CHECK (fiscal_negative_adjustments >= 0);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_fiscal_positive_adjustments_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_fiscal_positive_adjustments_check CHECK (fiscal_positive_adjustments >= 0);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_general_taxable_income_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_general_taxable_income_check CHECK (general_taxable_income >= 0);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_gross_turnover_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_gross_turnover_check CHECK (gross_turnover >= 0);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_overpayment_remaining_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_overpayment_remaining_check CHECK (overpayment_remaining >= 0);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_pph23_credit_available_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_pph23_credit_available_check CHECK (pph23_credit_available >= 0);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_pph25_credit_available_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_pph25_credit_available_check CHECK (pph25_credit_available >= 0);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_pph29_payable_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_pph29_payable_check CHECK (pph29_payable >= 0);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_rate_method_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_rate_method_check CHECK (rate_method = ANY (ARRAY['GENERAL_22'::text, 'ARTICLE_31E_FULL'::text, 'ARTICLE_31E_PARTIAL'::text, 'LOSS_OR_NIL'::text]));

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_reason_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_tax_rule_snapshot_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_tax_rule_snapshot_check CHECK (jsonb_typeof(tax_rule_snapshot) = 'object'::text);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_tax_year_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_tax_year_check CHECK (tax_year >= 2020 AND tax_year <= 2100);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_taxable_income_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_taxable_income_check CHECK (taxable_income >= 0 AND (taxable_income % 1000::bigint) = 0);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_taxpayer_type_check
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_taxpayer_type_check CHECK (taxpayer_type = ANY (ARRAY['BADAN'::text, 'PT_PERORANGAN'::text, 'KOPERASI'::text]));

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_adjustment_ref_check
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_adjustment_ref_check CHECK (length(btrim(adjustment_ref)) >= 3);

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_amount_check
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_amount_check CHECK (amount > 0);

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_category_check
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_category_check CHECK (category = ANY (ARRAY['NON_DEDUCTIBLE_EXPENSE'::text, 'TAXABLE_INCOME_ADDITION'::text, 'NON_TAXABLE_INCOME'::text, 'DEDUCTIBLE_EXPENSE'::text, 'TIMING_DIFFERENCE'::text, 'OTHER_STATUTORY'::text]));

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_device_id_check
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_direction_check
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_direction_check CHECK (direction = ANY (ARRAY['POSITIVE'::text, 'NEGATIVE'::text]));

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_evidence_check
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_evidence_check CHECK (jsonb_typeof(evidence) = 'object'::text AND evidence <> '{}'::jsonb);

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_legal_basis_check
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_legal_basis_check CHECK (length(btrim(legal_basis)) >= 3);

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_reason_check
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_tax_year_check
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_tax_year_check CHECK (tax_year >= 2020 AND tax_year <= 2100);

-- public.corporate_fiscal_loss_applications.corporate_fiscal_loss_applications_amount_applied_check
ALTER TABLE ONLY public.corporate_fiscal_loss_applications ADD CONSTRAINT corporate_fiscal_loss_applications_amount_applied_check CHECK (amount_applied > 0);

-- public.corporate_fiscal_loss_carryforwards.corporate_fiscal_loss_carryforwards_check
ALTER TABLE ONLY public.corporate_fiscal_loss_carryforwards ADD CONSTRAINT corporate_fiscal_loss_carryforwards_check CHECK (expires_after_tax_year = (origin_tax_year + 5));

-- public.corporate_fiscal_loss_carryforwards.corporate_fiscal_loss_carryforwards_origin_tax_year_check
ALTER TABLE ONLY public.corporate_fiscal_loss_carryforwards ADD CONSTRAINT corporate_fiscal_loss_carryforwards_origin_tax_year_check CHECK (origin_tax_year >= 2020 AND origin_tax_year <= 2100);

-- public.corporate_fiscal_loss_carryforwards.corporate_fiscal_loss_carryforwards_original_loss_check
ALTER TABLE ONLY public.corporate_fiscal_loss_carryforwards ADD CONSTRAINT corporate_fiscal_loss_carryforwards_original_loss_check CHECK (original_loss > 0);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_annual_installment_basis_check
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_annual_installment_basis_check CHECK (annual_installment_basis >= 0);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_calculation_snapshot_check
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_calculation_snapshot_check CHECK (jsonb_typeof(calculation_snapshot) = 'object'::text);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_check
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_check CHECK (effective_to_month >= effective_from_month);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_device_id_check
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_effective_from_month_check
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_effective_from_month_check CHECK (effective_from_month = date_trunc('month'::text, effective_from_month::timestamp with time zone)::date);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_effective_to_month_check
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_effective_to_month_check CHECK (effective_to_month = date_trunc('month'::text, effective_to_month::timestamp with time zone)::date);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_monthly_amount_check
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_monthly_amount_check CHECK (monthly_amount >= 0);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_reason_check
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_source_reference_check
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_source_reference_check CHECK (length(btrim(source_reference)) >= 3);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_tax_year_check
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_tax_year_check CHECK (tax_year >= 2020 AND tax_year <= 2100);

-- public.customer_receivable_allocations.customer_receivable_allocations_amount_applied_check
ALTER TABLE ONLY public.customer_receivable_allocations ADD CONSTRAINT customer_receivable_allocations_amount_applied_check CHECK (amount_applied > 0);

-- public.customer_receivable_allocations.customer_receivable_allocations_cash_tax_check
ALTER TABLE ONLY public.customer_receivable_allocations ADD CONSTRAINT customer_receivable_allocations_cash_tax_check CHECK (cash_received >= 0 AND withheld_tax_amount >= 0 AND (cash_received + withheld_tax_amount) = amount_applied);

-- public.customer_receivable_allocations.customer_receivable_allocations_customer_ref_check
ALTER TABLE ONLY public.customer_receivable_allocations ADD CONSTRAINT customer_receivable_allocations_customer_ref_check CHECK (length(btrim(customer_ref)) >= 1);

-- public.customer_receivable_allocations.customer_receivable_allocations_device_id_check
ALTER TABLE ONLY public.customer_receivable_allocations ADD CONSTRAINT customer_receivable_allocations_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.customer_receivable_allocations.customer_receivable_allocations_reason_check
ALTER TABLE ONLY public.customer_receivable_allocations ADD CONSTRAINT customer_receivable_allocations_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.customer_receivable_allocations.customer_receivable_allocations_receipt_transaction_ref_check
ALTER TABLE ONLY public.customer_receivable_allocations ADD CONSTRAINT customer_receivable_allocations_receipt_transaction_ref_check CHECK (length(btrim(receipt_transaction_ref)) >= 1);

-- public.customer_receivables.customer_receivables_check
ALTER TABLE ONLY public.customer_receivables ADD CONSTRAINT customer_receivables_check CHECK (remaining_amount >= 0 AND remaining_amount <= original_amount);

-- public.customer_receivables.customer_receivables_customer_ref_check
ALTER TABLE ONLY public.customer_receivables ADD CONSTRAINT customer_receivables_customer_ref_check CHECK (length(btrim(customer_ref)) >= 1);

-- public.customer_receivables.customer_receivables_device_id_check
ALTER TABLE ONLY public.customer_receivables ADD CONSTRAINT customer_receivables_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.customer_receivables.customer_receivables_original_amount_check
ALTER TABLE ONLY public.customer_receivables ADD CONSTRAINT customer_receivables_original_amount_check CHECK (original_amount > 0);

-- public.customer_receivables.customer_receivables_reason_check
ALTER TABLE ONLY public.customer_receivables ADD CONSTRAINT customer_receivables_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.customer_receivables.customer_receivables_sale_transaction_ref_check
ALTER TABLE ONLY public.customer_receivables ADD CONSTRAINT customer_receivables_sale_transaction_ref_check CHECK (length(btrim(sale_transaction_ref)) >= 1);

-- public.customer_receivables.customer_receivables_withholding_base_check
ALTER TABLE ONLY public.customer_receivables ADD CONSTRAINT customer_receivables_withholding_base_check CHECK (withholding_base_original >= 0 AND withholding_base_remaining >= 0 AND withholding_base_remaining <= withholding_base_original);

-- public.customer_receivables.customer_receivables_withholding_object_check
ALTER TABLE ONLY public.customer_receivables ADD CONSTRAINT customer_receivables_withholding_object_check CHECK (withholding_tax_object = ANY (ARRAY['NONE'::text, 'SERVICE'::text]));

-- public.customer_withholding_tax_credits.customer_withholding_tax_credits_device_id_check
ALTER TABLE ONLY public.customer_withholding_tax_credits ADD CONSTRAINT customer_withholding_tax_credits_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.customer_withholding_tax_credits.customer_withholding_tax_credits_legal_rule_snapshot_check
ALTER TABLE ONLY public.customer_withholding_tax_credits ADD CONSTRAINT customer_withholding_tax_credits_legal_rule_snapshot_check CHECK (jsonb_typeof(legal_rule_snapshot) = 'object'::text);

-- public.customer_withholding_tax_credits.customer_withholding_tax_credits_reason_check
ALTER TABLE ONLY public.customer_withholding_tax_credits ADD CONSTRAINT customer_withholding_tax_credits_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.customer_withholding_tax_credits.customer_withholding_tax_credits_tax_amount_check
ALTER TABLE ONLY public.customer_withholding_tax_credits ADD CONSTRAINT customer_withholding_tax_credits_tax_amount_check CHECK (tax_amount > 0);

-- public.customer_withholding_tax_credits.customer_withholding_tax_credits_tax_object_code_check
ALTER TABLE ONLY public.customer_withholding_tax_credits ADD CONSTRAINT customer_withholding_tax_credits_tax_object_code_check CHECK (tax_object_code = 'SERVICE'::text);

-- public.customer_withholding_tax_credits.customer_withholding_tax_credits_withholding_base_check
ALTER TABLE ONLY public.customer_withholding_tax_credits ADD CONSTRAINT customer_withholding_tax_credits_withholding_base_check CHECK (withholding_base > 0);

-- public.devices.devices_platform_check
ALTER TABLE ONLY public.devices ADD CONSTRAINT devices_platform_check CHECK (platform = ANY (ARRAY['android_play'::text, 'android_direct'::text]));

-- public.employee_payables.employee_payables_check
ALTER TABLE ONLY public.employee_payables ADD CONSTRAINT employee_payables_check CHECK (remaining_amount >= 0 AND remaining_amount <= original_amount);

-- public.employee_payables.employee_payables_device_id_check
ALTER TABLE ONLY public.employee_payables ADD CONSTRAINT employee_payables_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.employee_payables.employee_payables_original_amount_check
ALTER TABLE ONLY public.employee_payables ADD CONSTRAINT employee_payables_original_amount_check CHECK (original_amount > 0);

-- public.employee_payables.employee_payables_reason_check
ALTER TABLE ONLY public.employee_payables ADD CONSTRAINT employee_payables_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.employee_tax_profiles.employee_tax_profiles_check
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_check CHECK (valid_to IS NULL OR valid_to >= valid_from);

-- public.employee_tax_profiles.employee_tax_profiles_dependents_check
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_dependents_check CHECK (dependents >= 0 AND dependents <= 3);

-- public.employee_tax_profiles.employee_tax_profiles_device_id_check
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.employee_tax_profiles.employee_tax_profiles_employment_type_check
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_employment_type_check CHECK (employment_type = 'PERMANENT'::text);

-- public.employee_tax_profiles.employee_tax_profiles_legal_basis_check
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_legal_basis_check CHECK (length(btrim(legal_basis)) >= 3);

-- public.employee_tax_profiles.employee_tax_profiles_marital_status_check
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_marital_status_check CHECK (marital_status = ANY (ARRAY['TK'::text, 'K'::text]));

-- public.employee_tax_profiles.employee_tax_profiles_ptkp_amount_check
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_ptkp_amount_check CHECK (ptkp_amount > 0);

-- public.employee_tax_profiles.employee_tax_profiles_reason_check
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.employee_tax_profiles.employee_tax_profiles_tax_method_check
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_tax_method_check CHECK (tax_method = ANY (ARRAY['EMPLOYEE_BORNE'::text, 'GROSS_UP'::text]));

-- public.employee_tax_profiles.employee_tax_profiles_ter_category_check
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_ter_category_check CHECK (ter_category = ANY (ARRAY['A'::text, 'B'::text, 'C'::text]));

-- public.extended_withholding_liabilities.extended_withholding_liabilitie_withholding_base_original_check
ALTER TABLE ONLY public.extended_withholding_liabilities ADD CONSTRAINT extended_withholding_liabilitie_withholding_base_original_check CHECK (withholding_base_original > 0);

-- public.extended_withholding_liabilities.extended_withholding_liabilities_check
ALTER TABLE ONLY public.extended_withholding_liabilities ADD CONSTRAINT extended_withholding_liabilities_check CHECK (remaining_amount >= 0 AND remaining_amount <= original_amount);

-- public.extended_withholding_liabilities.extended_withholding_liabilities_check1
ALTER TABLE ONLY public.extended_withholding_liabilities ADD CONSTRAINT extended_withholding_liabilities_check1 CHECK (withholding_base_remaining >= 0 AND withholding_base_remaining <= withholding_base_original);

-- public.extended_withholding_liabilities.extended_withholding_liabilities_device_id_check
ALTER TABLE ONLY public.extended_withholding_liabilities ADD CONSTRAINT extended_withholding_liabilities_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.extended_withholding_liabilities.extended_withholding_liabilities_liability_account_check
ALTER TABLE ONLY public.extended_withholding_liabilities ADD CONSTRAINT extended_withholding_liabilities_liability_account_check CHECK (liability_account = ANY (ARRAY['2-2020'::text, '2-2080'::text]));

-- public.extended_withholding_liabilities.extended_withholding_liabilities_original_amount_check
ALTER TABLE ONLY public.extended_withholding_liabilities ADD CONSTRAINT extended_withholding_liabilities_original_amount_check CHECK (original_amount > 0);

-- public.extended_withholding_liabilities.extended_withholding_liabilities_reason_check
ALTER TABLE ONLY public.extended_withholding_liabilities ADD CONSTRAINT extended_withholding_liabilities_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.extended_withholding_liabilities.extended_withholding_liabilities_tax_object_code_check
ALTER TABLE ONLY public.extended_withholding_liabilities ADD CONSTRAINT extended_withholding_liabilities_tax_object_code_check CHECK (tax_object_code = ANY (ARRAY['ROYALTY'::text, 'INTEREST'::text, 'DIVIDEND'::text]));

-- public.extended_withholding_payments.extended_withholding_payments_cash_paid_check
ALTER TABLE ONLY public.extended_withholding_payments ADD CONSTRAINT extended_withholding_payments_cash_paid_check CHECK (cash_paid >= 0);

-- public.extended_withholding_payments.extended_withholding_payments_check
ALTER TABLE ONLY public.extended_withholding_payments ADD CONSTRAINT extended_withholding_payments_check CHECK (withholding_amount > 0 AND (cash_paid + withholding_amount) = gross_applied);

-- public.extended_withholding_payments.extended_withholding_payments_device_id_check
ALTER TABLE ONLY public.extended_withholding_payments ADD CONSTRAINT extended_withholding_payments_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.extended_withholding_payments.extended_withholding_payments_gross_applied_check
ALTER TABLE ONLY public.extended_withholding_payments ADD CONSTRAINT extended_withholding_payments_gross_applied_check CHECK (gross_applied > 0);

-- public.extended_withholding_payments.extended_withholding_payments_legal_rule_snapshot_check
ALTER TABLE ONLY public.extended_withholding_payments ADD CONSTRAINT extended_withholding_payments_legal_rule_snapshot_check CHECK (jsonb_typeof(legal_rule_snapshot) = 'object'::text);

-- public.extended_withholding_payments.extended_withholding_payments_reason_check
ALTER TABLE ONLY public.extended_withholding_payments ADD CONSTRAINT extended_withholding_payments_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.fixed_asset_depreciation_events.fixed_asset_depreciation_events_accumulated_after_check
ALTER TABLE ONLY public.fixed_asset_depreciation_events ADD CONSTRAINT fixed_asset_depreciation_events_accumulated_after_check CHECK (accumulated_after > 0);

-- public.fixed_asset_depreciation_events.fixed_asset_depreciation_events_amount_check
ALTER TABLE ONLY public.fixed_asset_depreciation_events ADD CONSTRAINT fixed_asset_depreciation_events_amount_check CHECK (amount > 0);

-- public.fixed_asset_depreciation_events.fixed_asset_depreciation_events_device_id_check
ALTER TABLE ONLY public.fixed_asset_depreciation_events ADD CONSTRAINT fixed_asset_depreciation_events_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.fixed_asset_depreciation_events.fixed_asset_depreciation_events_reason_check
ALTER TABLE ONLY public.fixed_asset_depreciation_events ADD CONSTRAINT fixed_asset_depreciation_events_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.fixed_asset_depreciation_events.fixed_asset_depreciation_events_sequence_no_check
ALTER TABLE ONLY public.fixed_asset_depreciation_events ADD CONSTRAINT fixed_asset_depreciation_events_sequence_no_check CHECK (sequence_no >= 1);

-- public.fixed_asset_depreciation_events.fixed_asset_depreciation_events_transaction_ref_check
ALTER TABLE ONLY public.fixed_asset_depreciation_events ADD CONSTRAINT fixed_asset_depreciation_events_transaction_ref_check CHECK (length(btrim(transaction_ref)) >= 1);

-- public.fixed_assets.fixed_assets_accumulated_depreciation_check
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_accumulated_depreciation_check CHECK (accumulated_depreciation >= 0);

-- public.fixed_assets.fixed_assets_asset_name_check
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_asset_name_check CHECK (length(btrim(asset_name)) >= 1);

-- public.fixed_assets.fixed_assets_asset_ref_check
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_asset_ref_check CHECK (length(btrim(asset_ref)) >= 1);

-- public.fixed_assets.fixed_assets_check
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_check CHECK (residual_value < cost);

-- public.fixed_assets.fixed_assets_check1
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_check1 CHECK (depreciation_start_date >= acquisition_date);

-- public.fixed_assets.fixed_assets_check2
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_check2 CHECK (accumulated_depreciation <= (cost - residual_value));

-- public.fixed_assets.fixed_assets_cost_check
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_cost_check CHECK (cost > 0);

-- public.fixed_assets.fixed_assets_depreciation_method_check
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_depreciation_method_check CHECK (depreciation_method = 'STRAIGHT_LINE'::text);

-- public.fixed_assets.fixed_assets_device_id_check
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.fixed_assets.fixed_assets_reason_check
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.fixed_assets.fixed_assets_residual_value_check
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_residual_value_check CHECK (residual_value >= 0);

-- public.fixed_assets.fixed_assets_status_check
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_status_check CHECK (status = ANY (ARRAY['ACTIVE'::text, 'FULLY_DEPRECIATED'::text]));

-- public.fixed_assets.fixed_assets_useful_life_months_check
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_useful_life_months_check CHECK (useful_life_months >= 1 AND useful_life_months <= 600);

-- public.inventory_average_events.inventory_average_events_business_ref_check
ALTER TABLE ONLY public.inventory_average_events ADD CONSTRAINT inventory_average_events_business_ref_check CHECK (length(btrim(business_ref)) >= 1);

-- public.inventory_average_events.inventory_average_events_device_id_check
ALTER TABLE ONLY public.inventory_average_events ADD CONSTRAINT inventory_average_events_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.inventory_average_events.inventory_average_events_event_type_check
ALTER TABLE ONLY public.inventory_average_events ADD CONSTRAINT inventory_average_events_event_type_check CHECK (event_type = ANY (ARRAY['receipt'::text, 'sale'::text, 'return'::text, 'adjustment'::text]));

-- public.inventory_average_events.inventory_average_events_quantity_delta_check
ALTER TABLE ONLY public.inventory_average_events ADD CONSTRAINT inventory_average_events_quantity_delta_check CHECK (quantity_delta <> 0);

-- public.inventory_average_events.inventory_average_events_reason_check
ALTER TABLE ONLY public.inventory_average_events ADD CONSTRAINT inventory_average_events_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.inventory_average_events.inventory_average_events_value_delta_check
ALTER TABLE ONLY public.inventory_average_events ADD CONSTRAINT inventory_average_events_value_delta_check CHECK (value_delta <> 0);

-- public.inventory_average_projection.inventory_average_projection_inventory_value_check
ALTER TABLE ONLY public.inventory_average_projection ADD CONSTRAINT inventory_average_projection_inventory_value_check CHECK (inventory_value >= 0);

-- public.inventory_average_projection.inventory_average_projection_on_hand_qty_check
ALTER TABLE ONLY public.inventory_average_projection ADD CONSTRAINT inventory_average_projection_on_hand_qty_check CHECK (on_hand_qty >= 0);

-- public.inventory_average_projection.inventory_average_projection_revision_check
ALTER TABLE ONLY public.inventory_average_projection ADD CONSTRAINT inventory_average_projection_revision_check CHECK (revision > 0);

-- public.inventory_average_projection.inventory_average_zero_value_check
ALTER TABLE ONLY public.inventory_average_projection ADD CONSTRAINT inventory_average_zero_value_check CHECK (on_hand_qty > 0 OR inventory_value = 0);

-- public.inventory_cost_layer_projection.inventory_cost_layer_projection_remaining_qty_check
ALTER TABLE ONLY public.inventory_cost_layer_projection ADD CONSTRAINT inventory_cost_layer_projection_remaining_qty_check CHECK (remaining_qty >= 0);

-- public.inventory_cost_layer_projection.inventory_cost_layer_projection_revision_check
ALTER TABLE ONLY public.inventory_cost_layer_projection ADD CONSTRAINT inventory_cost_layer_projection_revision_check CHECK (revision > 0);

-- public.inventory_cost_layer_projection.inventory_cost_layer_projection_unit_cost_check
ALTER TABLE ONLY public.inventory_cost_layer_projection ADD CONSTRAINT inventory_cost_layer_projection_unit_cost_check CHECK (unit_cost >= 0);

-- public.inventory_events.inventory_events_component_identity_check
ALTER TABLE ONLY public.inventory_events ADD CONSTRAINT inventory_events_component_identity_check CHECK (event_component = 'combined'::text AND lot_id IS NOT NULL AND length(btrim(lot_id)) > 0 AND cost_layer_id IS NOT NULL AND length(btrim(cost_layer_id)) > 0 OR event_component = 'physical'::text AND lot_id IS NOT NULL AND length(btrim(lot_id)) > 0 AND cost_layer_id IS NULL OR event_component = 'valuation'::text AND lot_id IS NULL AND cost_layer_id IS NOT NULL AND length(btrim(cost_layer_id)) > 0);

-- public.inventory_events.inventory_events_event_component_check
ALTER TABLE ONLY public.inventory_events ADD CONSTRAINT inventory_events_event_component_check CHECK (event_component = ANY (ARRAY['combined'::text, 'physical'::text, 'valuation'::text]));

-- public.inventory_events.inventory_events_event_type_check
ALTER TABLE ONLY public.inventory_events ADD CONSTRAINT inventory_events_event_type_check CHECK (event_type = ANY (ARRAY['receipt'::text, 'sale'::text, 'adjustment'::text, 'reversal'::text]));

-- public.inventory_events.inventory_events_quantity_delta_check
ALTER TABLE ONLY public.inventory_events ADD CONSTRAINT inventory_events_quantity_delta_check CHECK (quantity_delta <> 0);

-- public.inventory_events.inventory_events_unit_cost_check
ALTER TABLE ONLY public.inventory_events ADD CONSTRAINT inventory_events_unit_cost_check CHECK (unit_cost >= 0);

-- public.inventory_lot_projection.inventory_lot_projection_on_hand_qty_check
ALTER TABLE ONLY public.inventory_lot_projection ADD CONSTRAINT inventory_lot_projection_on_hand_qty_check CHECK (on_hand_qty >= 0);

-- public.inventory_lot_projection.inventory_lot_projection_revision_check
ALTER TABLE ONLY public.inventory_lot_projection ADD CONSTRAINT inventory_lot_projection_revision_check CHECK (revision > 0);

-- public.inventory_product_projection.inventory_product_projection_on_hand_qty_check
ALTER TABLE ONLY public.inventory_product_projection ADD CONSTRAINT inventory_product_projection_on_hand_qty_check CHECK (on_hand_qty >= 0);

-- public.inventory_product_projection.inventory_product_projection_revision_check
ALTER TABLE ONLY public.inventory_product_projection ADD CONSTRAINT inventory_product_projection_revision_check CHECK (revision > 0);

-- public.licences.licences_max_user_check
ALTER TABLE ONLY public.licences ADD CONSTRAINT licences_max_user_check CHECK (max_user > 0);

-- public.licences.licences_package_id_check
ALTER TABLE ONLY public.licences ADD CONSTRAINT licences_package_id_check CHECK (package_id = ANY (ARRAY['com.btp.uat'::text, 'com.btp.pos'::text]));

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_app_version_check
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_app_version_check CHECK (length(btrim(app_version)) >= 1);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_check
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_check CHECK (gross_turnover_ytd_after = (gross_turnover_ytd_before + gross_turnover_month));

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_check1
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_check1 CHECK (exempt_turnover_month >= 0 AND exempt_turnover_month <= gross_turnover_month);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_check2
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_check2 CHECK (taxable_turnover_month = (gross_turnover_month - exempt_turnover_month));

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_check3
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_check3 CHECK (period_end = (date_trunc('month'::text, period_start::timestamp with time zone) + '1 mon -1 days'::interval)::date);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_check4
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_check4 CHECK (tax_amount = 0 AND tax_journal_id IS NULL AND tax_document_id IS NULL OR tax_amount > 0 AND tax_journal_id IS NOT NULL AND tax_document_id IS NOT NULL);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_device_id_check
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_gross_turnover_month_check
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_gross_turnover_month_check CHECK (gross_turnover_month >= 0);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_gross_turnover_ytd_before_check
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_gross_turnover_ytd_before_check CHECK (gross_turnover_ytd_before >= 0);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_period_start_check
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_period_start_check CHECK (period_start = date_trunc('month'::text, period_start::timestamp with time zone)::date);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_reason_check
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_tax_amount_check
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_tax_amount_check CHECK (tax_amount >= 0);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_tax_rule_snapshot_check
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_tax_rule_snapshot_check CHECK (jsonb_typeof(tax_rule_snapshot) = 'object'::text);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_taxpayer_type_check
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_taxpayer_type_check CHECK (taxpayer_type = ANY (ARRAY['OP'::text, 'PT_PERORANGAN'::text, 'KOPERASI'::text]));

-- public.payroll_payment_allocations.payroll_payment_allocations_amount_applied_check
ALTER TABLE ONLY public.payroll_payment_allocations ADD CONSTRAINT payroll_payment_allocations_amount_applied_check CHECK (amount_applied > 0);

-- public.payroll_payment_allocations.payroll_payment_allocations_device_id_check
ALTER TABLE ONLY public.payroll_payment_allocations ADD CONSTRAINT payroll_payment_allocations_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.payroll_payment_allocations.payroll_payment_allocations_payment_transaction_ref_check
ALTER TABLE ONLY public.payroll_payment_allocations ADD CONSTRAINT payroll_payment_allocations_payment_transaction_ref_check CHECK (length(btrim(payment_transaction_ref)) >= 1);

-- public.payroll_payment_allocations.payroll_payment_allocations_reason_check
ALTER TABLE ONLY public.payroll_payment_allocations ADD CONSTRAINT payroll_payment_allocations_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.payroll_tax_evidence.payroll_tax_evidence_annual_pph21_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_annual_pph21_check CHECK (annual_pph21 >= 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_annual_taxable_income_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_annual_taxable_income_check CHECK (annual_taxable_income >= 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_cash_compensation_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_cash_compensation_check CHECK (cash_compensation > 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_device_id_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.payroll_tax_evidence.payroll_tax_evidence_employee_pension_contribution_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_employee_pension_contribution_check CHECK (employee_pension_contribution >= 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_job_expense_deduction_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_job_expense_deduction_check CHECK (job_expense_deduction >= 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_mandatory_religious_contribution_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_mandatory_religious_contribution_check CHECK (mandatory_religious_contribution >= 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_payroll_ref_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_payroll_ref_check CHECK (length(btrim(payroll_ref)) >= 1);

-- public.payroll_tax_evidence.payroll_tax_evidence_prior_withholding_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_prior_withholding_check CHECK (prior_withholding >= 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_ptkp_amount_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_ptkp_amount_check CHECK (ptkp_amount > 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_reason_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.payroll_tax_evidence.payroll_tax_evidence_rule_snapshot_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_rule_snapshot_check CHECK (jsonb_typeof(rule_snapshot) = 'object'::text);

-- public.payroll_tax_evidence.payroll_tax_evidence_salary_payable_amount_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_salary_payable_amount_check CHECK (salary_payable_amount > 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_tax_allowance_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_tax_allowance_check CHECK (tax_allowance >= 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_tax_method_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_tax_method_check CHECK (tax_method = ANY (ARRAY['EMPLOYEE_BORNE'::text, 'GROSS_UP'::text]));

-- public.payroll_tax_evidence.payroll_tax_evidence_taxable_gross_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_taxable_gross_check CHECK (taxable_gross > 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_ter_category_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_ter_category_check CHECK (ter_category = ANY (ARRAY['A'::text, 'B'::text, 'C'::text]));

-- public.payroll_tax_evidence.payroll_tax_evidence_ytd_job_expense_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_ytd_job_expense_check CHECK (ytd_job_expense >= 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_ytd_pension_contribution_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_ytd_pension_contribution_check CHECK (ytd_pension_contribution >= 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_ytd_religious_contribution_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_ytd_religious_contribution_check CHECK (ytd_religious_contribution >= 0);

-- public.payroll_tax_evidence.payroll_tax_evidence_ytd_taxable_gross_check
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_ytd_taxable_gross_check CHECK (ytd_taxable_gross >= 0);

-- public.plans.plans_duration_days_check
ALTER TABLE ONLY public.plans ADD CONSTRAINT plans_duration_days_check CHECK (duration_days > 0);

-- public.plans.plans_features_array
ALTER TABLE ONLY public.plans ADD CONSTRAINT plans_features_array CHECK (jsonb_typeof(features) = 'array'::text);

-- public.plans.plans_max_devices_check
ALTER TABLE ONLY public.plans ADD CONSTRAINT plans_max_devices_check CHECK (max_devices > 0);

-- public.plans.plans_price_idr_direct_check
ALTER TABLE ONLY public.plans ADD CONSTRAINT plans_price_idr_direct_check CHECK (price_idr_direct >= 0);

-- public.pos_manager_pins.pos_manager_pins_failed_attempts_check
ALTER TABLE ONLY public.pos_manager_pins ADD CONSTRAINT pos_manager_pins_failed_attempts_check CHECK (failed_attempts >= 0 AND failed_attempts <= 3);

-- public.pos_memberships.pos_memberships_role_check
ALTER TABLE ONLY public.pos_memberships ADD CONSTRAINT pos_memberships_role_check CHECK (role = ANY (ARRAY['cashier'::text, 'manager'::text, 'owner'::text]));

-- public.pos_pin_audit.pos_pin_audit_attempt_count_check
ALTER TABLE ONLY public.pos_pin_audit ADD CONSTRAINT pos_pin_audit_attempt_count_check CHECK (attempt_count >= 0 AND attempt_count <= 3);

-- public.product_master.product_master_barcode_not_blank
ALTER TABLE ONLY public.product_master ADD CONSTRAINT product_master_barcode_not_blank CHECK (barcode IS NULL OR length(btrim(barcode)) >= 1 AND length(btrim(barcode)) <= 120);

-- public.product_master.product_master_expiry_policy
ALTER TABLE ONLY public.product_master ADD CONSTRAINT product_master_expiry_policy CHECK (track_expiry OR min_shelf_life_days = 0);

-- public.product_master.product_master_name_not_blank
ALTER TABLE ONLY public.product_master ADD CONSTRAINT product_master_name_not_blank CHECK (length(btrim(name_id)) >= 1 AND length(btrim(name_id)) <= 240);

-- public.product_master.product_master_price_nonnegative
ALTER TABLE ONLY public.product_master ADD CONSTRAINT product_master_price_nonnegative CHECK (price >= 0);

-- public.product_master.product_master_shelf_life_nonnegative
ALTER TABLE ONLY public.product_master ADD CONSTRAINT product_master_shelf_life_nonnegative CHECK (min_shelf_life_days >= 0);

-- public.product_master.product_master_sku_not_blank
ALTER TABLE ONLY public.product_master ADD CONSTRAINT product_master_sku_not_blank CHECK (length(btrim(sku)) >= 1 AND length(btrim(sku)) <= 120);

-- public.product_master.product_master_vat_object_code_check
ALTER TABLE ONLY public.product_master ADD CONSTRAINT product_master_vat_object_code_check CHECK (vat_object_code = ANY (ARRAY['NON_LUXURY'::text, 'LUXURY_CONSUMER'::text]));

-- public.product_master.product_master_version_positive
ALTER TABLE ONLY public.product_master ADD CONSTRAINT product_master_version_positive CHECK (version > 0);

-- public.receivable_allowance_events.receivable_allowance_events_adjustment_transaction_ref_check
ALTER TABLE ONLY public.receivable_allowance_events ADD CONSTRAINT receivable_allowance_events_adjustment_transaction_ref_check CHECK (length(btrim(adjustment_transaction_ref)) >= 1);

-- public.receivable_allowance_events.receivable_allowance_events_device_id_check
ALTER TABLE ONLY public.receivable_allowance_events ADD CONSTRAINT receivable_allowance_events_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.receivable_allowance_events.receivable_allowance_events_previous_allowance_check
ALTER TABLE ONLY public.receivable_allowance_events ADD CONSTRAINT receivable_allowance_events_previous_allowance_check CHECK (previous_allowance >= 0);

-- public.receivable_allowance_events.receivable_allowance_events_reason_check
ALTER TABLE ONLY public.receivable_allowance_events ADD CONSTRAINT receivable_allowance_events_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.receivable_allowance_events.receivable_allowance_events_target_allowance_check
ALTER TABLE ONLY public.receivable_allowance_events ADD CONSTRAINT receivable_allowance_events_target_allowance_check CHECK (target_allowance >= 0);

-- public.receivable_allowances.receivable_allowances_allowance_amount_check
ALTER TABLE ONLY public.receivable_allowances ADD CONSTRAINT receivable_allowances_allowance_amount_check CHECK (allowance_amount >= 0);

-- public.receivable_allowances.receivable_allowances_customer_ref_check
ALTER TABLE ONLY public.receivable_allowances ADD CONSTRAINT receivable_allowances_customer_ref_check CHECK (length(btrim(customer_ref)) >= 1);

-- public.sale_line_evidence.sale_line_evidence_check
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_check CHECK (line_kind = 'STOCK'::text AND product_id IS NOT NULL AND original_cogs > 0 OR line_kind = 'SERVICE'::text AND product_id IS NULL AND original_cogs = 0);

-- public.sale_line_evidence.sale_line_evidence_discount_amount_check
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_discount_amount_check CHECK (discount_amount >= 0);

-- public.sale_line_evidence.sale_line_evidence_discount_check
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_discount_check CHECK (discount_amount < list_amount);

-- public.sale_line_evidence.sale_line_evidence_dpp_check
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_dpp_check CHECK (dpp >= 0);

-- public.sale_line_evidence.sale_line_evidence_gross_amount_check
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_gross_amount_check CHECK (gross_amount >= 0);

-- public.sale_line_evidence.sale_line_evidence_identity_check
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_identity_check CHECK (line_kind = 'STOCK'::text AND product_id IS NOT NULL AND service_profile_id IS NULL OR line_kind = 'SERVICE'::text AND product_id IS NULL AND service_profile_id IS NOT NULL);

-- public.sale_line_evidence.sale_line_evidence_line_kind_check
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_line_kind_check CHECK (line_kind = ANY (ARRAY['STOCK'::text, 'SERVICE'::text]));

-- public.sale_line_evidence.sale_line_evidence_list_amount_check
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_list_amount_check CHECK (list_amount > 0);

-- public.sale_line_evidence.sale_line_evidence_original_cogs_check
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_original_cogs_check CHECK (original_cogs >= 0);

-- public.sale_line_evidence.sale_line_evidence_quantity_check
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_quantity_check CHECK (quantity > 0);

-- public.sale_line_evidence.sale_line_evidence_tax_snapshot_check
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_tax_snapshot_check CHECK (jsonb_typeof(tax_snapshot) = 'object'::text);

-- public.sale_line_evidence.sale_line_evidence_unit_price_check
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_unit_price_check CHECK (unit_price > 0);

-- public.sale_line_evidence.sale_line_evidence_vat_amount_check
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_vat_amount_check CHECK (vat_amount >= 0);

-- public.sale_return_line_evidence.sale_return_line_evidence_cogs_restored_check
ALTER TABLE ONLY public.sale_return_line_evidence ADD CONSTRAINT sale_return_line_evidence_cogs_restored_check CHECK (cogs_restored >= 0);

-- public.sale_return_line_evidence.sale_return_line_evidence_dpp_reversed_check
ALTER TABLE ONLY public.sale_return_line_evidence ADD CONSTRAINT sale_return_line_evidence_dpp_reversed_check CHECK (dpp_reversed >= 0);

-- public.sale_return_line_evidence.sale_return_line_evidence_quantity_check
ALTER TABLE ONLY public.sale_return_line_evidence ADD CONSTRAINT sale_return_line_evidence_quantity_check CHECK (quantity > 0);

-- public.sale_return_line_evidence.sale_return_line_evidence_vat_reversed_check
ALTER TABLE ONLY public.sale_return_line_evidence ADD CONSTRAINT sale_return_line_evidence_vat_reversed_check CHECK (vat_reversed >= 0);

-- public.service_tax_profiles.service_tax_profiles_check
ALTER TABLE ONLY public.service_tax_profiles ADD CONSTRAINT service_tax_profiles_check CHECK (valid_to IS NULL OR valid_to >= valid_from);

-- public.service_tax_profiles.service_tax_profiles_device_id_check
ALTER TABLE ONLY public.service_tax_profiles ADD CONSTRAINT service_tax_profiles_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.service_tax_profiles.service_tax_profiles_legal_basis_check
ALTER TABLE ONLY public.service_tax_profiles ADD CONSTRAINT service_tax_profiles_legal_basis_check CHECK (length(btrim(legal_basis)) >= 3);

-- public.service_tax_profiles.service_tax_profiles_name_id_check
ALTER TABLE ONLY public.service_tax_profiles ADD CONSTRAINT service_tax_profiles_name_id_check CHECK (length(btrim(name_id)) >= 1);

-- public.service_tax_profiles.service_tax_profiles_pph23_object_check
ALTER TABLE ONLY public.service_tax_profiles ADD CONSTRAINT service_tax_profiles_pph23_object_check CHECK (pph23_object_code = ANY (ARRAY['NONE'::text, 'SERVICE'::text]));

-- public.service_tax_profiles.service_tax_profiles_reason_check
ALTER TABLE ONLY public.service_tax_profiles ADD CONSTRAINT service_tax_profiles_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.service_tax_profiles.service_tax_profiles_service_code_check
ALTER TABLE ONLY public.service_tax_profiles ADD CONSTRAINT service_tax_profiles_service_code_check CHECK (length(btrim(service_code)) >= 1);

-- public.service_tax_profiles.service_tax_profiles_unit_price_check
ALTER TABLE ONLY public.service_tax_profiles ADD CONSTRAINT service_tax_profiles_unit_price_check CHECK (unit_price > 0);

-- public.service_tax_profiles.service_tax_profiles_vat_object_code_check
ALTER TABLE ONLY public.service_tax_profiles ADD CONSTRAINT service_tax_profiles_vat_object_code_check CHECK (vat_object_code = ANY (ARRAY['NON_LUXURY'::text, 'LUXURY_CONSUMER'::text]));

-- public.subscription_events.subscription_events_provider_check
ALTER TABLE ONLY public.subscription_events ADD CONSTRAINT subscription_events_provider_check CHECK (provider = ANY (ARRAY['play_billing'::text, 'midtrans'::text, 'system'::text]));

-- public.subscriptions.midtrans_amount_positive
ALTER TABLE ONLY public.subscriptions ADD CONSTRAINT midtrans_amount_positive CHECK (midtrans_amount_idr IS NULL OR midtrans_amount_idr > 0);

-- public.subscriptions.midtrans_duration_positive
ALTER TABLE ONLY public.subscriptions ADD CONSTRAINT midtrans_duration_positive CHECK (midtrans_duration_days IS NULL OR midtrans_duration_days > 0);

-- public.subscriptions.subscriptions_grace_check
ALTER TABLE ONLY public.subscriptions ADD CONSTRAINT subscriptions_grace_check CHECK (grace_period_end IS NULL OR grace_period_end >= current_period_end);

-- public.subscriptions.subscriptions_period_check
ALTER TABLE ONLY public.subscriptions ADD CONSTRAINT subscriptions_period_check CHECK (current_period_end >= current_period_start);

-- public.subscriptions.subscriptions_provider_check
ALTER TABLE ONLY public.subscriptions ADD CONSTRAINT subscriptions_provider_check CHECK (payment_provider = ANY (ARRAY['play_billing'::text, 'midtrans'::text]));

-- public.subscriptions.subscriptions_provider_identity_check
ALTER TABLE ONLY public.subscriptions ADD CONSTRAINT subscriptions_provider_identity_check CHECK (payment_provider = 'play_billing'::text AND play_purchase_token IS NOT NULL OR payment_provider = 'midtrans'::text AND midtrans_order_id IS NOT NULL);

-- public.subscriptions.subscriptions_status_check
ALTER TABLE ONLY public.subscriptions ADD CONSTRAINT subscriptions_status_check CHECK (status = ANY (ARRAY['pending'::text, 'active'::text, 'past_due'::text, 'expired'::text, 'cancelled'::text]));

-- public.supplier_liabilities.supplier_liabilities_check
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_check CHECK (remaining_amount >= 0 AND remaining_amount <= original_amount);

-- public.supplier_liabilities.supplier_liabilities_device_id_check
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.supplier_liabilities.supplier_liabilities_liability_kind_check
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_liability_kind_check CHECK (liability_kind = ANY (ARRAY['INVENTORY'::text, 'SERVICE'::text, 'RENT'::text]));

-- public.supplier_liabilities.supplier_liabilities_original_amount_check
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_original_amount_check CHECK (original_amount > 0);

-- public.supplier_liabilities.supplier_liabilities_purchase_transaction_ref_check
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_purchase_transaction_ref_check CHECK (length(btrim(purchase_transaction_ref)) >= 1);

-- public.supplier_liabilities.supplier_liabilities_reason_check
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.supplier_liabilities.supplier_liabilities_supplier_ref_check
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_supplier_ref_check CHECK (length(btrim(supplier_ref)) >= 1);

-- public.supplier_liabilities.supplier_liabilities_tax_object_code_check
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_tax_object_code_check CHECK (tax_object_code = ANY (ARRAY['NONE'::text, 'SERVICE'::text, 'ASSET_RENT_NON_LAND_BUILDING'::text, 'LAND_BUILDING_RENT'::text, 'ROYALTY'::text, 'INTEREST'::text, 'DIVIDEND'::text]));

-- public.supplier_liabilities.supplier_liabilities_withholding_base_check
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_withholding_base_check CHECK (withholding_base_original >= 0 AND withholding_base_remaining >= 0 AND withholding_base_remaining <= withholding_base_original);

-- public.supplier_payment_allocations.supplier_payment_allocations_check
ALTER TABLE ONLY public.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_check CHECK (cash_paid >= 0 AND cash_paid <= gross_applied);

-- public.supplier_payment_allocations.supplier_payment_allocations_check1
ALTER TABLE ONLY public.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_check1 CHECK (withholding_amount >= 0 AND withholding_amount < gross_applied);

-- public.supplier_payment_allocations.supplier_payment_allocations_device_id_check
ALTER TABLE ONLY public.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.supplier_payment_allocations.supplier_payment_allocations_gross_applied_check
ALTER TABLE ONLY public.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_gross_applied_check CHECK (gross_applied > 0);

-- public.supplier_payment_allocations.supplier_payment_allocations_payment_transaction_ref_check
ALTER TABLE ONLY public.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_payment_transaction_ref_check CHECK (length(btrim(payment_transaction_ref)) >= 1);

-- public.supplier_payment_allocations.supplier_payment_allocations_reason_check
ALTER TABLE ONLY public.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.tax_document_events.tax_document_events_details_check
ALTER TABLE ONLY public.tax_document_events ADD CONSTRAINT tax_document_events_details_check CHECK (jsonb_typeof(details) = 'object'::text);

-- public.tax_document_events.tax_document_events_device_id_check
ALTER TABLE ONLY public.tax_document_events ADD CONSTRAINT tax_document_events_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.tax_document_events.tax_document_events_reason_check
ALTER TABLE ONLY public.tax_document_events ADD CONSTRAINT tax_document_events_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.tax_document_lines.tax_document_lines_check
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_check CHECK (discount_amount >= 0 AND discount_amount < list_amount);

-- public.tax_document_lines.tax_document_lines_check1
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_check1 CHECK (gross_amount = (dpp + tax_amount));

-- public.tax_document_lines.tax_document_lines_dpp_check
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_dpp_check CHECK (dpp >= 0);

-- public.tax_document_lines.tax_document_lines_gross_amount_check
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_gross_amount_check CHECK (gross_amount >= 0);

-- public.tax_document_lines.tax_document_lines_item_code_check
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_item_code_check CHECK (length(btrim(item_code)) >= 1);

-- public.tax_document_lines.tax_document_lines_item_name_check
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_item_name_check CHECK (length(btrim(item_name)) >= 1);

-- public.tax_document_lines.tax_document_lines_line_kind_check
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_line_kind_check CHECK (line_kind = ANY (ARRAY['STOCK'::text, 'SERVICE'::text]));

-- public.tax_document_lines.tax_document_lines_list_amount_check
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_list_amount_check CHECK (list_amount > 0);

-- public.tax_document_lines.tax_document_lines_quantity_check
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_quantity_check CHECK (quantity > 0);

-- public.tax_document_lines.tax_document_lines_tax_amount_check
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_tax_amount_check CHECK (tax_amount >= 0);

-- public.tax_document_lines.tax_document_lines_tax_rule_snapshot_check
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_tax_rule_snapshot_check CHECK (jsonb_typeof(tax_rule_snapshot) = 'object'::text);

-- public.tax_document_lines.tax_document_lines_unit_price_check
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_unit_price_check CHECK (unit_price > 0);

-- public.tax_documents.tax_documents_device_id_check
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.tax_documents.tax_documents_document_type_check
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_document_type_check CHECK (document_type = ANY (ARRAY['VAT_OUTPUT'::text, 'VAT_INPUT'::text, 'VAT_RETURN'::text, 'VAT_REPLACEMENT'::text, 'VAT_CANCELLATION'::text, 'PPH21_26'::text, 'PPH23_UNIFICATION'::text, 'PPH_FINAL'::text]));

-- public.tax_documents.tax_documents_dpp_check
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_dpp_check CHECK (dpp >= 0);

-- public.tax_documents.tax_documents_gross_amount_check
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_gross_amount_check CHECK (gross_amount >= 0);

-- public.tax_documents.tax_documents_invoice_status_check
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_invoice_status_check CHECK (invoice_status = ANY (ARRAY['PENDING'::text, 'VALID'::text, 'INVALID'::text]));

-- public.tax_documents.tax_documents_legal_rule_snapshot_check
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_legal_rule_snapshot_check CHECK (jsonb_typeof(legal_rule_snapshot) = 'object'::text);

-- public.tax_documents.tax_documents_reason_check
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.tax_documents.tax_documents_status_check
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_status_check CHECK (status = ANY (ARRAY['DRAFT'::text, 'VALIDATED'::text, 'SUBMITTED'::text, 'ACCEPTED'::text, 'REJECTED'::text, 'CANCELLED'::text, 'REPLACED'::text, 'REPORTED'::text]));

-- public.tax_documents.tax_documents_tax_amount_check
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_tax_amount_check CHECK (tax_amount >= 0);

-- public.tax_documents.tax_documents_tax_rate_snapshot_check
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_tax_rate_snapshot_check CHECK (jsonb_typeof(tax_rate_snapshot) = 'object'::text);

-- public.tax_documents.tax_documents_vat_transaction_code_check
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_vat_transaction_code_check CHECK (vat_transaction_code IS NULL OR vat_transaction_code ~ '^[0-9]{2}$'::text);

-- public.tax_parties.tax_parties_certificate_status_check
ALTER TABLE ONLY public.tax_parties ADD CONSTRAINT tax_parties_certificate_status_check CHECK (certificate_status = ANY (ARRAY['VALID'::text, 'INVALID'::text, 'PENDING'::text, 'NOT_REQUIRED'::text]));

-- public.tax_parties.tax_parties_check
ALTER TABLE ONLY public.tax_parties ADD CONSTRAINT tax_parties_check CHECK (valid_to IS NULL OR valid_to >= valid_from);

-- public.tax_parties.tax_parties_device_id_check
ALTER TABLE ONLY public.tax_parties ADD CONSTRAINT tax_parties_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.tax_parties.tax_parties_display_name_check
ALTER TABLE ONLY public.tax_parties ADD CONSTRAINT tax_parties_display_name_check CHECK (length(btrim(display_name)) >= 1);

-- public.tax_parties.tax_parties_legal_basis_check
ALTER TABLE ONLY public.tax_parties ADD CONSTRAINT tax_parties_legal_basis_check CHECK (length(btrim(legal_basis)) >= 3);

-- public.tax_parties.tax_parties_metadata_check
ALTER TABLE ONLY public.tax_parties ADD CONSTRAINT tax_parties_metadata_check CHECK (jsonb_typeof(metadata) = 'object'::text);

-- public.tax_parties.tax_parties_party_kind_check
ALTER TABLE ONLY public.tax_parties ADD CONSTRAINT tax_parties_party_kind_check CHECK (party_kind = ANY (ARRAY['SELF'::text, 'CUSTOMER'::text, 'VENDOR'::text, 'EMPLOYEE'::text, 'SHAREHOLDER'::text]));

-- public.tax_parties.tax_parties_reason_check
ALTER TABLE ONLY public.tax_parties ADD CONSTRAINT tax_parties_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.tax_parties.tax_parties_taxpayer_type_check
ALTER TABLE ONLY public.tax_parties ADD CONSTRAINT tax_parties_taxpayer_type_check CHECK (taxpayer_type = ANY (ARRAY['OP'::text, 'BADAN'::text, 'PT_PERORANGAN'::text, 'KOPERASI'::text, 'PEMERINTAH'::text, 'LUAR_NEGERI'::text]));

-- public.tax_payment_refs.tax_payment_refs_amount_check
ALTER TABLE ONLY public.tax_payment_refs ADD CONSTRAINT tax_payment_refs_amount_check CHECK (amount > 0);

-- public.tax_payment_refs.tax_payment_refs_device_id_check
ALTER TABLE ONLY public.tax_payment_refs ADD CONSTRAINT tax_payment_refs_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.tax_payment_refs.tax_payment_refs_obligation_snapshot_check
ALTER TABLE ONLY public.tax_payment_refs ADD CONSTRAINT tax_payment_refs_obligation_snapshot_check CHECK (obligation_snapshot IS NULL OR obligation_snapshot > 0);

-- public.tax_payment_refs.tax_payment_refs_period_check
ALTER TABLE ONLY public.tax_payment_refs ADD CONSTRAINT tax_payment_refs_period_check CHECK (tax_period_start IS NULL AND tax_period_end IS NULL OR tax_period_start IS NOT NULL AND tax_period_end IS NOT NULL AND tax_period_end >= tax_period_start);

-- public.tax_payment_refs.tax_payment_refs_reason_check
ALTER TABLE ONLY public.tax_payment_refs ADD CONSTRAINT tax_payment_refs_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.tax_payment_refs.tax_payment_refs_status_check
ALTER TABLE ONLY public.tax_payment_refs ADD CONSTRAINT tax_payment_refs_status_check CHECK (status = ANY (ARRAY['CREATED'::text, 'PAID'::text, 'CANCELLED'::text]));

-- public.tax_payment_refs.tax_payment_refs_tax_code_check
ALTER TABLE ONLY public.tax_payment_refs ADD CONSTRAINT tax_payment_refs_tax_code_check CHECK (tax_code IS NULL OR (tax_code = ANY (ARRAY['PPN'::text, 'PPH21'::text, 'PPH23'::text, 'PPH_FINAL'::text, 'PPH25'::text, 'PPH29'::text])));

-- public.tax_rate_brackets.tax_rate_brackets_category_check
ALTER TABLE ONLY public.tax_rate_brackets ADD CONSTRAINT tax_rate_brackets_category_check CHECK (category = ANY (ARRAY['A'::text, 'B'::text, 'C'::text]));

-- public.tax_rate_brackets.tax_rate_brackets_check
ALTER TABLE ONLY public.tax_rate_brackets ADD CONSTRAINT tax_rate_brackets_check CHECK (upper_bound IS NULL OR upper_bound >= lower_bound);

-- public.tax_rate_brackets.tax_rate_brackets_check1
ALTER TABLE ONLY public.tax_rate_brackets ADD CONSTRAINT tax_rate_brackets_check1 CHECK (end_date IS NULL OR end_date >= effective_date);

-- public.tax_rate_brackets.tax_rate_brackets_legal_basis_check
ALTER TABLE ONLY public.tax_rate_brackets ADD CONSTRAINT tax_rate_brackets_legal_basis_check CHECK (length(btrim(legal_basis)) >= 3);

-- public.tax_rate_brackets.tax_rate_brackets_lower_bound_check
ALTER TABLE ONLY public.tax_rate_brackets ADD CONSTRAINT tax_rate_brackets_lower_bound_check CHECK (lower_bound >= 0);

-- public.tax_rate_brackets.tax_rate_brackets_rate_check
ALTER TABLE ONLY public.tax_rate_brackets ADD CONSTRAINT tax_rate_brackets_rate_check CHECK (rate >= 0::numeric AND rate <= 1::numeric);

-- public.tax_rate_brackets.tax_rate_brackets_tax_code_check
ALTER TABLE ONLY public.tax_rate_brackets ADD CONSTRAINT tax_rate_brackets_tax_code_check CHECK (tax_code = 'PPH21_TER'::text);

-- public.tax_rates.tax_rates_calculation_method_check
ALTER TABLE ONLY public.tax_rates ADD CONSTRAINT tax_rates_calculation_method_check CHECK (calculation_method = ANY (ARRAY['PERCENT_DPP'::text, 'DPP_NILAI_LAIN'::text, 'TURNOVER_FINAL'::text]));

-- public.tax_rates.tax_rates_check
ALTER TABLE ONLY public.tax_rates ADD CONSTRAINT tax_rates_check CHECK (end_date IS NULL OR end_date >= effective_date);

-- public.tax_rates.tax_rates_dpp_multiplier_check
ALTER TABLE ONLY public.tax_rates ADD CONSTRAINT tax_rates_dpp_multiplier_check CHECK (dpp_multiplier > 0::numeric AND dpp_multiplier <= 1::numeric);

-- public.tax_rates.tax_rates_legal_basis_check
ALTER TABLE ONLY public.tax_rates ADD CONSTRAINT tax_rates_legal_basis_check CHECK (length(btrim(legal_basis)) >= 3);

-- public.tax_rates.tax_rates_metadata_check
ALTER TABLE ONLY public.tax_rates ADD CONSTRAINT tax_rates_metadata_check CHECK (jsonb_typeof(metadata) = 'object'::text);

-- public.tax_rates.tax_rates_statutory_rate_check
ALTER TABLE ONLY public.tax_rates ADD CONSTRAINT tax_rates_statutory_rate_check CHECK (statutory_rate >= 0::numeric AND statutory_rate <= 1::numeric);

-- public.tax_rates.tax_rates_tax_code_check
ALTER TABLE ONLY public.tax_rates ADD CONSTRAINT tax_rates_tax_code_check CHECK (tax_code = ANY (ARRAY['PPN'::text, 'PPH23'::text, 'PPH_FINAL_4_2'::text, 'PPH_FINAL_UMKM'::text, 'PPH_BADAN'::text]));

-- public.tenants.tenants_paket_check
ALTER TABLE ONLY public.tenants ADD CONSTRAINT tenants_paket_check CHECK (paket = ANY (ARRAY['basic'::text, 'pro'::text, 'enterprise'::text]));

-- public.vat_period_settlements.vat_period_settlements_app_version_check
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_app_version_check CHECK (length(btrim(app_version)) >= 1);

-- public.vat_period_settlements.vat_period_settlements_carry_in_check
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_carry_in_check CHECK (carry_in >= 0);

-- public.vat_period_settlements.vat_period_settlements_carry_out_check
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_carry_out_check CHECK (carry_out >= 0);

-- public.vat_period_settlements.vat_period_settlements_check
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_check CHECK (period_end = (date_trunc('month'::text, period_start::timestamp with time zone) + '1 mon -1 days'::interval)::date);

-- public.vat_period_settlements.vat_period_settlements_check1
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_check1 CHECK (return_credit_reclass = GREATEST(output_vat_reductions - output_vat_charged, 0::bigint));

-- public.vat_period_settlements.vat_period_settlements_check2
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_check2 CHECK (offset_used = LEAST(GREATEST(output_vat_charged - output_vat_reductions, 0::bigint), input_vat_current + carry_in));

-- public.vat_period_settlements.vat_period_settlements_check3
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_check3 CHECK (net_payable = (GREATEST(output_vat_charged - output_vat_reductions, 0::bigint) - offset_used));

-- public.vat_period_settlements.vat_period_settlements_check4
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_check4 CHECK (carry_out = (input_vat_current + carry_in + return_credit_reclass - offset_used));

-- public.vat_period_settlements.vat_period_settlements_check5
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_check5 CHECK ((offset_used + return_credit_reclass) = 0 AND settlement_journal_id IS NULL OR (offset_used + return_credit_reclass) > 0 AND settlement_journal_id IS NOT NULL);

-- public.vat_period_settlements.vat_period_settlements_device_id_check
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_device_id_check CHECK (length(btrim(device_id)) >= 1);

-- public.vat_period_settlements.vat_period_settlements_input_vat_current_check
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_input_vat_current_check CHECK (input_vat_current >= 0);

-- public.vat_period_settlements.vat_period_settlements_net_payable_check
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_net_payable_check CHECK (net_payable >= 0);

-- public.vat_period_settlements.vat_period_settlements_offset_used_check
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_offset_used_check CHECK (offset_used >= 0);

-- public.vat_period_settlements.vat_period_settlements_output_vat_charged_check
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_output_vat_charged_check CHECK (output_vat_charged >= 0);

-- public.vat_period_settlements.vat_period_settlements_output_vat_reductions_check
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_output_vat_reductions_check CHECK (output_vat_reductions >= 0);

-- public.vat_period_settlements.vat_period_settlements_period_start_check
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_period_start_check CHECK (period_start = date_trunc('month'::text, period_start::timestamp with time zone)::date);

-- public.vat_period_settlements.vat_period_settlements_reason_check
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_reason_check CHECK (length(btrim(reason)) >= 3);

-- public.vat_period_settlements.vat_period_settlements_return_credit_reclass_check
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_return_credit_reclass_check CHECK (return_credit_reclass >= 0);

-- private.tenant_accounting_links.tenant_accounting_links_accounting_tenant_id_fkey
ALTER TABLE ONLY private.tenant_accounting_links ADD CONSTRAINT tenant_accounting_links_accounting_tenant_id_fkey FOREIGN KEY (accounting_tenant_id) REFERENCES accounting_tenants(tenant_id);

-- private.tenant_accounting_links.tenant_accounting_links_actor_user_id_fkey
ALTER TABLE ONLY private.tenant_accounting_links ADD CONSTRAINT tenant_accounting_links_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- private.tenant_accounting_links.tenant_accounting_links_config_tenant_id_fkey
ALTER TABLE ONLY private.tenant_accounting_links ADD CONSTRAINT tenant_accounting_links_config_tenant_id_fkey FOREIGN KEY (config_tenant_id) REFERENCES tenants(tenant_id);

-- public.accounting_events.accounting_events_actor_user_id_fkey
ALTER TABLE ONLY public.accounting_events ADD CONSTRAINT accounting_events_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- public.accounting_events.accounting_events_journal_id_fkey
ALTER TABLE ONLY public.accounting_events ADD CONSTRAINT accounting_events_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES accounting_journals(journal_id) ON DELETE RESTRICT;

-- public.accounting_events.accounting_events_tenant_id_fkey
ALTER TABLE ONLY public.accounting_events ADD CONSTRAINT accounting_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id) ON DELETE RESTRICT;

-- public.accounting_journal_lines.accounting_journal_lines_account_code_fkey
ALTER TABLE ONLY public.accounting_journal_lines ADD CONSTRAINT accounting_journal_lines_account_code_fkey FOREIGN KEY (account_code) REFERENCES accounting_coa(account_code);

-- public.accounting_journal_lines.accounting_line_journal_tenant_fk
ALTER TABLE ONLY public.accounting_journal_lines ADD CONSTRAINT accounting_line_journal_tenant_fk FOREIGN KEY (journal_id, tenant_id) REFERENCES accounting_journals(journal_id, tenant_id) ON DELETE RESTRICT;

-- public.accounting_journals.accounting_journals_actor_user_id_fkey
ALTER TABLE ONLY public.accounting_journals ADD CONSTRAINT accounting_journals_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- public.accounting_journals.accounting_journals_reversal_of_fkey
ALTER TABLE ONLY public.accounting_journals ADD CONSTRAINT accounting_journals_reversal_of_fkey FOREIGN KEY (reversal_of) REFERENCES accounting_journals(journal_id) ON DELETE RESTRICT;

-- public.accounting_journals.accounting_journals_tenant_id_fkey
ALTER TABLE ONLY public.accounting_journals ADD CONSTRAINT accounting_journals_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id) ON DELETE RESTRICT;

-- public.accounting_memberships.accounting_memberships_tenant_id_fkey
ALTER TABLE ONLY public.accounting_memberships ADD CONSTRAINT accounting_memberships_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id) ON DELETE RESTRICT;

-- public.accounting_memberships.accounting_memberships_user_id_fkey
ALTER TABLE ONLY public.accounting_memberships ADD CONSTRAINT accounting_memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- public.accounting_periods.accounting_periods_closed_by_fkey
ALTER TABLE ONLY public.accounting_periods ADD CONSTRAINT accounting_periods_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES auth.users(id) ON DELETE SET NULL;

-- public.accounting_periods.accounting_periods_reopened_by_fkey
ALTER TABLE ONLY public.accounting_periods ADD CONSTRAINT accounting_periods_reopened_by_fkey FOREIGN KEY (reopened_by) REFERENCES auth.users(id) ON DELETE SET NULL;

-- public.accounting_periods.accounting_periods_tenant_id_fkey
ALTER TABLE ONLY public.accounting_periods ADD CONSTRAINT accounting_periods_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id) ON DELETE RESTRICT;

-- public.accounting_tenants.accounting_tenants_owner_user_id_fkey
ALTER TABLE ONLY public.accounting_tenants ADD CONSTRAINT accounting_tenants_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- public.accounting_transaction_evidence.accounting_transaction_evidence_actor_user_id_fkey
ALTER TABLE ONLY public.accounting_transaction_evidence ADD CONSTRAINT accounting_transaction_evidence_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.accounting_transaction_evidence.accounting_transaction_evidence_journal_id_fkey
ALTER TABLE ONLY public.accounting_transaction_evidence ADD CONSTRAINT accounting_transaction_evidence_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES accounting_journals(journal_id);

-- public.accounting_transaction_evidence.accounting_transaction_evidence_tenant_id_fkey
ALTER TABLE ONLY public.accounting_transaction_evidence ADD CONSTRAINT accounting_transaction_evidence_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.coretax_outbox.coretax_outbox_tax_document_id_fkey
ALTER TABLE ONLY public.coretax_outbox ADD CONSTRAINT coretax_outbox_tax_document_id_fkey FOREIGN KEY (tax_document_id) REFERENCES tax_documents(tax_document_id);

-- public.coretax_outbox.coretax_outbox_tenant_id_fkey
ALTER TABLE ONLY public.coretax_outbox ADD CONSTRAINT coretax_outbox_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.coretax_template_registry.coretax_template_registry_verified_by_fkey
ALTER TABLE ONLY public.coretax_template_registry ADD CONSTRAINT coretax_template_registry_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES auth.users(id);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_actor_user_id_fkey
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_annual_journal_id_fkey
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_annual_journal_id_fkey FOREIGN KEY (annual_journal_id) REFERENCES accounting_journals(journal_id);

-- public.corporate_annual_tax_periods.corporate_annual_tax_periods_tenant_id_fkey
ALTER TABLE ONLY public.corporate_annual_tax_periods ADD CONSTRAINT corporate_annual_tax_periods_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_actor_user_id_fkey
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_reverses_adjustment_id_fkey
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_reverses_adjustment_id_fkey FOREIGN KEY (reverses_adjustment_id) REFERENCES corporate_fiscal_adjustments(adjustment_id);

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_tenant_id_fkey
ALTER TABLE ONLY public.corporate_fiscal_adjustments ADD CONSTRAINT corporate_fiscal_adjustments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.corporate_fiscal_loss_applications.corporate_fiscal_loss_applications_loss_id_fkey
ALTER TABLE ONLY public.corporate_fiscal_loss_applications ADD CONSTRAINT corporate_fiscal_loss_applications_loss_id_fkey FOREIGN KEY (loss_id) REFERENCES corporate_fiscal_loss_carryforwards(loss_id);

-- public.corporate_fiscal_loss_applications.corporate_fiscal_loss_applications_target_annual_period_id_fkey
ALTER TABLE ONLY public.corporate_fiscal_loss_applications ADD CONSTRAINT corporate_fiscal_loss_applications_target_annual_period_id_fkey FOREIGN KEY (target_annual_period_id) REFERENCES corporate_annual_tax_periods(annual_period_id);

-- public.corporate_fiscal_loss_applications.corporate_fiscal_loss_applications_tenant_id_fkey
ALTER TABLE ONLY public.corporate_fiscal_loss_applications ADD CONSTRAINT corporate_fiscal_loss_applications_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.corporate_fiscal_loss_carryforwards.corporate_fiscal_loss_carryforward_source_annual_period_id_fkey
ALTER TABLE ONLY public.corporate_fiscal_loss_carryforwards ADD CONSTRAINT corporate_fiscal_loss_carryforward_source_annual_period_id_fkey FOREIGN KEY (source_annual_period_id) REFERENCES corporate_annual_tax_periods(annual_period_id);

-- public.corporate_fiscal_loss_carryforwards.corporate_fiscal_loss_carryforwards_tenant_id_fkey
ALTER TABLE ONLY public.corporate_fiscal_loss_carryforwards ADD CONSTRAINT corporate_fiscal_loss_carryforwards_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_actor_user_id_fkey
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_source_annual_period_id_fkey
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_source_annual_period_id_fkey FOREIGN KEY (source_annual_period_id) REFERENCES corporate_annual_tax_periods(annual_period_id);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_supersedes_authority_id_fkey
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_supersedes_authority_id_fkey FOREIGN KEY (supersedes_authority_id) REFERENCES corporate_pph25_authorities(authority_id);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_tenant_id_fkey
ALTER TABLE ONLY public.corporate_pph25_authorities ADD CONSTRAINT corporate_pph25_authorities_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.customer_receivable_allocations.customer_receivable_allocatio_tenant_id_sale_transaction_r_fkey
ALTER TABLE ONLY public.customer_receivable_allocations ADD CONSTRAINT customer_receivable_allocatio_tenant_id_sale_transaction_r_fkey FOREIGN KEY (tenant_id, sale_transaction_ref) REFERENCES customer_receivables(tenant_id, sale_transaction_ref);

-- public.customer_receivable_allocations.customer_receivable_allocations_actor_user_id_fkey
ALTER TABLE ONLY public.customer_receivable_allocations ADD CONSTRAINT customer_receivable_allocations_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.customer_receivable_allocations.customer_receivable_allocations_receipt_journal_id_fkey
ALTER TABLE ONLY public.customer_receivable_allocations ADD CONSTRAINT customer_receivable_allocations_receipt_journal_id_fkey FOREIGN KEY (receipt_journal_id) REFERENCES accounting_journals(journal_id);

-- public.customer_receivable_allocations.customer_receivable_allocations_tenant_id_fkey
ALTER TABLE ONLY public.customer_receivable_allocations ADD CONSTRAINT customer_receivable_allocations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.customer_receivables.customer_receivables_actor_user_id_fkey
ALTER TABLE ONLY public.customer_receivables ADD CONSTRAINT customer_receivables_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.customer_receivables.customer_receivables_sale_journal_id_fkey
ALTER TABLE ONLY public.customer_receivables ADD CONSTRAINT customer_receivables_sale_journal_id_fkey FOREIGN KEY (sale_journal_id) REFERENCES accounting_journals(journal_id);

-- public.customer_receivables.customer_receivables_tenant_id_fkey
ALTER TABLE ONLY public.customer_receivables ADD CONSTRAINT customer_receivables_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.customer_withholding_tax_credits.customer_withholding_tax_credits_actor_user_id_fkey
ALTER TABLE ONLY public.customer_withholding_tax_credits ADD CONSTRAINT customer_withholding_tax_credits_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.customer_withholding_tax_credits.customer_withholding_tax_credits_receipt_journal_id_fkey
ALTER TABLE ONLY public.customer_withholding_tax_credits ADD CONSTRAINT customer_withholding_tax_credits_receipt_journal_id_fkey FOREIGN KEY (receipt_journal_id) REFERENCES accounting_journals(journal_id);

-- public.customer_withholding_tax_credits.customer_withholding_tax_credits_tenant_id_fkey
ALTER TABLE ONLY public.customer_withholding_tax_credits ADD CONSTRAINT customer_withholding_tax_credits_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.devices.devices_tenant_id_fkey
ALTER TABLE ONLY public.devices ADD CONSTRAINT devices_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE;

-- public.devices.devices_user_id_fkey
ALTER TABLE ONLY public.devices ADD CONSTRAINT devices_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- public.employee_payables.employee_payables_actor_user_id_fkey
ALTER TABLE ONLY public.employee_payables ADD CONSTRAINT employee_payables_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.employee_payables.employee_payables_payroll_journal_id_fkey
ALTER TABLE ONLY public.employee_payables ADD CONSTRAINT employee_payables_payroll_journal_id_fkey FOREIGN KEY (payroll_journal_id) REFERENCES accounting_journals(journal_id);

-- public.employee_payables.employee_payables_tenant_id_employee_party_id_fkey
ALTER TABLE ONLY public.employee_payables ADD CONSTRAINT employee_payables_tenant_id_employee_party_id_fkey FOREIGN KEY (tenant_id, employee_party_id) REFERENCES tax_parties(tenant_id, party_id);

-- public.employee_payables.employee_payables_tenant_id_fkey
ALTER TABLE ONLY public.employee_payables ADD CONSTRAINT employee_payables_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.employee_payables.employee_payables_tenant_id_payroll_ref_fkey
ALTER TABLE ONLY public.employee_payables ADD CONSTRAINT employee_payables_tenant_id_payroll_ref_fkey FOREIGN KEY (tenant_id, payroll_ref) REFERENCES payroll_tax_evidence(tenant_id, payroll_ref);

-- public.employee_tax_profiles.employee_tax_profiles_actor_user_id_fkey
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.employee_tax_profiles.employee_tax_profiles_tenant_id_employee_party_id_fkey
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_tenant_id_employee_party_id_fkey FOREIGN KEY (tenant_id, employee_party_id) REFERENCES tax_parties(tenant_id, party_id);

-- public.employee_tax_profiles.employee_tax_profiles_tenant_id_fkey
ALTER TABLE ONLY public.employee_tax_profiles ADD CONSTRAINT employee_tax_profiles_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.extended_withholding_liabilities.extended_withholding_liabilities_actor_user_id_fkey
ALTER TABLE ONLY public.extended_withholding_liabilities ADD CONSTRAINT extended_withholding_liabilities_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.extended_withholding_liabilities.extended_withholding_liabilities_source_journal_id_fkey
ALTER TABLE ONLY public.extended_withholding_liabilities ADD CONSTRAINT extended_withholding_liabilities_source_journal_id_fkey FOREIGN KEY (source_journal_id) REFERENCES accounting_journals(journal_id);

-- public.extended_withholding_liabilities.extended_withholding_liabilities_tenant_id_fkey
ALTER TABLE ONLY public.extended_withholding_liabilities ADD CONSTRAINT extended_withholding_liabilities_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.extended_withholding_payments.extended_withholding_payments_actor_user_id_fkey
ALTER TABLE ONLY public.extended_withholding_payments ADD CONSTRAINT extended_withholding_payments_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.extended_withholding_payments.extended_withholding_payments_payment_journal_id_fkey
ALTER TABLE ONLY public.extended_withholding_payments ADD CONSTRAINT extended_withholding_payments_payment_journal_id_fkey FOREIGN KEY (payment_journal_id) REFERENCES accounting_journals(journal_id);

-- public.extended_withholding_payments.extended_withholding_payments_tenant_id_fkey
ALTER TABLE ONLY public.extended_withholding_payments ADD CONSTRAINT extended_withholding_payments_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.fixed_asset_depreciation_events.fixed_asset_depreciation_events_actor_user_id_fkey
ALTER TABLE ONLY public.fixed_asset_depreciation_events ADD CONSTRAINT fixed_asset_depreciation_events_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.fixed_asset_depreciation_events.fixed_asset_depreciation_events_journal_id_fkey
ALTER TABLE ONLY public.fixed_asset_depreciation_events ADD CONSTRAINT fixed_asset_depreciation_events_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES accounting_journals(journal_id);

-- public.fixed_asset_depreciation_events.fixed_asset_depreciation_events_tenant_id_asset_id_fkey
ALTER TABLE ONLY public.fixed_asset_depreciation_events ADD CONSTRAINT fixed_asset_depreciation_events_tenant_id_asset_id_fkey FOREIGN KEY (tenant_id, asset_id) REFERENCES fixed_assets(tenant_id, asset_id);

-- public.fixed_asset_depreciation_events.fixed_asset_depreciation_events_tenant_id_fkey
ALTER TABLE ONLY public.fixed_asset_depreciation_events ADD CONSTRAINT fixed_asset_depreciation_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.fixed_assets.fixed_assets_acquisition_journal_id_fkey
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_acquisition_journal_id_fkey FOREIGN KEY (acquisition_journal_id) REFERENCES accounting_journals(journal_id);

-- public.fixed_assets.fixed_assets_actor_user_id_fkey
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.fixed_assets.fixed_assets_tenant_id_fkey
ALTER TABLE ONLY public.fixed_assets ADD CONSTRAINT fixed_assets_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.inventory_average_events.inventory_average_event_product_fk
ALTER TABLE ONLY public.inventory_average_events ADD CONSTRAINT inventory_average_event_product_fk FOREIGN KEY (tenant_id, product_id) REFERENCES product_master(tenant_id, product_id);

-- public.inventory_average_events.inventory_average_events_actor_user_id_fkey
ALTER TABLE ONLY public.inventory_average_events ADD CONSTRAINT inventory_average_events_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.inventory_average_projection.inventory_average_product_fk
ALTER TABLE ONLY public.inventory_average_projection ADD CONSTRAINT inventory_average_product_fk FOREIGN KEY (tenant_id, product_id) REFERENCES product_master(tenant_id, product_id);

-- public.inventory_cost_layer_projection.inventory_cost_projection_product_fk
ALTER TABLE ONLY public.inventory_cost_layer_projection ADD CONSTRAINT inventory_cost_projection_product_fk FOREIGN KEY (tenant_id, product_id) REFERENCES product_master(tenant_id, product_id) ON DELETE RESTRICT;

-- public.inventory_events.inventory_events_actor_user_id_fkey
ALTER TABLE ONLY public.inventory_events ADD CONSTRAINT inventory_events_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

-- public.inventory_events.inventory_events_tenant_id_fkey
ALTER TABLE ONLY public.inventory_events ADD CONSTRAINT inventory_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id) ON DELETE RESTRICT;

-- public.inventory_events.inventory_events_tenant_product_fk
ALTER TABLE ONLY public.inventory_events ADD CONSTRAINT inventory_events_tenant_product_fk FOREIGN KEY (tenant_id, product_id) REFERENCES product_master(tenant_id, product_id) ON DELETE RESTRICT;

-- public.inventory_lot_projection.inventory_lot_projection_product_fk
ALTER TABLE ONLY public.inventory_lot_projection ADD CONSTRAINT inventory_lot_projection_product_fk FOREIGN KEY (tenant_id, product_id) REFERENCES product_master(tenant_id, product_id) ON DELETE RESTRICT;

-- public.inventory_product_projection.inventory_product_projection_product_fk
ALTER TABLE ONLY public.inventory_product_projection ADD CONSTRAINT inventory_product_projection_product_fk FOREIGN KEY (tenant_id, product_id) REFERENCES product_master(tenant_id, product_id) ON DELETE RESTRICT;

-- public.licences.licences_tenant_id_fkey
ALTER TABLE ONLY public.licences ADD CONSTRAINT licences_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE;

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_actor_user_id_fkey
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_tax_document_id_fkey
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_tax_document_id_fkey FOREIGN KEY (tax_document_id) REFERENCES tax_documents(tax_document_id);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_tax_journal_id_fkey
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_tax_journal_id_fkey FOREIGN KEY (tax_journal_id) REFERENCES accounting_journals(journal_id);

-- public.owner_turnover_tax_periods.owner_turnover_tax_periods_tenant_id_fkey
ALTER TABLE ONLY public.owner_turnover_tax_periods ADD CONSTRAINT owner_turnover_tax_periods_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.payroll_payment_allocations.payroll_payment_allocations_actor_user_id_fkey
ALTER TABLE ONLY public.payroll_payment_allocations ADD CONSTRAINT payroll_payment_allocations_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.payroll_payment_allocations.payroll_payment_allocations_payment_journal_id_fkey
ALTER TABLE ONLY public.payroll_payment_allocations ADD CONSTRAINT payroll_payment_allocations_payment_journal_id_fkey FOREIGN KEY (payment_journal_id) REFERENCES accounting_journals(journal_id);

-- public.payroll_payment_allocations.payroll_payment_allocations_tenant_id_employee_party_id_fkey
ALTER TABLE ONLY public.payroll_payment_allocations ADD CONSTRAINT payroll_payment_allocations_tenant_id_employee_party_id_fkey FOREIGN KEY (tenant_id, employee_party_id) REFERENCES tax_parties(tenant_id, party_id);

-- public.payroll_payment_allocations.payroll_payment_allocations_tenant_id_fkey
ALTER TABLE ONLY public.payroll_payment_allocations ADD CONSTRAINT payroll_payment_allocations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.payroll_payment_allocations.payroll_payment_allocations_tenant_id_payroll_ref_fkey
ALTER TABLE ONLY public.payroll_payment_allocations ADD CONSTRAINT payroll_payment_allocations_tenant_id_payroll_ref_fkey FOREIGN KEY (tenant_id, payroll_ref) REFERENCES employee_payables(tenant_id, payroll_ref);

-- public.payroll_tax_evidence.payroll_tax_evidence_actor_user_id_fkey
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.payroll_tax_evidence.payroll_tax_evidence_journal_id_fkey
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES accounting_journals(journal_id);

-- public.payroll_tax_evidence.payroll_tax_evidence_tenant_id_employee_party_id_fkey
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_tenant_id_employee_party_id_fkey FOREIGN KEY (tenant_id, employee_party_id) REFERENCES tax_parties(tenant_id, party_id);

-- public.payroll_tax_evidence.payroll_tax_evidence_tenant_id_fkey
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.payroll_tax_evidence.payroll_tax_evidence_tenant_id_profile_id_fkey
ALTER TABLE ONLY public.payroll_tax_evidence ADD CONSTRAINT payroll_tax_evidence_tenant_id_profile_id_fkey FOREIGN KEY (tenant_id, profile_id) REFERENCES employee_tax_profiles(tenant_id, profile_id);

-- public.pos_accounting_tenant_map.pos_accounting_tenant_map_accounting_tenant_id_fkey
ALTER TABLE ONLY public.pos_accounting_tenant_map ADD CONSTRAINT pos_accounting_tenant_map_accounting_tenant_id_fkey FOREIGN KEY (accounting_tenant_id) REFERENCES accounting_tenants(tenant_id) ON DELETE RESTRICT;

-- public.pos_accounting_tenant_map.pos_accounting_tenant_map_pos_tenant_id_fkey
ALTER TABLE ONLY public.pos_accounting_tenant_map ADD CONSTRAINT pos_accounting_tenant_map_pos_tenant_id_fkey FOREIGN KEY (pos_tenant_id) REFERENCES tenants(tenant_id) ON DELETE RESTRICT;

-- public.pos_manager_pins.pos_manager_pins_tenant_id_fkey
ALTER TABLE ONLY public.pos_manager_pins ADD CONSTRAINT pos_manager_pins_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE;

-- public.pos_memberships.pos_memberships_tenant_id_fkey
ALTER TABLE ONLY public.pos_memberships ADD CONSTRAINT pos_memberships_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE;

-- public.pos_memberships.pos_memberships_user_id_fkey
ALTER TABLE ONLY public.pos_memberships ADD CONSTRAINT pos_memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- public.pos_pin_audit.pos_pin_audit_tenant_id_fkey
ALTER TABLE ONLY public.pos_pin_audit ADD CONSTRAINT pos_pin_audit_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE;

-- public.product_master.product_master_tenant_id_fkey
ALTER TABLE ONLY public.product_master ADD CONSTRAINT product_master_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id) ON DELETE RESTRICT;

-- public.receivable_allowance_events.receivable_allowance_events_actor_user_id_fkey
ALTER TABLE ONLY public.receivable_allowance_events ADD CONSTRAINT receivable_allowance_events_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.receivable_allowance_events.receivable_allowance_events_journal_id_fkey
ALTER TABLE ONLY public.receivable_allowance_events ADD CONSTRAINT receivable_allowance_events_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES accounting_journals(journal_id);

-- public.receivable_allowance_events.receivable_allowance_events_tenant_id_fkey
ALTER TABLE ONLY public.receivable_allowance_events ADD CONSTRAINT receivable_allowance_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.receivable_allowance_events.receivable_allowance_events_tenant_id_sale_transaction_ref_fkey
ALTER TABLE ONLY public.receivable_allowance_events ADD CONSTRAINT receivable_allowance_events_tenant_id_sale_transaction_ref_fkey FOREIGN KEY (tenant_id, sale_transaction_ref) REFERENCES customer_receivables(tenant_id, sale_transaction_ref);

-- public.receivable_allowances.receivable_allowances_tenant_id_fkey
ALTER TABLE ONLY public.receivable_allowances ADD CONSTRAINT receivable_allowances_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.receivable_allowances.receivable_allowances_tenant_id_sale_transaction_ref_fkey
ALTER TABLE ONLY public.receivable_allowances ADD CONSTRAINT receivable_allowances_tenant_id_sale_transaction_ref_fkey FOREIGN KEY (tenant_id, sale_transaction_ref) REFERENCES customer_receivables(tenant_id, sale_transaction_ref);

-- public.sale_line_evidence.sale_line_evidence_revenue_account_fkey
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_revenue_account_fkey FOREIGN KEY (revenue_account) REFERENCES accounting_coa(account_code);

-- public.sale_line_evidence.sale_line_evidence_service_fk
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_service_fk FOREIGN KEY (tenant_id, service_profile_id) REFERENCES service_tax_profiles(tenant_id, service_profile_id);

-- public.sale_line_evidence.sale_line_evidence_tenant_id_product_id_fkey
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_tenant_id_product_id_fkey FOREIGN KEY (tenant_id, product_id) REFERENCES product_master(tenant_id, product_id);

-- public.sale_line_evidence.sale_line_evidence_tenant_id_transaction_ref_fkey
ALTER TABLE ONLY public.sale_line_evidence ADD CONSTRAINT sale_line_evidence_tenant_id_transaction_ref_fkey FOREIGN KEY (tenant_id, transaction_ref) REFERENCES accounting_transaction_evidence(tenant_id, transaction_ref);

-- public.sale_return_line_evidence.sale_return_line_evidence_tenant_id_original_transaction_r_fkey
ALTER TABLE ONLY public.sale_return_line_evidence ADD CONSTRAINT sale_return_line_evidence_tenant_id_original_transaction_r_fkey FOREIGN KEY (tenant_id, original_transaction_ref, line_key) REFERENCES sale_line_evidence(tenant_id, transaction_ref, line_key);

-- public.sale_return_line_evidence.sale_return_line_evidence_tenant_id_return_transaction_ref_fkey
ALTER TABLE ONLY public.sale_return_line_evidence ADD CONSTRAINT sale_return_line_evidence_tenant_id_return_transaction_ref_fkey FOREIGN KEY (tenant_id, return_transaction_ref) REFERENCES accounting_transaction_evidence(tenant_id, transaction_ref);

-- public.service_tax_profiles.service_tax_profiles_actor_user_id_fkey
ALTER TABLE ONLY public.service_tax_profiles ADD CONSTRAINT service_tax_profiles_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.service_tax_profiles.service_tax_profiles_tenant_id_fkey
ALTER TABLE ONLY public.service_tax_profiles ADD CONSTRAINT service_tax_profiles_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.subscription_events.subscription_events_sub_id_fkey
ALTER TABLE ONLY public.subscription_events ADD CONSTRAINT subscription_events_sub_id_fkey FOREIGN KEY (sub_id) REFERENCES subscriptions(sub_id) ON DELETE SET NULL;

-- public.subscriptions.subscriptions_plan_id_fkey
ALTER TABLE ONLY public.subscriptions ADD CONSTRAINT subscriptions_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES plans(plan_id);

-- public.subscriptions.subscriptions_user_id_fkey
ALTER TABLE ONLY public.subscriptions ADD CONSTRAINT subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- public.supplier_liabilities.supplier_liabilities_actor_user_id_fkey
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.supplier_liabilities.supplier_liabilities_purchase_journal_id_fkey
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_purchase_journal_id_fkey FOREIGN KEY (purchase_journal_id) REFERENCES accounting_journals(journal_id);

-- public.supplier_liabilities.supplier_liabilities_tenant_id_fkey
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.supplier_liabilities.supplier_liabilities_tenant_id_vendor_party_id_fkey
ALTER TABLE ONLY public.supplier_liabilities ADD CONSTRAINT supplier_liabilities_tenant_id_vendor_party_id_fkey FOREIGN KEY (tenant_id, vendor_party_id) REFERENCES tax_parties(tenant_id, party_id);

-- public.supplier_payment_allocations.supplier_payment_allocations_actor_user_id_fkey
ALTER TABLE ONLY public.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.supplier_payment_allocations.supplier_payment_allocations_payment_journal_id_fkey
ALTER TABLE ONLY public.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_payment_journal_id_fkey FOREIGN KEY (payment_journal_id) REFERENCES accounting_journals(journal_id);

-- public.supplier_payment_allocations.supplier_payment_allocations_tenant_id_fkey
ALTER TABLE ONLY public.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.supplier_payment_allocations.supplier_payment_allocations_tenant_id_purchase_transactio_fkey
ALTER TABLE ONLY public.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_tenant_id_purchase_transactio_fkey FOREIGN KEY (tenant_id, purchase_transaction_ref) REFERENCES supplier_liabilities(tenant_id, purchase_transaction_ref);

-- public.supplier_payment_allocations.supplier_payment_allocations_tenant_id_vendor_party_id_fkey
ALTER TABLE ONLY public.supplier_payment_allocations ADD CONSTRAINT supplier_payment_allocations_tenant_id_vendor_party_id_fkey FOREIGN KEY (tenant_id, vendor_party_id) REFERENCES tax_parties(tenant_id, party_id);

-- public.tax_document_events.tax_document_events_actor_user_id_fkey
ALTER TABLE ONLY public.tax_document_events ADD CONSTRAINT tax_document_events_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.tax_document_events.tax_document_events_tax_document_id_fkey
ALTER TABLE ONLY public.tax_document_events ADD CONSTRAINT tax_document_events_tax_document_id_fkey FOREIGN KEY (tax_document_id) REFERENCES tax_documents(tax_document_id);

-- public.tax_document_events.tax_document_events_tenant_id_fkey
ALTER TABLE ONLY public.tax_document_events ADD CONSTRAINT tax_document_events_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.tax_document_lines.tax_document_lines_tax_document_id_fkey
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_tax_document_id_fkey FOREIGN KEY (tax_document_id) REFERENCES tax_documents(tax_document_id);

-- public.tax_document_lines.tax_document_lines_tenant_id_fkey
ALTER TABLE ONLY public.tax_document_lines ADD CONSTRAINT tax_document_lines_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.tax_documents.tax_documents_actor_user_id_fkey
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.tax_documents.tax_documents_journal_id_fkey
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_journal_id_fkey FOREIGN KEY (journal_id) REFERENCES accounting_journals(journal_id);

-- public.tax_documents.tax_documents_reference_document_id_fkey
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_reference_document_id_fkey FOREIGN KEY (reference_document_id) REFERENCES tax_documents(tax_document_id);

-- public.tax_documents.tax_documents_tenant_id_counterparty_id_fkey
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_tenant_id_counterparty_id_fkey FOREIGN KEY (tenant_id, counterparty_id) REFERENCES tax_parties(tenant_id, party_id);

-- public.tax_documents.tax_documents_tenant_id_fkey
ALTER TABLE ONLY public.tax_documents ADD CONSTRAINT tax_documents_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.tax_parties.tax_parties_actor_user_id_fkey
ALTER TABLE ONLY public.tax_parties ADD CONSTRAINT tax_parties_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.tax_parties.tax_parties_tenant_id_fkey
ALTER TABLE ONLY public.tax_parties ADD CONSTRAINT tax_parties_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.tax_payment_refs.tax_payment_refs_actor_user_id_fkey
ALTER TABLE ONLY public.tax_payment_refs ADD CONSTRAINT tax_payment_refs_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.tax_payment_refs.tax_payment_refs_payment_journal_id_fkey
ALTER TABLE ONLY public.tax_payment_refs ADD CONSTRAINT tax_payment_refs_payment_journal_id_fkey FOREIGN KEY (payment_journal_id) REFERENCES accounting_journals(journal_id);

-- public.tax_payment_refs.tax_payment_refs_tax_document_id_fkey
ALTER TABLE ONLY public.tax_payment_refs ADD CONSTRAINT tax_payment_refs_tax_document_id_fkey FOREIGN KEY (tax_document_id) REFERENCES tax_documents(tax_document_id);

-- public.tax_payment_refs.tax_payment_refs_tenant_id_fkey
ALTER TABLE ONLY public.tax_payment_refs ADD CONSTRAINT tax_payment_refs_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.tax_rate_brackets.tax_rate_brackets_created_by_fkey
ALTER TABLE ONLY public.tax_rate_brackets ADD CONSTRAINT tax_rate_brackets_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);

-- public.tax_rates.tax_rates_created_by_fkey
ALTER TABLE ONLY public.tax_rates ADD CONSTRAINT tax_rates_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);

-- public.tenant_services.tenant_services_tenant_id_fkey
ALTER TABLE ONLY public.tenant_services ADD CONSTRAINT tenant_services_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id) ON DELETE CASCADE;

-- public.vat_period_settlements.vat_period_settlements_actor_user_id_fkey
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id);

-- public.vat_period_settlements.vat_period_settlements_settlement_journal_id_fkey
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_settlement_journal_id_fkey FOREIGN KEY (settlement_journal_id) REFERENCES accounting_journals(journal_id);

-- public.vat_period_settlements.vat_period_settlements_tenant_id_fkey
ALTER TABLE ONLY public.vat_period_settlements ADD CONSTRAINT vat_period_settlements_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES accounting_tenants(tenant_id);

-- public.accounting_journal_lines.accounting_journal_lines_balance
ALTER TABLE ONLY public.accounting_journal_lines ADD CONSTRAINT accounting_journal_lines_balance TRIGGER DEFERRABLE INITIALLY DEFERRED;

-- public.accounting_journals.accounting_journal_parent_balance
ALTER TABLE ONLY public.accounting_journals ADD CONSTRAINT accounting_journal_parent_balance TRIGGER DEFERRABLE INITIALLY DEFERRED;
-- Non-constraint indexes.

-- private.tenant_accounting_links.tenant_accounting_links_accounting_start_uq
CREATE UNIQUE INDEX tenant_accounting_links_accounting_start_uq ON private.tenant_accounting_links USING btree (accounting_tenant_id, valid_from);

-- private.tenant_accounting_links.tenant_accounting_links_config_start_uq
CREATE UNIQUE INDEX tenant_accounting_links_config_start_uq ON private.tenant_accounting_links USING btree (config_tenant_id, valid_from);

-- public.accounting_events.accounting_events_actor_idx
CREATE INDEX accounting_events_actor_idx ON public.accounting_events USING btree (actor_user_id) WHERE (actor_user_id IS NOT NULL);

-- public.accounting_events.accounting_events_journal_idx
CREATE INDEX accounting_events_journal_idx ON public.accounting_events USING btree (journal_id) WHERE (journal_id IS NOT NULL);

-- public.accounting_events.accounting_events_tenant_time_idx
CREATE INDEX accounting_events_tenant_time_idx ON public.accounting_events USING btree (tenant_id, occurred_at DESC);

-- public.accounting_journal_lines.accounting_journal_lines_account_idx
CREATE INDEX accounting_journal_lines_account_idx ON public.accounting_journal_lines USING btree (account_code);

-- public.accounting_journal_lines.accounting_journal_lines_journal_tenant_idx
CREATE INDEX accounting_journal_lines_journal_tenant_idx ON public.accounting_journal_lines USING btree (journal_id, tenant_id);

-- public.accounting_journal_lines.accounting_journal_lines_tenant_idx
CREATE INDEX accounting_journal_lines_tenant_idx ON public.accounting_journal_lines USING btree (tenant_id, journal_id);

-- public.accounting_journals.accounting_journals_actor_idx
CREATE INDEX accounting_journals_actor_idx ON public.accounting_journals USING btree (actor_user_id) WHERE (actor_user_id IS NOT NULL);

-- public.accounting_journals.accounting_journals_tenant_date_idx
CREATE INDEX accounting_journals_tenant_date_idx ON public.accounting_journals USING btree (tenant_id, journal_date, posted_at);

-- public.accounting_journals.accounting_journals_transaction_ref_idx
CREATE INDEX accounting_journals_transaction_ref_idx ON public.accounting_journals USING btree (tenant_id, transaction_ref);

-- public.accounting_journals.accounting_one_reversal_per_journal_idx
CREATE UNIQUE INDEX accounting_one_reversal_per_journal_idx ON public.accounting_journals USING btree (reversal_of) WHERE (reversal_of IS NOT NULL);

-- public.accounting_memberships.accounting_memberships_user_idx
CREATE INDEX accounting_memberships_user_idx ON public.accounting_memberships USING btree (user_id, tenant_id) WHERE is_active;

-- public.accounting_periods.accounting_periods_closed_by_idx
CREATE INDEX accounting_periods_closed_by_idx ON public.accounting_periods USING btree (closed_by) WHERE (closed_by IS NOT NULL);

-- public.accounting_periods.accounting_periods_reopened_by_idx
CREATE INDEX accounting_periods_reopened_by_idx ON public.accounting_periods USING btree (reopened_by) WHERE (reopened_by IS NOT NULL);

-- public.accounting_periods.accounting_periods_tenant_dates_idx
CREATE INDEX accounting_periods_tenant_dates_idx ON public.accounting_periods USING btree (tenant_id, period_start, period_end, status);

-- public.accounting_tenants.accounting_tenants_owner_idx
CREATE INDEX accounting_tenants_owner_idx ON public.accounting_tenants USING btree (owner_user_id) WHERE (owner_user_id IS NOT NULL);

-- public.config_history.idx_config_history_changed_at
CREATE INDEX idx_config_history_changed_at ON public.config_history USING btree (changed_at DESC);

-- public.config_history.idx_config_history_key
CREATE INDEX idx_config_history_key ON public.config_history USING btree (key);

-- public.coretax_outbox.coretax_outbox_one_per_tax_document
CREATE UNIQUE INDEX coretax_outbox_one_per_tax_document ON public.coretax_outbox USING btree (tax_document_id);

-- public.coretax_template_registry.coretax_one_active_per_code_uq
CREATE UNIQUE INDEX coretax_one_active_per_code_uq ON public.coretax_template_registry USING btree (template_code) WHERE is_active;

-- public.coretax_template_registry.coretax_template_version_uq
CREATE UNIQUE INDEX coretax_template_version_uq ON public.coretax_template_registry USING btree (template_code, template_version);

-- public.corporate_fiscal_adjustments.corporate_fiscal_adjustments_single_reversal_uq
CREATE UNIQUE INDEX corporate_fiscal_adjustments_single_reversal_uq ON public.corporate_fiscal_adjustments USING btree (reverses_adjustment_id) WHERE (reverses_adjustment_id IS NOT NULL);

-- public.corporate_pph25_authorities.corporate_pph25_authorities_effective_uq
CREATE UNIQUE INDEX corporate_pph25_authorities_effective_uq ON public.corporate_pph25_authorities USING btree (tenant_id, tax_year, effective_from_month);

-- public.devices.idx_devices_user
CREATE INDEX idx_devices_user ON public.devices USING btree (user_id);

-- public.devices.idx_devices_user_platform
CREATE INDEX idx_devices_user_platform ON public.devices USING btree (user_id, platform);

-- public.inventory_cost_layer_projection.inventory_cost_layer_projection_tenant_product_idx
CREATE INDEX inventory_cost_layer_projection_tenant_product_idx ON public.inventory_cost_layer_projection USING btree (tenant_id, product_id);

-- public.inventory_events.inventory_events_actor_user_idx
CREATE INDEX inventory_events_actor_user_idx ON public.inventory_events USING btree (actor_user_id);

-- public.inventory_events.inventory_events_product_idx
CREATE INDEX inventory_events_product_idx ON public.inventory_events USING btree (tenant_id, product_id, server_sequence);

-- public.inventory_events.inventory_events_tenant_sequence_idx
CREATE INDEX inventory_events_tenant_sequence_idx ON public.inventory_events USING btree (tenant_id, server_sequence);

-- public.inventory_lot_projection.inventory_lot_projection_tenant_product_idx
CREATE INDEX inventory_lot_projection_tenant_product_idx ON public.inventory_lot_projection USING btree (tenant_id, product_id);

-- public.plans.idx_plans_active
CREATE INDEX idx_plans_active ON public.plans USING btree (is_active);

-- public.pos_memberships.idx_pos_memberships_user_active
CREATE INDEX idx_pos_memberships_user_active ON public.pos_memberships USING btree (user_id, tenant_id) WHERE (is_active = true);

-- public.pos_pin_audit.idx_pos_pin_audit_actor_time
CREATE INDEX idx_pos_pin_audit_actor_time ON public.pos_pin_audit USING btree (actor_id, occurred_at DESC);

-- public.pos_pin_audit.idx_pos_pin_audit_tenant_time
CREATE INDEX idx_pos_pin_audit_tenant_time ON public.pos_pin_audit USING btree (tenant_id, occurred_at DESC);

-- public.product_master.product_master_tenant_active_idx
CREATE INDEX product_master_tenant_active_idx ON public.product_master USING btree (tenant_id, is_active, updated_at, product_id);

-- public.product_master.product_master_tenant_barcode_unique
CREATE UNIQUE INDEX product_master_tenant_barcode_unique ON public.product_master USING btree (tenant_id, barcode) WHERE (barcode IS NOT NULL);

-- public.subscription_events.idx_subscription_events_provider
CREATE INDEX idx_subscription_events_provider ON public.subscription_events USING btree (provider, received_at DESC);

-- public.subscription_events.idx_subscription_events_sub
CREATE INDEX idx_subscription_events_sub ON public.subscription_events USING btree (sub_id, received_at DESC);

-- public.subscriptions.idx_subscriptions_grace
CREATE INDEX idx_subscriptions_grace ON public.subscriptions USING btree (grace_period_end);

-- public.subscriptions.idx_subscriptions_plan_id
CREATE INDEX idx_subscriptions_plan_id ON public.subscriptions USING btree (plan_id);

-- public.subscriptions.idx_subscriptions_provider
CREATE INDEX idx_subscriptions_provider ON public.subscriptions USING btree (payment_provider);

-- public.subscriptions.idx_subscriptions_status
CREATE INDEX idx_subscriptions_status ON public.subscriptions USING btree (status);

-- public.subscriptions.idx_subscriptions_user
CREATE INDEX idx_subscriptions_user ON public.subscriptions USING btree (user_id);

-- public.subscriptions.idx_subscriptions_user_period
CREATE INDEX idx_subscriptions_user_period ON public.subscriptions USING btree (user_id, current_period_end DESC);

-- public.tax_documents.tax_documents_vat_input_document_number_uq
CREATE UNIQUE INDEX tax_documents_vat_input_document_number_uq ON public.tax_documents USING btree (tenant_id, document_number) WHERE ((document_type = 'VAT_INPUT'::text) AND (document_number IS NOT NULL));

-- public.tax_payment_refs.tax_payment_refs_tenant_billing_code_uq
CREATE UNIQUE INDEX tax_payment_refs_tenant_billing_code_uq ON public.tax_payment_refs USING btree (tenant_id, billing_code);

-- public.tax_rate_brackets.tax_rate_brackets_start_uq
CREATE UNIQUE INDEX tax_rate_brackets_start_uq ON public.tax_rate_brackets USING btree (tax_code, category, lower_bound, effective_date);

-- public.tax_rates.tax_rates_start_uq
CREATE UNIQUE INDEX tax_rates_start_uq ON public.tax_rates USING btree (tax_code, object_code, category, effective_date);
