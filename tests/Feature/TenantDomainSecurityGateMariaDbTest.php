<?php

namespace Tests\Feature;

use App\Models\Central\Subscription;
use App\Models\Central\Tenant;
use Illuminate\Database\Events\QueryExecuted;
use Illuminate\Testing\TestResponse;
use Illuminate\Support\Facades\DB;
use Stancl\Tenancy\Facades\Tenancy;
use Tests\Support\ProvisionedTenantPair;
use Tests\TestCase;

class TenantDomainSecurityGateMariaDbTest extends TestCase
{
    use ProvisionedTenantPair;

    protected function setUp(): void
    {
        parent::setUp();
        config(['tenancy.central_domains' => ['localhost', 'central.test', 'app.central.test']]);
    }

    public function test_membership_and_device_denials_happen_before_any_tenant_database_query(): void
    {
        $pair = $this->attachTenantPrincipals($this->createProvisionedTenantPair('preauth'));
        $tenantQueries = [];

        DB::listen(static function (QueryExecuted $query) use (&$tenantQueries): void {
            if ($query->connectionName === 'tenant') {
                $tenantQueries[] = $query->sql;
            }
        });

        $wrongMembership = $this->requestOnHost(
            'GET',
            $pair['hostB'],
            '/tenant/context',
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId']]
        );
        $this->assertSame(403, $wrongMembership->getStatusCode());
        $this->assertSame([], $tenantQueries, 'Membership must be checked on central before tenant initialization.');

        $wrongDevice = $this->requestOnHost(
            'GET',
            $pair['hostA'],
            '/tenant/context',
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceBId']]
        );
        $this->assertSame(404, $wrongDevice->getStatusCode());
        $this->assertSame([], $tenantQueries, 'Device ownership must be checked on central before tenant initialization.');
    }

    public function test_expired_subscription_blocks_tenant_domain_access_before_database_initialization(): void
    {
        $pair = $this->attachTenantPrincipals($this->createProvisionedTenantPair('expired'));
        Subscription::on('central')
            ->where('tenant_id', $pair['tenantAId'])
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->firstOrFail()
            ->update([
                'status' => 'active',
                'expires_at' => now()->subSecond(),
            ]);

        $tenantQueries = [];
        DB::listen(static function (QueryExecuted $query) use (&$tenantQueries): void {
            if ($query->connectionName === 'tenant') {
                $tenantQueries[] = $query->sql;
            }
        });

        $response = $this->requestOnHost(
            'GET',
            $pair['hostA'],
            '/tenant/context',
            $pair['tokenA'],
            ['X-Device-ID' => $pair['deviceAId']]
        );

        $this->assertSame(402, $response->getStatusCode());
        $this->assertSame([], $tenantQueries, 'Entitlement must be checked on central before tenant initialization.');
    }

    public function test_tenant_product_routes_require_read_and_write_scopes(): void
    {
        $pair = $this->attachTenantPrincipals($this->createProvisionedTenantPair('scope'));
        $productId = 'scope-product-' . $pair['suffix'];

        Tenancy::initialize($pair['tenantA']);
        try {
            DB::connection('tenant')->table('products')->insert([
                'id' => $productId,
                'name' => 'Scope proof fixture',
                'price' => 2500,
                'is_active' => true,
                'requires_review' => false,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        } finally {
            Tenancy::end();
            DB::purge('tenant');
        }

        $readOnlyConfigToken = $pair['userA']
            ->createToken('config-only-' . $pair['suffix'], ['config:read'])
            ->plainTextToken;

        $readDenied = $this->requestOnHost(
            'GET',
            $pair['hostA'],
            '/tenant/products',
            $readOnlyConfigToken,
            ['X-Device-ID' => $pair['deviceAId']]
        );
        $this->assertSame(403, $readDenied->getStatusCode());

        $writeDenied = $this->requestOnHost(
            'PATCH',
            $pair['hostA'],
            '/tenant/products/' . $productId,
            $readOnlyConfigToken,
            ['X-Device-ID' => $pair['deviceAId']],
            ['price' => 1]
        );
        $this->assertSame(403, $writeDenied->getStatusCode());

        Tenancy::initialize($pair['tenantA']);
        try {
            $this->assertSame(
                2500,
                (int) DB::connection('tenant')->table('products')->where('id', $productId)->value('price')
            );
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
        $this->flushHeaders();
        $requestHeaders = array_merge(['Host' => $host, 'Accept' => 'application/json'], $headers);
        if ($token !== null) {
            $requestHeaders['Authorization'] = 'Bearer ' . $token;
        }

        try {
            return $this->withHeaders($requestHeaders)->json($method, $uri, $payload);
        } finally {
            $this->flushHeaders();
        }
    }
}
