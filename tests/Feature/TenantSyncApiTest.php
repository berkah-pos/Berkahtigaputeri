<?php

namespace Tests\Feature;

use App\Models\Central\User;
use App\Services\TenantRuntimeCredentialResolver;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Tests\TestCase;

class TenantSyncApiTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->assertSame('pgsql', DB::connection('central')->getDriverName());
        // CI migrations have already created disposable central and tenant schemas.
        // The refresh trait would drop the central schema and break later API tests.
        DB::connection('central')->beginTransaction();
        // The test provider resolves only the explicit fixture reference to the
        // current disposable tenant DB password. No real secret store is used.
        $this->app->instance(
            TenantRuntimeCredentialResolver::class,
            new class implements TenantRuntimeCredentialResolver {
                public function resolve(string $tenantId, string $secretReference): string
                {
                    if ($secretReference !== 'ci-secret-ref://tenant/'.$tenantId.'/runtime') {
                        throw new \RuntimeException('Unexpected disposable test secret reference.');
                    }

                    return (string) config('database.connections.tenant.password');
                }
            }
        );
    }

    protected function tearDown(): void
    {
        $connection = DB::connection('central');
        if ($connection->transactionLevel() > 0) {
            $connection->rollBack();
        }
        parent::tearDown();
    }


    public function test_authenticated_device_sync_is_server_bound_idempotent_and_conflict_safe(): void
    {
        [, , , $bearer] = $this->identityFixture(true);
        $productId = 'sync-product-'.Str::lower(Str::ulid());
        $eventId = 'outbox:product:'.Str::lower(Str::ulid());
        $event = [
            'event_id' => $eventId,
            'entity_type' => 'product',
            'entity_id' => $productId,
            'payload' => [
                'event_id' => $eventId,
                'event_type' => 'product',
                'payload_version' => 1,
                'entity_id' => $productId,
                'product' => [
                    'id' => $productId,
                    'sku' => 'SKU-'.Str::upper(Str::random(8)),
                    'name_id' => 'Produk sinkronisasi',
                    'barcode' => null,
                    'price' => 12000,
                    'ppn_exempt' => false,
                    'track_expiry' => false,
                    'min_shelf_life_days' => 0,
                    'requires_review' => false,
                    'is_active' => true,
                ],
            ],
        ];

        $accepted = $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['app_version' => 'test-1', 'events' => [$event]]);
        $accepted->assertOk()->assertJsonPath('results.0.status', 'accepted');
        $this->assertDatabaseHas('products', [
            'id' => $productId,
            'name' => 'Produk sinkronisasi',
            'price' => 12000,
        ], 'tenant');

        $replayed = $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$event]]);
        $replayed->assertOk()->assertJsonPath('results.0.status', 'replayed');

        $event['payload']['product']['price'] = 13000;
        $conflict = $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$event]]);
        $conflict->assertOk()->assertJsonPath('results.0.status', 'conflict');

        $mismatch = $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', [
                'device_id' => hash('sha256', 'different-device'),
                'events' => [[
                    'event_id' => 'outbox:product:device-mismatch',
                    'entity_type' => 'product',
                    'entity_id' => $productId.'-2',
                    'payload' => [
                        'event_id' => 'outbox:product:device-mismatch',
                        'event_type' => 'product',
                        'payload_version' => 1,
                        'entity_id' => $productId.'-2',
                        'product' => [
                            'id' => $productId.'-2',
                            'sku' => 'SKU-MISMATCH',
                            'name_id' => 'Must not be accepted',
                            'price' => 1,
                            'ppn_exempt' => false,
                        ],
                    ],
                ]],
            ]);
        $mismatch->assertForbidden()->assertJsonPath('error.code', 'device_identity_mismatch');
    }

    public function test_positive_cost_receipt_without_counter_account_is_rejected_without_server_writes(): void
    {
        [, , , $bearer] = $this->identityFixture(true);
        $productId = 'receipt-product-'.Str::lower(Str::ulid());
        $productEventId = 'outbox:product:'.Str::lower(Str::ulid());
        $receiptEventId = 'outbox:inventory_receipt:'.Str::lower(Str::ulid());
        $productPayload = [
            'event_id' => $productEventId,
            'event_type' => 'product',
            'payload_version' => 1,
            'entity_id' => $productId,
            'product' => [
                'id' => $productId,
                'sku' => 'SKU-'.Str::upper(Str::random(8)),
                'name_id' => 'Receipt policy test',
                'barcode' => null,
                'price' => 12000,
                'ppn_exempt' => false,
                'track_expiry' => false,
                'min_shelf_life_days' => 0,
                'requires_review' => false,
                'is_active' => true,
            ],
        ];
        $receiptPayload = [
            'event_id' => $receiptEventId,
            'event_type' => 'inventory_receipt',
            'payload_version' => 1,
            'entity_id' => $productId,
            'receipt' => [
                'product_id' => $productId,
                'lot_id' => 'LOT-'.Str::lower(Str::ulid()),
                'cost_layer_id' => 'COST-'.Str::lower(Str::ulid()),
                'quantity' => 2,
                'unit_cost' => 12000,
                'batch_no' => 'BATCH-'.Str::upper(Str::random(8)),
                'expiry_date' => null,
                'acquired_at_utc' => now()->utc()->toIso8601String(),
                'timezone' => 'Asia/Jakarta',
                'counter_account_code' => null,
            ],
        ];

        $response = $this->withHeader('Authorization', 'Bearer '.$bearer)->postJson('/api/v1/sync', [
            'events' => [
                [
                    'event_id' => $productEventId,
                    'entity_type' => 'product',
                    'entity_id' => $productId,
                    'payload' => $productPayload,
                ],
                [
                    'event_id' => $receiptEventId,
                    'entity_type' => 'inventory_receipt',
                    'entity_id' => $productId,
                    'payload' => $receiptPayload,
                ],
            ],
        ]);

        $response->assertOk()
            ->assertJsonPath('results.0.status', 'accepted')
            ->assertJsonPath('results.1.status', 'conflict');
        $response->assertJsonPath(
            'results.1.message',
            'Akun lawan penerimaan wajib dipilih: kas, QRIS, transfer bank, atau utang supplier.'
        );
        $this->assertDatabaseMissing('inventory_lots', ['id' => $receiptPayload['receipt']['lot_id']], 'tenant');
        $this->assertDatabaseMissing('journal_entries', ['source_event_id' => $receiptEventId], 'tenant');
        $this->assertDatabaseMissing('sync_receipts', ['event_id' => $receiptEventId], 'tenant');
    }

    public function test_sync_fails_closed_until_a_tenant_runtime_connection_is_registered(): void
    {
        [, , , $bearer] = $this->identityFixture(false);
        $eventId = 'outbox:product:unregistered-'.Str::lower(Str::ulid());
        $productId = 'unregistered-'.Str::lower(Str::ulid());

        $response = $this->withHeader('Authorization', 'Bearer '.$bearer)->postJson('/api/v1/sync', [
            'events' => [[
                'event_id' => $eventId,
                'entity_type' => 'product',
                'entity_id' => $productId,
                'payload' => [
                    'event_id' => $eventId,
                    'event_type' => 'product',
                    'payload_version' => 1,
                    'entity_id' => $productId,
                    'product' => [
                        'id' => $productId,
                        'sku' => 'SKU-UNREGISTERED',
                        'name_id' => 'Unregistered',
                        'price' => 100,
                        'ppn_exempt' => false,
                    ],
                ],
            ]],
        ]);

        $response->assertStatus(503)->assertJsonPath('error.code', 'tenant_database_not_provisioned');
        $this->assertDatabaseMissing('products', ['id' => $productId], 'tenant');
    }

    /** @return array{string,string,User,string} */
    private function identityFixture(bool $registerDatabase): array
    {
        $now = now();
        $tenantId = (string) Str::ulid();
        $deviceId = hash('sha256', (string) Str::ulid());
        $deviceSecretHash = hash('sha256', 'test-device-secret-'.Str::random(16));

        DB::connection('central')->table('tenants')->insert([
            'id' => $tenantId,
            'data' => json_encode(['name' => 'Sync test tenant'], JSON_THROW_ON_ERROR),
            'template_id' => 'BASIC',
            'status' => 'active',
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $user = User::query()->create([
            'name' => 'Sync Test User',
            'email' => 'sync-'.Str::lower(Str::ulid()).'@example.test',
            'password' => Hash::make(Str::random(32)),
            'tenant_id' => $tenantId,
            'is_active' => true,
        ]);

        DB::connection('central')->table('tenant_memberships')->insert([
            'user_id' => $user->id,
            'tenant_id' => $tenantId,
            'role' => 'owner',
            'status' => 'active',
            'joined_at' => $now,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        DB::connection('central')->table('subscriptions')->insert([
            'tenant_id' => $tenantId,
            'plan' => 'trial',
            'status' => 'trial',
            'expires_at' => null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        DB::connection('central')->table('device_registry')->insert([
            'device_id' => $deviceId,
            'tenant_id' => $tenantId,
            'owner_user_id' => $user->id,
            'status' => 'active',
            'registered_at' => $now,
            'device_name' => 'test-device',
            'platform' => 'android',
            'device_secret_hash' => $deviceSecretHash,
            'revoked_at' => null,
            'last_seen_at' => null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $token = $user->createToken('sync-test:'.$deviceId, ['*']);
        $token->accessToken->forceFill([
            'tenant_id' => $tenantId,
            'device_id' => $deviceId,
            'expires_at' => now()->addHour(),
        ])->save();

        if ($registerDatabase) {
            $tenantConnection = (array) config('database.connections.tenant', []);
            DB::connection('central')->table('tenant_database_registry')->insert([
                'tenant_id' => $tenantId,
                'database_name' => $tenantConnection['database'],
                'runtime_username' => $tenantConnection['username'],
                'runtime_secret_ref' => 'ci-secret-ref://tenant/'.$tenantId.'/runtime',
                'status' => 'active',
                'provisioned_at' => $now,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }

        return [$tenantId, $deviceId, $user, $token->plainTextToken];
    }
}
