<?php

namespace App\Services;

use App\Models\Central\AuditEvent;
use Closure;
use Illuminate\Database\Connection;
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

        // Configuration errors must fail without a database connection. Once the
        // connection definitions are safe, verify eligibility in the central registry
        // before connecting to the privileged broker or writing any credentials.
        $centralIdentity = $this->assertTenantIsEligibleForProvisioning($tenant);

        $connection = DB::connection('provisioner');
        $connection->getPdo();
        $brokerIdentity = $connection->selectOne(
            'SELECT current_database() AS database_name, current_user AS role_name, session_user AS session_role_name'
        );

        if ($brokerIdentity === null
            || $centralIdentity['database'] === (string) $brokerIdentity->database_name
            || $centralIdentity['username'] === (string) $brokerIdentity->role_name) {
            // Avoid retaining a connection that resolved to the central identity.
            DB::purge('provisioner');
            throw new RuntimeException(
                'Provisioner connection resolves to the central database or role; refusing provisioning.'
            );
        }

        if ((string) $brokerIdentity->session_role_name !== (string) $brokerIdentity->role_name) {
            DB::purge('provisioner');
            throw new RuntimeException(
                'Provisioner connection must authenticate directly as its effective role; role switching is not allowed.'
            );
        }

        $brokerRole = (string) $brokerIdentity->role_name;
        $brokerPrivileges = $connection->selectOne(
            'SELECT rolcanlogin::int AS can_login, rolsuper::int AS is_superuser,
                    rolcreatedb::int AS can_create_database, rolcreaterole::int AS can_create_role,
                    rolreplication::int AS can_replicate, rolbypassrls::int AS bypasses_rls
             FROM pg_roles WHERE rolname = current_user'
        );

        if ($brokerPrivileges === null
            || (int) $brokerPrivileges->can_login !== 1
            || (int) $brokerPrivileges->is_superuser !== 0
            || (int) $brokerPrivileges->can_create_database !== 1
            || (int) $brokerPrivileges->can_create_role !== 1
            || (int) $brokerPrivileges->can_replicate !== 0
            || (int) $brokerPrivileges->bypasses_rls !== 0) {
            DB::purge('provisioner');
            throw new RuntimeException(
                'Provisioner role must LOGIN, be a non-superuser, have CREATEDB and CREATEROLE, and have neither REPLICATION nor BYPASSRLS; refusing provisioning.'
            );
        }

        $brokerNetwork = $connection->selectOne('SELECT inet_client_addr()::text AS client_address');
        $brokerAuditContext = [
            'broker_database' => (string) $brokerIdentity->database_name,
            'broker_role' => $brokerRole,
            'broker_session_role' => (string) $brokerIdentity->session_role_name,
            'broker_client_address' => $brokerNetwork?->client_address,
        ];

        $brokerIdentifier = $this->identifier($brokerRole);

        // Session-level lock serializes concurrent attempts for this tenant. It is
        // held across CREATE DATABASE, which cannot run inside a transaction.
        $lockKey = $this->advisoryLockKey($tenant);
        $connection->select('SELECT pg_advisory_lock(?)', [$lockKey]);
        $temporaryOwnerMembershipGranted = false;
        $provisioningFailure = null;

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

            $this->runAuditedSql(
                $tenant,
                'role.create.owner',
                'role',
                $ownerRole,
                $brokerAuditContext,
                $connection,
                'CREATE ROLE ' . $this->identifier($ownerRole)
                . ' NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS'
            );
            $this->runAuditedSql(
                $tenant,
                'role.create.runtime',
                'role',
                $runtimeRole,
                $brokerAuditContext,
                $connection,
                'CREATE ROLE ' . $this->identifier($runtimeRole)
                . ' LOGIN PASSWORD ' . $this->literal($runtimePassword)
                . ' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS'
            );
            $this->runAuditedSql(
                $tenant,
                'role.create.migrator',
                'role',
                $migratorRole,
                $brokerAuditContext,
                $connection,
                'CREATE ROLE ' . $this->identifier($migratorRole)
                . ' LOGIN PASSWORD ' . $this->literal($migratorPassword)
                . ' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS'
            );
            // A tenant migrator must be able to SET ROLE to the no-login owner
            // during controlled schema/ACL setup. Default ACLs are also defined for
            // objects created directly by the migrator.
            $this->runAuditedSql(
                $tenant,
                'role.membership.grant.migrator_owner',
                'role_membership',
                $ownerRole . '->' . $migratorRole,
                $brokerAuditContext,
                $connection,
                'GRANT ' . $this->identifier($ownerRole) . ' TO ' . $this->identifier($migratorRole)
            );

            // A non-superuser must be allowed to SET ROLE to the requested owner
            // before it can create a database owned by that role. This membership
            // exists only for CREATE DATABASE and is revoked immediately afterwards.
            $this->runAuditedSql(
                $tenant,
                'role.membership.grant.broker_owner_temporary',
                'role_membership',
                $ownerRole . '->' . $brokerRole,
                $brokerAuditContext,
                $connection,
                'GRANT ' . $this->identifier($ownerRole) . ' TO ' . $brokerIdentifier
            );
            $temporaryOwnerMembershipGranted = true;
            $this->runAuditedSql(
                $tenant,
                'database.create',
                'database',
                $database,
                $brokerAuditContext,
                $connection,
                'CREATE DATABASE ' . $this->identifier($database)
                . ' OWNER ' . $this->identifier($ownerRole)
                . ' TEMPLATE template0 ENCODING \'UTF8\''
            );
            $this->runAuditedSql(
                $tenant,
                'role.membership.revoke.broker_owner_temporary',
                'role_membership',
                $ownerRole . '->' . $brokerRole,
                $brokerAuditContext,
                $connection,
                'REVOKE ' . $this->identifier($ownerRole) . ' FROM ' . $brokerIdentifier
            );
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

            $this->runAuditedSql(
                $tenant,
                'role.switch.owner',
                'role',
                $ownerRole,
                $brokerAuditContext,
                $target,
                'SET ROLE ' . $this->identifier($ownerRole)
            );
            $this->runAuditedSql(
                $tenant,
                'database.revoke_public',
                'database',
                $database,
                $brokerAuditContext,
                $target,
                'REVOKE ALL ON DATABASE ' . $this->identifier($database) . ' FROM PUBLIC'
            );
            $this->runAuditedSql(
                $tenant,
                'database.grant_connect.runtime',
                'database_role',
                $database . '->' . $runtimeRole,
                $brokerAuditContext,
                $target,
                'GRANT CONNECT ON DATABASE ' . $this->identifier($database)
                . ' TO ' . $this->identifier($runtimeRole)
            );
            $this->runAuditedSql(
                $tenant,
                'database.grant_connect.migrator',
                'database_role',
                $database . '->' . $migratorRole,
                $brokerAuditContext,
                $target,
                'GRANT CONNECT ON DATABASE ' . $this->identifier($database)
                . ' TO ' . $this->identifier($migratorRole)
            );

            $this->runAuditedSql(
                $tenant,
                'schema.change_owner',
                'schema',
                'public->' . $ownerRole,
                $brokerAuditContext,
                $target,
                'ALTER SCHEMA public OWNER TO ' . $this->identifier($ownerRole)
            );
            $this->runAuditedSql(
                $tenant,
                'schema.revoke_public',
                'schema',
                'public',
                $brokerAuditContext,
                $target,
                'REVOKE ALL ON SCHEMA public FROM PUBLIC'
            );
            $this->runAuditedSql(
                $tenant,
                'schema.grant_usage.runtime',
                'schema_role',
                'public->' . $runtimeRole,
                $brokerAuditContext,
                $target,
                'GRANT USAGE ON SCHEMA public TO ' . $this->identifier($runtimeRole)
            );
            $this->runAuditedSql(
                $tenant,
                'schema.grant_usage_create.migrator',
                'schema_role',
                'public->' . $migratorRole,
                $brokerAuditContext,
                $target,
                'GRANT USAGE, CREATE ON SCHEMA public TO ' . $this->identifier($migratorRole)
            );

            $this->runAuditedSql(
                $tenant,
                'default_privileges.tables.owner_runtime',
                'default_privileges',
                $ownerRole . '->' . $runtimeRole . ':tables',
                $brokerAuditContext,
                $target,
                'ALTER DEFAULT PRIVILEGES FOR ROLE ' . $this->identifier($ownerRole)
                . ' IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO '
                . $this->identifier($runtimeRole)
            );
            $this->runAuditedSql(
                $tenant,
                'default_privileges.sequences.owner_runtime',
                'default_privileges',
                $ownerRole . '->' . $runtimeRole . ':sequences',
                $brokerAuditContext,
                $target,
                'ALTER DEFAULT PRIVILEGES FOR ROLE ' . $this->identifier($ownerRole)
                . ' IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO '
                . $this->identifier($runtimeRole)
            );

            $this->runAuditedSql(
                $tenant,
                'role.reset_to_migrator',
                'role',
                $migratorRole,
                $brokerAuditContext,
                $target,
                'RESET ROLE'
            );
            $this->runAuditedSql(
                $tenant,
                'default_privileges.tables.migrator_runtime',
                'default_privileges',
                $migratorRole . '->' . $runtimeRole . ':tables',
                $brokerAuditContext,
                $target,
                'ALTER DEFAULT PRIVILEGES FOR ROLE ' . $this->identifier($migratorRole)
                . ' IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO '
                . $this->identifier($runtimeRole)
            );
            $this->runAuditedSql(
                $tenant,
                'default_privileges.sequences.migrator_runtime',
                'default_privileges',
                $migratorRole . '->' . $runtimeRole . ':sequences',
                $brokerAuditContext,
                $target,
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
            $provisioningFailure = $exception;
            // No automatic DROP: a partial failure may already contain data.
            throw new RuntimeException(
                'Tenant provisioning failed; resources were not automatically removed. Manual verification is required.',
                previous: $exception
            );
        } finally {
            $cleanupFailure = null;

            if ($temporaryOwnerMembershipGranted) {
                // Emergency cleanup must run even if the central audit store is unavailable.
                try {
                    $this->appendProvisioningAuditEvent(
                        $tenant,
                        'role.membership.revoke.broker_owner_temporary.attempted',
                        'role_membership',
                        $ownerRole . '->' . $brokerRole,
                        $brokerAuditContext,
                        ['cleanup_path' => true]
                    );
                } catch (Throwable $auditException) {
                    $cleanupFailure = $auditException;
                }

                try {
                    $connection->statement(
                        'REVOKE ' . $this->identifier($ownerRole) . ' FROM ' . $brokerIdentifier
                    );
                    $temporaryOwnerMembershipGranted = false;
                } catch (Throwable $revokeException) {
                    try {
                        $this->appendProvisioningAuditEvent(
                            $tenant,
                            'role.membership.revoke.broker_owner_temporary.failed',
                            'role_membership',
                            $ownerRole . '->' . $brokerRole,
                            $brokerAuditContext,
                            [
                                'cleanup_path' => true,
                                'exception_type' => get_class($revokeException),
                                'sqlstate' => preg_match('/^[0-9A-Z]{5}$/', (string) $revokeException->getCode())
                                    ? (string) $revokeException->getCode()
                                    : null,
                            ]
                        );
                    } catch (Throwable $auditException) {
                        $cleanupFailure ??= $auditException;
                    }
                    $cleanupFailure = new RuntimeException(
                        'CRITICAL: failed to revoke temporary tenant-owner membership from the provisioning broker.',
                        previous: $revokeException
                    );
                }

                if (! $temporaryOwnerMembershipGranted) {
                    try {
                        $this->appendProvisioningAuditEvent(
                            $tenant,
                            'role.membership.revoke.broker_owner_temporary.succeeded',
                            'role_membership',
                            $ownerRole . '->' . $brokerRole,
                            $brokerAuditContext,
                            ['cleanup_path' => true]
                        );
                    } catch (Throwable $auditException) {
                        $cleanupFailure ??= $auditException;
                    }
                }
            }

            DB::purge('provisioning_target');
            try {
                $connection->select('SELECT pg_advisory_unlock(?)', [$lockKey]);
            } catch (Throwable $unlockException) {
                $cleanupFailure ??= new RuntimeException(
                    'Unable to release tenant provisioning advisory lock; inspect the broker connection before retrying.',
                    previous: $unlockException
                );
            }

            if ($cleanupFailure !== null) {
                $cleanupMessage = $temporaryOwnerMembershipGranted
                    ? 'CRITICAL: the broker may retain temporary tenant-owner membership; inspect PostgreSQL role membership before any retry.'
                    : 'Provisioning cleanup or audit verification failed; manual verification is required.';
                if ($provisioningFailure !== null) {
                    $cleanupMessage .= ' A provisioning failure also occurred.';
                }
                throw new RuntimeException($cleanupMessage, previous: $cleanupFailure);
            }
        }
    }

    /**
     * Execute one privilege-sensitive provisioning statement with an append-only audit trail.
     * An attempt record must be stored before ordinary DDL/grant actions proceed. If an
     * action fails, record only the exception class/SQLSTATE, never SQL, passwords or messages.
     */
    private function runAuditedSql(
        string $tenantId,
        string $action,
        string $resourceType,
        string $resourceName,
        array $brokerContext,
        Connection $target,
        string $sql
    ): void {
        $this->appendProvisioningAuditEvent(
            $tenantId,
            $action . '.attempted',
            $resourceType,
            $resourceName,
            $brokerContext
        );

        try {
            $target->statement($sql);
        } catch (Throwable $operationException) {
            try {
                $this->appendProvisioningAuditEvent(
                    $tenantId,
                    $action . '.failed',
                    $resourceType,
                    $resourceName,
                    $brokerContext,
                    [
                        'exception_type' => get_class($operationException),
                        'sqlstate' => preg_match('/^[0-9A-Z]{5}$/', (string) $operationException->getCode())
                            ? (string) $operationException->getCode()
                            : null,
                    ]
                );
            } catch (Throwable $auditException) {
                throw new RuntimeException(
                    'Provisioning action failed and its failure audit could not be recorded; stop and manually verify PostgreSQL resources.',
                    previous: $operationException
                );
            }

            throw $operationException;
        }

        try {
            $this->appendProvisioningAuditEvent(
                $tenantId,
                $action . '.succeeded',
                $resourceType,
                $resourceName,
                $brokerContext
            );
        } catch (Throwable $auditException) {
            throw new RuntimeException(
                'A PostgreSQL provisioning action may have succeeded but its completion audit could not be recorded; stop and manually verify resources.',
                previous: $auditException
            );
        }
    }

    /**
     * Keep the relational tenant_id field NULL so immutable provisioning evidence is
     * independent of the tenant-row lifecycle. The canonical ID remains in scope_id
     * and metadata. Hash resource names and never store credentials or raw SQL.
     *
     * @param array<string, mixed> $brokerContext
     * @param array<string, mixed> $details
     */
    private function appendProvisioningAuditEvent(
        string $tenantId,
        string $action,
        string $resourceType,
        string $resourceName,
        array $brokerContext,
        array $details = []
    ): void {
        AuditEvent::query()->create([
            'actor_user_id' => null,
            'tenant_id' => null,
            'scope_type' => 'tenant_provisioning',
            'scope_id' => $tenantId,
            'action' => 'tenant_provisioning.' . $action,
            'metadata' => array_merge(
                $brokerContext,
                [
                    'tenant_id' => $tenantId,
                    'resource_type' => $resourceType,
                    'resource_name_sha256' => hash('sha256', $resourceType . "\0" . $resourceName),
                ],
                $details
            ),
        ]);
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

    /**
     * Check tenant eligibility in the authoritative central registry and return
     * the identity actually used by the central PDO connection. The broker must
     * later prove it resolves to a different database and role.
     *
     * @return array{database:string,username:string}
     */
    private function assertTenantIsEligibleForProvisioning(string $tenant): array
    {
        $central = DB::connection('central');
        $record = $central
            ->table('tenants')
            ->select('status')
            ->where('id', $tenant)
            ->first();

        if ($record === null) {
            throw new RuntimeException('Tenant must exist in the central registry before provisioning.');
        }

        if (($record->status ?? null) !== 'pending') {
            throw new RuntimeException('Only tenants with pending status may be provisioned.');
        }

        $identity = $central->selectOne(
            'SELECT current_database() AS database_name, current_user AS role_name'
        );

        if ($identity === null) {
            throw new RuntimeException('Unable to verify the effective central PostgreSQL identity.');
        }

        return [
            'database' => (string) $identity->database_name,
            'username' => (string) $identity->role_name,
        ];
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
