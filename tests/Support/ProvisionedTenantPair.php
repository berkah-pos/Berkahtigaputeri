<?php

namespace Tests\Support;

use App\Models\Central\DeviceRegistry;
use App\Models\Central\Domain;
use App\Models\Central\Tenant;
use App\Models\Central\Subscription;
use App\Models\Central\User;
use App\Services\TenantDatabaseProvisioner;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Assert;

trait ProvisionedTenantPair
{
    protected function createProvisionedTenantPair(string $label): array
    {
        $version = (string) DB::connection('central')->selectOne('SELECT VERSION() AS version')->version;
        Assert::assertStringContainsString('MariaDB', $version, 'Integration tests require real MariaDB.');
        Assert::assertMatchesRegularExpression('/^11\.4\./', $version, 'Integration tests require MariaDB 11.4.');

        $suffix = bin2hex(random_bytes(5));
        $tenantA = Tenant::withoutEvents(fn (): Tenant => Tenant::on('central')->create([
            'id' => $label . '-a-' . $suffix,
            'template_id' => 'BASIC',
            'is_active' => true,
        ]));
        $tenantB = Tenant::withoutEvents(fn (): Tenant => Tenant::on('central')->create([
            'id' => $label . '-b-' . $suffix,
            'template_id' => 'BASIC',
            'is_active' => true,
        ]));

        $provisioner = app(TenantDatabaseProvisioner::class);
        $provisioner->provision($tenantA);
        $provisioner->provision($tenantB);
        // Every ordinary route fixture begins with an explicit valid entitlement;
        // negative tests overwrite or supersede it deliberately.
        foreach ([$tenantA, $tenantB] as $tenant) {
            Subscription::on('central')->create([
                'tenant_id' => (string) $tenant->getTenantKey(),
                'plan' => 'integration-test',
                'status' => 'active',
                'expires_at' => now()->addDays(30),
                'max_users' => 10,
            ]);
        }

        $tenantA->refresh();
        $tenantB->refresh();

        $stateA = $tenantA->database_provisioning ?? [];
        $stateB = $tenantB->database_provisioning ?? [];
        Assert::assertSame('provisioned', $stateA['status'] ?? null);
        Assert::assertSame('provisioned', $stateB['status'] ?? null);
        Assert::assertNotSame($stateA['database_name'] ?? null, $stateB['database_name'] ?? null);
        Assert::assertNotSame($stateA['runtime_username'] ?? null, $stateB['runtime_username'] ?? null);

        return [
            'suffix' => $suffix,
            'tenantA' => $tenantA,
            'tenantB' => $tenantB,
            'tenantAId' => (string) $tenantA->getTenantKey(),
            'tenantBId' => (string) $tenantB->getTenantKey(),
            'databaseA' => (string) $stateA['database_name'],
            'databaseB' => (string) $stateB['database_name'],
            'runtimeUserA' => (string) $stateA['runtime_username'],
            'runtimeUserB' => (string) $stateB['runtime_username'],
            'runtimePasswordA' => Crypt::decryptString($stateA['runtime_password_encrypted']),
            'runtimePasswordB' => Crypt::decryptString($stateB['runtime_password_encrypted']),
        ];
    }

    protected function attachTenantPrincipals(array $pair): array
    {
        $suffix = $pair['suffix'];
        $hostA = 'a-' . $suffix . '.tenant.test';
        $hostB = 'b-' . $suffix . '.tenant.test';

        Domain::on('central')->create([
            'domain' => $hostA,
            'tenant_id' => $pair['tenantAId'],
            'is_active' => true,
        ]);
        Domain::on('central')->create([
            'domain' => $hostB,
            'tenant_id' => $pair['tenantBId'],
            'is_active' => true,
        ]);

        $userA = User::on('central')->create([
            'name' => 'Phase 4 Tenant A',
            'email' => 'a-' . $suffix . '@example.test',
            'password' => Hash::make('phase4-test-a-' . $suffix),
            'tenant_id' => $pair['tenantAId'],
            'is_super_admin' => false,
            'is_active' => true,
        ]);
        $userB = User::on('central')->create([
            'name' => 'Phase 4 Tenant B',
            'email' => 'b-' . $suffix . '@example.test',
            'password' => Hash::make('phase4-test-b-' . $suffix),
            'tenant_id' => $pair['tenantBId'],
            'is_super_admin' => false,
            'is_active' => true,
        ]);

        DB::connection('central')->table('tenant_memberships')->insert([
            [
                'tenant_id' => $pair['tenantAId'],
                'user_id' => $userA->getAuthIdentifier(),
                'is_active' => true,
                'role' => 'member',
                'created_at' => now(),
                'updated_at' => now(),
            ],
            [
                'tenant_id' => $pair['tenantBId'],
                'user_id' => $userB->getAuthIdentifier(),
                'is_active' => true,
                'role' => 'member',
                'created_at' => now(),
                'updated_at' => now(),
            ],
        ]);

        $deviceAId = 'device-a-' . $suffix;
        $deviceBId = 'device-b-' . $suffix;
        DeviceRegistry::on('central')->create([
            'device_id' => $deviceAId,
            'tenant_id' => $pair['tenantAId'],
            'owner_user_id' => $userA->getAuthIdentifier(),
            'status' => 'active',
            'registered_at' => now(),
        ]);
        DeviceRegistry::on('central')->create([
            'device_id' => $deviceBId,
            'tenant_id' => $pair['tenantBId'],
            'owner_user_id' => $userB->getAuthIdentifier(),
            'status' => 'active',
            'registered_at' => now(),
        ]);

        $tokenA = $userA->createToken('phase4-a-' . $suffix, ['config:read', 'sync:write', 'products:read', 'products:write'])->plainTextToken;
        $tokenB = $userB->createToken('phase4-b-' . $suffix, ['config:read', 'sync:write'])->plainTextToken;

        return array_merge($pair, [
            'hostA' => $hostA,
            'hostB' => $hostB,
            'userA' => $userA,
            'userB' => $userB,
            'userAId' => (int) $userA->getAuthIdentifier(),
            'userBId' => (int) $userB->getAuthIdentifier(),
            'deviceAId' => $deviceAId,
            'deviceBId' => $deviceBId,
            'tokenA' => $tokenA,
            'tokenB' => $tokenB,
        ]);
    }

    protected function runtimeConnectionFor(array $pair, string $side): string
    {
        $suffix = $pair['suffix'];
        $database = $pair['database' . $side];
        $username = $pair['runtimeUser' . $side];
        $password = $pair['runtimePassword' . $side];
        $connectionName = 'phase4_runtime_' . strtolower($side) . '_' . $suffix;

        config(['database.connections.' . $connectionName => array_merge(
            config('database.connections.tenant_template'),
            ['database' => $database, 'username' => $username, 'password' => $password]
        )]);
        DB::purge($connectionName);

        return $connectionName;
    }

    protected function assertMariaDbPrivilegeDenied(callable $operation): void
    {
        try {
            $operation();
        } catch (\Throwable $exception) {
            $driverCode = (int) ($exception->errorInfo[1] ?? 0);
            Assert::assertContains(
                $driverCode,
                [1044, 1045, 1142, 1227],
                'Expected MariaDB privilege denial; got ' . $exception::class . ' / driver code ' . $driverCode
            );
            return;
        }

        Assert::fail('MariaDB unexpectedly permitted a cross-database operation.');
    }

    protected function quoteDatabaseIdentifier(string $identifier): string
    {
        Assert::assertMatchesRegularExpression('/^[A-Za-z0-9_]{1,64}$/D', $identifier);

        return chr(96) . $identifier . chr(96);
    }
}
