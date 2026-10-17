<?php

namespace Tests\Feature;

use App\Http\Middleware\HostDomainBoundary;
use App\Models\Central\User;
use App\Services\TenantHostResolver;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Request as SymfonyRequest;
use Tests\TestCase;

class HostTenantBoundaryPostgresTest extends TestCase
{
    /** @var list<string> */
    private array $createdTables = [];

    /** @var list<string> */
    private array $tenantIds = [];

    /** @var list<string> */
    private array $domainNames = [];

    /** @var list<string> */
    private array $deviceIds = [];

    /** @var list<int> */
    private array $userIds = [];

    protected function setUp(): void
    {
        parent::setUp();

        $this->assertSame('pgsql', config('database.connections.central.driver'));
        $this->assertSame(
            'berkahpos_central_ci',
            config('database.connections.central.database'),
            'Security feature tests may only mutate the disposable central CI database.',
        );

        $version = (int) DB::connection('central')->selectOne('SHOW server_version_num')->server_version_num;
        $this->assertGreaterThanOrEqual(170000, $version, 'These feature tests require real PostgreSQL 17.');

        config(['app.url' => 'https://central.example.test']);
        SymfonyRequest::setTrustedProxies([], 0);
        $this->ensureFixtureSchema();
    }

    protected function tearDown(): void
    {
        try {
            if (Schema::connection('central')->hasTable('device_registry')) {
                DB::connection('central')->table('device_registry')->whereIn('device_id', $this->deviceIds)->delete();
            }

            if (Schema::connection('central')->hasTable('tenant_services')) {
                DB::connection('central')->table('tenant_services')->whereIn('tenant_id', $this->tenantIds)->delete();
            }

            if (Schema::connection('central')->hasTable('subscriptions')) {
                DB::connection('central')->table('subscriptions')->whereIn('tenant_id', $this->tenantIds)->delete();
            }

            if (Schema::connection('central')->hasTable('domains')) {
                DB::connection('central')->table('domains')->whereIn('domain', $this->domainNames)->delete();
            }

            if (Schema::connection('central')->hasTable('personal_access_tokens') && $this->userIds !== []) {
                DB::connection('central')->table('personal_access_tokens')
                    ->where('tokenable_type', User::class)
                    ->whereIn('tokenable_id', $this->userIds)
                    ->delete();
            }

            if (Schema::connection('central')->hasTable('users') && $this->userIds !== []) {
                DB::connection('central')->table('users')->whereIn('id', $this->userIds)->delete();
            }

            if (Schema::connection('central')->hasTable('tenants')) {
                DB::connection('central')->table('tenants')->whereIn('id', $this->tenantIds)->delete();
            }

            foreach (array_reverse($this->createdTables) as $table) {
                Schema::connection('central')->dropIfExists($table);
            }
        } finally {
            SymfonyRequest::setTrustedProxies([], 0);
            parent::tearDown();
        }
    }

    public function test_central_and_tenant_route_groups_reject_the_wrong_host_class(): void
    {
        [, $domain] = $this->createTenant('central-boundary');

        $this->getJson('https://central.example.test/api/v1/platform-health')
            ->assertOk();

        $this->getJson('https://'.$domain.'/api/v1/platform-health')
            ->assertNotFound();

        $this->getJson('https://central.example.test/api/v1/tenant/context?service=POS')
            ->assertNotFound();
    }

    public function test_unknown_custom_and_malformed_hosts_fail_closed_without_host_details(): void
    {
        [, $domain] = $this->createTenant('host-not-found');

        $this->getJson('https://unknown-custom.example.test/api/v1/platform-health')
            ->assertNotFound()
            ->assertDontSee($domain);

        $request = Request::create('/', 'GET', [], [], [], [
            'HTTP_HOST' => 'tenant-a.example.test,evil.example.test',
        ]);

        $this->assertNull(app(TenantHostResolver::class)->resolve($request));
    }

    public function test_untrusted_forwarded_host_cannot_override_host_but_configured_proxy_can(): void
    {
        $this->withServerVariables(['REMOTE_ADDR' => '203.0.113.25'])
            ->withHeaders([
                'X-Forwarded-Host' => 'attacker.example.test',
            ])
            ->getJson('https://central.example.test/api/v1/platform-health')
            ->assertNotFound();

        SymfonyRequest::setTrustedProxies(['10.10.0.2'], SymfonyRequest::HEADER_X_FORWARDED_HOST);

        $this->withServerVariables(['REMOTE_ADDR' => '10.10.0.2'])
            ->withHeaders([
                'X-Forwarded-Host' => 'central.example.test',
            ])
            ->getJson('https://internal-proxy.example.test/api/v1/platform-health')
            ->assertOk();
    }

    public function test_multi_value_forwarded_host_is_rejected_even_from_a_trusted_proxy(): void
    {
        SymfonyRequest::setTrustedProxies(['10.10.0.2'], SymfonyRequest::HEADER_X_FORWARDED_HOST);

        $this->withServerVariables(['REMOTE_ADDR' => '10.10.0.2'])
            ->withHeaders([
                'X-Forwarded-Host' => 'central.example.test,attacker.example.test',
            ])
            ->getJson('https://central.example.test/api/v1/platform-health')
            ->assertNotFound();
    }

    public function test_duplicated_host_parameters_in_forwarded_header_are_rejected(): void
    {
        SymfonyRequest::setTrustedProxies(['10.10.0.2'], 0);

        $this->withServerVariables(['REMOTE_ADDR' => '10.10.0.2'])
            ->withHeaders([
                'Forwarded' => 'for=192.0.2.60;host=central.example.test;host=attacker.example.test',
            ])
            ->getJson('https://central.example.test/api/v1/platform-health')
            ->assertNotFound();
    }

    public function test_active_membership_device_subscription_and_service_entitlement_allow_only_server_checked_context(): void
    {
        [$tenantId, $domain] = $this->createTenant('member-a');
        $user = $this->createUser($tenantId);
        $deviceId = $this->createDevice($tenantId, (int) $user->getKey());
        $token = $user->createToken('security-feature-test')->plainTextToken;

        $this->withHeaders(['X-Device-ID' => $deviceId])
            ->withToken($token)
            ->getJson('https://'.$domain.'/api/v1/tenant/context?service=POS')
            ->assertOk()
            ->assertExactJson([
                'tenant_id' => $tenantId,
                'device_id' => $deviceId,
                'service' => 'POS',
            ]);
    }

    public function test_publishable_key_is_not_authentication_and_missing_identity_is_rejected(): void
    {
        [, $domain] = $this->createTenant('no-publishable-key');
        $user = $this->createUser($this->tenantIds[0]);
        $deviceId = $this->createDevice($this->tenantIds[0], (int) $user->getKey());

        $this->withHeaders([
            'X-Device-ID' => $deviceId,
            'X-Publishable-Key' => 'public-but-not-an-identity',
        ])
            ->getJson('https://'.$domain.'/api/v1/tenant/context?service=POS')
            ->assertUnauthorized();
    }

    public function test_client_tenant_and_domain_selectors_cannot_override_the_host_resolved_tenant(): void
    {
        [$tenantA, $domainA] = $this->createTenant('selector-a');
        [$tenantB, $domainB] = $this->createTenant('selector-b');
        $user = $this->createUser($tenantA);
        $deviceId = $this->createDevice($tenantA, (int) $user->getKey());
        $token = $user->createToken('selector-test')->plainTextToken;

        $this->withHeaders(['X-Device-ID' => $deviceId, 'X-Tenant-ID' => $tenantB])
            ->withToken($token)
            ->getJson('https://'.$domainA.'/api/v1/tenant/context?service=POS')
            ->assertNotFound()
            ->assertDontSee($tenantB);

        $this->withHeaders(['X-Device-ID' => $deviceId, 'X-Tenant-ID' => $tenantA])
            ->withToken($token)
            ->getJson('https://'.$domainA.'/api/v1/tenant/context?service=POS&domain='.urlencode($domainB))
            ->assertNotFound()
            ->assertDontSee($domainB);

        $this->withHeaders(['X-Device-ID' => $deviceId, 'X-Tenant-ID' => $tenantA])
            ->withToken($token)
            ->getJson('https://'.$domainA.'/api/v1/tenant/context?service=POS&tenant_id='.urlencode($tenantB))
            ->assertNotFound()
            ->assertDontSee($tenantB);
    }

    public function test_device_selector_must_be_owned_by_the_authenticated_user_and_resolved_tenant(): void
    {
        [$tenantA, $domainA] = $this->createTenant('device-owner-a');
        [$tenantB] = $this->createTenant('device-owner-b');
        $userA = $this->createUser($tenantA);
        $userB = $this->createUser($tenantB);
        $deviceB = $this->createDevice($tenantB, (int) $userB->getKey());
        $tokenA = $userA->createToken('device-owner-a')->plainTextToken;

        $this->withHeaders(['X-Device-ID' => $deviceB])
            ->withToken($tokenA)
            ->getJson('https://'.$domainA.'/api/v1/tenant/context?service=POS')
            ->assertNotFound()
            ->assertDontSee($tenantB);
    }

    public function test_malformed_array_selectors_and_invalid_device_ids_fail_closed(): void
    {
        [$tenantId, $domain] = $this->createTenant('malformed-selectors');
        $user = $this->createUser($tenantId);
        $deviceId = $this->createDevice($tenantId, (int) $user->getKey());
        $token = $user->createToken('malformed-selectors')->plainTextToken;

        $this->withHeaders(['X-Device-ID' => $deviceId])
            ->withToken($token)
            ->getJson('https://'.$domain.'/api/v1/tenant/context?service%5B%5D=POS')
            ->assertNotFound();

        $this->withHeaders(['X-Device-ID' => 'device A,device B'])
            ->withToken($token)
            ->getJson('https://'.$domain.'/api/v1/tenant/context?service=POS')
            ->assertNotFound();
    }

    public function test_inactive_membership_device_tenant_domain_subscription_and_entitlement_are_denied(): void
    {
        [$tenantId, $domain] = $this->createTenant('inactive-state');
        $user = $this->createUser($tenantId, false);
        $deviceId = $this->createDevice($tenantId, (int) $user->getKey());
        $token = $user->createToken('inactive-state')->plainTextToken;

        $this->tenantRequest($domain, $deviceId, $token)->assertNotFound();

        DB::connection('central')->table('users')->where('id', $user->getKey())->update(['is_active' => true]);
        DB::connection('central')->table('device_registry')->where('device_id', $deviceId)->update(['status' => 'pending']);
        $this->tenantRequest($domain, $deviceId, $token)->assertNotFound();

        DB::connection('central')->table('device_registry')->where('device_id', $deviceId)->update(['status' => 'active']);
        DB::connection('central')->table('subscriptions')->where('tenant_id', $tenantId)->update(['status' => 'cancelled']);
        $this->tenantRequest($domain, $deviceId, $token)->assertNotFound();

        DB::connection('central')->table('subscriptions')->where('tenant_id', $tenantId)->update([
            'status' => 'active',
            'expires_at' => now()->subMinute(),
        ]);
        $this->tenantRequest($domain, $deviceId, $token)->assertNotFound();

        DB::connection('central')->table('subscriptions')->where('tenant_id', $tenantId)->update([
            'status' => 'active',
            'expires_at' => now()->addDay(),
        ]);
        DB::connection('central')->table('tenant_services')
            ->where('tenant_id', $tenantId)
            ->where('service', 'POS')
            ->update(['enabled' => false]);
        $this->tenantRequest($domain, $deviceId, $token)->assertNotFound();

        DB::connection('central')->table('tenant_services')
            ->where('tenant_id', $tenantId)
            ->where('service', 'POS')
            ->update(['enabled' => true]);
        DB::connection('central')->table('tenants')->where('id', $tenantId)
            ->update(['data' => json_encode(['status' => 'suspended'])]);
        $this->tenantRequest($domain, $deviceId, $token)->assertNotFound();

        DB::connection('central')->table('tenants')->where('id', $tenantId)
            ->update(['data' => json_encode(['status' => 'ready'])]);
        $this->markDomainInactive($domain);
        $this->tenantRequest($domain, $deviceId, $token)->assertNotFound();
    }

    public function test_changed_domain_mapping_is_rechecked_on_the_next_request_without_cache(): void
    {
        [$tenantA, $domainA] = $this->createTenant('domain-change-a');
        [$tenantB] = $this->createTenant('domain-change-b');
        $userA = $this->createUser($tenantA);
        $deviceA = $this->createDevice($tenantA, (int) $userA->getKey());
        $tokenA = $userA->createToken('domain-change-a')->plainTextToken;

        $this->tenantRequest($domainA, $deviceA, $tokenA)->assertOk();

        // A stale cache entry, if any caller previously wrote one, must never decide routing.
        cache()->put('tenant:domain:'.$domainA, ['tenant_id' => $tenantA], 600);
        DB::connection('central')->table('domains')->where('domain', $domainA)->update(['tenant_id' => $tenantB]);

        $this->tenantRequest($domainA, $deviceA, $tokenA)
            ->assertNotFound()
            ->assertDontSee($tenantB);
    }

    public function test_overlapping_host_boundary_requests_keep_context_request_scoped(): void
    {
        [$tenantA, $domainA] = $this->createTenant('overlap-a');
        [$tenantB, $domainB] = $this->createTenant('overlap-b');

        $boundary = app(HostDomainBoundary::class);
        $requestA = Request::create('/', 'GET', [], [], [], ['HTTP_HOST' => $domainA]);
        $requestB = Request::create('/', 'GET', [], [], [], ['HTTP_HOST' => $domainB]);

        $boundary->handle($requestA, function (Request $activeA) use ($boundary, $requestB, $tenantA, $tenantB) {
            $this->assertSame($tenantA, $activeA->attributes->get('host_boundary')['tenant_id']);

            $boundary->handle($requestB, function (Request $activeB) use ($tenantB) {
                $this->assertSame($tenantB, $activeB->attributes->get('host_boundary')['tenant_id']);

                return response()->noContent();
            });

            // A remains A after B enters and exits the same middleware instance.
            $this->assertSame($tenantA, $activeA->attributes->get('host_boundary')['tenant_id']);

            return response()->noContent();
        });

        $this->assertFalse($requestA->attributes->has('host_boundary'));
        $this->assertFalse($requestB->attributes->has('host_boundary'));
    }

    public function test_shared_resolver_keeps_interleaved_tenant_resolutions_request_scoped(): void
    {
        [$tenantA, $domainA] = $this->createTenant('interleaved-a');
        [$tenantB, $domainB] = $this->createTenant('interleaved-b');
        $resolver = app(TenantHostResolver::class);
        $requestA = Request::create('/', 'GET', [], [], [], ['HTTP_HOST' => $domainA]);
        $requestB = Request::create('/', 'GET', [], [], [], ['HTTP_HOST' => $domainB]);

        $resolvedA = $resolver->resolve($requestA);
        $resolvedB = $resolver->resolve($requestB);

        $this->assertSame($tenantA, $resolvedA['tenant_id'] ?? null);
        $this->assertSame($tenantB, $resolvedB['tenant_id'] ?? null);
        $this->assertNotSame($resolvedA, $resolvedB);
    }

    private function tenantRequest(string $host, string $deviceId, string $token)
    {
        return $this->withHeaders(['X-Device-ID' => $deviceId])
            ->withToken($token)
            ->getJson('https://'.$host.'/api/v1/tenant/context?service=POS');
    }

    /**
     * @return array{0: string, 1: string}
     */
    private function createTenant(string $label, string $status = 'ready'): array
    {
        $tenantId = 'test-'.$label.'-'.Str::lower(Str::random(10));
        $domain = 'tenant-'.Str::lower($label).'-'.Str::lower(Str::random(8)).'.example.test';
        $now = now();

        DB::connection('central')->table('tenants')->insert([
            'id' => $tenantId,
            'data' => json_encode(['status' => $status]),
            'template_id' => 'BASIC',
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        DB::connection('central')->table('domains')->insert([
            'domain' => $domain,
            'tenant_id' => $tenantId,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        DB::connection('central')->table('subscriptions')->insert([
            'tenant_id' => $tenantId,
            'plan' => 'test',
            'status' => 'active',
            'expires_at' => now()->addDay(),
            'provider_reference' => null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        DB::connection('central')->table('tenant_services')->insert([
            'tenant_id' => $tenantId,
            'service' => 'POS',
            'enabled' => true,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $this->tenantIds[] = $tenantId;
        $this->domainNames[] = $domain;

        return [$tenantId, $domain];
    }

    private function createUser(string $tenantId, bool $active = true): User
    {
        $user = User::query()->create([
            'name' => 'Security Test User',
            'email' => Str::uuid().'@example.test',
            'password' => Hash::make(Str::random(32)),
            'tenant_id' => $tenantId,
            'is_super_admin' => false,
            'is_active' => $active,
        ]);

        $this->userIds[] = (int) $user->getKey();

        return $user;
    }

    private function createDevice(string $tenantId, int $ownerUserId, string $status = 'active'): string
    {
        $deviceId = 'device-'.Str::lower(Str::random(14));
        $now = now();

        DB::connection('central')->table('device_registry')->insert([
            'device_id' => $deviceId,
            'tenant_id' => $tenantId,
            'owner_user_id' => $ownerUserId,
            'status' => $status,
            'registered_at' => $now,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $this->deviceIds[] = $deviceId;

        return $deviceId;
    }

    private function markDomainInactive(string $domain): void
    {
        $schema = Schema::connection('central');

        if ($schema->hasColumn('domains', 'is_active')) {
            DB::connection('central')->table('domains')->where('domain', $domain)->update(['is_active' => false]);

            return;
        }

        if ($schema->hasColumn('domains', 'status')) {
            DB::connection('central')->table('domains')->where('domain', $domain)->update(['status' => 'suspended']);

            return;
        }

        // The current migration has no active/status column, so removing the mapping
        // is the supported revocation operation until the schema owner adds one.
        DB::connection('central')->table('domains')->where('domain', $domain)->delete();
    }

    private function ensureFixtureSchema(): void
    {
        $schema = Schema::connection('central');

        if (! $schema->hasTable('tenants')) {
            $schema->create('tenants', function (Blueprint $table): void {
                $table->string('id')->primary();
                $table->json('data')->nullable();
                $table->string('template_id', 40)->default('BASIC');
                $table->timestamps();
            });
            $this->createdTables[] = 'tenants';
        }

        if (! $schema->hasTable('domains')) {
            $schema->create('domains', function (Blueprint $table): void {
                $table->string('domain')->primary();
                $table->string('tenant_id');
                $table->timestamps();
            });
            $this->createdTables[] = 'domains';
        }

        if (! $schema->hasTable('users')) {
            $schema->create('users', function (Blueprint $table): void {
                $table->id();
                $table->string('name');
                $table->string('email')->unique();
                $table->timestamp('email_verified_at')->nullable();
                $table->string('password');
                $table->string('tenant_id')->nullable()->index();
                $table->boolean('is_super_admin')->default(false);
                $table->boolean('is_active')->default(true);
                $table->rememberToken();
                $table->timestamps();
            });
            $this->createdTables[] = 'users';
        }

        if (! $schema->hasTable('subscriptions')) {
            $schema->create('subscriptions', function (Blueprint $table): void {
                $table->id();
                $table->string('tenant_id')->index();
                $table->string('plan', 40)->default('trial');
                $table->string('status', 20)->default('trial');
                $table->timestamp('expires_at')->nullable();
                $table->string('provider_reference')->nullable();
                $table->timestamps();
            });
            $this->createdTables[] = 'subscriptions';
        }

        if (! $schema->hasTable('tenant_services')) {
            $schema->create('tenant_services', function (Blueprint $table): void {
                $table->string('tenant_id');
                $table->string('service', 20);
                $table->boolean('enabled')->default(false);
                $table->timestamps();
                $table->primary(['tenant_id', 'service']);
            });
            $this->createdTables[] = 'tenant_services';
        }

        if (! $schema->hasTable('device_registry')) {
            $schema->create('device_registry', function (Blueprint $table): void {
                $table->string('device_id', 150)->primary();
                $table->string('tenant_id')->index();
                $table->foreignId('owner_user_id')->nullable()->index();
                $table->string('status', 20)->default('pending');
                $table->timestamp('registered_at')->nullable();
                $table->timestamps();
            });
            $this->createdTables[] = 'device_registry';
        }

        if (! $schema->hasTable('personal_access_tokens')) {
            $schema->create('personal_access_tokens', function (Blueprint $table): void {
                $table->id();
                $table->morphs('tokenable');
                $table->string('name');
                $table->string('token', 64)->unique();
                $table->text('abilities')->nullable();
                $table->timestamp('last_used_at')->nullable();
                $table->timestamp('expires_at')->nullable();
                $table->timestamps();
            });
            $this->createdTables[] = 'personal_access_tokens';
        }
    }
}
