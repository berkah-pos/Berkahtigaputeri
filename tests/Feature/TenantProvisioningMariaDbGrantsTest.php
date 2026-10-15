<?php

namespace Tests\Feature;

use App\Models\Central\Tenant;
use App\Services\TenantDatabaseProvisioner;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\Process\Process;
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
        $this->runConcurrentProvisioning((string) $tenantA->getTenantKey());
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
        $passwordB = Crypt::decryptString($stateB['runtime_password_encrypted']);

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

        // Seed a real row in tenant B using tenant B's own restricted account.
        $runtimeB = $this->runtimeConnection('phase2_runtime_b', $databaseB, $userB, $passwordB);
        $productIdB = 'phase2-b-'.substr($suffix, 0, 10);
        DB::connection($runtimeB)->table('products')->insert([
            'id' => $productIdB, 'name' => 'Tenant B grant test', 'price' => 3,
        ]);

        $quotedTenantB = $this->quoteIdentifier($databaseB);
        $quotedCentral = $this->quoteIdentifier('berkahpos_central');
        $quotedProducts = $this->quoteIdentifier('products');
        $quotedTenants = $this->quoteIdentifier('tenants');
        $this->assertQueryDenied(fn () => $own->statement(
            'INSERT INTO '.$quotedTenantB.'.'.$quotedProducts.' (id, name, price) VALUES (?, ?, ?)',
            ['cross-tenant-insert-'.$suffix, 'must be denied', 1]
        ));
        $this->assertQueryDenied(fn () => $own->statement(
            'UPDATE '.$quotedTenantB.'.'.$quotedProducts.' SET price = ? WHERE id = ?',
            [99, $productIdB]
        ));
        $this->assertQueryDenied(fn () => $own->statement(
            'DELETE FROM '.$quotedTenantB.'.'.$quotedProducts.' WHERE id = ?',
            [$productIdB]
        ));

        // Explicit central data-manipulation probes prove central isolation as well.
        $this->assertQueryDenied(fn () => $own->statement(
            'INSERT INTO '.$quotedCentral.'.'.$quotedTenants.' (id, template_id) VALUES (?, ?)',
            ['cross-central-'.$suffix, 'BASIC']
        ));
        $this->assertQueryDenied(fn () => $own->statement(
            'UPDATE '.$quotedCentral.'.'.$quotedTenants.' SET template_id = ? WHERE id = ?',
            ['PRO', (string) $tenantA->getTenantKey()]
        ));
        $this->assertQueryDenied(fn () => $own->statement(
            'DELETE FROM '.$quotedCentral.'.'.$quotedTenants.' WHERE id = ?',
            [(string) $tenantA->getTenantKey()]
        ));

        // A runtime user cannot delegate privileges or create other accounts.
        $this->assertQueryDenied(fn () => $own->statement(
            "GRANT SELECT ON {$quotedTenantB}.* TO '{$userB}'@'%'"
        ));
        $dummyPassword = bin2hex(random_bytes(12));
        $this->assertQueryDenied(fn () => $own->statement(
            "CREATE USER 'phase2_denied_{$suffix}'@'%' IDENTIFIED BY '{$dummyPassword}'"
        ));

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

    public function test_resumes_after_interruption_only_for_a_verified_empty_database(): void
    {
        $this->assertSame('testing', config('app.env'));
        $tenantId = 'phase2-resume-'.bin2hex(random_bytes(6));
        $tenant = $this->makeTestTenant($tenantId);
        $provisioner = app(TenantDatabaseProvisioner::class);

        $databaseName = $provisioner->databaseName($tenantId);
        $username = $provisioner->runtimeUsername($tenantId);
        $password = Str::random(64);
        $provisioningId = (string) Str::uuid();

        $tenant->setAttribute('tenancy_db_name', $databaseName);
        $data = $tenant->data ?? [];
        $data['database_provisioning'] = [
            'status' => 'provisioning',
            'tenant_id' => $tenantId,
            'database_name' => $databaseName,
            'runtime_username' => $username,
            'runtime_password_encrypted' => Crypt::encryptString($password),
            'provisioning_id' => $provisioningId,
            'reserved_at' => now()->toIso8601String(),
        ];
        $tenant->data = $data;
        $tenant->save();

        // Simulate a process interruption immediately after CREATE DATABASE:
        // the reservation and intent/absence audit exist, but the DB has no
        // tables, user, marker, or completion event yet.
        $this->recordProvisioningAudit($tenantId, $provisioningId, 'database.create.intent', [
            'database_name' => $databaseName,
        ]);
        $this->recordProvisioningAudit($tenantId, $provisioningId, 'database.absent.verified', [
            'database_name' => $databaseName,
        ]);
        DB::connection('provisioner')->statement(
            'CREATE DATABASE '.$this->quoteIdentifier($databaseName).' CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci'
        );

        $provisioner->provision($tenant);
        $tenant->refresh();

        $state = $tenant->data['database_provisioning'];
        $this->assertSame('provisioned', $state['status']);
        $this->assertSame($databaseName, $state['database_name']);
        $this->assertSame($username, $state['runtime_username']);

        $schema = DB::connection('provisioner')->selectOne(
            'SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = ?',
            [$databaseName]
        );
        $this->assertNotNull($schema);
        $this->assertTrue($this->auditActionExists($provisioningId, 'database.create.recovered_after_interruption'));
        $this->assertTrue($this->auditActionExists($provisioningId, 'ownership_marker.create.completed'));
        $this->assertTrue($this->auditActionExists($provisioningId, 'provisioning.completed'));
        $this->assertExactRuntimeGrants($username, $databaseName);
    }

    private function runConcurrentProvisioning(string $tenantId): void
    {
        $command = [PHP_BINARY, base_path('artisan'), 'tenant:provision-database', $tenantId];
        $first = new Process($command, base_path());
        $second = new Process($command, base_path());

        // Start two independent PHP processes before waiting for either. The
        // advisory lock and reservation must serialize the privileged actions.
        $first->start();
        $second->start();
        $first->wait();
        $second->wait();

        $this->assertSame(0, $first->getExitCode(), 'First concurrent provisioner process failed.');
        $this->assertSame(0, $second->getExitCode(), 'Second concurrent provisioner process failed.');

        $tenant = Tenant::on('central')->findOrFail($tenantId);
        $state = $tenant->data['database_provisioning'];
        $id = (string) $state['provisioning_id'];

        $databaseCreates = DB::connection('central')->table('audit_events')
            ->where('scope_type', 'tenant_db_provisioning')
            ->where('scope_id', $id)
            ->where('action', 'database.create.completed')
            ->count();
        $userCreates = DB::connection('central')->table('audit_events')
            ->where('scope_type', 'tenant_db_provisioning')
            ->where('scope_id', $id)
            ->where('action', 'runtime_user.create.completed')
            ->count();

        $this->assertSame(1, $databaseCreates, 'Concurrent retries must create one database.');
        $this->assertSame(1, $userCreates, 'Concurrent retries must create one runtime account.');
    }

    private function recordProvisioningAudit(string $tenantId, string $provisioningId, string $action, array $metadata): void
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

    private function auditActionExists(string $provisioningId, string $action): bool
    {
        return DB::connection('central')->table('audit_events')
            ->where('scope_type', 'tenant_db_provisioning')
            ->where('scope_id', $provisioningId)
            ->where('action', $action)
            ->exists();
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
        $scoped = array_values(array_filter(
            $grants,
            static fn (string $item): bool => ! preg_match('/^GRANT USAGE ON \*\.\* TO /i', $item)
        ));

        $this->assertCount(1, $scoped, 'Tenant runtime user must have exactly one non-USAGE grant.');
        $statement = str_replace('\\_', '_', $scoped[0]);
        $pattern = '/^GRANT (.+) ON [`]?([A-Za-z0-9_]+)[`]?\.\* TO /i';
        $this->assertMatchesRegularExpression($pattern, $statement, 'Runtime grant must be database-scoped.');
        preg_match($pattern, $statement, $matches);
        $this->assertSame($databaseName, $matches[2], 'Runtime grant must name only its own database.');
        $privileges = array_map('trim', explode(',', strtoupper($matches[1])));
        sort($privileges);
        $expected = ['DELETE', 'INSERT', 'SELECT', 'UPDATE'];
        sort($expected);
        $this->assertSame($expected, $privileges, 'Runtime user must have exactly CRUD privileges.');
        $this->assertStringNotContainsString('WITH GRANT OPTION', strtoupper($statement));
        $this->assertStringNotContainsString('berkahpos_central', strtolower($statement));
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
        } catch (\Throwable $exception) {
            $this->assertPrivilegeDenial($exception);
            return;
        } finally {
            DB::purge($connectionName);
            config(['database.connections.'.$connectionName => null]);
        }

        $this->fail('Tenant credential unexpectedly connected with forbidden default database '.$forbiddenDatabase);
    }

    private function assertQueryDenied(callable $query): void
    {
        try {
            $query();
        } catch (\Throwable $exception) {
            $this->assertPrivilegeDenial($exception);
            return;
        }

        $this->fail('MariaDB unexpectedly allowed a forbidden privilege operation.');
    }

    private function assertPrivilegeDenial(\Throwable $exception): void
    {
        $driverCode = (int) ($exception->errorInfo[1] ?? 0);
        $this->assertContains(
            $driverCode,
            [1044, 1045, 1142, 1227],
            'Expected a MariaDB privilege denial, got '.$exception::class.' with driver code '.$driverCode.'.'
        );
    }

    private function quoteIdentifier(string $identifier): string
    {
        $this->assertMatchesRegularExpression('/^[A-Za-z0-9_]{1,64}$/', $identifier);
        return chr(96).$identifier.chr(96);
    }
}
