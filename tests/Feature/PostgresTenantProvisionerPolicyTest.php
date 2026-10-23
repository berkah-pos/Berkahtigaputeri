<?php

namespace Tests\Feature;

use App\Services\PostgresTenantProvisioner;
use Illuminate\Support\Facades\Artisan;
use RuntimeException;
use Tests\TestCase;

class PostgresTenantProvisionerPolicyTest extends TestCase
{
    public function test_provision_command_fails_closed_when_isolated_worker_mode_is_disabled(): void
    {
        config([
            'openbao.provisioner_mode' => false,
            'openbao.provisioner_token' => null,
            'openbao.address' => null,
        ]);

        $exitCode = Artisan::call('tenants:provision-database', [
            'tenantId' => '01ARZ3NDEKTSV4RRFFQ69G5FAV',
        ]);

        $this->assertSame(1, $exitCode);
        $this->assertStringContainsString(
            'Provisioning is disabled or its isolated-worker configuration is incomplete or inconsistent.',
            Artisan::output()
        );
    }

    public function test_provision_command_fails_closed_when_central_and_provisioner_urls_target_different_servers(): void
    {
        config([
            'openbao.provisioner_mode' => true,
            'openbao.provisioner_token' => 'synthetic-provisioner-token',
            'openbao.address' => 'https://openbao.test.internal',
            'database.connections.central.url' => 'postgresql://central@central-db.internal:5432/berkahpos_central',
            // A stale host field must not hide the URL host that Laravel will use.
            'database.connections.central.host' => 'shared-db.internal',
            'database.connections.central.port' => '5432',
            'database.connections.provisioner.driver' => 'pgsql',
            'database.connections.provisioner.url' => null,
            'database.connections.provisioner.host' => 'shared-db.internal',
            'database.connections.provisioner.port' => '5432',
            'database.connections.provisioner.username' => 'synthetic-provisioner',
            'database.connections.provisioner.password' => 'synthetic-provisioner-password',
            'database.connections.tenant.url' => null,
            'database.connections.tenant.host' => 'shared-db.internal',
            'database.connections.tenant.port' => '5432',
        ]);

        $exitCode = Artisan::call('tenants:provision-database', [
            'tenantId' => '01ARZ3NDEKTSV4RRFFQ69G5FAV',
        ]);

        $this->assertSame(1, $exitCode);
        $this->assertStringContainsString(
            'Provisioning is disabled or its isolated-worker configuration is incomplete or inconsistent.',
            Artisan::output()
        );
    }

    public function test_provision_command_fails_closed_when_tenant_migration_endpoint_differs(): void
    {
        config([
            'openbao.provisioner_mode' => true,
            'openbao.provisioner_token' => 'synthetic-provisioner-token',
            'openbao.address' => 'https://openbao.test.internal',
            'database.connections.central.url' => null,
            'database.connections.central.host' => 'shared-db.internal',
            'database.connections.central.port' => '5432',
            'database.connections.provisioner.driver' => 'pgsql',
            'database.connections.provisioner.url' => 'postgresql://synthetic-provisioner@shared-db.internal:5432/postgres',
            'database.connections.provisioner.host' => 'stale-host-that-must-be-ignored.internal',
            'database.connections.provisioner.port' => '5432',
            'database.connections.provisioner.username' => 'synthetic-provisioner',
            'database.connections.provisioner.password' => 'synthetic-provisioner-password',
            // ProvisionTenantDatabase sets url=null before migrations, so host/port are authoritative here.
            'database.connections.tenant.url' => 'postgresql://tenant@shared-db.internal:5432/ignored',
            'database.connections.tenant.host' => 'different-tenant-db.internal',
            'database.connections.tenant.port' => '5432',
        ]);

        $exitCode = Artisan::call('tenants:provision-database', [
            'tenantId' => '01ARZ3NDEKTSV4RRFFQ69G5FAV',
        ]);

        $this->assertSame(1, $exitCode);
        $this->assertStringContainsString(
            'Provisioning is disabled or its isolated-worker configuration is incomplete or inconsistent.',
            Artisan::output()
        );
    }

    public function test_tenant_identifier_is_normalized_only_when_it_is_a_canonical_ulid(): void
    {
        $provisioner = new PostgresTenantProvisioner();

        $this->assertSame(
            '01ARZ3NDEKTSV4RRFFQ69G5FAV',
            $provisioner->normalizeTenantId('01arz3ndektsv4rrffq69g5fav')
        );
    }

    public function test_malformed_tenant_identifiers_are_rejected_before_database_access(): void
    {
        $provisioner = new PostgresTenantProvisioner();

        foreach ([
            '',
            'tenant-a',
            '01ARZ3NDEKTSV4RRFFQ69G5FA!', // punctuation
            '81ARZ3NDEKTSV4RRFFQ69G5FAV', // invalid ULID first character
            '01ARZ3NDEKTSV4RRFFQ69G5FAV-extra',
        ] as $invalid) {
            try {
                $provisioner->provision(
                    $invalid,
                    function (): string {
                        $this->fail('Credential storage must not run for an invalid tenant ID.');
                    },
                    function (): void {
                        $this->fail('Credential cleanup must not run for an invalid tenant ID.');
                    }
                );
                $this->fail('Expected invalid tenant ID to be rejected.');
            } catch (RuntimeException $exception) {
                $this->assertSame('Tenant ID must be a canonical ULID.', $exception->getMessage());
            }
        }
    }

    public function test_provisioner_preflight_honors_url_overrides_for_database_and_username(): void
    {
        $cases = [
            [
                'description' => 'effective usernames match despite distinct sibling config',
                'central_url' => 'postgresql://central_runtime:central-test-password@127.0.0.1:5432/berkahpos_central',
                'provisioner_url' => 'postgresql://central_runtime:provisioner-test-password@127.0.0.1:5432/postgres',
            ],
            [
                'description' => 'effective database names match despite distinct sibling config',
                'central_url' => 'postgresql://central_runtime:central-test-password@127.0.0.1:5432/berkahpos_central',
                'provisioner_url' => 'postgresql://provisioner_runtime:provisioner-test-password@127.0.0.1:5432/berkahpos_central',
            ],
        ];

        foreach ($cases as $case) {
            config([
                'database.connections.central.driver' => 'pgsql',
                'database.connections.central.url' => $case['central_url'],
                'database.connections.central.database' => 'stale_central_database',
                'database.connections.central.username' => 'stale_central_runtime',
                'database.connections.provisioner.driver' => 'pgsql',
                'database.connections.provisioner.url' => $case['provisioner_url'],
                'database.connections.provisioner.database' => 'stale_provisioner_database',
                'database.connections.provisioner.username' => 'stale_provisioner_runtime',
                'database.connections.provisioner.password' => '',
            ]);

            $stored = false;

            try {
                (new PostgresTenantProvisioner())->provision(
                    '01ARZ3NDEKTSV4RRFFQ69G5FAV',
                    function () use (&$stored): string {
                        $stored = true;

                        return 'test-secret-reference';
                    },
                    static function (string $key): void {}
                );
                $this->fail('Provisioning must reject '.$case['description'].' before connecting.');
            } catch (RuntimeException $exception) {
                $this->assertSame(
                    'Provisioner credentials must be non-empty and distinct from central runtime credentials.',
                    $exception->getMessage(),
                    $case['description']
                );
            }

            $this->assertFalse($stored, 'Credentials must not be stored after the URL-effective preflight fails.');
        }
    }

    public function test_provisioning_fails_closed_when_broker_credentials_are_missing_or_shared(): void
    {
        config([
            'database.connections.central.database' => 'berkahpos_central',
            'database.connections.central.username' => 'central_runtime',
            'database.connections.provisioner.driver' => 'pgsql',
            'database.connections.provisioner.database' => 'berkahpos_central',
            'database.connections.provisioner.username' => 'central_runtime',
            'database.connections.provisioner.password' => 'test-only',
        ]);

        $stored = false;

        try {
            (new PostgresTenantProvisioner())->provision(
                '01ARZ3NDEKTSV4RRFFQ69G5FAV',
                function () use (&$stored): string {
                    $stored = true;

                    return 'test-secret-reference';
                },
                static function (string $key): void {}
            );
            $this->fail('Expected shared broker/runtime credentials to be rejected.');
        } catch (RuntimeException $exception) {
            $this->assertSame(
                'Provisioner credentials must be non-empty and distinct from central runtime credentials.',
                $exception->getMessage()
            );
        }

        $this->assertFalse($stored, 'No secrets or database resources should be created after a failed preflight.');
    }
}
