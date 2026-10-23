<?php

namespace Tests\Feature;

use App\Services\PostgresTenantProvisioner;
use App\Services\TenantRuntimeCredentialResolver;
use Illuminate\Database\Connection;
use Illuminate\Database\QueryException;
use Illuminate\Http\Client\Request as HttpRequest;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use PDOException;
use Tests\TestCase;
use Throwable;

class PostgresTenantProvisionerIntegrationTest extends TestCase
{
    private bool $integrationEnabled = false;

    /** @var list<string> */
    private array $tenantIds = [];

    /** @var array<string, string> */
    private array $credentials = [];

    protected function setUp(): void
    {
        parent::setUp();

        $this->integrationEnabled = getenv('RUN_POSTGRES_TENANT_PROVISIONER_INTEGRATION') === '1';
        if (! $this->integrationEnabled) {
            $this->markTestSkipped('Requires the isolated PostgreSQL 17 provisioning integration job.');
        }

        $this->assertSame('pgsql', config('database.connections.central.driver'));
        $this->assertSame('pgsql', config('database.connections.provisioner.driver'));

        $this->tenantIds = [
            strtoupper((string) Str::ulid()),
            strtoupper((string) Str::ulid()),
        ];
        $this->assertNotSame($this->tenantIds[0], $this->tenantIds[1]);
    }

    protected function tearDown(): void
    {
        if ($this->integrationEnabled) {
            $central = DB::connection('central');
            $broker = DB::connection('provisioner');
            $brokerRole = (string) $broker->scalar('SELECT current_user');

            foreach ($this->tenantIds as $tenantId) {
                $database = 'berkahpos_t_' . strtolower($tenantId);
                $suffix = strtolower($tenantId);
                $ownerRole = 'berkah_t_' . $suffix . '_owner';
                $runtimeRole = 'berkah_t_' . $suffix . '_runtime';
                $migratorRole = 'berkah_t_' . $suffix . '_migrator';

                foreach ([
                    'provisioner_runtime_' . $suffix,
                    'provisioner_migrator_' . $suffix,
                    'provisioner_runtime_cross_tenant',
                    'provisioner_runtime_reverse_cross_tenant',
                    'provisioner_runtime_central_denied',
                    'provisioning_target',
                ] as $connectionName) {
                    DB::purge($connectionName);
                }

                try {
                    $central->statement('DROP DATABASE IF EXISTS "' . $database . '" WITH (FORCE)');
                } catch (Throwable $exception) {
                    fwrite(STDERR, "Disposable PG17 database cleanup warning: " . $exception->getMessage() . PHP_EOL);
                }

                try {
                    $existingRoles = $central->select(
                        'SELECT rolname FROM pg_roles WHERE rolname IN (?, ?, ?)',
                        [$ownerRole, $runtimeRole, $migratorRole]
                    );
                    $existingNames = array_map(static fn (object $row): string => $row->rolname, $existingRoles);

                    if (in_array($ownerRole, $existingNames, true) && in_array($migratorRole, $existingNames, true)) {
                        $membership = $central->selectOne(
                            'SELECT 1 FROM pg_auth_members m
                             JOIN pg_roles granted ON granted.oid = m.roleid
                             JOIN pg_roles member ON member.oid = m.member
                             JOIN pg_roles grantor ON grantor.oid = m.grantor
                             WHERE granted.rolname = ? AND member.rolname = ? AND grantor.rolname = ?',
                            [$ownerRole, $migratorRole, $brokerRole]
                        );
                        if ($membership !== null) {
                            $central->statement(
                                'REVOKE "' . $ownerRole . '" FROM "' . $migratorRole
                                . '" GRANTED BY "' . $brokerRole . '"'
                            );
                        }
                    }
                    if (in_array($ownerRole, $existingNames, true)) {
                        $membership = $central->selectOne(
                            'SELECT 1 FROM pg_auth_members m
                             JOIN pg_roles granted ON granted.oid = m.roleid
                             JOIN pg_roles member ON member.oid = m.member
                             JOIN pg_roles grantor ON grantor.oid = m.grantor
                             WHERE granted.rolname = ? AND member.rolname = ? AND grantor.rolname = ?',
                            [$ownerRole, $brokerRole, $brokerRole]
                        );
                        if ($membership !== null) {
                            $central->statement(
                                'REVOKE "' . $ownerRole . '" FROM "' . $brokerRole
                                . '" GRANTED BY "' . $brokerRole . '"'
                            );
                        }
                    }

                    foreach ([$migratorRole, $runtimeRole, $ownerRole] as $role) {
                        $central->statement('DROP ROLE IF EXISTS "' . $role . '"');
                    }
                } catch (Throwable $exception) {
                    // The workflow creates a fresh disposable PostgreSQL service per run.
                    // Preserve the original test failure; CI destroys the service after the job.
                    fwrite(STDERR, "Disposable PG17 role cleanup warning: " . $exception->getMessage() . PHP_EOL);
                }

                try {
                    // The command acceptance test creates a central tenant and registry row.
                    $central->table('tenant_database_registry')->where('tenant_id', $tenantId)->delete();
                    $central->table('tenants')->where('id', $tenantId)->delete();
                } catch (Throwable $exception) {
                    fwrite(STDERR, "Disposable PG17 central-row cleanup warning: " . $exception->getMessage() . PHP_EOL);
                }
            }
        }

        parent::tearDown();
    }

    public function test_retry_after_success_fails_closed_without_changing_existing_tenant_data(): void
    {
        $tenantId = $this->tenantIds[0];
        $storedPasswords = [];
        $provisioner = new PostgresTenantProvisioner();

        $tenant = $provisioner->provision(
            $tenantId,
            function (string $key, string $password) use (&$storedPasswords): string {
                $storedPasswords[$key] = $password;

                return 'ci-secret-ref://' . $key;
            },
            function (string $key) use (&$storedPasswords): void {
                unset($storedPasswords[$key]);
            }
        );

        $this->assertCount(2, $storedPasswords);
        $temporaryConnection = (array) config('database.connections.provisioning_target', []);
        $this->assertSame('__tenant_not_configured__', $temporaryConnection['database'] ?? null);
        $this->assertSame('', $temporaryConnection['username'] ?? null);
        $this->assertSame('', $temporaryConnection['password'] ?? null, 'The migrator password must not remain in Laravel config.');
        $this->assertNull($temporaryConnection['url'] ?? null);
        $suffix = strtolower($tenantId);
        $table = 'provisioner_retry_guard_' . strtolower(substr($tenantId, 0, 8));
        $migrator = $this->connectionAs(
            'provisioner_migrator_' . $suffix,
            $tenant['database'],
            $tenant['migrator_role'],
            $storedPasswords['tenant/' . $tenantId . '/migrator']
        );
        $migrator->statement(
            'CREATE TABLE public."' . $table . '" (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)'
        );
        $migrator->insert(
            'INSERT INTO public."' . $table . '" (id, payload) VALUES (?, ?)',
            [1, 'preserve-existing-tenant-data']
        );

        $retryCredentialCalls = 0;
        try {
            $provisioner->provision(
                $tenantId,
                function (string $key, string $password) use (&$retryCredentialCalls): string {
                    $retryCredentialCalls++;

                    return 'ci-secret-ref://' . $key;
                },
                static function (string $key): void {}
            );
            $this->fail('A retry without verified provisioning ownership must fail closed.');
        } catch (\RuntimeException $exception) {
            $this->assertSame(
                'Tenant provisioning failed; resources were not automatically removed. Manual verification is required.',
                $exception->getMessage()
            );
            $this->assertNotNull($exception->getPrevious());
            $this->assertSame(
                'Tenant database or role already exists; refusing to adopt or modify unverified resources.',
                $exception->getPrevious()->getMessage()
            );
        }

        $this->assertSame(0, $retryCredentialCalls, 'A refused retry must not write or rotate credentials.');
        $central = DB::connection('central');
        $this->assertSame(
            1,
            (int) $central->scalar(
                'SELECT COUNT(*) FROM pg_database WHERE datname = ?',
                [$tenant['database']]
            )
        );
        $this->assertSame(
            3,
            (int) $central->scalar(
                'SELECT COUNT(*) FROM pg_roles WHERE rolname IN (?, ?, ?)',
                [$tenant['owner_role'], $tenant['runtime_role'], $tenant['migrator_role']]
            )
        );
        $this->assertSame(
            $tenant['owner_role'],
            $central->scalar(
                'SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = ?',
                [$tenant['database']]
            )
        );

        $runtime = $this->connectionAs(
            'provisioner_runtime_' . $suffix,
            $tenant['database'],
            $tenant['runtime_role'],
            $storedPasswords['tenant/' . $tenantId . '/runtime']
        );
        $this->assertSame(
            'preserve-existing-tenant-data',
            $runtime->scalar('SELECT payload FROM public."' . $table . '" WHERE id = 1')
        );
        $this->assertSame(1, (int) $runtime->scalar('SELECT COUNT(*) FROM public."' . $table . '"'));
    }

    public function test_concurrent_provisioning_serializes_competing_attempts_for_the_same_tenant(): void
    {
        if (! function_exists('proc_open')) {
            $this->markTestSkipped('The concurrency acceptance test requires PHP proc_open in isolated CI.');
        }

        $tenantId = $this->tenantIds[0];
        $barrierDir = sys_get_temp_dir() . '/berkahpos-provision-concurrency-' . bin2hex(random_bytes(8));
        $this->assertTrue(mkdir($barrierDir, 0700), 'Could not create the disposable concurrency barrier directory.');

        /** @var list<array{process: resource|null, pipes: array<int, resource>, slot:string}> $processes */
        $processes = [];
        $results = [];
        $bothWorkersReady = false;

        try {
            for ($slot = 0; $slot < 2; $slot++) {
                $descriptors = [
                    0 => ['pipe', 'r'],
                    1 => ['pipe', 'w'],
                    2 => ['pipe', 'w'],
                ];
                $pipes = [];
                $process = proc_open(
                    [
                        PHP_BINARY,
                        base_path('tests/Fixtures/provision_tenant_process.php'),
                        $tenantId,
                        $barrierDir,
                        (string) $slot,
                        '750',
                    ],
                    $descriptors,
                    $pipes,
                    base_path()
                );

                if (! is_resource($process)) {
                    throw new \RuntimeException('Unable to start a disposable tenant provisioning worker.');
                }

                fclose($pipes[0]);
                $processes[] = ['process' => $process, 'pipes' => $pipes, 'slot' => (string) $slot];
            }

            $deadline = microtime(true) + 20;
            while (microtime(true) < $deadline) {
                if (is_file($barrierDir . '/0.ready') && is_file($barrierDir . '/1.ready')) {
                    $bothWorkersReady = true;
                    break;
                }
                usleep(10_000);
            }

            // Release both bootstrapped workers together so the database lock is
            // contended while the winner is deliberately delayed in secret storage.
            file_put_contents($barrierDir . '/release', 'go', LOCK_EX);

            foreach ($processes as $index => $worker) {
                $stdout = stream_get_contents($worker['pipes'][1]);
                $stderr = stream_get_contents($worker['pipes'][2]);
                fclose($worker['pipes'][1]);
                fclose($worker['pipes'][2]);

                $exitCode = proc_close($worker['process']);
                $processes[$index]['process'] = null;

                $payloadLine = null;
                foreach (preg_split('/\R/', (string) $stdout) ?: [] as $line) {
                    if (str_starts_with($line, 'PROVISION_RESULT:')) {
                        $payloadLine = substr($line, strlen('PROVISION_RESULT:'));
                    }
                }

                if ($payloadLine === null) {
                    throw new \RuntimeException(
                        'Concurrency worker returned no result marker. stdout='
                        . substr((string) $stdout, 0, 1000)
                        . '; stderr=' . substr((string) $stderr, 0, 1000)
                    );
                }

                $results[] = [
                    'payload' => json_decode($payloadLine, true, 512, JSON_THROW_ON_ERROR),
                    'exit_code' => $exitCode,
                    'stderr' => (string) $stderr,
                ];
            }
        } finally {
            // Ensure a failed assertion or process startup does not strand a worker.
            file_put_contents($barrierDir . '/release', 'go', LOCK_EX);
            foreach ($processes as $worker) {
                if (is_resource($worker['process'])) {
                    proc_terminate($worker['process']);
                    foreach ($worker['pipes'] as $pipe) {
                        if (is_resource($pipe)) {
                            fclose($pipe);
                        }
                    }
                    proc_close($worker['process']);
                }
            }
            foreach (glob($barrierDir . '/*') ?: [] as $path) {
                if (is_file($path)) {
                    unlink($path);
                }
            }
            rmdir($barrierDir);
        }

        $this->assertTrue($bothWorkersReady, 'Both subprocesses must be ready before the race is released.');
        $this->assertCount(2, $results);

        $successes = array_values(array_filter(
            $results,
            static fn (array $result): bool => ($result['payload']['ok'] ?? false) === true
        ));
        $failures = array_values(array_filter(
            $results,
            static fn (array $result): bool => ($result['payload']['ok'] ?? true) === false
        ));

        $this->assertCount(1, $successes, 'Exactly one concurrent provisioning attempt must create the tenant resources.');
        $this->assertCount(1, $failures, 'The competing attempt must fail closed after the lock is released.');
        $this->assertSame(0, $successes[0]['exit_code']);
        $this->assertSame(1, $failures[0]['exit_code']);
        $this->assertSame(2, $successes[0]['payload']['store_calls']);
        $this->assertSame(0, $failures[0]['payload']['store_calls']);
        $this->assertSame(
            'Tenant database or role already exists; refusing to adopt or modify unverified resources.',
            $failures[0]['payload']['previous'] ?? null
        );

        $database = 'berkahpos_t_' . strtolower($tenantId);
        $suffix = strtolower($tenantId);
        $ownerRole = 'berkah_t_' . $suffix . '_owner';
        $runtimeRole = 'berkah_t_' . $suffix . '_runtime';
        $migratorRole = 'berkah_t_' . $suffix . '_migrator';
        $central = DB::connection('central');

        $this->assertSame(
            1,
            (int) $central->scalar('SELECT COUNT(*) FROM pg_database WHERE datname = ?', [$database])
        );
        $this->assertSame(
            3,
            (int) $central->scalar(
                'SELECT COUNT(*) FROM pg_roles WHERE rolname IN (?, ?, ?)',
                [$ownerRole, $runtimeRole, $migratorRole]
            )
        );
        $this->assertSame(
            $ownerRole,
            $central->scalar('SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = ?', [$database])
        );
    }

    public function test_existing_tenant_database_or_role_is_never_adopted_and_credentials_are_not_stored(): void
    {
        $broker = DB::connection('provisioner');
        $databaseTenant = $this->tenantIds[0];
        $roleTenant = $this->tenantIds[1];
        $databaseName = 'berkahpos_t_' . strtolower($databaseTenant);
        $preexistingOwnerRole = 'berkah_t_' . strtolower($roleTenant) . '_owner';

        // Simulate unregistered resources left by an earlier or external process.
        $broker->statement('CREATE DATABASE "' . $databaseName . '" TEMPLATE template0');
        $broker->statement(
            'CREATE ROLE "' . $preexistingOwnerRole . '" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS'
        );

        $credentialStoreCalls = 0;
        foreach ([$databaseTenant, $roleTenant] as $tenantId) {
            try {
                (new PostgresTenantProvisioner())->provision(
                    $tenantId,
                    function (string $key, string $password) use (&$credentialStoreCalls): string {
                        $credentialStoreCalls++;

                        return 'ci-secret-ref://' . $key;
                    },
                    static function (string $key): void {}
                );
                $this->fail('Provisioning must refuse to adopt any existing tenant database or role.');
            } catch (\RuntimeException $exception) {
                $this->assertSame(
                    'Tenant provisioning failed; resources were not automatically removed. Manual verification is required.',
                    $exception->getMessage()
                );
                $this->assertNotNull($exception->getPrevious());
                $this->assertSame(
                    'Tenant database or role already exists; refusing to adopt or modify unverified resources.',
                    $exception->getPrevious()->getMessage()
                );
            }
        }

        $this->assertSame(0, $credentialStoreCalls, 'Existing resources must be detected before credential storage.');
        $central = DB::connection('central');
        $this->assertSame(
            1,
            (int) $central->scalar('SELECT COUNT(*) FROM pg_database WHERE datname = ?', [$databaseName])
        );
        $this->assertSame(
            1,
            (int) $central->scalar('SELECT COUNT(*) FROM pg_roles WHERE rolname = ?', [$preexistingOwnerRole])
        );
        $this->assertNoTenantResources($databaseTenant, false, true);
        $this->assertNoTenantResources($roleTenant, true, false);
    }

    public function test_secret_store_failure_creates_no_tenant_database_or_roles(): void
    {
        $tenantId = $this->tenantIds[0];
        $storeCalls = 0;

        try {
            (new PostgresTenantProvisioner())->provision(
                $tenantId,
                function (string $key, string $password) use (&$storeCalls): string {
                    $storeCalls++;
                    throw new \RuntimeException('simulated secret-store outage');
                },
                static function (string $key): void {}
            );
            $this->fail('Provisioning must stop if the secret store fails.');
        } catch (\RuntimeException $exception) {
            $this->assertSame(
                'Tenant provisioning failed; resources were not automatically removed. Manual verification is required.',
                $exception->getMessage()
            );
            $this->assertNotNull($exception->getPrevious());
            $this->assertSame('simulated secret-store outage', $exception->getPrevious()->getMessage());
        }

        $this->assertSame(1, $storeCalls, 'The first failed secret write must stop provisioning immediately.');
        $this->assertNoTenantResources($tenantId);
    }

    public function test_second_secret_write_failure_compensates_both_stable_keys_before_database_creation(): void
    {
        $tenantId = $this->tenantIds[0];
        $secrets = [];
        $storeCalls = [];
        $deleteCalls = [];

        try {
            (new PostgresTenantProvisioner())->provision(
                $tenantId,
                function (string $key, string $password) use (&$secrets, &$storeCalls): string {
                    $storeCalls[] = $key;
                    if (str_ends_with($key, '/migrator')) {
                        // Simulate a failed remote write after the runtime secret was stored.
                        throw new \RuntimeException('simulated migrator secret-store outage');
                    }

                    $secrets[$key] = $password;

                    return 'ci-secret-ref://' . $key;
                },
                function (string $key) use (&$secrets, &$deleteCalls): void {
                    $deleteCalls[] = $key;
                    unset($secrets[$key]);
                }
            );
            $this->fail('Provisioning must stop when the second secret write fails.');
        } catch (\RuntimeException $exception) {
            $this->assertSame(
                'Tenant provisioning failed; resources were not automatically removed. Manual verification is required.',
                $exception->getMessage()
            );
            $this->assertNotNull($exception->getPrevious());
            $this->assertSame('simulated migrator secret-store outage', $exception->getPrevious()->getMessage());
        }

        $runtimeKey = 'tenant/' . $tenantId . '/runtime';
        $migratorKey = 'tenant/' . $tenantId . '/migrator';
        $this->assertSame([$runtimeKey, $migratorKey], $storeCalls);
        $this->assertSame([$runtimeKey, $migratorKey], $deleteCalls);
        $this->assertSame([], $secrets, 'No orphaned credential should remain after successful compensation.');
        $this->assertNoTenantResources($tenantId);
    }

    public function test_failed_secret_compensation_surfaces_manual_verification_and_attempts_both_deletes(): void
    {
        $tenantId = $this->tenantIds[0];
        $runtimeKey = 'tenant/' . $tenantId . '/runtime';
        $migratorKey = 'tenant/' . $tenantId . '/migrator';
        $secrets = [];
        $storeCalls = [];
        $deleteCalls = [];

        try {
            (new PostgresTenantProvisioner())->provision(
                $tenantId,
                function (string $key, string $password) use (&$secrets, &$storeCalls, $migratorKey): string {
                    $storeCalls[] = $key;
                    if ($key === $migratorKey) {
                        // Simulate a remote write failure after runtime was persisted.
                        throw new \RuntimeException('simulated migrator secret-store outage');
                    }

                    $secrets[$key] = $password;

                    return 'ci-secret-ref://' . $key;
                },
                function (string $key) use (&$secrets, &$deleteCalls, $runtimeKey): void {
                    $deleteCalls[] = $key;
                    if ($key === $runtimeKey) {
                        // Leave one key orphaned to model an unavailable secret store.
                        throw new \RuntimeException('simulated runtime secret-delete outage');
                    }

                    unset($secrets[$key]);
                }
            );
            $this->fail('Provisioning must report incomplete secret cleanup.');
        } catch (\RuntimeException $exception) {
            $this->assertSame(
                'Tenant provisioning failed; resources were not automatically removed. Manual verification is required.',
                $exception->getMessage()
            );
            $this->assertNotNull($exception->getPrevious());
            $this->assertStringContainsString(
                'Credential persistence failed and secret cleanup is incomplete; manual secret-manager verification is required.',
                $exception->getPrevious()->getMessage()
            );
            $this->assertStringContainsString(
                'simulated runtime secret-delete outage',
                $exception->getPrevious()->getMessage()
            );
            $this->assertSame(
                'simulated migrator secret-store outage',
                $exception->getPrevious()->getPrevious()?->getMessage()
            );
        }

        $this->assertSame([$runtimeKey, $migratorKey], $storeCalls);
        $this->assertSame(
            [$runtimeKey, $migratorKey],
            $deleteCalls,
            'Cleanup of the second key must still be attempted after the first cleanup fails.'
        );
        $this->assertSame(
            [$runtimeKey => 'non-empty'],
            array_map(static fn (string $secret): string => 'non-empty', $secrets),
            'The simulated unavailable secret must remain visible for manual reconciliation.'
        );
        $this->assertNoTenantResources($tenantId);
    }

    public function test_non_superuser_broker_provisions_two_isolated_tenants_with_working_runtime_grants(): void
    {
        $broker = DB::connection('provisioner');
        $brokerRole = $broker->selectOne(
            'SELECT rolsuper::int AS rolsuper, rolcreatedb::int AS rolcreatedb, rolcreaterole::int AS rolcreaterole
             FROM pg_roles WHERE rolname = current_user'
        );

        $this->assertNotNull($brokerRole);
        $this->assertSame(0, (int) $brokerRole->rolsuper, 'Provisioning integration must not use a PostgreSQL superuser.');
        $this->assertSame(1, (int) $brokerRole->rolcreatedb);
        $this->assertSame(1, (int) $brokerRole->rolcreaterole);

        $storeCredential = function (string $key, string $password): string {
            $this->credentials[$key] = $password;

            return 'ci-secret-ref://' . $key;
        };
        $deleteCredential = function (string $key): void {
            unset($this->credentials[$key]);
        };

        $provisioner = new PostgresTenantProvisioner();
        $tenantA = $provisioner->provision($this->tenantIds[0], $storeCredential, $deleteCredential);
        $tenantB = $provisioner->provision($this->tenantIds[1], $storeCredential, $deleteCredential);

        $this->assertNotSame($tenantA['database'], $tenantB['database']);
        $this->assertNotSame($tenantA['runtime_role'], $tenantB['runtime_role']);
        $this->assertNotSame($tenantA['migrator_role'], $tenantB['migrator_role']);
        $this->assertSame(
            'ci-secret-ref://tenant/' . $this->tenantIds[0] . '/runtime',
            $tenantA['credential_refs']['runtime']
        );
        $this->assertSame(
            'ci-secret-ref://tenant/' . $this->tenantIds[0] . '/migrator',
            $tenantA['credential_refs']['migrator']
        );
        $this->assertArrayNotHasKey('runtime_password', $tenantA);
        $this->assertArrayNotHasKey('migrator_password', $tenantA);

        $roles = DB::connection('central')->select(
            'SELECT rolname, rolcanlogin::int AS rolcanlogin, rolsuper::int AS rolsuper,
                    rolcreatedb::int AS rolcreatedb, rolcreaterole::int AS rolcreaterole,
                    rolreplication::int AS rolreplication, rolbypassrls::int AS rolbypassrls
             FROM pg_roles
             WHERE rolname IN (?, ?, ?, ?, ?, ?)',
            [
                $tenantA['owner_role'], $tenantA['runtime_role'], $tenantA['migrator_role'],
                $tenantB['owner_role'], $tenantB['runtime_role'], $tenantB['migrator_role'],
            ]
        );
        $this->assertCount(6, $roles);

        foreach ($roles as $role) {
            $this->assertSame(0, (int) $role->rolsuper, $role->rolname . ' must not be a superuser.');
            $this->assertSame(0, (int) $role->rolcreatedb, $role->rolname . ' must not create databases.');
            $this->assertSame(0, (int) $role->rolcreaterole, $role->rolname . ' must not create roles.');
            $this->assertSame(0, (int) $role->rolreplication, $role->rolname . ' must not replicate.');
            $this->assertSame(0, (int) $role->rolbypassrls, $role->rolname . ' must not bypass RLS.');
            $expectedCanLogin = str_ends_with($role->rolname, '_owner') ? 0 : 1;
            $this->assertSame($expectedCanLogin, (int) $role->rolcanlogin);
        }

        $databaseOwners = DB::connection('central')->select(
            'SELECT datname, pg_get_userbyid(datdba) AS owner_role
             FROM pg_database WHERE datname IN (?, ?)',
            [$tenantA['database'], $tenantB['database']]
        );
        $this->assertCount(2, $databaseOwners);
        $ownerByDatabase = [];
        foreach ($databaseOwners as $databaseOwner) {
            $ownerByDatabase[$databaseOwner->datname] = $databaseOwner->owner_role;
        }
        $this->assertSame($tenantA['owner_role'], $ownerByDatabase[$tenantA['database']]);
        $this->assertSame($tenantB['owner_role'], $ownerByDatabase[$tenantB['database']]);

        $table = 'provisioner_events_' . strtolower(substr($this->tenantIds[0], 0, 8));
        $migrator = $this->connectionAs(
            'provisioner_migrator_' . strtolower($this->tenantIds[0]),
            $tenantA['database'],
            $tenantA['migrator_role'],
            $this->credentials['tenant/' . $this->tenantIds[0] . '/migrator']
        );
        $migrator->statement(
            'CREATE TABLE public."' . $table . '" (id BIGSERIAL PRIMARY KEY, payload TEXT NOT NULL)'
        );
        $migrator->insert('INSERT INTO public."' . $table . '" (payload) VALUES (?)', ['created-by-migrator']);

        $runtimeA = $this->connectionAs(
            'provisioner_runtime_' . strtolower($this->tenantIds[0]),
            $tenantA['database'],
            $tenantA['runtime_role'],
            $this->credentials['tenant/' . $this->tenantIds[0] . '/runtime']
        );
        $this->assertSame(
            'created-by-migrator',
            $runtimeA->scalar('SELECT payload FROM public."' . $table . '" WHERE id = 1')
        );
        $runtimeA->insert('INSERT INTO public."' . $table . '" (payload) VALUES (?)', ['created-by-runtime']);
        $this->assertSame(2, (int) $runtimeA->scalar('SELECT COUNT(*) FROM public."' . $table . '"'));
        $this->assertSame(
            1,
            $runtimeA->update('UPDATE public."' . $table . '" SET payload = ? WHERE payload = ?', [
                'updated-by-runtime',
                'created-by-runtime',
            ])
        );
        $this->assertSame(
            'updated-by-runtime',
            $runtimeA->scalar('SELECT payload FROM public."' . $table . '" WHERE id = 2')
        );
        $this->assertSame(
            1,
            $runtimeA->delete('DELETE FROM public."' . $table . '" WHERE payload = ?', ['updated-by-runtime'])
        );
        $this->assertSame(1, (int) $runtimeA->scalar('SELECT COUNT(*) FROM public."' . $table . '"'));

        try {
            $runtimeA->statement('CREATE TABLE public.runtime_must_not_ddl (id INTEGER)');
            $this->fail('Tenant runtime must not have CREATE privileges in the tenant schema.');
        } catch (QueryException $exception) {
            $this->assertStringContainsString('permission denied', strtolower($exception->getMessage()));
        }

        $runtimeB = $this->connectionAs(
            'provisioner_runtime_' . strtolower($this->tenantIds[1]),
            $tenantB['database'],
            $tenantB['runtime_role'],
            $this->credentials['tenant/' . $this->tenantIds[1] . '/runtime']
        );

        $this->assertConnectionDenied(
            'provisioner_runtime_cross_tenant',
            $tenantB['database'],
            $tenantA['runtime_role'],
            $this->credentials['tenant/' . $this->tenantIds[0] . '/runtime']
        );
        $this->assertConnectionDenied(
            'provisioner_runtime_reverse_cross_tenant',
            $tenantA['database'],
            $tenantB['runtime_role'],
            $this->credentials['tenant/' . $this->tenantIds[1] . '/runtime']
        );
        $this->assertConnectionDenied(
            'provisioner_runtime_central_denied',
            (string) config('database.connections.central.database'),
            $tenantA['runtime_role'],
            $this->credentials['tenant/' . $this->tenantIds[0] . '/runtime']
        );

        $this->assertConnectionDenied(
            'provisioner_migrator_cross_tenant',
            $tenantB['database'],
            $tenantA['migrator_role'],
            $this->credentials['tenant/' . $this->tenantIds[0] . '/migrator']
        );
        $this->assertConnectionDenied(
            'provisioner_migrator_reverse_cross_tenant',
            $tenantA['database'],
            $tenantB['migrator_role'],
            $this->credentials['tenant/' . $this->tenantIds[1] . '/migrator']
        );
        $this->assertConnectionDenied(
            'provisioner_migrator_central_denied',
            (string) config('database.connections.central.database'),
            $tenantA['migrator_role'],
            $this->credentials['tenant/' . $this->tenantIds[0] . '/migrator']
        );

        $this->assertSame(0, (int) $runtimeB->scalar('SELECT COUNT(*) FROM information_schema.tables WHERE table_name = ?', [$table]));
        $this->assertFalse((bool) DB::connection('central')->scalar(
            'SELECT has_database_privilege(?, ?, \'CONNECT\')::int',
            [$tenantA['runtime_role'], config('database.connections.central.database')]
        ));
    }

    public function test_openbao_worker_command_provisions_database_and_migrates_before_registry_activation(): void
    {
        $tenantId = $this->tenantIds[0];
        $now = now();

        DB::connection('central')->table('tenants')->insert([
            'id' => $tenantId,
            'data' => json_encode(['name' => 'OpenBao provisioning integration'], JSON_THROW_ON_ERROR),
            'template_id' => 'BASIC',
            'status' => 'pending',
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        config([
            'openbao.address' => 'https://openbao.integration.test',
            'openbao.kv_mount' => 'secret',
            'openbao.runtime_token' => 'synthetic-runtime-token',
            'openbao.provisioner_token' => 'synthetic-provisioner-token',
            'openbao.ca_bundle' => null,
            'openbao.connect_timeout_seconds' => 2,
            'openbao.timeout_seconds' => 3,
            'openbao.provisioner_mode' => true,
            'database.connections.tenant.host' => config('database.connections.provisioner.host'),
            'database.connections.tenant.port' => config('database.connections.provisioner.port'),
            'database.connections.tenant.sslmode' => config('database.connections.provisioner.sslmode'),
            'database.connections.tenant.url' => null,
        ]);

        /** @var array<string, string> $vaultSecrets */
        $vaultSecrets = [];
        $storedMigratorPassword = null;
        Http::fake(function (HttpRequest $request) use (&$vaultSecrets, &$storedMigratorPassword) {
            $path = (string) parse_url($request->url(), PHP_URL_PATH);

            if ($request->method() === 'POST' && str_starts_with($path, '/v1/secret/data/tenant/')) {
                $password = $request->data()['data']['password'] ?? null;
                if (! is_string($password) || $password === '') {
                    return Http::response(['errors' => ['invalid synthetic test payload']], 400);
                }
                $vaultSecrets[$path] = $password;
                if (str_ends_with($path, '/migrator')) {
                    $storedMigratorPassword = $password;
                }

                return Http::response(['data' => ['version' => 1]], 200);
            }

            if ($request->method() === 'GET' && array_key_exists($path, $vaultSecrets)) {
                return Http::response(['data' => ['data' => ['password' => $vaultSecrets[$path]]]], 200);
            }

            if ($request->method() === 'DELETE' && str_starts_with($path, '/v1/secret/metadata/tenant/')) {
                unset($vaultSecrets[str_replace('/metadata/', '/data/', $path)]);

                return Http::response([], 204);
            }

            return Http::response(['errors' => ['synthetic path not found']], 404);
        });

        $exitCode = Artisan::call('tenants:provision-database', ['tenantId' => $tenantId]);
        $output = Artisan::output();

        $this->assertSame(0, $exitCode, 'Provision command failed: '.$output);
        $this->assertCount(1, $vaultSecrets, 'Only the runtime credential should remain in OpenBao after activation.');
        $this->assertArrayHasKey('/v1/secret/data/tenant/'.$tenantId.'/runtime', $vaultSecrets);
        $this->assertArrayNotHasKey('/v1/secret/data/tenant/'.$tenantId.'/migrator', $vaultSecrets);
        $this->assertIsString($storedMigratorPassword, 'The temporary migrator password must have existed during migration.');
        $registry = DB::connection('central')->table('tenant_database_registry')
            ->where('tenant_id', $tenantId)
            ->first();

        $this->assertNotNull($registry);
        $this->assertSame('active', $registry->status);
        $this->assertNotNull($registry->provisioned_at);
        $this->assertSame(
            'openbao:kv-v2:secret/tenant/'.$tenantId.'/runtime',
            $registry->runtime_secret_ref
        );

        $migratorRole = 'berkah_t_'.strtolower($tenantId).'_migrator';
        $ownerRole = 'berkah_t_'.strtolower($tenantId).'_owner';
        $migratorState = DB::connection('central')->selectOne(
            'SELECT rolcanlogin::int AS rolcanlogin FROM pg_roles WHERE rolname = ?',
            [$migratorRole]
        );
        $this->assertNotNull($migratorState);
        $this->assertSame(0, (int) $migratorState->rolcanlogin, 'The tenant migrator must be NOLOGIN after successful migrations.');
        $this->assertFalse((bool) DB::connection('central')->scalar(
            'SELECT EXISTS (
                SELECT 1 FROM pg_auth_members
                WHERE roleid = (SELECT oid FROM pg_roles WHERE rolname = ?)
                  AND member = (SELECT oid FROM pg_roles WHERE rolname = ?)
            )::int',
            [$ownerRole, $migratorRole]
        ), 'The temporary migrator must not retain membership in the no-login owner role.');

        $migratorConnectionName = 'provisioner_migrator_retired_'.strtolower($tenantId);
        $migratorConnection = $this->connectionAs(
            $migratorConnectionName,
            'berkahpos_t_'.strtolower($tenantId),
            $migratorRole,
            (string) $storedMigratorPassword
        );
        try {
            $migratorConnection->getPdo();
            $this->fail('A retired tenant migrator must reject its old password.');
        } catch (PDOException $exception) {
            $message = strtolower($exception->getMessage());
            $this->assertTrue(
                str_contains($message, 'not permitted to log in')
                || str_contains($message, 'password authentication failed'),
                'The retired migrator must reject authentication after being disabled.'
            );
        } finally {
            DB::purge($migratorConnectionName);
        }

        $runtimePassword = $vaultSecrets['/v1/secret/data/tenant/'.$tenantId.'/runtime'];
        $this->assertSame(
            $runtimePassword,
            app(TenantRuntimeCredentialResolver::class)->resolve(
                $tenantId,
                $registry->runtime_secret_ref
            )
        );

        $connectionName = 'provisioner_runtime_verify_'.strtolower($tenantId);
        $runtime = $this->connectionAs(
            $connectionName,
            'berkahpos_t_'.strtolower($tenantId),
            'berkah_t_'.strtolower($tenantId).'_runtime',
            $runtimePassword
        );
        $this->assertSame('products', $runtime->scalar("SELECT to_regclass('public.products')"));
        $this->assertFalse((bool) DB::connection('central')->scalar(
            'SELECT has_database_privilege(?, ?, \'CONNECT\')::int',
            ['berkah_t_'.strtolower($tenantId).'_runtime', config('database.connections.central.database')]
        ));
        DB::purge($connectionName);

        Http::assertSent(static fn (HttpRequest $request): bool =>
            $request->method() === 'GET'
            && str_ends_with($request->url(), '/v1/secret/data/tenant/'.$tenantId.'/migrator')
            && $request->header('X-Vault-Token') === ['synthetic-provisioner-token']
        );
        Http::assertSent(static fn (HttpRequest $request): bool =>
            $request->method() === 'GET'
            && str_ends_with($request->url(), '/v1/secret/data/tenant/'.$tenantId.'/runtime')
            && $request->header('X-Vault-Token') === ['synthetic-runtime-token']
        );

        Http::assertSent(static fn (HttpRequest $request): bool =>
            $request->method() === 'DELETE'
            && str_ends_with($request->url(), '/v1/secret/metadata/tenant/'.$tenantId.'/migrator')
            && $request->header('X-Vault-Token') === ['synthetic-provisioner-token']
        );
    }

    private function assertNoTenantResources(
        string $tenantId,
        bool $allowOwnerRole = false,
        bool $allowDatabase = false
    ): void {
        $tenant = strtoupper($tenantId);
        $database = 'berkahpos_t_' . strtolower($tenant);
        $suffix = strtolower($tenant);
        $roles = [
            'berkah_t_' . $suffix . '_owner',
            'berkah_t_' . $suffix . '_runtime',
            'berkah_t_' . $suffix . '_migrator',
        ];
        $central = DB::connection('central');

        $this->assertSame(
            $allowDatabase ? 1 : 0,
            (int) $central->scalar('SELECT COUNT(*) FROM pg_database WHERE datname = ?', [$database]),
            'Unexpected tenant database resource for ' . $tenant
        );
        $existingRoleCount = (int) $central->scalar(
            'SELECT COUNT(*) FROM pg_roles WHERE rolname IN (?, ?, ?)',
            $roles
        );
        $this->assertSame(
            $allowOwnerRole ? 1 : 0,
            $existingRoleCount,
            'Unexpected tenant login/owner role resources for ' . $tenant
        );
    }

    private function connectionAs(string $name, string $database, string $username, string $password): Connection
    {
        $base = config('database.connections.provisioner');
        $base['url'] = null;
        $base['database'] = $database;
        $base['username'] = $username;
        $base['password'] = $password;

        config(['database.connections.' . $name => $base]);
        DB::purge($name);

        return DB::connection($name);
    }

    private function assertConnectionDenied(string $name, string $database, string $username, string $password): void
    {
        $connection = $this->connectionAs($name, $database, $username, $password);

        try {
            $connection->getPdo();
            $this->fail('Expected database CONNECT to be denied for ' . $username . ' against ' . $database . '.');
        } catch (PDOException $exception) {
            $this->assertTrue(
                str_contains(strtolower($exception->getMessage()), 'permission denied for database')
                || (string) $exception->getCode() === '42501',
                'Expected a PostgreSQL permission denial, got: ' . $exception->getMessage()
            );
        } finally {
            DB::purge($name);
        }
    }
}
