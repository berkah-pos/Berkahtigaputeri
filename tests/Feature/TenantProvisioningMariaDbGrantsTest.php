<?php

namespace Tests\Feature;

use App\Models\Central\Tenant;
use App\Services\TenantDatabaseProvisioner;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Stancl\Tenancy\Facades\Tenancy;
use Tests\TestCase;

class TenantProvisioningMariaDbGrantsTest extends TestCase
{
    /** Uses actual MariaDB accounts/privileges; no DB/connection mocks are involved. */
    public function test_each_tenant_user_has_only_own_database_crud_and_cannot_connect_elsewhere(): void
    {
        $this->assertSame('testing', config('app.env'));
        $centralVersion = (string) DB::connection('central')->selectOne('SELECT VERSION() AS v')->v;
        $this->assertStringContainsString('MariaDB', $centralVersion);
        $this->assertMatchesRegularExpression('/^11\.4\./', $centralVersion);

        $suffix = bin2hex(random_bytes(6));
        $tenantA = $this->makeTestTenant('phase2-a-'.$suffix);
        $tenantB = $this->makeTestTenant('phase2-b-'.$suffix);
        $service = app(TenantDatabaseProvisioner::class);

        // These operations create real schemas, MariaDB accounts, grants and
        // tenant migrations on the disposable CI MariaDB service container.
        $service->provision($tenantA);
        $service->provision($tenantB);

        $tenantA->refresh();
        $tenantB->refresh();
        $stateA = $tenantA->data['database_provisioning'];
        $stateB = $tenantB->data['database_provisioning'];
        $databaseA = $stateA['database_name'];
        $databaseB = $stateB['database_name'];
        $userA = $stateA['runtime_username'];
        $passwordA = Crypt::decryptString($stateA['runtime_password_encrypted']);
        $userB = $stateB['runtime_username'];

        $this->assertNotSame($databaseA, $databaseB);
        $this->assertNotSame($userA, $userB);
        $this->assertSame('provisioned', $stateA['status']);
        $this->assertSame('provisioned', $stateB['status']);

        $this->assertExactRuntimeGrants($userA, $databaseA);
        $this->assertExactRuntimeGrants($userB, $databaseB);

        // The package-managed TenantDatabaseManager must resolve the encrypted
        // credentials and establish the intended tenant connection.
        Tenancy::initialize($tenantA);
        try {
            $current = DB::connection('tenant')->selectOne('SELECT DATABASE() AS db');
            $this->assertSame($databaseA, $current->db);
            DB::connection('tenant')->selectOne('SELECT COUNT(*) AS count FROM products');
        } finally {
            Tenancy::end();
            DB::purge('tenant');
        }

        $runtimeA = $this->runtimeConnection('phase2_runtime_a', $databaseA, $userA, $passwordA);
        $own = DB::connection($runtimeA);
        $productId = 'phase2-'.substr($suffix, 0, 10);
        $own->table('products')->insert(['id' => $productId, 'name' => 'Grant test', 'price' => 1]);
        $own->table('products')->where('id', $productId)->update(['price' => 2]);
        $this->assertSame(2.0, (float) $own->table('products')->where('id', $productId)->value('price'));
        $own->table('products')->where('id', $productId)->delete();

        $this->assertQueryDenied(fn () => $own->statement(
            'CREATE TABLE '.$this->quoteIdentifier('ddl_probe_'.$suffix).' (id INT PRIMARY KEY)'
        ));
        $this->assertQueryDenied(fn () => $own->statement('ALTER TABLE products ADD COLUMN phase2_ddl_probe INT'));
        $this->assertQueryDenied(fn () => $own->statement('DROP TABLE products'));
        $this->assertQueryDenied(fn () => $own->selectOne(
            'SELECT COUNT(*) FROM '.$this->quoteIdentifier('berkahpos_central').'.'.$this->quoteIdentifier('tenants')
        ));
        $this->assertQueryDenied(fn () => $own->selectOne(
            'SELECT COUNT(*) FROM '.$this->quoteIdentifier($databaseB).'.'.$this->quoteIdentifier('products')
        ));
        $this->assertQueryDenied(fn () => $own->statement(
            'USE '.$this->quoteIdentifier('berkahpos_central')
        ));
        $this->assertQueryDenied(fn () => $own->statement(
            'USE '.$this->quoteIdentifier($databaseB)
        ));

        // A connection whose default schema is central or tenant B must not be
        // established with tenant A's actual username/password.
        $this->assertDatabaseConnectionDenied($databaseA, $userA, $passwordA, 'berkahpos_central');
        $this->assertDatabaseConnectionDenied($databaseA, $userA, $passwordA, $databaseB);

        // Re-running the exact job after completion is idempotent: same account,
        // same schema, same provisioning ID and no destructive compensation.
        $provisioningId = $stateA['provisioning_id'];
        $service->provision($tenantA);
        $tenantA->refresh();
        $this->assertSame($databaseA, $tenantA->data['database_provisioning']['database_name']);
        $this->assertSame($userA, $tenantA->data['database_provisioning']['runtime_username']);
        $this->assertSame($provisioningId, $tenantA->data['database_provisioning']['provisioning_id']);

        $completed = DB::connection('central')->table('audit_events')
            ->where('scope_type', 'tenant_db_provisioning')
            ->where('scope_id', $provisioningId)
            ->where('action', 'provisioning.completed')
            ->exists();
        $this->assertTrue($completed);
    }

    private function makeTestTenant(string $id): Tenant
    {
        return Tenant::withoutEvents(fn (): Tenant => Tenant::on('central')->create([
            'id' => $id,
            'template_id' => 'BASIC',
        ]));
    }

    private function assertExactRuntimeGrants(string $username, string $databaseName): void
    {
        $rows = DB::connection('provisioner')->select("SHOW GRANTS FOR '{$username}'@'%'");
        $grants = array_map(static fn ($row): string => (string) array_values((array) $row)[0], $rows);
        $scoped = array_values(array_filter($grants, static fn (string $grant): bool => ! str_contains(strtoupper($grant), 'GRANT USAGE ON *.*')));

        $this->assertCount(1, $scoped, 'Tenant runtime user must have exactly one non-USAGE grant.');
        $grant = strtoupper(str_replace('\\_', '_', $scoped[0]));
        $this->assertStringContainsString('SELECT, INSERT, UPDATE, DELETE', $grant);
        $this->assertStringContainsString(chr(96).strtoupper($databaseName).chr(96).'.*', $grant);
        $this->assertStringNotContainsString('CREATE', $grant);
        $this->assertStringNotContainsString('ALTER', $grant);
        $this->assertStringNotContainsString('DROP', $grant);
        $this->assertStringNotContainsString('GRANT OPTION', $grant);
        $this->assertStringNotContainsString('berkahpos_central', strtolower($grant));
    }

    private function runtimeConnection(string $name, string $databaseName, string $username, string $password): string
    {
        config(['database.connections.'.$name => array_merge(
            config('database.connections.tenant_template'),
            ['database' => $databaseName, 'username' => $username, 'password' => $password],
        )]);
        DB::purge($name);

        return $name;
    }

    private function assertDatabaseConnectionDenied(
        string $ownDatabase,
        string $username,
        string $password,
        string $forbiddenDatabase,
    ): void {
        $connectionName = 'phase2_forbidden_'.substr(hash('sha256', $forbiddenDatabase), 0, 12);
        config(['database.connections.'.$connectionName => array_merge(
            config('database.connections.tenant_template'),
            ['database' => $forbiddenDatabase, 'username' => $username, 'password' => $password],
        )]);
        DB::purge($connectionName);

        try {
            DB::connection($connectionName)->selectOne('SELECT DATABASE() AS db');
            $this->fail('Tenant credential unexpectedly connected with forbidden default database '.$forbiddenDatabase);
        } catch (QueryException) {
            $this->assertTrue(true);
        } finally {
            DB::purge($connectionName);
            config(['database.connections.'.$connectionName => null]);
        }
    }

    private function assertQueryDenied(callable $query): void
    {
        try {
            $query();
            $this->fail('MariaDB unexpectedly allowed a forbidden privilege operation.');
        } catch (QueryException) {
            $this->assertTrue(true);
        }
    }

    private function quoteIdentifier(string $identifier): string
    {
        $this->assertMatchesRegularExpression('/^[A-Za-z0-9_]{1,64}$/', $identifier);
        return chr(96).$identifier.chr(96);
    }
}
