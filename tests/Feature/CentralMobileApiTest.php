<?php

namespace Tests\Feature;

use App\Models\Central\User;
use App\Services\TenantDatabaseRunner;
use Closure;
use Illuminate\Database\Connection;
use Illuminate\Foundation\Testing\TestResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Tests\TestCase;

class CentralMobileApiTest extends TestCase
{
    private ?Connection $tenantFixtureDb = null;
    private string $tenantId;
    private string $deviceId;
    private string $email;
    private User $user;
    private bool $originalGlobalConfigExists = false;
    /** @var array<string, mixed> */
    private array $originalGlobalConfig = [];
    private bool $originalBasicTemplateExists = false;
    /** @var array<string, mixed> */
    private array $originalBasicTemplate = [];
    /** @var list<string> */
    private array $additionalTenantIds = [];

    protected function setUp(): void
    {
        parent::setUp();

        $central = DB::connection('central');
        $fixture = DB::connection('central_migrator');

        $globalBefore = $fixture->table('global_configs')->where('key', 'global')->first();
        $this->originalGlobalConfigExists = $globalBefore !== null;
        $this->originalGlobalConfig = $globalBefore === null ? [] : (array) $globalBefore;
        $templateBefore = $fixture->table('templates')->where('id', 'BASIC')->first();
        $this->originalBasicTemplateExists = $templateBefore !== null;
        $this->originalBasicTemplate = $templateBefore === null ? [] : (array) $templateBefore;

        $central->beginTransaction();

        $suffix = str_replace('-', '', (string) Str::uuid());
        $this->tenantId = 'test_tenant_'.$suffix;
        $this->deviceId = 'test_device_'.$suffix;
        $this->email = 'api-'.$suffix.'@example.test';

        $now = now();
        // Seed identity and entitlement rows with the disposable migration role.
        // The application-facing central connection intentionally has SELECT-only
        // access to users, memberships, and subscriptions.
        $fixture->table('tenants')->insert([
            'id' => $this->tenantId,
            'data' => json_encode(['test_fixture' => true], JSON_THROW_ON_ERROR),
            'template_id' => 'BASIC',
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $fixture->table('subscriptions')->insert([
            'tenant_id' => $this->tenantId,
            'plan' => 'basic',
            'status' => 'trial',
            'expires_at' => now()->addDays(14),
            'provider_reference' => null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $fixture->table('global_configs')->updateOrInsert(
            ['key' => 'global'],
            [
                'config' => json_encode(['origin' => 'global', 'nested' => ['keep' => true, 'choice' => 'global']], JSON_THROW_ON_ERROR),
                'version' => 1,
                'created_at' => $now,
                'updated_at' => $now,
            ]
        );
        $fixture->table('templates')->updateOrInsert(
            ['id' => 'BASIC'],
            [
                'config' => json_encode(['origin' => 'template', 'template_only' => true, 'nested' => ['template' => true, 'choice' => 'template']], JSON_THROW_ON_ERROR),
                'version' => 1,
                'created_at' => $now,
                'updated_at' => $now,
            ]
        );
        $fixture->table('tenant_configs')->insert([
            'tenant_id' => $this->tenantId,
            'service' => null,
            'service_scope' => '__base__',
            'template_id' => 'BASIC',
            'config' => json_encode(['origin' => 'tenant', 'tenant_only' => true, 'nested' => ['base' => true, 'choice' => 'tenant']], JSON_THROW_ON_ERROR),
            'version' => 2,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $fixture->table('tenant_configs')->insert([
            'tenant_id' => $this->tenantId,
            'service' => 'pos',
            'service_scope' => 'pos',
            'template_id' => null,
            'config' => json_encode(['origin' => 'pos', 'service_only' => 'pos', 'nested' => ['service' => true, 'choice' => 'pos']], JSON_THROW_ON_ERROR),
            'version' => 3,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $fixture->table('tenant_configs')->insert([
            'tenant_id' => $this->tenantId,
            'service' => 'akuntansi',
            'service_scope' => 'akuntansi',
            'template_id' => null,
            'config' => json_encode(['accounting_only' => 'must_not_leak'], JSON_THROW_ON_ERROR),
            'version' => 4,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $fixture->table('tenant_services')->insert([
            ['tenant_id' => $this->tenantId, 'service' => 'pos', 'enabled' => true, 'created_at' => $now, 'updated_at' => $now],
            ['tenant_id' => $this->tenantId, 'service' => 'akuntansi', 'enabled' => true, 'created_at' => $now, 'updated_at' => $now],
        ]);

        $this->user = $this->createFixtureUser([
            'name' => 'API Test',
            'email' => $this->email,
            'password' => Hash::make('Test-Passphrase-2026!'),
            'tenant_id' => $this->tenantId,
            'is_super_admin' => false,
            'is_active' => true,
        ]);

        $fixture->table('tenant_memberships')->insert([
            'tenant_id' => $this->tenantId,
            'user_id' => $this->user->id,
            'role' => 'owner',
            'status' => 'active',
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $fixture->table('device_registry')->insert([
            'device_id' => $this->deviceId,
            'tenant_id' => $this->tenantId,
            'owner_user_id' => $this->user->id,
            'status' => 'active',
            'registered_at' => $now,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $fixture->table('device_configs')->insert([
            'device_id' => $this->deviceId,
            'tenant_id' => $this->tenantId,
            'config' => json_encode(['device_only' => true, 'nested' => ['device' => true]], JSON_THROW_ON_ERROR),
            'version' => 5,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
    }

    protected function tearDown(): void
    {
        if ($this->tenantFixtureDb !== null) {
            while ($this->tenantFixtureDb->transactionLevel() > 0) {
                $this->tenantFixtureDb->rollBack();
            }
        }

        $central = DB::connection('central');
        if ($central->transactionLevel() > 0) {
            $central->rollBack();
        }

        // Fixture identity rows were committed through central_migrator so the
        // restricted application connection could exercise real authorization.
        $fixture = DB::connection('central_migrator');
        $userIds = $fixture->table('users')
            ->where('tenant_id', $this->tenantId)
            ->pluck('id')
            ->all();
        if ($userIds !== []) {
            $fixture->table('personal_access_tokens')
                ->where('tokenable_type', User::class)
                ->whereIn('tokenable_id', $userIds)
                ->delete();
        }
        // Remove fixture rows committed through the migrator connection.
        // Delete dependants before device/tenant rows because the FK is composite.
        $fixture->table('device_configs')->where('tenant_id', $this->tenantId)->delete();
        $fixture->table('device_registry')->where('tenant_id', $this->tenantId)->delete();
        $fixture->table('tenant_configs')->where('tenant_id', $this->tenantId)->delete();
        $fixture->table('tenant_services')->where('tenant_id', $this->tenantId)->delete();
        foreach ($this->additionalTenantIds as $additionalTenantId) {
            $fixture->table('device_configs')->where('tenant_id', $additionalTenantId)->delete();
            $fixture->table('device_registry')->where('tenant_id', $additionalTenantId)->delete();
            $fixture->table('tenant_configs')->where('tenant_id', $additionalTenantId)->delete();
            $fixture->table('tenant_services')->where('tenant_id', $additionalTenantId)->delete();
            $fixture->table('subscriptions')->where('tenant_id', $additionalTenantId)->delete();
            $fixture->table('tenants')->where('id', $additionalTenantId)->delete();
        }
        $fixture->table('users')->where('tenant_id', $this->tenantId)->delete();
        $fixture->table('subscriptions')->where('tenant_id', $this->tenantId)->delete();
        $fixture->table('tenants')->where('id', $this->tenantId)->delete();

        // Restore shared workbook-backed fixture rows so later tests see the
        // original imported canonical values, not the synthetic precedence values.
        $fixture->table('global_configs')->where('key', 'global')->delete();
        if ($this->originalGlobalConfigExists) {
            $fixture->table('global_configs')->insert($this->originalGlobalConfig);
        }
        $fixture->table('templates')->where('id', 'BASIC')->delete();
        if ($this->originalBasicTemplateExists) {
            $fixture->table('templates')->insert($this->originalBasicTemplate);
        }

        parent::tearDown();
    }

    /** @param array<string, mixed> $attributes */
    private function createFixtureUser(array $attributes): User
    {
        $now = now();
        $attributes['created_at'] = $now;
        $attributes['updated_at'] = $now;

        $id = DB::connection('central_migrator')->table('users')->insertGetId($attributes);

        return User::on('central')->findOrFail($id);
    }

    public function test_login_issues_a_limited_lifetime_token_for_an_active_entitled_user(): void
    {
        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $this->email,
            'password' => 'Test-Passphrase-2026!',
            'device_name' => 'test-device',
        ]);

        $response->assertOk()
            ->assertJsonPath('token_type', 'Bearer')
            ->assertJsonPath('user.tenant_id', $this->tenantId)
            ->assertJsonStructure(['access_token', 'expires_at', 'user' => ['id', 'name', 'email', 'tenant_id']]);

        $this->assertNotEmpty($response->json('access_token'));
        $this->assertTrue(now()->lessThanOrEqualTo(\Illuminate\Support\Carbon::parse($response->json('expires_at'))));
    }

    public function test_login_rejects_a_user_without_active_tenant_membership(): void
    {
        DB::connection('central_migrator')->table('tenant_memberships')
            ->where('tenant_id', $this->tenantId)
            ->where('user_id', $this->user->id)
            ->update(['status' => 'revoked']);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $this->email,
            'password' => 'Test-Passphrase-2026!',
        ]);

        $response->assertForbidden()->assertJsonPath('error.code', 'tenant_membership_required');
        $this->assertSame(0, DB::connection('central')->table('personal_access_tokens')->count());
    }

    public function test_invalid_password_is_rejected_without_issuing_a_token(): void
    {
        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $this->email,
            'password' => 'wrong password',
        ]);

        $response->assertUnauthorized()->assertJsonPath('error.code', 'invalid_credentials');
        $this->assertSame(0, DB::connection('central')->table('personal_access_tokens')->count());
    }

    public function test_device_enrollment_binds_a_new_device_to_the_authenticated_tenant_and_user(): void
    {
        $newDevice = 'new_device_'.str_replace('-', '', (string) Str::uuid());

        $response = $this->actingAs($this->user, 'sanctum')
            ->postJson('/api/v1/devices/enroll', ['device_id' => $newDevice]);

        $response->assertCreated()
            ->assertJsonPath('device_id', $newDevice)
            ->assertJsonPath('tenant_id', $this->tenantId);

        $device = DB::connection('central')->table('device_registry')->where('device_id', $newDevice)->first();
        $this->assertNotNull($device);
        $this->assertSame($this->tenantId, $device->tenant_id);
        $this->assertSame((int) $this->user->id, (int) $device->owner_user_id);
        $this->assertSame('active', $device->status);
    }

    public function test_sync_rejects_an_unregistered_device_before_opening_a_tenant_database(): void
    {
        $unknownDevice = 'unknown_device_'.str_replace('-', '', (string) Str::uuid());

        $response = $this->actingAs($this->user, 'sanctum')
            ->postJson('/api/v1/sync', [
                'device_id' => $unknownDevice,
                'app_version' => 'test',
                'events' => [[
                    'event_id' => 'outbox:sale:tx-test-1',
                    'entity_type' => 'sale',
                    'entity_id' => 'sale:tx-test-1',
                    'payload' => [
                        'payload_version' => 1,
                        'event_id' => 'outbox:sale:tx-test-1',
                        'event_type' => 'sale',
                        'entity_id' => 'sale:tx-test-1',
                        'transaction_id' => 'tx-test-1',
                    ],
                ]],
            ]);

        $response->assertForbidden()->assertJsonPath('error.code', 'device_not_authorized');
    }

    public function test_device_enrollment_rejects_a_device_already_owned_by_another_tenant(): void
    {
        $otherTenant = 'other_tenant_'.str_replace('-', '', (string) Str::uuid());
        $this->additionalTenantIds[] = $otherTenant;
        $now = now();
        DB::connection('central_migrator')->table('tenants')->insert([
            'id' => $otherTenant,
            'data' => null,
            'template_id' => 'BASIC',
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        DB::connection('central_migrator')->table('device_registry')->insert([
            'device_id' => 'foreign_device_'.$otherTenant,
            'tenant_id' => $otherTenant,
            'owner_user_id' => $this->user->id,
            'status' => 'active',
            'registered_at' => $now,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $response = $this->actingAs($this->user, 'sanctum')
            ->postJson('/api/v1/devices/enroll', ['device_id' => 'foreign_device_'.$otherTenant]);

        $response->assertStatus(409)->assertJsonPath('error.code', 'device_already_bound');
    }

    public function test_effective_config_uses_five_layer_precedence_and_does_not_merge_another_service(): void
    {
        $response = $this->actingAs($this->user, 'sanctum')
            ->postJson('/api/v1/config/effective', [
                'device_id' => $this->deviceId,
                'service' => 'pos',
            ]);

        $response->assertOk()
            ->assertJsonPath('tenant_id', $this->tenantId)
            ->assertJsonPath('service', 'pos')
            ->assertJsonPath('config.origin', 'pos')
            ->assertJsonPath('config.nested.keep', true)
            ->assertJsonPath('config.nested.template', true)
            ->assertJsonPath('config.nested.base', true)
            ->assertJsonPath('config.nested.service', true)
            ->assertJsonPath('config.nested.device', true)
            ->assertJsonPath('config.nested.choice', 'pos')
            ->assertJsonPath('config.device_only', true)
            ->assertJsonPath('versions.device', 5)
            ->assertJsonStructure(['sha256']);
        $this->assertSame(64, strlen((string) $response->json('sha256')));
    }

    public function test_effective_config_fails_closed_when_service_is_disabled(): void
    {
        DB::connection('central_migrator')->table('tenant_services')
            ->where('tenant_id', $this->tenantId)
            ->where('service', 'pos')
            ->update(['enabled' => false]);

        $response = $this->actingAs($this->user, 'sanctum')
            ->postJson('/api/v1/config/effective', [
                'device_id' => $this->deviceId,
                'service' => 'pos',
            ]);

        $response->assertStatus(503)->assertJsonPath('error.code', 'effective_config_unavailable');
    }

    public function test_effective_config_rejects_another_users_device(): void
    {
        $otherUser = $this->createFixtureUser([
            'name' => 'Other User',
            'email' => 'other-'.str_replace('-', '', (string) Str::uuid()).'@example.test',
            'password' => Hash::make('Another-Passphrase-2026!'),
            'tenant_id' => $this->tenantId,
            'is_super_admin' => false,
            'is_active' => true,
        ]);
        DB::connection('central_migrator')->table('device_registry')
            ->where('device_id', $this->deviceId)
            ->update(['owner_user_id' => $otherUser->id]);

        $response = $this->actingAs($this->user, 'sanctum')
            ->postJson('/api/v1/config/effective', [
                'device_id' => $this->deviceId,
                'service' => 'pos',
            ]);

        $response->assertForbidden()->assertJsonPath('error.code', 'device_not_authorized');
    }

    public function test_sync_posts_and_replays_a_real_balanced_sale_with_local_fingerprint(): void
    {
        $tenantDb = DB::connection('tenant_migrator');
        $tenantDb->beginTransaction();
        $this->tenantFixtureDb = $tenantDb;

        // Exercise the complete controller transaction against the migrated
        // PostgreSQL 17 tenant schema. Privileged dynamic provisioning itself is
        // covered by the isolated provisioning/role CI gates.
        $this->app->instance(TenantDatabaseRunner::class, new class($tenantDb) extends TenantDatabaseRunner {
            public function __construct(private Connection $testConnection)
            {
            }

            public function run(string $tenantId, Closure $operation): mixed
            {
                return $this->testConnection->transaction(
                    fn () => $operation($this->testConnection),
                    3
                );
            }
        });

        $suffix = substr(str_replace('-', '', (string) Str::uuid()), 0, 12);
        $transactionId = 'sync-' . $suffix;
        $saleId = 'sale:' . $transactionId;
        $eventId = 'outbox:sale:' . $transactionId;
        $productId = 'sync-product-' . $suffix;
        $lotId = 'sync-lot-' . $suffix;
        $costLayerId = 'sync-cost-' . $suffix;
        $occurredAt = '2026-10-21T03:00:00.000000Z';
        $businessDate = '2026-10-21';
        $createdAt = now();

        $tenantDb->table('products')->insert([
            'id' => $productId,
            'sku' => 'SYNC-' . $suffix,
            'barcode' => null,
            'name' => 'Integration test product',
            'category_id' => null,
            'price' => 10000.00,
            'requires_review' => false,
            'is_active' => true,
            'stock_qty' => 2,
            'ppn_exempt' => true,
            'track_expiry' => false,
            'min_shelf_life_days' => 0,
            'created_at' => $createdAt,
            'updated_at' => $createdAt,
        ]);
        $tenantDb->table('inventory_lots')->insert([
            'id' => $lotId,
            'product_id' => $productId,
            'batch_code' => 'BATCH-' . $suffix,
            'expires_at' => null,
            'quantity_received' => 2,
            'quantity_remaining' => 2,
            'unit_cost' => 4000.00,
            'received_at' => $occurredAt,
            'reserved_qty' => 0,
            'status' => 'saleable',
            'created_at' => $createdAt,
            'updated_at' => $createdAt,
        ]);
        $tenantDb->table('inventory_cost_layers')->insert([
            'id' => $costLayerId,
            'product_id' => $productId,
            'lot_id' => $lotId,
            'original_qty' => 2,
            'remaining_qty' => 2,
            'unit_cost' => 4000.00,
            'acquired_at' => $occurredAt,
            'created_at' => $createdAt,
            'updated_at' => $createdAt,
        ]);

        // Flutter stores canonical request JSON in this field, not a digest.
        $fingerprint = json_encode([
            'transactionId' => $transactionId,
            'method' => 'cash',
            'occurredAtUtc' => $occurredAt,
            'transactionDiscountAmount' => 0,
            'reservationId' => null,
            'timezone' => 'Asia/Jakarta',
            'lines' => [[
                'productId' => $productId,
                'quantity' => 1,
                'itemDiscountAmount' => 0,
            ]],
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
        $this->assertGreaterThan(64, strlen($fingerprint));

        $event = [
            'event_id' => $eventId,
            'entity_type' => 'sale',
            'entity_id' => $saleId,
            'payload' => [
                'payload_version' => 1,
                'event_id' => $eventId,
                'event_type' => 'sale',
                'entity_id' => $saleId,
                'transaction_id' => $transactionId,
                'sale' => [
                    'id' => $saleId,
                    'transaction_id' => $transactionId,
                    'occurred_at_utc' => $occurredAt,
                    'timezone' => 'Asia/Jakarta',
                    'request_fingerprint' => $fingerprint,
                    'payment_method' => 'cash',
                    'business_date' => $businessDate,
                    'gross_amount' => 10000,
                    'item_discount_amount' => 0,
                    'transaction_discount_amount' => 0,
                    'discount_amount' => 0,
                    'taxable_dpp' => 0,
                    'exempt_dpp' => 10000,
                    'dpp' => 10000,
                    'ppn_amount' => 0,
                    'grand_total' => 10000,
                    'cogs_amount' => 4000,
                ],
                'items' => [[
                    'id' => $saleId . ':item:0',
                    'sale_id' => $saleId,
                    'line_no' => 0,
                    'product_id' => $productId,
                    'quantity' => 1,
                    'unit_price' => 10000,
                    'gross_amount' => 10000,
                    'item_discount_amount' => 0,
                    'transaction_discount_amount' => 0,
                    'discount_amount' => 0,
                    'dpp' => 10000,
                    'ppn_exempt' => true,
                    'cogs_amount' => 4000,
                    'allocations' => [[
                        'allocation_no' => 0,
                        'lot_id' => $lotId,
                        'quantity' => 1,
                    ]],
                    'cost_consumptions' => [[
                        'consumption_no' => 0,
                        'cost_layer_id' => $costLayerId,
                        'quantity' => 1,
                        'unit_cost' => 4000,
                        'total_cost' => 4000,
                    ]],
                ]],
                'journal' => [
                    'id' => 'journal:sale:' . $transactionId,
                    'transaction_id' => $transactionId,
                    'business_date' => $businessDate,
                    'lines' => [
                        ['line_no' => 0, 'account_code' => '1-1010', 'debit' => 10000, 'credit' => 0],
                        ['line_no' => 1, 'account_code' => '4-4010', 'debit' => 0, 'credit' => 10000],
                        ['line_no' => 2, 'account_code' => '5-5010', 'debit' => 4000, 'credit' => 0],
                        ['line_no' => 3, 'account_code' => '1-1040', 'debit' => 0, 'credit' => 4000],
                    ],
                ],
            ],
        ];

        $response = $this->actingAs($this->user, 'sanctum')->postJson('/api/v1/sync', [
            'device_id' => $this->deviceId,
            'app_version' => 'integration-test',
            'events' => [$event],
        ]);
        $this->assertSame('accepted', $response->json('results.0.status'), json_encode($response->json(), JSON_UNESCAPED_SLASHES));
        $this->assertSame($eventId, $response->json('results.0.receipt_id'));

        $sale = $tenantDb->table('sales')->where('id', $saleId)->first();
        $this->assertNotNull($sale);
        $this->assertSame($fingerprint, $sale->request_fingerprint);
        $this->assertSame('posted', $tenantDb->table('journal_entries')
            ->where('id', 'journal:sale:' . $transactionId)->value('status'));
        $this->assertSame(1, $tenantDb->table('accounting_events')->where('event_id', $eventId)->count());
        $this->assertEquals(1.0, (float) $tenantDb->table('products')->where('id', $productId)->value('stock_qty'));
        $this->assertEquals(1.0, (float) $tenantDb->table('inventory_lots')->where('id', $lotId)->value('quantity_remaining'));
        $this->assertEquals(1.0, (float) $tenantDb->table('inventory_cost_layers')->where('id', $costLayerId)->value('remaining_qty'));

        $replay = $this->actingAs($this->user, 'sanctum')->postJson('/api/v1/sync', [
            'device_id' => $this->deviceId,
            'app_version' => 'integration-test',
            'events' => [$event],
        ]);
        $replay->assertOk()->assertJsonPath('results.0.status', 'replayed');
        $this->assertSame(1, $tenantDb->table('sales')->where('id', $saleId)->count());
        $this->assertSame(1, $tenantDb->table('journal_entries')
            ->where('id', 'journal:sale:' . $transactionId)->count());
        $this->assertSame(1, $tenantDb->table('sync_receipts')->where('event_id', $eventId)->count());
    }


}
