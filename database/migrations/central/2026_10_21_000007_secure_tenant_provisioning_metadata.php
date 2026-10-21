<?php

use Illuminate\\Database\\Migrations\\Migration;
use Illuminate\\Database\\Schema\\Blueprint;
use Illuminate\\Support\\Facades\\DB;
use Illuminate\\Support\\Facades\\Schema;

return new class extends Migration
{
    protected $connection = 'central_migrator';

    public function up(): void
    {
        $schema = Schema::connection('central_migrator');
        if (! $schema->hasColumn('domains', 'is_active')) {
            $schema->table('domains', function (Blueprint $table): void {
                // Preserve existing domain behavior; new provisioned domains are
                // explicitly inserted inactive and activated only after smoke tests.
                $table->boolean('is_active')->default(true);
            });
        }

        DB::connection('central_migrator')->unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION public.btp_guard_tenant_provisioning_event_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Tenant provisioning events are append-only audit records'
        USING ERRCODE = '55000';
END;
$$;

DROP TRIGGER IF EXISTS btp_tenant_provisioning_event_immutable
    ON public.tenant_provisioning_events;
CREATE TRIGGER btp_tenant_provisioning_event_immutable
BEFORE UPDATE OR DELETE ON public.tenant_provisioning_events
FOR EACH ROW EXECUTE FUNCTION public.btp_guard_tenant_provisioning_event_mutation();
SQL);
    }

    public function down(): void
    {
        DB::connection('central_migrator')->unprepared(<<<'SQL'
DROP TRIGGER IF EXISTS btp_tenant_provisioning_event_immutable
    ON public.tenant_provisioning_events;
DROP FUNCTION IF EXISTS public.btp_guard_tenant_provisioning_event_mutation();
SQL);

        $schema = Schema::connection('central_migrator');
        if ($schema->hasColumn('domains', 'is_active')) {
            $schema->table('domains', function (Blueprint $table): void {
                $table->dropColumn('is_active');
            });
        }
    }
};
