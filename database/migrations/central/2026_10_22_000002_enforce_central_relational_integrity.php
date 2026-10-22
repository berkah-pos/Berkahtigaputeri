<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'central';

    public function up(): void
    {
        Schema::connection('central')->table('tenants', function (Blueprint $table): void {
            $table->foreign('template_id', 'tenants_template_id_fk')
                ->references('id')->on('templates')->restrictOnDelete();
        });
        Schema::connection('central')->table('users', function (Blueprint $table): void {
            $table->foreign('tenant_id', 'users_tenant_id_fk')
                ->references('id')->on('tenants')->restrictOnDelete();
        });
        Schema::connection('central')->table('tenant_configs', function (Blueprint $table): void {
            $table->foreign('template_id', 'tenant_configs_template_id_fk')
                ->references('id')->on('templates')->restrictOnDelete();
        });
        Schema::connection('central')->table('audit_events', function (Blueprint $table): void {
            $table->foreign('tenant_id', 'audit_events_tenant_id_fk')
                ->references('id')->on('tenants')->restrictOnDelete();
            $table->index(['tenant_id', 'created_at'], 'audit_events_tenant_created_idx');
        });

        DB::connection('central')->unprepared(<<<'SQL'
ALTER TABLE templates
    ADD CONSTRAINT templates_canonical_id_check
    CHECK (id IN ('BASIC', 'PRO', 'ENTERPRISE')),
    ADD CONSTRAINT templates_version_positive_check CHECK (version >= 1);

ALTER TABLE tenants
    ADD CONSTRAINT tenants_canonical_template_check
    CHECK (template_id IN ('BASIC', 'PRO', 'ENTERPRISE'));

ALTER TABLE global_configs
    ADD CONSTRAINT global_configs_version_positive_check CHECK (version >= 1);

ALTER TABLE tenant_configs
    ADD CONSTRAINT tenant_configs_version_positive_check CHECK (version >= 1),
    ADD CONSTRAINT tenant_configs_service_scope_check
    CHECK (
        (service IS NULL AND service_scope = '__base__')
        OR
        (service IS NOT NULL AND service_scope = service AND service IN ('pos', 'akuntansi'))
    );

ALTER TABLE tenant_services
    ADD CONSTRAINT tenant_services_service_check CHECK (service IN ('pos', 'akuntansi'));

ALTER TABLE audit_events
    ADD CONSTRAINT audit_events_scope_nonempty_check CHECK (length(btrim(scope_type)) > 0 AND length(btrim(scope_id)) > 0),
    ADD CONSTRAINT audit_events_action_nonempty_check CHECK (length(btrim(action)) > 0),
    ADD CONSTRAINT audit_events_previous_version_nonnegative_check CHECK (previous_version IS NULL OR previous_version >= 0),
    ADD CONSTRAINT audit_events_new_version_positive_check CHECK (new_version IS NULL OR new_version >= 1);

CREATE OR REPLACE FUNCTION btp_reject_central_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'central audit_events is append-only; corrections must be new events'
        USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER audit_events_append_only_update_delete
    BEFORE UPDATE OR DELETE ON audit_events
    FOR EACH ROW EXECUTE FUNCTION btp_reject_central_audit_mutation();

CREATE TRIGGER audit_events_append_only_truncate
    BEFORE TRUNCATE ON audit_events
    FOR EACH STATEMENT EXECUTE FUNCTION btp_reject_central_audit_mutation();
SQL);
    }

    public function down(): void
    {
        DB::connection('central')->unprepared(<<<'SQL'
DROP TRIGGER IF EXISTS audit_events_append_only_update_delete ON audit_events;
DROP TRIGGER IF EXISTS audit_events_append_only_truncate ON audit_events;
DROP FUNCTION IF EXISTS btp_reject_central_audit_mutation();

ALTER TABLE audit_events
    DROP CONSTRAINT IF EXISTS audit_events_new_version_positive_check,
    DROP CONSTRAINT IF EXISTS audit_events_previous_version_nonnegative_check,
    DROP CONSTRAINT IF EXISTS audit_events_action_nonempty_check,
    DROP CONSTRAINT IF EXISTS audit_events_scope_nonempty_check;
ALTER TABLE tenant_services DROP CONSTRAINT IF EXISTS tenant_services_service_check;
ALTER TABLE tenant_configs
    DROP CONSTRAINT IF EXISTS tenant_configs_service_scope_check,
    DROP CONSTRAINT IF EXISTS tenant_configs_version_positive_check;
ALTER TABLE global_configs DROP CONSTRAINT IF EXISTS global_configs_version_positive_check;
ALTER TABLE tenants DROP CONSTRAINT IF EXISTS tenants_canonical_template_check;
ALTER TABLE templates
    DROP CONSTRAINT IF EXISTS templates_version_positive_check,
    DROP CONSTRAINT IF EXISTS templates_canonical_id_check;
SQL);

        Schema::connection('central')->table('audit_events', function (Blueprint $table): void {
            $table->dropIndex('audit_events_tenant_created_idx');
            $table->dropForeign('audit_events_tenant_id_fk');
        });
        Schema::connection('central')->table('tenant_configs', function (Blueprint $table): void {
            $table->dropForeign('tenant_configs_template_id_fk');
        });
        Schema::connection('central')->table('users', function (Blueprint $table): void {
            $table->dropForeign('users_tenant_id_fk');
        });
        Schema::connection('central')->table('tenants', function (Blueprint $table): void {
            $table->dropForeign('tenants_template_id_fk');
        });
    }
};
