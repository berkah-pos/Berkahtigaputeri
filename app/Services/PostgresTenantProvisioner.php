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
 * Credential callbacks persist each generated credential and return a non-secret
 * reference. The delete callback must idempotently remove a secret by stable key.
 * If either write fails, both keys are compensated before database resources exist.
 */
final class PostgresTenantProvisioner
{
    /**
     * Create a tenant database and three distinct roles using the private broker
     * connection. Existing/unregistered resources are never adopted or dropped.
     *
     * @param Closure(string, string): string $storeCredential Receives a stable
     *        secret key and password; returns a secret-manager reference.
     * @param Closure(string): void $deleteCredential Idempotently deletes a secret
     *        by stable key, including when a preceding write timed out ambiguously.
     * @return array{tenant_id:string,database:string,runtime_role:string,migrator_role:string,owner_role:string,credential_refs:array{runtime:string,migrator:string}}
     */
    public function provision(string $tenantId, Closure $storeCredential, Closure $deleteCredential): array
    {
        $tenant = $this->normalizeTenantId($tenantId);
        $database = 'berkahpos_t_' . strtolower($tenant);
        $suffix = strtolower($tenant);
        $ownerRole = 'berkah_t_' . $suffix . '_owner';
        $runtimeRole = 'berkah_t_' . $suffix . '_runtime';
        $migratorRole = 'berkah_t_' . $suffix . '_migrator';

        $broker = $this->validatedBrokerConfig();

        $connection = DB::connection('provisioner');
        $connection->getPdo();
        $brokerRole = (string) $connection->scalar('SELECT current_user');
        $brokerIdentifier = $this->identifier($brokerRole);

        // Session-level lock serializes concurrent attempts for this tenant. It is
        // held across CREATE DATABASE, which cannot run inside a transaction.
        $lockKey = $this->advisoryLockKey($tenant);
        $connection->select('SELECT pg_advisory_lock(?)', [$lockKey]);
        $temporaryOwnerMembershipGranted = false;

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

            // Check resource collision before writing credentials to the secret manager.
            // Stable keys let compensation clean up even if a remote write timed out
            // after persisting a secret but before returning its reference.
            $runtimeKey = 'tenant/' . $tenant . '/runtime';
            $migratorKey = 'tenant/' . $tenant . '/migrator';
            $runtimePassword = bin2hex(random_bytes(32));
            $migratorPassword = bin2hex(random_bytes(32));
            $runtimeRef = null;
            $migratorRef = null;

            try {
                $runtimeRef = $storeCredential($runtimeKey, $runtimePassword);
                if (! is_string($runtimeRef) || $runtimeRef === '') {
                    throw new RuntimeException('Secret manager did not return a valid runtime credential reference.');
                }

                $migratorRef = $storeCredential($migratorKey, $migratorPassword);
                if (! is_string($migratorRef) || $migratorRef === '') {
                    throw new RuntimeException('Secret manager did not return a valid migrator credential reference.');
                }
            } catch (Throwable $storeException) {
                $cleanupFailures = [];

                foreach ([$runtimeKey, $migratorKey] as $secretKey) {
                    try {
                        $deleteCredential($secretKey);
                    } catch (Throwable $cleanupException) {
                        $cleanupFailures[] = $secretKey . ': ' . $cleanupException->getMessage();
                    }
                }

                if ($cleanupFailures !== []) {
                    throw new RuntimeException(
                        'Credential persistence failed and secret cleanup is incomplete; manual secret-manager verification is required. '
                        . implode('; ', $cleanupFailures),
                        previous: $storeException
                    );
                }

                throw $storeException;
            }

            $connection->statement(
                'CREATE ROLE ' . $this->identifier($ownerRole)
                . ' NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS'
            );
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
            // A tenant migrator must be able to SET ROLE to the no-login owner
            // during controlled schema/ACL setup. Default ACLs are also defined for
            // objects created directly by the migrator.
            $connection->statement(
                'GRANT ' . $this->identifier($ownerRole) . ' TO ' . $this->identifier($migratorRole)
            );

            // A non-superuser must be allowed to SET ROLE to the requested owner
            // before it can create a database owned by that role. This membership
            // exists only for CREATE DATABASE and is revoked immediately afterwards.
            $connection->statement('GRANT ' . $this->identifier($ownerRole) . ' TO ' . $brokerIdentifier);
            $temporaryOwnerMembershipGranted = true;
            $connection->statement(
                'CREATE DATABASE ' . $this->identifier($database)
                . ' OWNER ' . $this->identifier($ownerRole)
                . ' TEMPLATE template0 ENCODING \'UTF8\''
            );
            $connection->statement('REVOKE ' . $this->identifier($ownerRole) . ' FROM ' . $brokerIdentifier);
            $temporaryOwnerMembershipGranted = false;

            // Bootstrap the database as the tenant migrator, not as the cluster
            // broker. Membership permits SET ROLE to the database owner during the
            // one-time schema/ACL setup. Default ACLs must be declared for the role
            // that actually creates future objects (migrator as well as owner).
            config(['database.connections.provisioning_target' => array_merge($broker, [
                'url' => null,
                'database' => $database,
                'username' => $migratorRole,
                'password' => $migratorPassword,
            ])]);
            DB::purge('provisioning_target');
            $target = DB::connection('provisioning_target');

            $target->statement('SET ROLE ' . $this->identifier($ownerRole));
            $target->statement(
                'REVOKE ALL ON DATABASE ' . $this->identifier($database) . ' FROM PUBLIC'
            );
            $target->statement(
                'GRANT CONNECT ON DATABASE ' . $this->identifier($database)
                . ' TO ' . $this->identifier($runtimeRole)
            );
            $target->statement(
                'GRANT CONNECT ON DATABASE ' . $this->identifier($database)
                . ' TO ' . $this->identifier($migratorRole)
            );

            $target->statement('ALTER SCHEMA public OWNER TO ' . $this->identifier($ownerRole));
            $target->statement('REVOKE ALL ON SCHEMA public FROM PUBLIC');
            $target->statement(
                'GRANT USAGE ON SCHEMA public TO ' . $this->identifier($runtimeRole)
            );
            $target->statement(
                'GRANT USAGE, CREATE ON SCHEMA public TO ' . $this->identifier($migratorRole)
            );

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

            $target->statement('RESET ROLE');
            $target->statement(
                'ALTER DEFAULT PRIVILEGES FOR ROLE ' . $this->identifier($migratorRole)
                . ' IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO '
                . $this->identifier($runtimeRole)
            );
            $target->statement(
                'ALTER DEFAULT PRIVILEGES FOR ROLE ' . $this->identifier($migratorRole)
                . ' IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO '
                . $this->identifier($runtimeRole)
            );

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
            if ($temporaryOwnerMembershipGranted) {
                try {
                    $connection->statement(
                        'REVOKE ' . $this->identifier($ownerRole) . ' FROM ' . $brokerIdentifier
                    );
                } catch (Throwable) {
                    // Reported as a partial-provisioning blocker; never auto-drop resources.
                }
            }

            // Purge the live connection, then scrub its runtime credential from
            // Laravel's config repository so a long-lived worker cannot retain it.
            try {
                DB::purge('provisioning_target');
            } finally {
                $targetConfig = (array) config('database.connections.provisioning_target', []);
                $targetConfig['url'] = null;
                $targetConfig['database'] = '__tenant_not_configured__';
                $targetConfig['username'] = '';
                $targetConfig['password'] = '';
                config(['database.connections.provisioning_target' => $targetConfig]);

                $connection->select('SELECT pg_advisory_unlock(?)', [$lockKey]);
            }
        }
    }

    /**
     * Retire the temporary tenant migrator after schema migrations succeed.
     *
     * The role remains as a non-login object owner for any migration-created
     * objects, but it loses LOGIN, its password verifier, owner-role membership,
     * and the OpenBao credential. It must not be reused for a future migration
     * without a separately reviewed reactivation flow.
     *
     * @param Closure(string): void $deleteCredential Deletes a secret by stable key.
     */
    public function retireMigratorCredential(string $tenantId, Closure $deleteCredential): void
    {
        $tenant = $this->normalizeTenantId($tenantId);
        $database = 'berkahpos_t_' . strtolower($tenant);
        $suffix = strtolower($tenant);
        $ownerRole = 'berkah_t_' . $suffix . '_owner';
        $migratorRole = 'berkah_t_' . $suffix . '_migrator';

        // Repeat the critical central/broker separation check at the privilege
        // retirement boundary instead of relying only on the earlier provision call.
        $this->validatedBrokerConfig();
        $connection = DB::connection('provisioner');

        $databaseOwner = $connection->scalar(
            'SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = ?',
            [$database]
        );
        $migrator = $connection->selectOne(
            'SELECT rolcanlogin::int AS rolcanlogin FROM pg_roles WHERE rolname = ?',
            [$migratorRole]
        );

        if ($databaseOwner !== $ownerRole || $migrator === null) {
            throw new RuntimeException('Tenant database or migrator role could not be verified; refusing credential retirement.');
        }

        // PASSWORD NULL removes the stored password verifier without placing a
        // newly generated credential into SQL text or PostgreSQL statement logs.
        $connection->statement(
            'ALTER ROLE ' . $this->identifier($migratorRole) . ' NOLOGIN PASSWORD NULL'
        );
        $connection->statement(
            'REVOKE ' . $this->identifier($ownerRole) . ' FROM ' . $this->identifier($migratorRole)
        );

        $retiredRole = $connection->selectOne(
            'SELECT rolcanlogin::int AS rolcanlogin FROM pg_roles WHERE rolname = ?',
            [$migratorRole]
        );
        $ownerMembership = $connection->selectOne(
            'SELECT 1
             FROM pg_auth_members AS membership
             JOIN pg_roles AS granted ON granted.oid = membership.roleid
             JOIN pg_roles AS member ON member.oid = membership.member
             WHERE granted.rolname = ? AND member.rolname = ?',
            [$ownerRole, $migratorRole]
        );

        if ($retiredRole === null || (int) $retiredRole->rolcanlogin !== 0 || $ownerMembership !== null) {
            throw new RuntimeException('Tenant migrator could not be securely retired; provisioning remains incomplete.');
        }

        // The database role is already unable to authenticate before the secret
        // is deleted. If OpenBao is unavailable, command activation must fail closed.
        $deleteCredential('tenant/' . $tenant . '/migrator');
    }

    /**
     * Validate sensitive effective PostgreSQL settings after honoring Laravel URL
     * precedence. Return the dedicated broker config for dynamic tenant connections.
     *
     * @return array<string, mixed>
     */
    private function validatedBrokerConfig(): array
    {
        $broker = config('database.connections.provisioner');
        $central = config('database.connections.central');

        if (! is_array($broker)
            || ! is_array($central)
            || ($broker['driver'] ?? null) !== 'pgsql') {
            throw new RuntimeException('Dedicated PostgreSQL provisioner connection is not configured.');
        }

        $centralDatabase = $this->effectiveConnectionSetting($central, 'database');
        $brokerDatabase = $this->effectiveConnectionSetting($broker, 'database');
        $centralUsername = $this->effectiveConnectionSetting($central, 'username');
        $brokerUsername = $this->effectiveConnectionSetting($broker, 'username');
        $brokerPassword = $this->effectiveConnectionSetting($broker, 'password');

        if ($centralDatabase === null
            || $brokerDatabase === null
            || $centralUsername === null
            || $brokerUsername === null
            || $brokerPassword === null
            || strcasecmp($brokerDatabase, $centralDatabase) === 0
            || strcasecmp($brokerUsername, $centralUsername) === 0) {
            throw new RuntimeException('Provisioner credentials must be non-empty and distinct from central runtime credentials.');
        }

        return $broker;
    }

    /**
     * Resolve a sensitive PostgreSQL connection setting with Laravel URL precedence.
     * Return null for incomplete/malformed URL configs so provisioning fails closed.
     */
    private function effectiveConnectionSetting(array $connection, string $setting): ?string
    {
        if (! in_array($setting, ['database', 'username', 'password'], true)) {
            return null;
        }

        $url = $connection['url'] ?? null;
        if (is_string($url) && trim($url) !== '') {
            $parts = parse_url(trim($url));
            if (! is_array($parts)
                || ! in_array(strtolower((string) ($parts['scheme'] ?? '')), ['postgres', 'postgresql', 'pgsql'], true)
                || ! is_string($parts['host'] ?? null)
                || trim($parts['host']) === '') {
                return null;
            }

            if ($setting === 'database') {
                $value = rawurldecode(trim((string) ($parts['path'] ?? ''), '/'));
            } else {
                $value = isset($parts[$setting]) ? rawurldecode((string) $parts[$setting]) : '';
            }
        } else {
            $value = $connection[$setting] ?? null;
        }

        if (! is_string($value) || trim($value) === '') {
            return null;
        }

        // PostgreSQL's unquoted role/database identifiers are case-insensitive.
        return $setting === 'password' ? $value : strtolower(trim($value));
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
