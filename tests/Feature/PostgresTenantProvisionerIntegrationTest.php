<?php

namespace Tests\Feature;

use App\Services\PostgresTenantProvisioner;
use Illuminate\Database\Connection;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
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
                        $central->statement('REVOKE "' . $ownerRole . '" FROM "' . $migratorRole . '"');
                    }
                    if (in_array($ownerRole, $existingNames, true)) {
                        $central->statement('REVOKE "' . $ownerRole . '" FROM "' . $brokerRole . '"');
                    }

                    foreach ([$migratorRole, $runtimeRole, $ownerRole] as $role) {
                        $central->statement('DROP ROLE IF EXISTS "' . $role . '"');
                    }
                } catch (Throwable $exception) {
                    // The workflow creates a fresh disposable PostgreSQL service per run.
                    // Preserve the original test failure; CI destroys the service after the job.
                    fwrite(STDERR, "Disposable PG17 role cleanup warning: " . $exception->getMessage() . PHP_EOL);
                }
            }
        }

        parent::tearDown();
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

        $provisioner = new PostgresTenantProvisioner();
        $tenantA = $provisioner->provision($this->tenantIds[0], $storeCredential);
        $tenantB = $provisioner->provision($this->tenantIds[1], $storeCredential);

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
