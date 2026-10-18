#!/usr/bin/env php
<?php

declare(strict_types=1);

/**
 * One-shot PostgreSQL 17 tenant database broker.
 *
 * Run only in a private, isolated provisioning service. Public web and ordinary
 * queue processes must never receive BROKER_DATABASE_* variables or secret files.
 *
 * provision ULID --runtime-password-file=/run/secrets/runtime-password \
 *                --migrator-password-file=/run/secrets/migrator-password
 * finalize ULID
 *
 * The database name is derived from a canonical ULID. Callers cannot supply SQL
 * identifiers. This program never drops a database or role and never prints secrets.
 */

const BROKER_ROLE = 'berkah_provisioner';
const LOCK_CLASS = 1849831267;

function failClosed(string $reason, string $sqlState = 'N/A'): never
{
    fwrite(STDERR, "FAIL CLOSED: {$reason}; SQLSTATE={$sqlState}; no database/role deletion attempted; secret values redacted.\n");
    exit(1);
}

function ident(string $identifier): string
{
    return '"' . str_replace('"', '""', $identifier) . '"';
}

function literal(PDO $pdo, string $value): string
{
    $quoted = $pdo->quote($value);
    if ($quoted === false) {
        throw new RuntimeException('Literal quoting failed.');
    }

    return $quoted;
}

function pgBool(mixed $value): bool
{
    // PDO_PGSQL can return booleans as PHP bools or PostgreSQL text literals.
    return $value === true || $value === 1 || $value === '1'
        || $value === 't' || $value === 'true';
}

function query(PDO $pdo, string $sql, array $params = []): PDOStatement
{
    $statement = $pdo->prepare($sql);
    $statement->execute($params);

    return $statement;
}

function row(PDO $pdo, string $sql, array $params = []): ?array
{
    $result = query($pdo, $sql, $params)->fetch(PDO::FETCH_ASSOC);

    return $result === false ? null : $result;
}

function verifyTenantId(string $tenantId): void
{
    if (!preg_match('/^[0-9A-HJKMNP-TV-Z]{26}$/', $tenantId)) {
        throw new InvalidArgumentException('Tenant ID must be a canonical 26-character ULID.');
    }
}

function namesFor(string $tenantId): array
{
    $suffix = strtolower($tenantId);

    return [
        'owner' => 'berkah_owner_' . $suffix,
        'runtime' => 'berkah_runtime_' . $suffix,
        'migrator' => 'berkah_migrator_' . $suffix,
        'database' => 'berkahpos_t_' . $suffix,
    ];
}

function roleComment(string $tenantId, string $kind): string
{
    return "berkah-pos:tenant-role:v1;tenant={$tenantId};kind={$kind}";
}

function databaseComment(string $tenantId, string $state): string
{
    return "berkah-pos:tenant-db:v1;tenant={$tenantId};state={$state}";
}

function readSecretFile(?string $path, string $label): string
{
    if ($path === null || $path === '' || !is_file($path) || is_link($path)) {
        throw new InvalidArgumentException("Missing protected {$label} file.");
    }
    $mode = fileperms($path);
    if ($mode === false || ($mode & 0077) !== 0) {
        throw new InvalidArgumentException("The {$label} file must be mode 0600 or stricter.");
    }
    $secret = file_get_contents($path);
    if ($secret === false) {
        throw new InvalidArgumentException("Unable to read {$label} file.");
    }
    $secret = rtrim($secret, "\r\n");
    if (!preg_match('/^[a-fA-F0-9]{64,128}$/', $secret)) {
        throw new InvalidArgumentException("The {$label} must be 64–128 hexadecimal characters.");
    }

    return $secret;
}

/**
 * Produce PostgreSQL's documented SCRAM-SHA-256 verifier format before sending
 * credentials to SQL. PostgreSQL statement logging can contain DDL literals;
 * raw passwords must never be interpolated into CREATE ROLE text.
 * This deliberately restricts accepted credentials to ASCII hex (no SASLprep edge cases).
 */
function scramVerifier(string $password): string
{
    $salt = random_bytes(16);
    $iterations = 4096;
    $saltedPassword = hash_pbkdf2('sha256', $password, $salt, $iterations, 32, true);
    $clientKey = hash_hmac('sha256', 'Client Key', $saltedPassword, true);
    $storedKey = hash('sha256', $clientKey, true);
    $serverKey = hash_hmac('sha256', 'Server Key', $saltedPassword, true);

    return 'SCRAM-SHA-256$' . $iterations . ':'
        . base64_encode($salt) . '$'
        . base64_encode($storedKey) . ':'
        . base64_encode($serverKey);
}

function connectBroker(): PDO
{
    $host = getenv('BROKER_DATABASE_HOST') ?: '';
    $port = getenv('BROKER_DATABASE_PORT') ?: '5432';
    $database = getenv('BROKER_DATABASE_NAME') ?: 'postgres';
    $username = getenv('BROKER_DATABASE_USERNAME') ?: '';
    $password = getenv('BROKER_DATABASE_PASSWORD');

    if ($host === '' || !ctype_digit($port) || (int) $port < 1 || (int) $port > 65535) {
        throw new InvalidArgumentException('Broker endpoint configuration is invalid.');
    }
    if ($database !== 'postgres' || $username !== BROKER_ROLE || $password === false || $password === '') {
        throw new InvalidArgumentException('Broker must use the dedicated role on the maintenance database only.');
    }

    $pdo = new PDO(
        "pgsql:host={$host};port={$port};dbname=postgres;connect_timeout=5",
        $username,
        $password,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ],
    );

    $principal = row(
        $pdo,
        'SELECT current_user AS role_name, current_database() AS database_name,
                rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls, rolinherit
           FROM pg_roles WHERE rolname = current_user'
    );
    if ($principal === null || $principal['role_name'] !== BROKER_ROLE
        || $principal['database_name'] !== 'postgres') {
        throw new RuntimeException('Broker PostgreSQL identity does not match the maintenance-database contract.');
    }
    $identityViolations = [];
    foreach ([
        'rolsuper' => false,
        'rolcreatedb' => true,
        'rolcreaterole' => false,
        'rolreplication' => false,
        'rolbypassrls' => false,
        'rolinherit' => false,
    ] as $attribute => $expected) {
        if (pgBool($principal[$attribute]) !== $expected) {
            $identityViolations[] = $attribute;
        }
    }
    if ($identityViolations !== []) {
        throw new RuntimeException('Broker role catalog attributes violate the contract: ' . implode(',', $identityViolations));
    }

    $forbiddenMembership = row(
        $pdo,
        "SELECT 1
           FROM pg_auth_members m
           JOIN pg_roles member ON member.oid = m.member
           JOIN pg_roles granted ON granted.oid = m.roleid
          WHERE member.rolname = current_user
            AND granted.rolname IN (
              'pg_read_all_data', 'pg_write_all_data', 'pg_read_server_files',
              'pg_write_server_files', 'pg_execute_server_program', 'pg_monitor',
              'pg_signal_backend'
            )
          LIMIT 1"
    );
    if ($forbiddenMembership !== null) {
        throw new RuntimeException('Broker has an unapproved predefined-role membership.');
    }

    return $pdo;
}

function audit(PDO $pdo, string $tenantId, string $action, string $target): void
{
    query($pdo, 'SELECT provisioning.record_event(:tenant_id, :action, :target)', [
        'tenant_id' => $tenantId,
        'action' => $action,
        'target' => $target,
    ]);
}

function withRole(PDO $pdo, string $role, callable $operation): mixed
{
    $pdo->exec('SET ROLE ' . ident($role));
    try {
        return $operation();
    } finally {
        $pdo->exec('RESET ROLE');
    }
}

function acquireTenantLock(PDO $pdo, string $tenantId): void
{
    query($pdo, 'SELECT pg_advisory_lock(:namespace, hashtext(:tenant_id))', [
        'namespace' => LOCK_CLASS,
        'tenant_id' => $tenantId,
    ]);
}

function releaseTenantLock(PDO $pdo, string $tenantId): void
{
    try {
        query($pdo, 'SELECT pg_advisory_unlock(:namespace, hashtext(:tenant_id))', [
            'namespace' => LOCK_CLASS,
            'tenant_id' => $tenantId,
        ]);
    } catch (Throwable) {
        // Closing the database session releases its session-level advisory lock.
    }
}

function getRole(PDO $pdo, string $name): ?array
{
    return row(
        $pdo,
        "SELECT oid, rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole,
                rolreplication, rolbypassrls, rolinherit, rolconnlimit,
                shobj_description(oid, 'pg_authid') AS role_comment
           FROM pg_roles WHERE rolname = :role_name",
        ['role_name' => $name],
    );
}

function verifyRole(PDO $pdo, string $name, string $tenantId, string $kind, bool $login): array
{
    $role = getRole($pdo, $name);
    if ($role === null || $role['role_comment'] !== roleComment($tenantId, $kind)) {
        throw new RuntimeException('Tenant role is absent or its provenance comment is invalid.');
    }

    if (pgBool($role['rolcanlogin']) !== $login
        || pgBool($role['rolsuper']) || pgBool($role['rolcreatedb'])
        || pgBool($role['rolcreaterole']) || pgBool($role['rolreplication'])
        || pgBool($role['rolbypassrls']) || pgBool($role['rolinherit'])) {
        throw new RuntimeException('Tenant role has unexpected PostgreSQL attributes.');
    }

    return $role;
}

function membership(PDO $pdo, string $member, string $granted): ?array
{
    return row(
        $pdo,
        "SELECT m.admin_option, m.inherit_option, m.set_option
           FROM pg_auth_members m
           JOIN pg_roles member ON member.oid = m.member
           JOIN pg_roles granted ON granted.oid = m.roleid
          WHERE member.rolname = :member AND granted.rolname = :granted",
        ['member' => $member, 'granted' => $granted],
    );
}

function databaseMeta(PDO $pdo, string $database): ?array
{
    return row(
        $pdo,
        "SELECT d.datname, pg_get_userbyid(d.datdba) AS owner_name, d.datallowconn,
                shobj_description(d.oid, 'pg_database') AS database_comment
           FROM pg_database d WHERE d.datname = :database_name",
        ['database_name' => $database],
    );
}

/** Database-wide PUBLIC ACL values from actual pg_database.datacl, not role-name pseudo-principals. */
function databaseAcl(PDO $pdo, array $names): array
{
    $acl = row(
        $pdo,
        "SELECT
             COALESCE(bool_or(a.grantee = 0 AND a.privilege_type = 'CONNECT'), FALSE) AS public_connect,
             COALESCE(bool_or(a.grantee = 0 AND a.privilege_type = 'TEMPORARY'), FALSE) AS public_temp,
             has_database_privilege(:broker_name, d.datname, 'CONNECT') AS broker_connect,
             has_database_privilege(:runtime_name, d.datname, 'CONNECT') AS runtime_connect,
             has_database_privilege(:migrator_name, d.datname, 'CONNECT') AS migrator_connect,
             d.datallowconn
           FROM pg_database d
           LEFT JOIN LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a ON TRUE
          WHERE d.datname = :database_name
          GROUP BY d.oid, d.datname, d.datallowconn",
        [
            'broker_name' => BROKER_ROLE,
            'runtime_name' => $names['runtime'],
            'migrator_name' => $names['migrator'],
            'database_name' => $names['database'],
        ],
    );
    if ($acl === null) {
        throw new RuntimeException('Expected database is missing from pg_database.');
    }

    return $acl;
}

function assertProvisioningState(PDO $pdo, string $tenantId, array $names): void
{
    $database = databaseMeta($pdo, $names['database']);
    if (
        $database === null || $database['owner_name'] !== $names['owner']
        || $database['database_comment'] !== databaseComment($tenantId, 'provisioning')
        || !pgBool($database['datallowconn'])
    ) {
        throw new RuntimeException('Tenant database is not in a verified provisioning state.');
    }

    verifyRole($pdo, $names['owner'], $tenantId, 'owner', false);
    verifyRole($pdo, $names['runtime'], $tenantId, 'runtime', true);
    verifyRole($pdo, $names['migrator'], $tenantId, 'migrator', true);

    $acl = databaseAcl($pdo, $names);
    if (
        pgBool($acl['public_connect']) || pgBool($acl['public_temp'])
        || pgBool($acl['broker_connect']) || pgBool($acl['runtime_connect'])
        || !pgBool($acl['migrator_connect'])
    ) {
        throw new RuntimeException('Database ACL does not match the closed provisioning contract.');
    }

    $runtimeMembership = membership($pdo, BROKER_ROLE, $names['runtime']);
    if ($runtimeMembership !== null) {
        throw new RuntimeException('Broker must never be a member of the runtime role.');
    }
    foreach (['owner', 'migrator'] as $kind) {
        $m = membership($pdo, BROKER_ROLE, $names[$kind]);
        if (
            $m === null || pgBool($m['admin_option'])
            || pgBool($m['inherit_option']) || !pgBool($m['set_option'])
        ) {
            throw new RuntimeException('Temporary broker membership is absent or broader than SET TRUE / ADMIN FALSE.');
        }
    }
}

function assertReadyState(PDO $pdo, string $tenantId, array $names): void
{
    $database = databaseMeta($pdo, $names['database']);
    if (
        $database === null || $database['owner_name'] !== $names['owner']
        || $database['database_comment'] !== databaseComment($tenantId, 'ready')
        || !pgBool($database['datallowconn'])
    ) {
        throw new RuntimeException('Tenant database is not in a verified ready state.');
    }

    verifyRole($pdo, $names['owner'], $tenantId, 'owner', false);
    verifyRole($pdo, $names['runtime'], $tenantId, 'runtime', true);
    verifyRole($pdo, $names['migrator'], $tenantId, 'migrator', false);

    $acl = databaseAcl($pdo, $names);
    if (
        pgBool($acl['public_connect']) || pgBool($acl['public_temp'])
        || pgBool($acl['broker_connect']) || !pgBool($acl['runtime_connect'])
        || pgBool($acl['migrator_connect'])
    ) {
        throw new RuntimeException('Ready database ACL does not match the tenant boundary contract.');
    }

    foreach (['owner', 'runtime', 'migrator'] as $kind) {
        if (membership($pdo, BROKER_ROLE, $names[$kind]) !== null) {
            throw new RuntimeException('Ready-state broker membership cleanup is incomplete.');
        }
    }
}

function prepareDatabase(PDO $pdo, string $tenantId, array $names): void
{
    $db = ident($names['database']);
    $owner = ident($names['owner']);
    $runtime = ident($names['runtime']);
    $migrator = ident($names['migrator']);

    $existing = databaseMeta($pdo, $names['database']);
    if ($existing === null) {
        // The durable intent was committed by ensure_tenant_roles before this
        // non-transactional CREATE DATABASE. The new database accepts no connections.
        $pdo->exec(
            'CREATE DATABASE ' . $db . ' OWNER ' . $owner . ' ALLOW_CONNECTIONS FALSE'
        );
        audit($pdo, $tenantId, 'database_created', $names['database']);
    } elseif (
        $existing['owner_name'] !== $names['owner']
        || !(
            $existing['database_comment'] === databaseComment($tenantId, 'provisioning')
            || ($existing['database_comment'] === null && !pgBool($existing['datallowconn']))
        )
    ) {
        audit($pdo, $tenantId, 'collision_rejected', $names['database']);
        throw new RuntimeException('Existing database is not the exact marked tenant database or recoverable closed intent; refusing to adopt it.');
    }

    // ACLs, marker, ALLOW_CONNECTIONS, and the durable intent state commit together.
    // If the process dies after CREATE DATABASE but before this transaction, the
    // intent stays database_intent and the unmarked database stays closed.
    $pdo->beginTransaction();
    try {
        $pdo->exec('SET ROLE ' . $owner);
        $pdo->exec('REVOKE CONNECT, TEMPORARY ON DATABASE ' . $db . ' FROM PUBLIC');
        $pdo->exec('REVOKE CONNECT ON DATABASE ' . $db . ' FROM ' . ident(BROKER_ROLE));
        $pdo->exec('REVOKE CONNECT ON DATABASE ' . $db . ' FROM ' . $runtime);
        $pdo->exec('GRANT CONNECT ON DATABASE ' . $db . ' TO ' . $migrator);
        // Broker gets temporary CONNECT only while configuring the isolated DB.
        $pdo->exec('GRANT CONNECT ON DATABASE ' . $db . ' TO ' . ident(BROKER_ROLE));
        $pdo->exec('COMMENT ON DATABASE ' . $db . ' IS ' . literal($pdo, databaseComment($tenantId, 'provisioning')));
        $pdo->exec('ALTER DATABASE ' . $db . ' ALLOW_CONNECTIONS TRUE');
        $pdo->exec('RESET ROLE');
        query($pdo, 'SELECT provisioning.mark_provisioning_intent(:tenant_id)', [
            'tenant_id' => $tenantId,
        ]);
        $pdo->commit();
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        try {
            $pdo->exec('RESET ROLE');
        } catch (Throwable) {
        }
        throw $error;
    }
}

function configureTenantSchema(PDO $control, string $tenantId, array $names): void
{
    $host = getenv('BROKER_DATABASE_HOST') ?: '';
    $port = getenv('BROKER_DATABASE_PORT') ?: '5432';
    $password = getenv('BROKER_DATABASE_PASSWORD');
    if ($host === '' || $password === false || $password === '') {
        throw new InvalidArgumentException('Broker tenant connection configuration is missing.');
    }

    $tenant = new PDO(
        "pgsql:host={$host};port={$port};dbname={$names['database']};connect_timeout=5",
        BROKER_ROLE,
        $password,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ],
    );

    try {
        withRole($tenant, $names['owner'], function () use ($tenant, $names): void {
            $tenant->exec('REVOKE ALL ON SCHEMA public FROM PUBLIC');
            $tenant->exec('GRANT USAGE ON SCHEMA public TO ' . ident($names['runtime']));
            $tenant->exec('GRANT USAGE, CREATE ON SCHEMA public TO ' . ident($names['migrator']));
        });

        withRole($tenant, $names['migrator'], function () use ($tenant, $names): void {
            $tenant->exec(
                'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO '
                . ident($names['runtime'])
            );
            $tenant->exec(
                'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO '
                . ident($names['runtime'])
            );
            $tenant->exec('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC');
            $tenant->exec('REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC');
            $tenant->exec(
                'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO '
                . ident($names['runtime'])
            );
            $tenant->exec(
                'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO '
                . ident($names['runtime'])
            );
        });
    } finally {
        $tenant = null;
    }

    withRole($control, $names['owner'], function () use ($control, $tenantId, $names): void {
        $db = ident($names['database']);
        $control->exec('REVOKE CONNECT ON DATABASE ' . $db . ' FROM ' . ident(BROKER_ROLE));
        $control->exec('REVOKE CONNECT, TEMPORARY ON DATABASE ' . $db . ' FROM PUBLIC');
        $control->exec('REVOKE CONNECT ON DATABASE ' . $db . ' FROM ' . ident($names['runtime']));
        $control->exec('GRANT CONNECT ON DATABASE ' . $db . ' TO ' . ident($names['migrator']));
        $control->exec('COMMENT ON DATABASE ' . $db . ' IS ' . literal($control, databaseComment($tenantId, 'provisioning')));
        $control->exec('ALTER DATABASE ' . $db . ' ALLOW_CONNECTIONS TRUE');
    });

    audit($control, $tenantId, 'schema_acl_hardened', 'schema:public');
    audit($control, $tenantId, 'database_acl_hardened', $names['database']);
}

function provision(PDO $pdo, string $tenantId, string $runtimePassword, string $migratorPassword): array
{
    $names = namesFor($tenantId);
    $state = row(
        $pdo,
        'SELECT provisioning.ensure_tenant_roles(:tenant_id, :runtime_password, :migrator_password) AS state',
        [
            'tenant_id' => $tenantId,
            'runtime_password' => scramVerifier($runtimePassword),
            'migrator_password' => scramVerifier($migratorPassword),
        ],
    );
    if ($state === null) {
        throw new RuntimeException('Role broker returned no state.');
    }

    if ($state['state'] === 'ready') {
        assertReadyState($pdo, $tenantId, $names);
        return ['result' => 'already_ready', 'tenant_id' => $tenantId, 'database' => $names['database']];
    }

    $prior = databaseMeta($pdo, $names['database']);
    prepareDatabase($pdo, $tenantId, $names);
    configureTenantSchema($pdo, $tenantId, $names);
    assertProvisioningState($pdo, $tenantId, $names);
    if ($prior !== null) {
        audit($pdo, $tenantId, 'provision_resumed', 'state:provisioning');
    }

    return [
        'result' => $prior === null ? 'provisioning' : 'resumed',
        'tenant_id' => $tenantId,
        'database' => $names['database'],
        'owner_role' => $names['owner'],
        'runtime_role' => $names['runtime'],
        'migrator_role' => $names['migrator'],
        'secret_values_emitted' => false,
    ];
}

function connectTemporaryTenant(PDO $control, string $tenantId, array $names): PDO
{
    withRole($control, $names['owner'], function () use ($control, $names): void {
        $db = ident($names['database']);
        $control->exec('GRANT CONNECT ON DATABASE ' . $db . ' TO ' . ident(BROKER_ROLE));
        $control->exec('GRANT CONNECT ON DATABASE ' . $db . ' TO ' . ident($names['migrator']));
    });

    $host = getenv('BROKER_DATABASE_HOST') ?: '';
    $port = getenv('BROKER_DATABASE_PORT') ?: '5432';
    $password = getenv('BROKER_DATABASE_PASSWORD');
    if ($host === '' || $password === false || $password === '') {
        throw new InvalidArgumentException('Broker tenant connection settings are missing.');
    }

    return new PDO(
        "pgsql:host={$host};port={$port};dbname={$names['database']};connect_timeout=5",
        BROKER_ROLE,
        $password,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ],
    );
}

function finalizeTenant(PDO $pdo, string $tenantId): void
{
    $names = namesFor($tenantId);
    $database = databaseMeta($pdo, $names['database']);
    if ($database === null || $database['owner_name'] !== $names['owner']) {
        throw new RuntimeException('Cannot finalize an absent or unverified tenant database.');
    }
    if ($database['database_comment'] === databaseComment($tenantId, 'ready')) {
        assertReadyState($pdo, $tenantId, $names);
        return;
    }
    if ($database['database_comment'] !== databaseComment($tenantId, 'provisioning')) {
        throw new RuntimeException('Cannot finalize an unmarked or mismatched tenant database.');
    }

    verifyRole($pdo, $names['owner'], $tenantId, 'owner', false);
    verifyRole($pdo, $names['runtime'], $tenantId, 'runtime', true);
    verifyRole($pdo, $names['migrator'], $tenantId, 'migrator', true);

    $tenant = connectTemporaryTenant($pdo, $tenantId, $names);
    try {
        withRole($tenant, $names['migrator'], function () use ($tenant): void {
            $required = ['migrations', 'products', 'sales', 'sync_receipts'];
            $statement = $tenant->query(
                "SELECT table_name FROM information_schema.tables
                  WHERE table_schema = 'public' AND table_type = 'BASE TABLE'"
            );
            $actual = array_column($statement->fetchAll(PDO::FETCH_ASSOC), 'table_name');
            $missing = array_diff($required, $actual);
            if ($missing !== []) {
                throw new RuntimeException('Tenant migration smoke gate is incomplete.');
            }
            $tenant->exec(
                'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO '
                . ident($names['runtime'])
            );
            $tenant->exec(
                'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO '
                . ident($names['runtime'])
            );
            $tenant->exec('REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC');
        });
    } finally {
        $tenant = null;
    }

    // Database ACL transition, ready marker, migrator lockout and membership
    // revocation are a single transaction. If any step fails, all are rolled back.
    $pdo->beginTransaction();
    try {
        $pdo->exec('SET ROLE ' . ident($names['owner']));
        $db = ident($names['database']);
        $pdo->exec('REVOKE CONNECT ON DATABASE ' . $db . ' FROM ' . ident(BROKER_ROLE));
        $pdo->exec('REVOKE CONNECT ON DATABASE ' . $db . ' FROM ' . ident($names['migrator']));
        $pdo->exec('REVOKE CONNECT, TEMPORARY ON DATABASE ' . $db . ' FROM PUBLIC');
        $pdo->exec('GRANT CONNECT ON DATABASE ' . $db . ' TO ' . ident($names['runtime']));
        $pdo->exec('COMMENT ON DATABASE ' . $db . ' IS ' . literal($pdo, databaseComment($tenantId, 'ready')));
        $pdo->exec('ALTER DATABASE ' . $db . ' ALLOW_CONNECTIONS TRUE');
        $result = row($pdo, 'SELECT provisioning.finalize_tenant_roles(:tenant_id) AS state', [
            'tenant_id' => $tenantId,
        ]);
        if ($result === null || $result['state'] !== 'ready') {
            throw new RuntimeException('Tenant finalization function did not return ready.');
        }
        $pdo->exec('RESET ROLE');
        $pdo->commit();
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        try {
            $pdo->exec('RESET ROLE');
        } catch (Throwable) {
        }
        throw $error;
    }

    audit($pdo, $tenantId, 'database_acl_hardened', $names['database']);
    assertReadyState($pdo, $tenantId, $names);
}

function main(array $argv): int
{
    if (count($argv) < 3) {
        throw new InvalidArgumentException('Expected command and canonical tenant ID.');
    }

    $command = $argv[1];
    $tenantId = $argv[2];
    verifyTenantId($tenantId);
    if (!in_array($command, ['provision', 'finalize'], true)) {
        throw new InvalidArgumentException('Only provision and finalize commands are supported.');
    }

    $options = [];
    foreach (array_slice($argv, 3) as $argument) {
        if (!preg_match('/^--([a-z-]+)=(.+)$/', $argument, $matches)) {
            throw new InvalidArgumentException('Invalid command option.');
        }
        if (isset($options[$matches[1]])) {
            throw new InvalidArgumentException('Duplicate command option.');
        }
        $options[$matches[1]] = $matches[2];
    }

    $runtimePassword = null;
    $migratorPassword = null;
    if ($command === 'provision') {
        if (array_diff(array_keys($options), ['runtime-password-file', 'migrator-password-file']) !== []) {
            throw new InvalidArgumentException('Unsupported provisioning option.');
        }
        $runtimePassword = readSecretFile($options['runtime-password-file'] ?? null, 'runtime password');
        $migratorPassword = readSecretFile($options['migrator-password-file'] ?? null, 'migrator password');
    } elseif ($options !== []) {
        throw new InvalidArgumentException('Finalize accepts no extra options.');
    }

    $pdo = connectBroker();
    acquireTenantLock($pdo, $tenantId);
    try {
        if ($command === 'provision') {
            $result = provision($pdo, $tenantId, $runtimePassword, $migratorPassword);
        } else {
            finalizeTenant($pdo, $tenantId);
            $result = ['result' => 'ready', 'tenant_id' => $tenantId, 'database' => namesFor($tenantId)['database']];
        }
        echo json_encode($result, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES) . PHP_EOL;
        return 0;
    } finally {
        releaseTenantLock($pdo, $tenantId);
    }
}

try {
    exit(main($argv));
} catch (Throwable $error) {
    $sqlState = $error instanceof PDOException && is_array($error->errorInfo)
        ? (string) ($error->errorInfo[0] ?? 'N/A')
        : 'N/A';

    // PDO exceptions can contain SQL or server diagnostic details, so never echo them.
    // Application validation/state errors are static messages authored above; redact
    // any long token/verifier pattern as a defence in depth before emitting the reason.
    $reason = 'unexpected error class ' . (new ReflectionClass($error))->getShortName();
    if ($error instanceof InvalidArgumentException || $error instanceof RuntimeException) {
        $reason = preg_replace('/[\\x00-\\x1F\\x7F]/', ' ', $error->getMessage()) ?? 'request rejected';
        $reason = preg_replace('/SCRAM-SHA-256\\$[^[:space:]]+/', '[SCRAM_VERIFIER_REDACTED]', $reason) ?? 'request rejected';
        $reason = preg_replace('/[A-Fa-f0-9]{64,}/', '[LONG_TOKEN_REDACTED]', $reason) ?? 'request rejected';
    }
    failClosed($reason, $sqlState);
}
