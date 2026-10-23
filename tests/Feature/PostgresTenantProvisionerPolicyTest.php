<?php

namespace Tests\Feature;

use App\Services\PostgresTenantProvisioner;
use RuntimeException;
use Tests\TestCase;

class PostgresTenantProvisionerPolicyTest extends TestCase
{
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
                $provisioner->provision($invalid, function (): string {
                    $this->fail('Credential storage must not run for an invalid tenant ID.');
                });
                $this->fail('Expected invalid tenant ID to be rejected.');
            } catch (RuntimeException $exception) {
                $this->assertSame('Tenant ID must be a canonical ULID.', $exception->getMessage());
            }
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
                }
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
