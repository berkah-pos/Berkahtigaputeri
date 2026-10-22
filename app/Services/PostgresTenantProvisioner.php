<?php

namespace App\Services;

use Closure;
use Illuminate\Support\Facades\DB;
use RuntimeException;
use Throwable;

/**
 * PostgreSQL-only tenant database bootstrap.
 *
 * This service is deliberately not registered as an HTTP endpoint. Run it only
 * from a separately isolated provisioning worker whose PROVISIONER_* credentials
 * are not present in web or ordinary queue containers.
 *
 * Credential callback must persist each generated credential in the approved
 * secret manager and return a non-secret reference. If persistence fails, no
 * database or login role is created.
 */
final class PostgresTenantProvisioner
{
    /**
     * Create a tenant database and three distinct roles using the private broker
     * connection. Existing/unregistered resources are never adopted or dropped.
     *
     * @param Closure(string, string): string $storeCredential Receives a stable
     *        secret key and password; returns a secret-manager reference.
     * @return array{tenant_id:string,database:string,runtime_role:string,migrator_role:string,owner_role:string,credential_refs:array{runtime:string,migrator:string}}
     */
    public function provision(string $tenantId, Closure $storeCredential): array
    {
        $tenant = $this->normalizeTenantId($tenantId);
        $database = 'berkahpos_t_' . strtolower($tenant);
        $suffix = strtolower($tenant);
        $ownerRole = 'berkah_t_' . $suffix . '_owner';
        $runtimeRole = 'berkah_t_' . $suffix . '_runtime';
        $migratorRole = 'berkah_t_' . $suffix . '_migrator';

        $broker = config('database.connections.provisioner');
        $central = config('database.connections.central');

        if (! is_array($broker) || ($broker['driver'] ?? null) !== 'pgsql') {
            throw new RuntimeException('Dedicated PostgreSQL provisioner connection is not configured.');
        }

        if (($broker['database'] ?? null) === ($central['database'] ?? null)
            || ($broker['username'] ?? null) === ($central['username'] ?? null)
            || empty($broker['username'])
            || empty($broker['password'])) {
            throw new RuntimeException('Provisioner credentials must be non-empty and distinct from central runtime credentials.');
        }

        $runtimePassword = bin2hex(random_bytes(32));
        $migratorPassword = bin2hex(random_bytes(32));

        // Persist secrets before creating any database objects. Never return passwords.
        $runtimeRef = $storeCredential('tenant/' . $tenant . '/runtime', $runtimePassword);
        $migratorRef = $storeCredential('tenant/' . $tenant . '/migrator', $migratorPassword);
        if (! is_string($runtimeRef) || $runtimeRef === '' || ! is_string($migratorRef) || $migratorRef === '') {
            throw new RuntimeException('Secret manager did not return valid credential references.');
        }

        $connection = DB::connection('provisioner');
        $connection->getPdo();

        // Session-level lock serializes concurrent attempts for this tenant. It is
        // held across CREATE DATABASE, which cannot run inside a transaction.
        $lockKey = $this->advisoryLockKey($tenant);
        $connection->select('SELECT pg_advisory_lock(?)', [$lockKey]);

        try {
            $existing = $connection->select(
                'SELECT datname FROM pg_database WHERE datname = ?',
                [$database]
            );
            $existingRoles = $connection->select(
                'SELECT rolname FROM pg_roles WHERE rolname IN (?, ?, ?)',
                [$ownerRole, $runtimeRole, $migratorRole]
            );

            if ($existing !== [] || $existingRoles !== []) {
                throw new RuntimeException('Tenant database or role already exists; refusing to adopt or modify unverified resources.');
            }

            $connection->statement('CREATE ROLE ' . $this->identifier($ownerRole) . ' NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS');
            $connection->statement(
                'CREATE ROLE ' . $this->identifier($runtimeRole)
                . ' LOGIN PASSWORD ' . $this->literal($runtimePassword)
                . ' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS'
            );
            $connection->statement(
                'CREATE ROLE ' . $this->identifier($migratorRole)
                . ' LOGIN PASSWORD ' . $this->literal($migratorPassword)
                . ' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS'
            );

            $connection->statement('GRANT ' . $this->identifier($ownerRole) . ' TO ' . $this->identifier($migratorRole));
            $connection->statement(
                'CREATE DATABASE ' . $this->identifier($database)
                . ' OWNER ' . $this->identifier($ownerRole)
                . ' TEMPLATE template0 ENCODING \'UTF8\''
            );

            // Use a temporary connection derived from the private broker settings,
            // never from caller-supplied database names or tenant IDs.
            config(['database.connections.provisioning_target' => array_merge($broker, [
                'database' => $database,
                'username' => $broker['username'],
                'password' => $broker['password'],
            ])]);
            DB::purge('provisioning_target');
            $target = DB::connection('provisioning_target');
            $target->statement('ALTER SCHEMA public OWNER TO ' . $this->identifier($ownerRole));
            $target->statement('REVOKE ALL ON SCHEMA public FROM PUBLIC');
            $target->statement('GRANT CONNECT ON DATABASE ' . $this->identifier($database) . ' TO ' . $this->identifier($runtimeRole));
            $target->statement('GRANT USAGE ON SCHEMA public TO ' . $this->identifier($runtimeRole));
            $target->statement('GRANT USAGE, CREATE ON SCHEMA public TO ' . $this->identifier($migratorRole));
            $target->statement('GRANT ' . $this->identifier($ownerRole) . ' TO ' . $this->identifier($migratorRole));
            $target->statement(
                'ALTER DEFAULT PRIVILEGES FOR ROLE ' . $this->identifier($ownerRole)
                . ' IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO '
                . $this->identifier($runtimeRole)
            );
            $target->statement(
                'ALTER DEFAULT PRIVILEGES FOR ROLE ' . $this->identifier($ownerRole)
                . ' IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO '
                . $this->identifier($runtimeRole)
            );

            // Explicitly revoke broad database connection and grant only tenant roles.
            $connection->statement('REVOKE ALL ON DATABASE ' . $this->identifier($database) . ' FROM PUBLIC');
            $connection->statement('GRANT CONNECT ON DATABASE ' . $this->identifier($database) . ' TO ' . $this->identifier($runtimeRole));
            $connection->statement('GRANT CONNECT ON DATABASE ' . $this->identifier($database) . ' TO ' . $this->identifier($migratorRole));

            return [
                'tenant_id' => $tenant,
                'database' => $database,
                'runtime_role' => $runtimeRole,
                'migrator_role' => $migratorRole,
                'owner_role' => $ownerRole,
                'credential_refs' => ['runtime' => $runtimeRef, 'migrator' => $migratorRef],
            ];
        } catch (Throwable $exception) {
            // No automatic DROP: a partial failure may already contain data.
            throw new RuntimeException(
                'Tenant provisioning failed; resources were not automatically removed. Manual verification is required.',
                previous: $exception
            );
        } finally {
            DB::purge('provisioning_target');
            $connection->select('SELECT pg_advisory_unlock(?)', [$lockKey]);
        }
    }

    public function normalizeTenantId(string $tenantId): string
    {
        $tenant = strtoupper(trim($tenantId));
        // Accept only canonical ULIDs, not arbitrary caller-controlled DB identifiers.
        if (! preg_match('/^[0-7][0-9A-HJKMNP-TV-Z]{25}$/', $tenant)) {
            throw new RuntimeException('Tenant ID must be a canonical ULID.');
        }

        return $tenant;
    }

    private function advisoryLockKey(string $tenant): int
    {
        // Stable signed 64-bit key derived from the canonical tenant identifier.
        $bytes = substr(hash('sha256', $tenant, true), 0, 8);
        $parts = unpack('Nhigh/Nlow', $bytes);
        $unsigned = ($parts['high'] << 32) | $parts['low'];

        return $unsigned > PHP_INT_MAX ? $unsigned - PHP_INT_MAX - 1 : $unsigned;
    }

    private function identifier(string $identifier): string
    {
        if (! preg_match('/^[a-z_][a-z0-9_]{0,62}$/', $identifier)) {
            throw new RuntimeException('Refusing unsafe PostgreSQL identifier.');
        }

        return '"' . $identifier . '"';
    }

    private function literal(string $value): string
    {
        return "'" . str_replace("'", "''", $value) . "'";
    }
}
