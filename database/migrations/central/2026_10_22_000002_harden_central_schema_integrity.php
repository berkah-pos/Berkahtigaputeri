<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    protected $connection = 'central';

    public function up(): void
    {
        $db = DB::connection('central');
        $columns = [
            'tenants' => ['created_at','updated_at'], 'domains' => ['created_at','updated_at'],
            'users' => ['email_verified_at','created_at','updated_at'],
            'personal_access_tokens' => ['last_used_at','expires_at','created_at','updated_at'],
            'subscriptions' => ['expires_at','created_at','updated_at'],
            'global_configs' => ['created_at','updated_at'], 'templates' => ['created_at','updated_at'],
            'tenant_configs' => ['created_at','updated_at'], 'tenant_services' => ['created_at','updated_at'],
            'device_registry' => ['registered_at','created_at','updated_at'], 'audit_events' => ['created_at'],
        ];
        foreach ($columns as $table => $fields) {
            foreach ($fields as $field) {
                $db->statement(sprintf(
                    'ALTER TABLE "%s" ALTER COLUMN "%s" TYPE timestamptz USING "%s" AT TIME ZONE \'UTC\'',
                    $table, $field, $field,
                ));
            }
        }

        $db->unprepared(<<<'SQL'
ALTER TABLE audit_events DROP CONSTRAINT IF EXISTS audit_events_actor_user_id_foreign;
ALTER TABLE audit_events ADD CONSTRAINT audit_events_actor_user_id_foreign
    FOREIGN KEY (actor_user_id) REFERENCES users(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE domains ADD CONSTRAINT domains_canonical_fqdn_check
    CHECK (domain = lower(btrim(domain)) AND domain !~ '[:/[:space:]]' AND domain <> '');
ALTER TABLE templates ADD CONSTRAINT templates_id_canonical_check CHECK (id IN ('BASIC','PRO','ENTERPRISE'));
ALTER TABLE tenants ADD CONSTRAINT tenants_template_id_canonical_check CHECK (template_id IN ('BASIC','PRO','ENTERPRISE'));
ALTER TABLE tenants ADD CONSTRAINT tenants_template_id_foreign FOREIGN KEY (template_id) REFERENCES templates(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE users ADD CONSTRAINT users_tenant_id_foreign FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON UPDATE RESTRICT ON DELETE SET NULL;
ALTER TABLE tenant_configs ADD CONSTRAINT tenant_configs_template_id_canonical_check CHECK (template_id IS NULL OR template_id IN ('BASIC','PRO','ENTERPRISE'));
ALTER TABLE tenant_configs ADD CONSTRAINT tenant_configs_template_id_foreign FOREIGN KEY (template_id) REFERENCES templates(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE global_configs ADD CONSTRAINT global_configs_single_canonical_key_check CHECK (key = 'global');
ALTER TABLE global_configs ADD CONSTRAINT global_configs_version_positive_check CHECK (version >= 1);
ALTER TABLE templates ADD CONSTRAINT templates_version_positive_check CHECK (version >= 1);
ALTER TABLE tenant_configs ADD CONSTRAINT tenant_configs_version_positive_check CHECK (version >= 1);
ALTER TABLE tenant_configs ADD CONSTRAINT tenant_configs_service_scope_consistent_check
    CHECK ((service_scope = '__base__' AND service IS NULL) OR (service_scope IN ('pos','akuntansi') AND service = service_scope));
ALTER TABLE tenant_services ADD CONSTRAINT tenant_services_service_allowlist_check CHECK (service IN ('pos','akuntansi'));
ALTER TABLE device_registry ADD CONSTRAINT device_registry_status_allowlist_check CHECK (status IN ('pending','active','suspended','revoked'));
SQL);

        $db->unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION btp_reject_central_audit_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Central audit_events is append-only; write a compensating event instead.'; END; $$;
CREATE TRIGGER btp_audit_events_append_only BEFORE UPDATE OR DELETE ON audit_events
    FOR EACH ROW EXECUTE FUNCTION btp_reject_central_audit_mutation();
CREATE TRIGGER btp_audit_events_no_truncate BEFORE TRUNCATE ON audit_events
    FOR EACH STATEMENT EXECUTE FUNCTION btp_reject_central_audit_mutation();
SQL);
    }

    public function down(): void
    {
        $db = DB::connection('central');
        $db->unprepared(<<<'SQL'
DROP TRIGGER IF EXISTS btp_audit_events_no_truncate ON audit_events;
DROP TRIGGER IF EXISTS btp_audit_events_append_only ON audit_events;
DROP FUNCTION IF EXISTS btp_reject_central_audit_mutation();
ALTER TABLE device_registry DROP CONSTRAINT IF EXISTS device_registry_status_allowlist_check;
ALTER TABLE tenant_services DROP CONSTRAINT IF EXISTS tenant_services_service_allowlist_check;
ALTER TABLE tenant_configs DROP CONSTRAINT IF EXISTS tenant_configs_service_scope_consistent_check;
ALTER TABLE tenant_configs DROP CONSTRAINT IF EXISTS tenant_configs_version_positive_check;
ALTER TABLE templates DROP CONSTRAINT IF EXISTS templates_version_positive_check;
ALTER TABLE global_configs DROP CONSTRAINT IF EXISTS global_configs_version_positive_check;
ALTER TABLE global_configs DROP CONSTRAINT IF EXISTS global_configs_single_canonical_key_check;
ALTER TABLE tenant_configs DROP CONSTRAINT IF EXISTS tenant_configs_template_id_foreign;
ALTER TABLE tenant_configs DROP CONSTRAINT IF EXISTS tenant_configs_template_id_canonical_check;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_tenant_id_foreign;
ALTER TABLE tenants DROP CONSTRAINT IF EXISTS tenants_template_id_foreign;
ALTER TABLE tenants DROP CONSTRAINT IF EXISTS tenants_template_id_canonical_check;
ALTER TABLE templates DROP CONSTRAINT IF EXISTS templates_id_canonical_check;
ALTER TABLE domains DROP CONSTRAINT IF EXISTS domains_canonical_fqdn_check;
ALTER TABLE audit_events DROP CONSTRAINT IF EXISTS audit_events_actor_user_id_foreign;
ALTER TABLE audit_events ADD CONSTRAINT audit_events_actor_user_id_foreign
    FOREIGN KEY (actor_user_id) REFERENCES users(id) ON DELETE SET NULL;
SQL);
        $columns = [
            'tenants' => ['created_at','updated_at'], 'domains' => ['created_at','updated_at'],
            'users' => ['email_verified_at','created_at','updated_at'],
            'personal_access_tokens' => ['last_used_at','expires_at','created_at','updated_at'],
            'subscriptions' => ['expires_at','created_at','updated_at'],
            'global_configs' => ['created_at','updated_at'], 'templates' => ['created_at','updated_at'],
            'tenant_configs' => ['created_at','updated_at'], 'tenant_services' => ['created_at','updated_at'],
            'device_registry' => ['registered_at','created_at','updated_at'], 'audit_events' => ['created_at'],
        ];
        foreach ($columns as $table => $fields) foreach ($fields as $field) {
            $db->statement(sprintf('ALTER TABLE "%s" ALTER COLUMN "%s" TYPE timestamp without time zone USING "%s" AT TIME ZONE \'UTC\'', $table, $field, $field));
        }
    }
};
