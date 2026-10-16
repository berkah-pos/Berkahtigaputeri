<?php

namespace App\Services;

use App\Models\Central\Tenant;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use RuntimeException;
use Throwable;

class TenantDatabaseProvisioner
{
    private const MARKER_TABLE = '__berkah_pos_provisioning';

    public function provision(Tenant $tenant): void
    {
        foreach ([
            'database.connections.provisioner.username',
            'database.connections.provisioner.password',
            'database.connections.migrator.username',
            'database.connections.migrator.password',
        ] as $credentialConfigKey) {
            if (trim((string) config($credentialConfigKey, '')) === '') {
                throw new RuntimeException('Provisioning requires the dedicated private worker credentials.');
            }
        }

        $tenantId = (string) $tenant->getTenantKey();
        if (! preg_match('/^[a-zA-Z0-9_-]{1,100}$/', $tenantId)) {
            throw new RuntimeException('Tenant key is not in the accepted identifier format.');
        }

        $databaseName = $this->databaseName($tenantId);
        $runtimeUsername = $this->runtimeUsername($tenantId);
        $lockName = 'bp-provision-'.substr(hash('sha256', $tenantId), 0, 40);
        $provisioner = DB::connection('provisioner');
        $lock = $provisioner->selectOne('SELECT GET_LOCK(?, 30) AS acquired', [$lockName]);

        if ((int) ($lock->acquired ?? 0) !== 1) {
            throw new RuntimeException('Could not acquire the tenant provisioning lock.');
        }

        $provisioningId = null;
        $reservationCreatedThisRun = false;

        try {
            $tenant->refresh();
            $state = $tenant->data['database_provisioning'] ?? null;

            if (! is_array($state)) {
                // A pre-existing DB/user without our central reservation is
                // untrusted. Never adopt or drop it automatically.
                if ($this->databaseExists($databaseName) || $this->runtimeUserExists($runtimeUsername)) {
                    $provisioningId = (string) Str::uuid();
                    $this->audit($tenantId, $provisioningId, 'provisioning.collision.detected', [
                        'database_name' => $databaseName,
                        'runtime_username' => $runtimeUsername,
                    ]);
                    throw new RuntimeException('An unregistered database or user already exists; manual review is required.');
                }

                $provisioningId = (string) Str::uuid();
                $runtimePassword = Str::random(64);
                $tenant->setAttribute('tenancy_db_name', $databaseName);
                $data = $tenant->data ?? [];
                $data['database_provisioning'] = [
                    'status' => 'provisioning',
                    'tenant_id' => $tenantId,
                    'database_name' => $databaseName,
                    'runtime_username' => $runtimeUsername,
                    'runtime_password_encrypted' => Crypt::encryptString($runtimePassword),
                    'provisioning_id' => $provisioningId,
                    'reserved_at' => now()->toIso8601String(),
                ];
                $tenant->data = $data;
                $tenant->save();
                $state = $tenant->data['database_provisioning'];
                $reservationCreatedThisRun = true;
                $this->audit($tenantId, $provisioningId, 'provisioning.reserved', [
                    'database_name' => $databaseName,
                    'runtime_username' => $runtimeUsername,
                ]);
            } else {
                $provisioningId = (string) ($state['provisioning_id'] ?? '');
                if ($provisioningId === ''
                    || ($state['tenant_id'] ?? null) !== $tenantId
                    || ($state['database_name'] ?? null) !== $databaseName
                    || ($state['runtime_username'] ?? null) !== $runtimeUsername
                    || empty($state['runtime_password_encrypted'])
                    || ! in_array($state['status'] ?? null, ['provisioning', 'provisioned'], true)) {
                    throw new RuntimeException('Stored provisioning metadata does not match the expected tenant identity.');
                }

                // Ensure the package resolves this exact database name.
                $tenant->setAttribute('tenancy_db_name', $databaseName);
                $tenant->save();
                $runtimePassword = Crypt::decryptString((string) $state['runtime_password_encrypted']);
            }

            $runtimePassword = $runtimePassword ?? Crypt::decryptString(
                (string) $state['runtime_password_encrypted']
            );

            $databaseExists = $this->databaseExists($databaseName);
            if (! $databaseExists) {
                $hasLaterProvisioningEvidence = ($state['status'] ?? null) === 'provisioned'
                    || $this->hasAuditAction($provisioningId, 'database.create.completed')
                    || $this->hasAuditAction($provisioningId, 'database.create.recovered_after_interruption')
                    || $this->hasAuditAction($provisioningId, 'runtime_user.create.intent')
                    || $this->hasAuditAction($provisioningId, 'ownership_marker.create.intent')
                    || $this->hasAuditAction($provisioningId, 'tenant_migrations.started')
                    || $this->hasAuditAction($provisioningId, 'provisioning.completed');
                if ($hasLaterProvisioningEvidence) {
                    $this->audit($tenantId, $provisioningId, 'provisioning.missing_database.refused', [
                        'database_name' => $databaseName,
                        'reason' => 'prior provisioning evidence indicates this database may have held data',
                    ]);
                    throw new RuntimeException('Previously provisioned tenant database is missing; automatic recreation refused for review.');
                }

                $this->audit($tenantId, $provisioningId, 'database.create.intent', [
                    'database_name' => $databaseName,
                ]);
                $this->audit($tenantId, $provisioningId, 'database.absent.verified', [
                    'database_name' => $databaseName,
                ]);
                $provisioner->statement(
                    'CREATE DATABASE '.$this->quoteIdentifier($databaseName).' CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci'
                );
                $this->audit($tenantId, $provisioningId, 'database.create.completed', [
                    'database_name' => $databaseName,
                ]);
            } else {
                $this->verifyOrResumeExistingDatabase($tenantId, $databaseName, $provisioningId, $state);
            }

            if (! $this->runtimeUserExists($runtimeUsername)) {
                $this->audit($tenantId, $provisioningId, 'runtime_user.create.intent', [
                    'runtime_username' => $runtimeUsername,
                    'database_name' => $databaseName,
                ]);
                // Password is a prepared binding and is never written to the audit
                // record, command output, or application log.
                $quotedPassword = $provisioner->getPdo()->quote($runtimePassword);
                if ($quotedPassword === false) {
                    throw new RuntimeException('Could not safely encode the generated tenant password.');
                }
                $provisioner->statement(
                    "CREATE USER IF NOT EXISTS '{$runtimeUsername}'@'%' IDENTIFIED BY ".$quotedPassword
                );
                $this->audit($tenantId, $provisioningId, 'runtime_user.create.completed', [
                    'runtime_username' => $runtimeUsername,
                    'database_name' => $databaseName,
                ]);
            } else {
                // A previously absent account that appears after this invocation
                // reserved the tenant ID is an external collision. Do not adopt it.
                if ($reservationCreatedThisRun) {
                    $this->audit($tenantId, $provisioningId, 'runtime_user.collision.detected', [
                        'runtime_username' => $runtimeUsername,
                        'reason' => 'account appeared after reservation and was absent at initial verification',
                    ]);
                    throw new RuntimeException('Tenant runtime account appeared during provisioning; resources were preserved for review.');
                }

                // A retry with an existing reservation can recover a create that
                // completed before its completion audit was written.
                $this->audit($tenantId, $provisioningId, 'runtime_user.create.recovered_or_existing_for_retry', [
                    'runtime_username' => $runtimeUsername,
                ]);
            }

            $this->audit($tenantId, $provisioningId, 'runtime_grant.intent', [
                'runtime_username' => $runtimeUsername,
                'database_name' => $databaseName,
                'privileges' => ['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            ]);
            $provisioner->statement(
                'GRANT SELECT, INSERT, UPDATE, DELETE ON '.$this->quoteIdentifier($databaseName).".* TO '{$runtimeUsername}'@'%'"
            );
            $this->assertRuntimeGrants($runtimeUsername, $databaseName);
            $this->audit($tenantId, $provisioningId, 'runtime_grant.completed', [
                'runtime_username' => $runtimeUsername,
                'database_name' => $databaseName,
                'privileges' => ['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
            ]);

            $this->ensureOwnershipMarker($tenantId, $databaseName, $provisioningId, $state);

            $this->audit($tenantId, $provisioningId, 'tenant_migrations.started', [
                'database_name' => $databaseName,
            ]);
            $this->runTenantMigrations($databaseName);
            $this->audit($tenantId, $provisioningId, 'tenant_migrations.completed', [
                'database_name' => $databaseName,
            ]);

            $this->assertRuntimeLogin($databaseName, $runtimeUsername, $runtimePassword);

            $tenant->refresh();
            $data = $tenant->data ?? [];
            $data['database_provisioning']['status'] = 'provisioned';
            $data['database_provisioning']['provisioned_at'] = now()->toIso8601String();
            unset($data['database_provisioning']['last_failure_code']);
            $tenant->data = $data;
            $tenant->save();

            $this->audit($tenantId, $provisioningId, 'provisioning.completed', [
                'database_name' => $databaseName,
                'runtime_username' => $runtimeUsername,
            ]);
            Log::info('Tenant database provisioning completed.', [
                'tenant_id' => $tenantId,
                'database_name' => $databaseName,
                'provisioning_id' => $provisioningId,
            ]);
        } catch (Throwable $exception) {
            if ($provisioningId !== null && $provisioningId !== '') {
                try {
                    $tenant->refresh();
                    $data = $tenant->data ?? [];
                    if (isset($data['database_provisioning'])) {
                        $data['database_provisioning']['status'] = 'provisioning';
                        $data['database_provisioning']['last_failure_code'] = $this->safeFailureCode($exception);
                        $tenant->data = $data;
                        $tenant->save();
                    }
                    $this->audit($tenantId, $provisioningId, 'provisioning.failed', [
                        'exception_class' => $exception::class,
                        'failure_code' => $this->safeFailureCode($exception),
                    ]);
                } catch (Throwable $auditException) {
                    Log::critical('Tenant provisioning failure could not be fully audited.', [
                        'tenant_id' => $tenantId,
                        'provisioning_id' => $provisioningId,
                        'audit_exception_class' => $auditException::class,
                    ]);
                }
            }

            // Intentionally no DROP DATABASE / DROP USER compensation. Unknown or
            // data-bearing state is preserved for audited operator review.
            Log::error('Tenant database provisioning failed; resources were preserved.', [
                'tenant_id' => $tenantId,
                'provisioning_id' => $provisioningId,
                'exception_class' => $exception::class,
                'failure_code' => $this->safeFailureCode($exception),
            ]);
            throw $exception;
        } finally {
            try {
                $provisioner->selectOne('SELECT RELEASE_LOCK(?) AS released', [$lockName]);
            } catch (Throwable) {
                // Session closure releases the MariaDB advisory lock as well.
            }
            foreach (['tenant', 'tenant_probe', 'migrator'] as $connection) {
                DB::purge($connection);
            }
        }
    }

    public function databaseName(string $tenantId): string
    {
        return 'berkahpos_tenant_'.substr(hash('sha256', $tenantId), 0, 32);
    }

    public function runtimeUsername(string $tenantId): string
    {
        return 'bp_t_'.substr(hash('sha256', $tenantId), 0, 20);
    }

    private function databaseExists(string $databaseName): bool
    {
        return DB::connection('provisioner')->selectOne(
            'SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = ?',
            [$databaseName]
        ) !== null;
    }

    private function runtimeUserExists(string $username): bool
    {
        try {
            DB::connection('provisioner')->select("SHOW GRANTS FOR '{$username}'@'%'");

            return true;
        } catch (QueryException $exception) {
            if ((int) ($exception->errorInfo[1] ?? 0) === 1141) {
                return false;
            }
            throw $exception;
        }
    }

    private function verifyOrResumeExistingDatabase(
        string $tenantId,
        string $databaseName,
        string $provisioningId,
        array $state,
    ): void {
        if ($this->tableExists($databaseName, self::MARKER_TABLE)) {
            $marker = $this->readMarker($databaseName);
            if ($marker !== null
                && (string) $marker->tenant_id === $tenantId
                && (string) $marker->provisioning_id === $provisioningId) {
                return;
            }

            // A marker table without a valid row is recoverable only if this
            // provisioning attempt created the database from a verified-empty
            // state and no other table has appeared.
            if (($state['status'] ?? null) === 'provisioning'
                && $marker === null
                && $this->tableCount($databaseName) === 1
                && $this->hasAuditAction($provisioningId, 'database.absent.verified')
                && $this->hasAuditAction($provisioningId, 'ownership_marker.create.intent')) {
                $this->insertMarker($databaseName, $tenantId, $provisioningId);
                $this->audit($tenantId, $provisioningId, 'ownership_marker.recovered', [
                    'database_name' => $databaseName,
                ]);

                return;
            }

            throw new RuntimeException('Existing tenant database ownership marker is invalid; database preserved for review.');
        }

        if (($state['status'] ?? null) !== 'provisioning'
            || ! $this->hasAuditAction($provisioningId, 'database.absent.verified')
            || $this->tableCount($databaseName) !== 0) {
            throw new RuntimeException('Existing tenant database has no verified ownership marker; database preserved for review.');
        }

        // Handles interruption after CREATE DATABASE but before creating the
        // first table. Resume only when our durable audit says it was empty.
        $this->audit($tenantId, $provisioningId, 'database.empty_retry_verified', [
            'database_name' => $databaseName,
        ]);
        $this->audit($tenantId, $provisioningId, 'database.create.recovered_after_interruption', [
            'database_name' => $databaseName,
            'recovery_condition' => 'provisioning reservation present, prior absence audit present, schema empty',
        ]);
    }

    private function ensureOwnershipMarker(
        string $tenantId,
        string $databaseName,
        string $provisioningId,
        array $state,
    ): void {
        if ($this->tableExists($databaseName, self::MARKER_TABLE)) {
            $marker = $this->readMarker($databaseName);
            if ($marker !== null) {
                if ((string) $marker->tenant_id !== $tenantId
                    || (string) $marker->provisioning_id !== $provisioningId) {
                    throw new RuntimeException('Tenant database ownership marker does not match; database preserved.');
                }

                return;
            }

            if (($state['status'] ?? null) === 'provisioned'
                || ! $this->hasAuditAction($provisioningId, 'ownership_marker.create.intent')) {
                throw new RuntimeException('Empty or incomplete ownership marker is not safely recoverable.');
            }
            $this->insertMarker($databaseName, $tenantId, $provisioningId);

            return;
        }

        if (($state['status'] ?? null) === 'provisioning') {
            if (! $this->hasAuditAction($provisioningId, 'database.absent.verified')
                || $this->tableCount($databaseName) !== 0) {
                throw new RuntimeException('Unmarked database is not verified empty; database preserved.');
            }
        } else {
            throw new RuntimeException('Provisioned tenant database is missing its ownership marker.');
        }

        $this->audit($tenantId, $provisioningId, 'ownership_marker.create.intent', [
            'database_name' => $databaseName,
        ]);
        $this->useMigratorDatabase($databaseName, function (): void {
            $identifier = $this->quoteIdentifier(self::MARKER_TABLE);
            DB::connection('migrator')->statement(
                'CREATE TABLE '.$identifier.' (
                    id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
                    tenant_id VARCHAR(100) NOT NULL,
                    provisioning_id CHAR(36) NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                ) ENGINE=InnoDB'
            );
        });
        $this->audit($tenantId, $provisioningId, 'ownership_marker.create.completed', [
            'database_name' => $databaseName,
        ]);
        $this->insertMarker($databaseName, $tenantId, $provisioningId);
    }

    private function insertMarker(string $databaseName, string $tenantId, string $provisioningId): void
    {
        $this->useMigratorDatabase($databaseName, function () use ($tenantId, $provisioningId): void {
            DB::connection('migrator')->insert(
                'INSERT INTO '.$this->quoteIdentifier(self::MARKER_TABLE).' (id, tenant_id, provisioning_id) VALUES (1, ?, ?)',
                [$tenantId, $provisioningId]
            );
        });
    }

    private function readMarker(string $databaseName): ?object
    {
        return $this->useMigratorDatabase($databaseName, function (): ?object {
            $rows = DB::connection('migrator')->select(
                'SELECT tenant_id, provisioning_id FROM '.$this->quoteIdentifier(self::MARKER_TABLE).' WHERE id = 1'
            );

            return $rows[0] ?? null;
        });
    }

    private function tableExists(string $databaseName, string $tableName): bool
    {
        return DB::connection('provisioner')->selectOne(
            'SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?',
            [$databaseName, $tableName]
        ) !== null;
    }

    private function tableCount(string $databaseName): int
    {
        $row = DB::connection('provisioner')->selectOne(
            'SELECT COUNT(*) AS table_count FROM information_schema.TABLES WHERE TABLE_SCHEMA = ?',
            [$databaseName]
        );

        return (int) ($row->table_count ?? 0);
    }

    private function assertRuntimeGrants(string $username, string $databaseName): void
    {
        $grants = DB::connection('provisioner')->select("SHOW GRANTS FOR '{$username}'@'%'");
        $applicationGrants = [];

        foreach ($grants as $row) {
            $grant = (string) array_values((array) $row)[0];
            if (preg_match('/^GRANT USAGE ON \*\.\* TO /i', $grant)) {
                continue;
            }
            if (stripos($grant, 'WITH GRANT OPTION') !== false) {
                throw new RuntimeException('Runtime tenant account unexpectedly has GRANT OPTION.');
            }
            if (! preg_match('/^GRANT (.+) ON [\x60]([^\x60]+)[\x60]\.\* TO /i', $grant, $matches)) {
                throw new RuntimeException('Runtime tenant account has an unrecognized or global privilege grant.');
            }
            $privileges = array_map('trim', explode(',', strtoupper($matches[1])));
            sort($privileges);
            $expected = ['DELETE', 'INSERT', 'SELECT', 'UPDATE'];
            sort($expected);

            $grantedDatabase = str_replace(['\\_', '\\%'], ['_', '%'], $matches[2]);
            if ($grantedDatabase !== $databaseName || $privileges !== $expected) {
                throw new RuntimeException('Runtime tenant account has grants outside its exact CRUD contract.');
            }
            $applicationGrants[] = $grant;
        }

        if (count($applicationGrants) !== 1) {
            throw new RuntimeException('Runtime tenant account must have exactly one tenant-database CRUD grant.');
        }
    }

    private function assertRuntimeLogin(string $databaseName, string $username, string $password): void
    {
        $template = config('database.connections.tenant_template');
        $probe = array_merge($template, [
            'database' => $databaseName,
            'username' => $username,
            'password' => $password,
        ]);
        config(['database.connections.tenant_probe' => $probe]);
        DB::purge('tenant_probe');
        try {
            $row = DB::connection('tenant_probe')->selectOne('SELECT DATABASE() AS database_name');
            if (($row->database_name ?? null) !== $databaseName) {
                throw new RuntimeException('Tenant runtime credential did not select the expected database.');
            }
            DB::connection('tenant_probe')->selectOne('SELECT COUNT(*) AS marker_count FROM '.$this->quoteIdentifier(self::MARKER_TABLE));
        } finally {
            DB::purge('tenant_probe');
            config(['database.connections.tenant_probe' => null]);
        }
    }

    private function runTenantMigrations(string $databaseName): void
    {
        $previous = config('database.connections.tenant');
        $template = config('database.connections.tenant_template');
        $migrationConfig = array_merge($template, [
            'database' => $databaseName,
            'username' => config('database.connections.migrator.username'),
            'password' => config('database.connections.migrator.password'),
        ]);

        config(['database.connections.tenant' => $migrationConfig]);
        DB::purge('tenant');
        try {
            $exitCode = Artisan::call('migrate', [
                '--database' => 'tenant',
                '--path' => database_path('migrations/tenant'),
                '--realpath' => true,
                '--force' => true,
            ]);
            if ($exitCode !== 0) {
                throw new RuntimeException('Tenant migrations returned a non-zero exit status.');
            }
        } finally {
            DB::purge('tenant');
            config(['database.connections.tenant' => $previous]);
        }
    }

    private function useMigratorDatabase(string $databaseName, callable $callback): mixed
    {
        $config = config('database.connections.migrator');
        $config['database'] = $databaseName;
        config(['database.connections.migrator' => $config]);
        DB::purge('migrator');

        try {
            return $callback();
        } finally {
            DB::purge('migrator');
            config(['database.connections.migrator' => array_merge(
                $config,
                ['database' => env('MIGRATOR_DB_DATABASE', 'information_schema')]
            )]);
        }
    }

    private function hasAuditAction(string $provisioningId, string $action): bool
    {
        return DB::connection('central')->table('audit_events')
            ->where('scope_type', 'tenant_db_provisioning')
            ->where('scope_id', $provisioningId)
            ->where('action', $action)
            ->exists();
    }

    private function audit(string $tenantId, string $provisioningId, string $action, array $metadata = []): void
    {
        DB::connection('central')->table('audit_events')->insert([
            'actor_user_id' => null,
            'tenant_id' => $tenantId,
            'scope_type' => 'tenant_db_provisioning',
            'scope_id' => $provisioningId,
            'action' => $action,
            'metadata' => json_encode($metadata, JSON_THROW_ON_ERROR),
            'created_at' => now(),
        ]);
    }

    private function safeFailureCode(Throwable $exception): string
    {
        if ($exception instanceof QueryException) {
            return (string) ($exception->errorInfo[1] ?? $exception->getCode());
        }

        return $exception::class;
    }

    private function quoteIdentifier(string $identifier): string
    {
        if (! preg_match('/^[a-zA-Z0-9_]{1,64}$/', $identifier)) {
            throw new RuntimeException('Generated database identifier failed the safe-identifier check.');
        }

        return chr(96).$identifier.chr(96);
    }
}
