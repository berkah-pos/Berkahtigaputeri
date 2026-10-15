<?php

namespace Tests\Feature;

use App\Models\Central\Domain;
use App\Models\Central\Tenant;
use App\Services\TenantHostResolver;
use App\Services\TenantScopedCache;
use App\Services\TenantScopedStorage;
use Illuminate\Testing\TestResponse;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Stancl\Tenancy\Facades\Tenancy;
use Tests\Support\ProvisionedTenantPair;
use Tests\TestCase;

class HostDomainTenantIsolationMariaDbTest extends TestCase
{
    use ProvisionedTenantPair;

    protected function setUp(): void
    {
        parent::setUp();
        config(['tenancy.central_domains' => ['localhost', 'central.test', 'app.central.test']]);
    }

    public function test_unknown_hosts_proxy_spoofing_and_central_tenant_route_boundaries_fail_closed(): void
    {
        $pair = $this->attachTenantPrincipals($this->createProvisionedTenantPair('phase4-host'));

        $this->assertSame(404, $this->requestOnHost('GET', 'attacker.invalid', '/')->getStatusCode());
        $this->assertSame(404, $this->requestOnHost('GET', 'central.test', '/tenant/context')->getStatusCode());

        // This is an actual central-only login route; tenant-domain dispatch must stop at middleware.
        $tenantToCentral = $this->requestOnHost(
            'POST',
            $pair['hostA'],
            '/api/v1/auth/login',
            null,
            [],
            ['email' => 'nobody@example.test', 'password' => 'not-used']
        );
        $this->assertSame(404, $tenantToCentral->getStatusCode());
        $this->assertSame(404, $this->requestOnHost('GET', $pair['hostA'], '/central/admin')->getStatusCode());

        $centralHostSpoof = $this->requestOnHost(
            'GET',
            'central.test',
            '/tenant/context',
            null,
            ['X-Forwarded-Host' => $pair['hostA']]
        );
        $this->assertSame(404, $centralHostSpoof->getStatusCode());

        $tenantHostSpoof = $this->requestOnHost(
            'GET',
            $pair['hostA'],
            '/tenant/context',
            $pair['tokenA'],
            ['X-Forwarded-Host' => $pair['hostB'], 'X-Device-ID' => $pair['deviceAId']]
        );
        $this->assertSame(404, $tenantHostSpoof->getStatusCode());

        $validTenant = $this->requestOnHost(
            'GET',
            $pair['hostA'],
            '/tenant/context',
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId']]
        );
        $validTenant->assertOk()->assertJsonPath('tenant_id', $pair['tenantAId']);
    }

    public function test_forged_tenant_device_and_host_selectors_cannot_read_or_mutate_tenant_b_products(): void
    {
        $pair = $this->attachTenantPrincipals($this->createProvisionedTenantPair('phase4-http'));
        $productA = 'product-a-' . $pair['suffix'];
        $productB = 'product-b-' . $pair['suffix'];
        $this->seedProduct($pair['tenantA'], $productA, '10.00');
        $this->seedProduct($pair['tenantB'], $productB, '37.25');

        $readBFromAHost = $this->requestOnHost(
            'GET',
            $pair['hostA'],
            '/tenant/products/' . $productB,
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId']]
        );
        $this->assertSame(404, $readBFromAHost->getStatusCode());

        $forgedTenantRead = $this->requestOnHost(
            'GET',
            $pair['hostA'],
            '/tenant/products/' . $productA . '?tenant_id=' . urlencode($pair['tenantBId']),
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId'], 'X-Tenant-ID' => $pair['tenantBId']]
        );
        $this->assertSame(404, $forgedTenantRead->getStatusCode());

        $forgedTenantMutation = $this->requestOnHost(
            'PATCH',
            $pair['hostA'],
            '/tenant/products/' . $productA,
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId']],
            ['tenant_id' => $pair['tenantBId'], 'price' => '0.01']
        );
        $this->assertSame(404, $forgedTenantMutation->getStatusCode());

        $forgedDeviceMutation = $this->requestOnHost(
            'PATCH',
            $pair['hostA'],
            '/tenant/products/' . $productA,
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceBId']],
            ['price' => '0.01']
        );
        $this->assertSame(404, $forgedDeviceMutation->getStatusCode());

        $crossDomainRead = $this->requestOnHost(
            'GET',
            $pair['hostB'],
            '/tenant/products/' . $productB,
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId']]
        );
        $this->assertContains($crossDomainRead->getStatusCode(), [403, 404]);

        $crossDomainMutation = $this->requestOnHost(
            'PATCH',
            $pair['hostB'],
            '/tenant/products/' . $productB,
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId']],
            ['price' => '0.01']
        );
        $this->assertContains($crossDomainMutation->getStatusCode(), [403, 404]);

        $this->assertSame('37.25', $this->readProductPrice($pair['tenantB'], $productB));
        $this->assertSame('10.00', $this->readProductPrice($pair['tenantA'], $productA));
    }

    public function test_domain_suspension_and_rename_evict_warmed_cache_and_reject_old_host_immediately(): void
    {
        $pair = $this->attachTenantPrincipals($this->createProvisionedTenantPair('phase4-cache'));
        $resolver = app(TenantHostResolver::class);
        $cacheKey = $resolver->cacheKey($pair['hostA']);

        $this->requestOnHost(
            'GET',
            $pair['hostA'],
            '/tenant/context',
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId']]
        )->assertOk();
        $this->assertTrue(Cache::has($cacheKey), 'A successful request must warm the host mapping cache.');

        $tenant = Tenant::on('central')->findOrFail($pair['tenantAId']);
        $tenant->is_active = false;
        $tenant->save();

        $this->assertFalse(Cache::has($cacheKey), 'Tenant suspension must invalidate cached host mappings.');
        $this->assertSame(404, $this->requestOnHost(
            'GET',
            $pair['hostA'],
            '/tenant/context',
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId']]
        )->getStatusCode());

        $tenant->refresh();
        $tenant->is_active = true;
        $tenant->save();
        $this->requestOnHost(
            'GET',
            $pair['hostA'],
            '/tenant/context',
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId']]
        )->assertOk();

        $domain = Domain::on('central')->where('domain', $pair['hostA'])->firstOrFail();
        $domain->is_active = false;
        $domain->save();
        $this->assertFalse(Cache::has($cacheKey), 'Domain suspension must invalidate its cached mapping.');

        // Matching forwarding metadata cannot revive the suspended domain.
        $this->assertSame(404, $this->requestOnHost(
            'GET',
            $pair['hostA'],
            '/tenant/context',
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId'], 'X-Forwarded-Host' => $pair['hostA']]
        )->getStatusCode());

        $domain->is_active = true;
        $domain->save();
        $this->requestOnHost(
            'GET',
            $pair['hostA'],
            '/tenant/context',
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId']]
        )->assertOk();
        $this->assertTrue(Cache::has($cacheKey));

        $domain->delete();
        $renamedHost = 'renamed-' . $pair['suffix'] . '.tenant.test';
        Domain::on('central')->create([
            'domain' => $renamedHost,
            'tenant_id' => $pair['tenantAId'],
            'is_active' => true,
        ]);

        $this->assertFalse(Cache::has($cacheKey), 'Renaming/removing a domain must evict the old hostname key.');
        $this->assertSame(404, $this->requestOnHost(
            'GET',
            $pair['hostA'],
            '/tenant/context',
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId']]
        )->getStatusCode());
        $this->requestOnHost(
            'GET',
            $renamedHost,
            '/tenant/context',
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId']]
        )->assertOk();
    }

    public function test_cache_keys_and_local_files_are_tenant_scoped_and_not_cross_readable(): void
    {
        $pair = $this->createProvisionedTenantPair('phase4-storage');
        $cache = app(TenantScopedCache::class);
        $storage = app(TenantScopedStorage::class);
        $pathA = null;
        $keyA = null;

        Tenancy::initialize($pair['tenantA']);
        try {
            $cache->put('isolation-proof', 'tenant-a-value');
            $storage->put('isolation-proof.txt', 'tenant-a-file');
            $keyA = $cache->scopedKey('isolation-proof');
            $pathA = $storage->scopedPath('isolation-proof.txt');
        } finally {
            Tenancy::end();
            DB::purge('tenant');
        }

        Tenancy::initialize($pair['tenantB']);
        try {
            $this->assertNull($cache->get('isolation-proof'));
            $this->assertNull($storage->get('isolation-proof.txt'));
            $this->assertNotSame($keyA, $cache->scopedKey('isolation-proof'));
            $this->assertNotSame($pathA, $storage->scopedPath('isolation-proof.txt'));
        } finally {
            Tenancy::end();
            DB::purge('tenant');
        }
    }

    private function requestOnHost(
        string $method,
        string $host,
        string $uri,
        ?string $token = null,
        array $headers = [],
        array $payload = []
    ): TestResponse {
        $requestHeaders = array_merge(['Host' => $host, 'Accept' => 'application/json'], $headers);
        if ($token !== null) {
            $requestHeaders['Authorization'] = 'Bearer ' . $token;
        }

        return $this->withHeaders($requestHeaders)->json($method, $uri, $payload);
    }

    private function seedProduct(Tenant $tenant, string $productId, string $price): void
    {
        Tenancy::initialize($tenant);
        try {
            DB::connection('tenant')->table('products')->insert([
                'id' => $productId,
                'name' => 'Isolation fixture',
                'price' => $price,
                'is_active' => true,
                'requires_review' => false,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        } finally {
            Tenancy::end();
            DB::purge('tenant');
        }
    }

    private function readProductPrice(Tenant $tenant, string $productId): string
    {
        Tenancy::initialize($tenant);
        try {
            return (string) DB::connection('tenant')->table('products')->where('id', $productId)->value('price');
        } finally {
            Tenancy::end();
            DB::purge('tenant');
        }
    }
}
