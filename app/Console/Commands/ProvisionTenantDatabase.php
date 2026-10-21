<?php

namespace App\\Console\\Commands;

use Illuminate\\Console\\Command;
use Illuminate\\Database\\Connection;
use Illuminate\\Support\\Facades\\Artisan;
use Illuminate\\Support\\Facades\\Config;
use Illuminate\\Support\\Facades\\Crypt;
use Illuminate\\Support\\Facades\\DB;
use RuntimeException;
use Throwable;

class ProvisionTenantDatabase extends Command
{
    protected $signature = 'tenants:provision
        {tenant_id : Existing canonical central tenant ID}
        {domain : Tenant domain to activate only after a successful database smoke test}
        {--actor-user-id= : Active central super-admin responsible for the action}
        {--reason= : Audited provisioning reason, at least 10 characters}';

    protected $description = 'Provision one restricted PostgreSQL database per tenant using the isolated private broker connections.';

    private string $stage = 'input_validation';

    private bool $provisioningStarted = false;

    private bool $migrationRoleEnabled = false;

    private bool $ownerMembershipGranted = false;

    private ?Connection $central = null;

    private ?Connection $broker = null;

    private string $tenantId = '';

    private int $actorId = 0;

    private string $reason = '';

    private string $databaseName = '';

    private string $runtimeRole = '';

    private string $migratorRole = '';

    private string $runtimePassword = '';

    private string $migratorPassword = '';

    public function handle(): int
    {
        $this->tenantId = trim((string) $this->argument('tenant_id'));
        $domain = strtolower(rtrim(trim((string) $this->argument('domain')), '.'));
        $this->actorId = (int) ($this->option('actor-user-id') ?? 0);
        $this->reason = trim((string) ($this->option('reason') ?? ''));

        if (! preg_match('/^[A-Za-z0-9_.-]{1,150}$/', $this->tenantId)) {
            $this->error('Tenant ID format is invalid.');
            return self::FAILURE;
        }

        if (! $this->isValidDomain($domain)) {
            $this->error('Domain must be a valid lowercase DNS hostname without a scheme, port, wildcard or IP literal.');
            return self::FAILURE;
        }

        if ($this->actorId < 1 || strlen($this->reason) < 10 || strlen($this->reason) > 500) {
            $this->error('An active central super-admin ID and a 10–500 character reason are required.');
            return self::FAILURE;
        }

        $hash = substr(hash('sha256', $this->tenantId), 0, 24);
        $this->databaseName = 'btp_t_'.$hash;
        $this->runtimeRole = 'btp_r_'.$hash;
        $this->migratorRole = 'btp_m_'.$hash;

        $locked = false;
        try {
            $this->stage = 'credential_preflight';
            $this->assertBrokerCredentials();

            $this->central = DB::connection('central_provisioner');
            $this->broker = DB::connection('tenant_provisioner');
            $this->assertRolePurpose();

            $this->stage = 'tenant_lock';
            $this->central->selectOne('SELECT pg_advisory_lock(hashtext(?)::bigint)', [$this->tenantId]);
            $locked = true;

            $this->stage = 'tenant_authorization';
            $tenant = $this->central->table('tenants')->where('id', $this->tenantId)->first();
            if ($tenant === null) {
                throw new RuntimeException('tenant_not_found');
            }

            $actor = $this->central->table('users')
                ->where('id', $this->actorId)
                ->where('is_active', true)
                ->where('is_super_admin', true)
                ->first();
            if ($actor === null) {
                throw new RuntimeException('active_super_admin_required');
            }

            $subscription = $this->central->table('subscriptions')
                ->where('tenant_id', $this->tenantId)
                ->orderByDesc('id')
                ->first();
            if ($subscription === null
                || ! in_array((string) $subscription->status, ['trial', 'active'], true)
                || ($subscription->expires_at !== null
                    && strtotime((string) $subscription->expires_at) <= time())) {
                throw new RuntimeException('active_or_trial_entitlement_required');
            }

            $existingDomain = $this->central->table('domains')->where('domain', $domain)->first();
            if ($existingDomain !== null && (string) $existingDomain->tenant_id !== $this->tenantId) {
                throw new RuntimeException('domain_owned_by_another_tenant');
            }

            $registry = $this->central->table('tenant_database_registry')
                ->where('tenant_id', $this->tenantId)
                ->first();

            if ($registry !== null) {
                if ((string) $registry->database_name !== $this->databaseName
                    || (string) $registry->runtime_username !== $this->runtimeRole) {
                    throw new RuntimeException('tenant_database_registry_identity_mismatch');
                }
                try {
                    $this->runtimePassword = Crypt::decryptString((string) $registry->runtime_password_encrypted);
                } catch (Throwable) {
                    throw new RuntimeException('stored_runtime_credential_unavailable');
                }
                if ($this->runtimePassword === '') {
                    throw new RuntimeException('stored_runtime_credential_unavailable');
                }
            } else {
                $this->runtimePassword = bin2hex(random_bytes(32));
                $this->central->table('tenant_database_registry')->insert([
                    'tenant_id' => $this->tenantId,
                    'database_name' => $this->databaseName,
                    'runtime_username' => $this->runtimeRole,
                    'runtime_password_encrypted' => Crypt::encryptString($this->runtimePassword),
                    'status' => 'pending',
                    'provisioned_at' => null,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
                $registry = $this->central->table('tenant_database_registry')
                    ->where('tenant_id', $this->tenantId)
                    ->first();
            }

            if ($registry !== null
                && $registry->status === 'active'
                && $this->databaseExists()
                && $this->roleIsOwnedAndSafe($this->runtimeRole, $this->roleComment('runtime'), true)
                && $this->roleIsOwnedAndSafe($this->migratorRole, $this->roleComment('migrator'), false)
                && $this->databaseIsOwnedAndMarked()
                && $existingDomain !== null
                && (bool) $existingDomain->is_active) {
                $this->stage = 'idempotent_smoke_check';
                $this->smokeTestRuntime();
                $this->recordEvent('idempotent_verify', $this->databaseName, 'success', [
                    'actor_user_id' => $this->actorId,
                    'reason' => $this->reason,
                ]);
                $this->info("Tenant {$this->tenantId} is already provisioned; no database or role was recreated.");
                return self::SUCCESS;
            }

            if ($existingDomain === null) {
                $this->central->table('domains')->insert([
                    'domain' => $domain,
                    'tenant_id' => $this->tenantId,
                    'is_active' => false,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
                $this->recordEvent('domain_reserved', $domain, 'success', [
                    'actor_user_id' => $this->actorId,
                    'reason' => $this->reason,
                    'is_active' => false,
                ]);
            }

            if ($registry !== null && $registry->status === 'active' && ! $this->databaseExists()) {
                throw new RuntimeException('active_tenant_database_missing_fail_closed');
            }

            $this->central->table('tenant_database_registry')
                ->where('tenant_id', $this->tenantId)
                ->update(['status' => 'provisioning', 'updated_at' => now()]);
            $this->provisioningStarted = true;
            $this->recordEvent('provisioning_started', $this->databaseName, 'started', [
                'actor_user_id' => $this->actorId,
                'reason' => $this->reason,
            ]);

            $this->stage = 'tenant_role_setup';
            $this->migratorPassword = bin2hex(random_bytes(32));
            $this->ensureSafeRole($this->migratorRole, $this->roleComment('migrator'), true, $this->migratorPassword);
            $this->migrationRoleEnabled = true;
            $this->ensureSafeRole($this->runtimeRole, $this->roleComment('runtime'), true, $this->runtimePassword);
            $this->recordEvent('roles_verified', $this->databaseName, 'success', [
                'actor_user_id' => $this->actorId,
                'runtime_role' => $this->runtimeRole,
                'migrator_role' => $this->migratorRole,
                'role_attributes' => 'NOSUPERUSER,NOCREATEDB,NOCREATEROLE,NOREPLICATION,NOBYPASSRLS,NOINHERIT',
            ]);

            $this->stage = 'database_setup';
            $this->grantTemporaryOwnerMembership();
            $this->ensureTenantDatabase($registry !== null && $registry->status === 'active');
            $this->configureDatabaseConnectAcl();
            $this->recordEvent('database_verified', $this->databaseName, 'success', [
                'actor_user_id' => $this->actorId,
                'database_owner' => $this->migratorRole,
            ]);

            $this->stage = 'tenant_migrations';
            $this->configureTenantMigratorConnection();
            $exitCode = Artisan::call('migrate', [
                '--database' => 'tenant_migrator',
                '--path' => 'database/migrations/tenant',
                '--force' => true,
                '--no-interaction' => true,
            ]);
            if ($exitCode !== self::SUCCESS) {
                throw new RuntimeException('tenant_migrations_failed');
            }
            $this->recordEvent('tenant_migrations_applied', $this->databaseName, 'success', [
                'actor_user_id' => $this->actorId,
                'migration_path' => 'database/migrations/tenant',
            ]);

            $this->stage = 'runtime_grants';
            $this->applyRuntimeGrants();
            $this->recordEvent('runtime_grants_applied', $this->databaseName, 'success', [
                'actor_user_id' => $this->actorId,
                'runtime_role' => $this->runtimeRole,
                'schema' => 'public',
            ]);

            $this->stage = 'runtime_smoke_test';
            $this->smokeTestRuntime();

            $this->stage = 'finalize_migrator';
            $this->broker->unprepared(
                'ALTER ROLE '.$this->identifier($this->migratorRole).' WITH NOLOGIN PASSWORD NULL '
                .'NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT'
            );
            $this->migrationRoleEnabled = false;
            $this->recordEvent('migrator_disabled', $this->migratorRole, 'success', [
                'actor_user_id' => $this->actorId,
                'reason' => 'Migration completed; tenant migrator remains NOLOGIN by default.',
            ]);

            $this->stage = 'activate_domain';
            $this->central->table('domains')
                ->where('domain', $domain)
                ->where('tenant_id', $this->tenantId)
                ->update(['is_active' => true, 'updated_at' => now()]);
            $this->central->table('tenant_database_registry')
                ->where('tenant_id', $this->tenantId)
                ->update(['status' => 'active', 'provisioned_at' => now(), 'updated_at' => now()]);
            $this->recordEvent('tenant_ready', $this->databaseName, 'success', [
                'actor_user_id' => $this->actorId,
                'domain' => $domain,
                'reason' => $this->reason,
                'database' => $this->databaseName,
                'runtime_role' => $this->runtimeRole,
                'migrator_login' => false,
            ]);

            $this->info("Tenant {$this->tenantId} provisioned; PostgreSQL runtime smoke checks passed and domain {$domain} is active.");
            return self::SUCCESS;
        } catch (Throwable $exception) {
            if ($this->migrationRoleEnabled && $this->broker !== null) {
                try {
                    $this->broker->unprepared(
                        'ALTER ROLE '.$this->identifier($this->migratorRole).' WITH NOLOGIN PASSWORD NULL '
                        .'NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT'
                    );
                    $this->migrationRoleEnabled = false;
                } catch (Throwable) {
                    // Fail closed; do not print SQL or credentials from the database exception.
                }
            }

            if ($this->ownerMembershipGranted && $this->broker !== null) {
                try {
                    $this->revokeTemporaryOwnerMembership();
                } catch (Throwable) {
                    // The role is marked by deterministic tenant ownership and can be remediated manually.
                }
            }

            if ($this->provisioningStarted && $this->central !== null) {
                try {
                    $this->central->table('tenant_database_registry')
                        ->where('tenant_id', $this->tenantId)
                        ->update(['status' => 'failed', 'updated_at' => now()]);
                    $this->recordEvent('provisioning_failed', $this->databaseName, 'failed', [
                        'actor_user_id' => $this->actorId,
                        'stage' => $this->stage,
                        'error_class' => $exception::class,
                        'reason' => $this->reason,
                        'resources_preserved' => true,
                    ]);
                } catch (Throwable) {
                    // Preserve the original failure without leaking database connection details.
                }
            }

            logger()->warning('Tenant database provisioning failed; existing resources were preserved.', [
                'tenant_id' => $this->tenantId,
                'stage' => $this->stage,
                'exception_class' => $exception::class,
            ]);
            $this->error("Tenant provisioning failed at stage '{$this->stage}'. No tenant database was dropped; inspect the private worker's redacted error logs.");
            return self::FAILURE;
        } finally {
            if ($this->ownerMembershipGranted && $this->broker !== null) {
                try {
                    $this->revokeTemporaryOwnerMembership();
                } catch (Throwable) {
                    logger()->critical('Could not remove temporary tenant-owner membership from provisioner role.', [
                        'tenant_id' => $this->tenantId,
                        'migrator_role' => $this->migratorRole,
                    ]);
                }
            }

            $this->resetDynamicConnections();
            if ($locked && $this->central !== null) {
                try {
                    $this->central->selectOne('SELECT pg_advisory_unlock(hashtext(?)::bigint)', [$this->tenantId]);
                } catch (Throwable) {
                    // Session close also releases the advisory lock.
                }
            }
        }
    }

    private function assertBrokerCredentials(): void
    {
        foreach (['central_provisioner', 'tenant_provisioner'] as $name) {
            $connection = config('database.connections.'.$name);
            if (! is_array($connection)
                || ! is_string($connection['username'] ?? null)
                || str_contains((string) ($connection['username'] ?? ''), '_role_required__')
                || ! is_string($connection['password'] ?? null)
                || trim((string) $connection['password']) === '') {
                throw new RuntimeException('private_provisioner_credentials_not_configured');
            }
        }

        $centralMigrator = config('database.connections.central_migrator.username');
        $tenantMigrator = config('database.connections.tenant_migrator.username');
        if (str_contains((string) $centralMigrator, '_role_required__')
            || str_contains((string) $tenantMigrator, '_role_required__')) {
            // The command must work without production DDL/migrator secrets preloaded.
            // It dynamically injects a single tenant-scoped migrator credential only
            // after the tenant identity and resources have been verified.
        }
    }

    private function assertRolePurpose(): void
    {
        $centralRole = $this->central?->selectOne(
            'SELECT rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls FROM pg_roles WHERE rolname = current_user'
        );
        if ($centralRole === null
            || $centralRole->rolsuper
            || $centralRole->rolcreatedb
            || $centralRole->rolcreaterole
            || $centralRole->rolreplication
            || $centralRole->rolbypassrls) {
            throw new RuntimeException('central_provisioner_role_is_overprivileged');
        }

        $brokerRole = $this->broker?->selectOne(
            'SELECT rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls FROM pg_roles WHERE rolname = current_user'
        );
        if ($brokerRole === null
            || $brokerRole->rolsuper
            || ! $brokerRole->rolcreatedb
            || ! $brokerRole->rolcreaterole
            || $brokerRole->rolreplication
            || $brokerRole->rolbypassrls) {
            throw new RuntimeException('tenant_provisioner_role_must_be_scoped_createdb_createrole');
        }
    }

    private function isValidDomain(string $domain): bool
    {
        if (strlen($domain) < 4 || strlen($domain) > 253 || filter_var($domain, FILTER_VALIDATE_IP) !== false) {
            return false;
        }

        return preg_match(
            '/^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/',
            $domain
        ) === 1;
    }

    private function roleComment(string $kind): string
    {
        return 'berkahpos tenant='.$this->tenantId.' kind='.$kind;
    }

    private function ensureSafeRole(string $role, string $comment, bool $login, string $password): void
    {
        $existing = $this->broker?->selectOne(
            "SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls, obj_description(oid, 'pg_authid') AS comment FROM pg_roles WHERE rolname = ?",
            [$role]
        );

        if ($existing !== null && (string) $existing->comment !== $comment) {
            throw new RuntimeException('existing_postgresql_role_owner_mismatch');
        }

        if ($existing !== null && ($existing->rolsuper || $existing->rolcreatedb
            || $existing->rolcreaterole || $existing->rolreplication || $existing->rolbypassrls)) {
            throw new RuntimeException('existing_postgresql_role_overprivileged');
        }

        $escapedPassword = str_replace("'", "''", $password);
        if ($existing === null) {
            $this->broker?->unprepared(
                'CREATE ROLE '.$this->identifier($role).' WITH LOGIN PASSWORD '."'{$escapedPassword}' "
                .'NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT'
            );
        } else {
            $this->broker?->unprepared(
                'ALTER ROLE '.$this->identifier($role).' WITH LOGIN PASSWORD '."'{$escapedPassword}' "
                .'NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT'
            );
        }

        $this->broker?->unprepared(
            'COMMENT ON ROLE '.$this->identifier($role).' IS '.$this->literal($comment)
        );
    }

    private function roleIsOwnedAndSafe(string $role, string $comment, bool $mustLogin): bool
    {
        $record = $this->broker?->selectOne(
            "SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls, obj_description(oid, 'pg_authid') AS comment FROM pg_roles WHERE rolname = ?",
            [$role]
        );

        return $record !== null
            && (string) $record->comment === $comment
            && (bool) $record->rolcanlogin === $mustLogin
            && ! $record->rolsuper && ! $record->rolcreatedb && ! $record->rolcreaterole
            && ! $record->rolreplication && ! $record->rolbypassrls;
    }

    private function databaseExists(): bool
    {
        return $this->broker?->selectOne('SELECT 1 FROM pg_database WHERE datname = ?', [$this->databaseName]) !== null;
    }

    private function databaseIsOwnedAndMarked(): bool
    {
        $record = $this->broker?->selectOne(
            "SELECT owner.rolname AS owner_name, shobj_description(database.oid, 'pg_database') AS comment FROM pg_database AS database JOIN pg_roles AS owner ON owner.oid = database.datdba WHERE database.datname = ?",
            [$this->databaseName]
        );

        return $record !== null
            && (string) $record->owner_name === $this->migratorRole
            && (string) $record->comment === $this->databaseComment();
    }

    private function databaseComment(): string
    {
        return 'berkahpos tenant='.$this->tenantId.' database';
    }

    private function grantTemporaryOwnerMembership(): void
    {
        $provisionerUser = (string) config('database.connections.tenant_provisioner.username');
        $this->broker?->unprepared(
            'GRANT '.$this->identifier($this->migratorRole).' TO '.$this->identifier($provisionerUser)
        );
        $this->ownerMembershipGranted = true;
    }

    private function revokeTemporaryOwnerMembership(): void
    {
        $provisionerUser = (string) config('database.connections.tenant_provisioner.username');
        $this->broker?->unprepared(
            'REVOKE '.$this->identifier($this->migratorRole).' FROM '.$this->identifier($provisionerUser)
        );
        $this->ownerMembershipGranted = false;
    }

    private function ensureTenantDatabase(bool $wasActive): void
    {
        $record = $this->broker?->selectOne(
            "SELECT owner.rolname AS owner_name, shobj_description(database.oid, 'pg_database') AS comment FROM pg_database AS database JOIN pg_roles AS owner ON owner.oid = database.datdba WHERE database.datname = ?",
            [$this->databaseName]
        );

        if ($record !== null) {
            if ((string) $record->owner_name !== $this->migratorRole
                || (string) $record->comment !== $this->databaseComment()) {
                throw new RuntimeException('existing_database_owner_or_identity_mismatch');
            }
            return;
        }

        if ($wasActive) {
            throw new RuntimeException('active_tenant_database_missing_fail_closed');
        }

        $this->broker?->unprepared(
            'CREATE DATABASE '.$this->identifier($this->databaseName).' OWNER '.$this->identifier($this->migratorRole)
        );
        $this->broker?->unprepared(
            'COMMENT ON DATABASE '.$this->identifier($this->databaseName).' IS '.$this->literal($this->databaseComment())
        );
    }

    private function configureDatabaseConnectAcl(): void
    {
        $database = $this->identifier($this->databaseName);
        $runtime = $this->identifier($this->runtimeRole);
        $migrator = $this->identifier($this->migratorRole);
        $this->broker?->unprepared('REVOKE CONNECT, TEMPORARY ON DATABASE '.$database.' FROM PUBLIC');
        $this->broker?->unprepared('GRANT CONNECT ON DATABASE '.$database.' TO '.$runtime.', '.$migrator);
    }

    private function configureTenantMigratorConnection(): void
    {
        $provisioner = config('database.connections.tenant_provisioner');
        Config::set('database.connections.tenant_migrator', [
            'driver' => 'pgsql',
            'host' => $provisioner['host'],
            'port' => $provisioner['port'],
            'database' => $this->databaseName,
            'username' => $this->migratorRole,
            'password' => $this->migratorPassword,
            'charset' => 'utf8',
            'prefix' => '',
            'prefix_indexes' => true,
            'search_path' => 'public',
            'sslmode' => $provisioner['sslmode'] ?? 'verify-full',
        ]);
        DB::purge('tenant_migrator');
    }

    private function applyRuntimeGrants(): void
    {
        $connection = DB::connection('tenant_migrator');
        $runtime = $this->identifier($this->runtimeRole);

        $connection->unprepared('REVOKE CREATE ON SCHEMA public FROM PUBLIC');
        $connection->unprepared('GRANT USAGE ON SCHEMA public TO '.$runtime);
        $connection->unprepared('REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM PUBLIC');
        $connection->unprepared('REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC');
        $connection->unprepared('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC');
        $connection->unprepared('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC');
        $connection->unprepared(
            'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO '.$runtime
        );
        $connection->unprepared(
            'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO '.$runtime
        );
        $connection->unprepared(
            'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO '.$runtime
        );
        $connection->unprepared(
            'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO '.$runtime
        );
        $connection->unprepared(
            'REVOKE ALL PRIVILEGES ON TABLE public.migrations FROM '.$runtime
        );
    }

    private function smokeTestRuntime(): void
    {
        $provisioner = config('database.connections.tenant_provisioner');
        Config::set('database.connections.tenant_runtime', [
            'driver' => 'pgsql',
            'host' => $provisioner['host'],
            'port' => $provisioner['port'],
            'database' => $this->databaseName,
            'username' => $this->runtimeRole,
            'password' => $this->runtimePassword,
            'charset' => 'utf8',
            'prefix' => '',
            'prefix_indexes' => true,
            'search_path' => 'public',
            'sslmode' => $provisioner['sslmode'] ?? 'verify-full',
        ]);
        DB::purge('tenant_runtime');

        try {
            $runtime = DB::connection('tenant_runtime');
            if ((int) $runtime->selectOne('SELECT 1 AS ok')->ok !== 1) {
                throw new RuntimeException('tenant_runtime_smoke_query_failed');
            }

            $privileges = $runtime->selectOne(
                "SELECT has_schema_privilege(current_user, 'public', 'CREATE') AS can_create_schema_objects, "
                ."has_table_privilege(current_user, 'public.migrations', 'INSERT') AS can_modify_migrations, "
                .'role.rolsuper, role.rolcreatedb, role.rolcreaterole, role.rolbypassrls '
                .'FROM pg_roles AS role WHERE role.rolname = current_user'
            );

            if ($privileges === null || $privileges->can_create_schema_objects
                || $privileges->can_modify_migrations || $privileges->rolsuper
                || $privileges->rolcreatedb || $privileges->rolcreaterole || $privileges->rolbypassrls) {
                throw new RuntimeException('tenant_runtime_privilege_smoke_failed');
            }

            $requiredTables = $runtime->selectOne(
                "SELECT to_regclass('public.journal_entries') IS NOT NULL AS has_journal_entries, "
                ."to_regclass('public.journal_lines') IS NOT NULL AS has_journal_lines, "
                ."to_regclass('public.accounting_periods') IS NOT NULL AS has_accounting_periods"
            );
            if ($requiredTables === null || ! $requiredTables->has_journal_entries
                || ! $requiredTables->has_journal_lines || ! $requiredTables->has_accounting_periods) {
                throw new RuntimeException('tenant_runtime_required_tables_missing');
            }
        } finally {
            DB::disconnect('tenant_runtime');
            DB::purge('tenant_runtime');
            Config::set('database.connections.tenant_runtime', [
                'driver' => 'pgsql',
                'host' => $provisioner['host'],
                'port' => $provisioner['port'],
                'database' => '__tenant_database_not_resolved__',
                'username' => '__tenant_runtime_role_required__',
                'password' => '',
                'charset' => 'utf8',
                'prefix' => '',
                'prefix_indexes' => true,
                'search_path' => 'public',
                'sslmode' => $provisioner['sslmode'] ?? 'verify-full',
            ]);
        }
    }

    private function resetDynamicConnections(): void
    {
        foreach (['tenant_migrator', 'tenant_runtime'] as $name) {
            try {
                DB::disconnect($name);
                DB::purge($name);
            } catch (Throwable) {
                // Connection may not have been constructed.
            }
        }

        $provisioner = config('database.connections.tenant_provisioner', []);
        Config::set('database.connections.tenant_migrator', [
            'driver' => 'pgsql',
            'host' => $provisioner['host'] ?? '127.0.0.1',
            'port' => $provisioner['port'] ?? '5432',
            'database' => $provisioner['database'] ?? 'postgres',
            'username' => '__tenant_migrator_role_required__',
            'password' => '',
            'charset' => 'utf8',
            'prefix' => '',
            'prefix_indexes' => true,
            'search_path' => 'public',
            'sslmode' => $provisioner['sslmode'] ?? 'verify-full',
        ]);
        Config::set('database.connections.tenant_runtime', [
            'driver' => 'pgsql',
            'host' => $provisioner['host'] ?? '127.0.0.1',
            'port' => $provisioner['port'] ?? '5432',
            'database' => '__tenant_database_not_resolved__',
            'username' => '__tenant_runtime_role_required__',
            'password' => '',
            'charset' => 'utf8',
            'prefix' => '',
            'prefix_indexes' => true,
            'search_path' => 'public',
            'sslmode' => $provisioner['sslmode'] ?? 'verify-full',
        ]);
    }

    private function recordEvent(string $event, string $resource, string $outcome, array $metadata): void
    {
        $this->central?->table('tenant_provisioning_events')->insert([
            'tenant_id' => $this->tenantId,
            'event' => $event,
            'resource' => $resource,
            'outcome' => $outcome,
            'metadata' => json_encode($metadata, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
            'occurred_at' => now(),
        ]);
    }

    private function identifier(string $name): string
    {
        if (preg_match('/^[A-Za-z_][A-Za-z0-9_]{0,62}$/', $name) !== 1) {
            throw new RuntimeException('generated_postgresql_identifier_invalid');
        }

        return '"'.$name.'"';
    }

    private function literal(string $value): string
    {
        return "'".str_replace("'", "''", $value)."'";
    }
}
