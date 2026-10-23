<?php

namespace Tests\Feature;

use App\Models\Central\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Tests\TestCase;

class TenantSyncApiTest extends TestCase
{
    use RefreshDatabase;

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
                'runtime_password_encrypted' => Crypt::encryptString((string) $tenantConnection['password']),
                'status' => 'active',
                'provisioned_at' => $now,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }

        return [$tenantId, $deviceId, $user, $token->plainTextToken];
    }
}
