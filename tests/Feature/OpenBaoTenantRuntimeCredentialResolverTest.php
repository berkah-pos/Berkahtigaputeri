<?php

namespace Tests\Feature;

use App\Services\OpenBaoKvV2Client;
use App\Services\OpenBaoTenantCredentialStore;
use App\Services\OpenBaoTenantRuntimeCredentialResolver;
use Illuminate\Http\Client\Request as HttpRequest;
use Illuminate\Support\Facades\Http;
use RuntimeException;
use Tests\TestCase;

class OpenBaoTenantRuntimeCredentialResolverTest extends TestCase
{
    private const TENANT = '01ARZ3NDEKTSV4RRFFQ69G5FAV';

    protected function setUp(): void
    {
        parent::setUp();

        config([
            'openbao.address' => 'https://openbao.test.internal',
            'openbao.kv_mount' => 'secret',
            'openbao.runtime_token' => 'synthetic-runtime-token',
            'openbao.provisioner_token' => 'synthetic-provisioner-token',
            'openbao.ca_bundle' => null,
            'openbao.connect_timeout_seconds' => 2,
            'openbao.timeout_seconds' => 3,
        ]);
    }

    public function test_runtime_resolver_reads_only_the_canonical_tenants_runtime_path(): void
    {
        Http::fake([
            'https://openbao.test.internal/v1/secret/data/tenant/'.self::TENANT.'/runtime' =>
                Http::response(['data' => ['data' => ['password' => 'synthetic-runtime-password']]], 200),
        ]);

        $resolver = new OpenBaoTenantRuntimeCredentialResolver(new OpenBaoKvV2Client());
        $reference = 'openbao:kv-v2:secret/tenant/'.self::TENANT.'/runtime';

        $this->assertSame('synthetic-runtime-password', $resolver->resolve(self::TENANT, $reference));
        Http::assertSent(static fn (HttpRequest $request): bool =>
            $request->method() === 'GET'
            && $request->url() === 'https://openbao.test.internal/v1/secret/data/tenant/'.self::TENANT.'/runtime'
            && $request->header('X-Vault-Token') === ['synthetic-runtime-token']
        );
    }

    public function test_runtime_resolver_rejects_tenant_mismatch_and_migrator_references_before_network_access(): void
    {
        Http::fake();

        $resolver = new OpenBaoTenantRuntimeCredentialResolver(new OpenBaoKvV2Client());

        try {
            $resolver->resolve(
                self::TENANT,
                'openbao:kv-v2:secret/tenant/'.self::TENANT.'/migrator'
            );
            $this->fail('A migrator reference must never be accepted by the runtime resolver.');
        } catch (RuntimeException $exception) {
            $this->assertSame('tenant_database_credentials_unavailable', $exception->getMessage());
            $this->assertNull($exception->getPrevious());
        }

        try {
            $resolver->resolve(
                self::TENANT,
                'openbao:kv-v2:secret/tenant/01ARZ3NDEKTSV4RRFFQ69G5FAW/runtime'
            );
            $this->fail('A reference to another tenant must be rejected.');
        } catch (RuntimeException $exception) {
            $this->assertSame('tenant_database_credentials_unavailable', $exception->getMessage());
        }

        Http::assertNothingSent();
    }

    public function test_provider_errors_are_redacted_from_the_runtime_exception(): void
    {
        Http::fake([
            '*' => Http::response(['errors' => ['provider-token=synthetic-do-not-leak']], 500),
        ]);

        $resolver = new OpenBaoTenantRuntimeCredentialResolver(new OpenBaoKvV2Client());

        try {
            $resolver->resolve(
                self::TENANT,
                'openbao:kv-v2:secret/tenant/'.self::TENANT.'/runtime'
            );
            $this->fail('An OpenBao server error must fail closed.');
        } catch (RuntimeException $exception) {
            $this->assertSame('tenant_database_credentials_unavailable', $exception->getMessage());
            $this->assertNull($exception->getPrevious());
            $this->assertStringNotContainsString('synthetic-do-not-leak', $exception->getMessage());
        }
    }

    public function test_secret_store_writes_runtime_and_migrator_secrets_and_deletes_by_kv_v2_metadata(): void
    {
        $stored = [];
        Http::fake(function (HttpRequest $request) use (&$stored) {
            $path = (string) parse_url($request->url(), PHP_URL_PATH);

            if ($request->method() === 'POST' && str_starts_with($path, '/v1/secret/data/tenant/')) {
                $stored[$path] = $request->data()['data']['password'] ?? null;

                return Http::response(['data' => ['version' => 1]], 200);
            }

            if ($request->method() === 'GET' && isset($stored[$path])) {
                return Http::response(['data' => ['data' => ['password' => $stored[$path]]]], 200);
            }

            if ($request->method() === 'DELETE' && str_starts_with($path, '/v1/secret/metadata/tenant/')) {
                unset($stored[str_replace('/metadata/', '/data/', $path)]);

                return Http::response([], 204);
            }

            return Http::response(['errors' => ['not found']], 404);
        });

        $store = new OpenBaoTenantCredentialStore(new OpenBaoKvV2Client());
        $runtimeReference = $store->storeCredential(
            'tenant/'.self::TENANT.'/runtime',
            'synthetic-runtime-password'
        );
        $migratorReference = $store->storeCredential(
            'tenant/'.self::TENANT.'/migrator',
            'synthetic-migrator-password'
        );

        $this->assertSame('openbao:kv-v2:secret/tenant/'.self::TENANT.'/runtime', $runtimeReference);
        $this->assertSame('openbao:kv-v2:secret/tenant/'.self::TENANT.'/migrator', $migratorReference);
        $this->assertSame(
            'synthetic-migrator-password',
            $store->resolveMigratorCredential(self::TENANT, $migratorReference)
        );

        $store->deleteCredential('tenant/'.self::TENANT.'/runtime');

        Http::assertSent(static fn (HttpRequest $request): bool =>
            $request->method() === 'POST'
            && $request->url() === 'https://openbao.test.internal/v1/secret/data/tenant/'.self::TENANT.'/runtime'
            && $request->header('X-Vault-Token') === ['synthetic-provisioner-token']
            && ($request->data()['data']['password'] ?? null) === 'synthetic-runtime-password'
        );
        Http::assertSent(static fn (HttpRequest $request): bool =>
            $request->method() === 'DELETE'
            && $request->url() === 'https://openbao.test.internal/v1/secret/metadata/tenant/'.self::TENANT.'/runtime'
            && $request->header('X-Vault-Token') === ['synthetic-provisioner-token']
        );
        $this->assertArrayNotHasKey('/v1/secret/data/tenant/'.self::TENANT.'/runtime', $stored);
        $this->assertSame('synthetic-migrator-password', $stored['/v1/secret/data/tenant/'.self::TENANT.'/migrator']);
    }

    public function test_insecure_openbao_http_endpoint_is_rejected(): void
    {
        config(['openbao.address' => 'http://openbao.test.internal:8200']);
        Http::fake();

        $resolver = new OpenBaoTenantRuntimeCredentialResolver(new OpenBaoKvV2Client());

        try {
            $resolver->resolve(
                self::TENANT,
                'openbao:kv-v2:secret/tenant/'.self::TENANT.'/runtime'
            );
            $this->fail('TLS verification cannot be disabled for the OpenBao API.');
        } catch (RuntimeException $exception) {
            $this->assertSame('tenant_database_credentials_unavailable', $exception->getMessage());
            $this->assertNull($exception->getPrevious());
        }

        Http::assertNothingSent();
    }
}
