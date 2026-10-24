<?php

namespace Tests\Feature;

use App\Models\Central\User;
use App\Services\TenantDatabaseRunner;
use App\Services\TenantRuntimeCredentialResolver;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
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

    public function test_product_status_sync_is_versioned_audited_and_rejects_stale_reactivation(): void
    {
        [, , $user, $bearer] = $this->identityFixture(true);
        $productId = 'status-product-'.Str::lower(Str::ulid());
        $makeEvent = static function (int $version, bool $active, ?array $statusChange = null) use ($productId): array {
            $eventId = 'outbox:product:'.Str::lower(Str::ulid());
            $product = [
                'id' => $productId,
                'sku' => 'SKU-STATUS-'.Str::upper(Str::random(6)),
                'name_id' => 'Lifecycle status test',
                'barcode' => null,
                'price' => 12000,
                'ppn_exempt' => false,
                'track_expiry' => false,
                'min_shelf_life_days' => 0,
                'requires_review' => false,
                'is_active' => $active,
                'version' => $version,
            ];
            if ($statusChange !== null) {
                $product['status_change'] = $statusChange;
            }

            return [
                'event_id' => $eventId,
                'entity_type' => 'product',
                'entity_id' => $productId,
                'payload' => [
                    'event_id' => $eventId,
                    'event_type' => 'product',
                    'payload_version' => 1,
                    'entity_id' => $productId,
                    'product' => $product,
                ],
            ];
        };

        $created = $makeEvent(1, true);
        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$created]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'accepted');
        $this->assertDatabaseHas('products', [
            'id' => $productId,
            'is_active' => true,
            'version' => 1,
        ], 'tenant');

        $deactivated = $makeEvent(2, false, [
            'from_active' => true,
            'to_active' => false,
            'reason' => 'Temporarily discontinued for test',
            'changed_at_utc' => now()->toIso8601String(),
        ]);
        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$deactivated]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'accepted')
            ->assertJsonPath('results.0.version', 2);
        $this->assertDatabaseHas('products', [
            'id' => $productId,
            'is_active' => false,
            'version' => 2,
        ], 'tenant');
        $this->assertDatabaseHas('product_status_audits', [
            'event_id' => $deactivated['event_id'],
            'product_id' => $productId,
            'version' => 2,
            'previous_is_active' => true,
            'is_active' => false,
            'reason' => 'Temporarily discontinued for test',
            'actor_user_id' => $user->id,
        ], 'tenant');

        // A distinct event ID carrying an old active revision must conflict,
        // not silently restore the product after the deactivation commit.
        $stale = $makeEvent(2, true);
        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$stale]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'conflict');
        $this->assertDatabaseHas('products', [
            'id' => $productId,
            'is_active' => false,
            'version' => 2,
        ], 'tenant');

        // Older clients may omit version on ordinary edits, but a legacy
        // payload that explicitly restores active=true is rejected.
        $legacyStale = $makeEvent(2, true);
        unset($legacyStale['payload']['product']['version']);
        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$legacyStale]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'conflict');
        $this->assertDatabaseHas('products', [
            'id' => $productId,
            'is_active' => false,
            'version' => 2,
        ], 'tenant');

        $reactivated = $makeEvent(3, true, [
            'from_active' => false,
            'to_active' => true,
            'reason' => 'Approved for sale again in test',
            'changed_at_utc' => now()->toIso8601String(),
        ]);
        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$reactivated]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'accepted')
            ->assertJsonPath('results.0.version', 3);
        $this->assertDatabaseHas('products', [
            'id' => $productId,
            'is_active' => true,
            'version' => 3,
        ], 'tenant');
        $this->assertSame(2, DB::connection('tenant')->table('product_status_audits')->where('product_id', $productId)->count());
    }

    public function test_product_status_change_requires_owner_or_manager_membership(): void
    {
        [$tenantId, , $user, $bearer] = $this->identityFixture(true);
        $productId = 'auth-product-'.Str::lower(Str::ulid());
        $makeEvent = static function (int $version, bool $active, ?array $statusChange = null) use ($productId): array {
            $eventId = 'outbox:product:'.Str::lower(Str::ulid());
            $product = [
                'id' => $productId,
                'sku' => 'SKU-AUTH-'.Str::upper(Str::random(6)),
                'name_id' => 'Lifecycle authorization test',
                'barcode' => null,
                'price' => 12000,
                'ppn_exempt' => false,
                'track_expiry' => false,
                'min_shelf_life_days' => 0,
                'requires_review' => false,
                'is_active' => $active,
                'version' => $version,
            ];
            if ($statusChange !== null) $product['status_change'] = $statusChange;
            return [
                'event_id' => $eventId,
                'entity_type' => 'product',
                'entity_id' => $productId,
                'payload' => [
                    'event_id' => $eventId,
                    'event_type' => 'product',
                    'payload_version' => 1,
                    'entity_id' => $productId,
                    'product' => $product,
                ],
            ];
        };

        $created = $makeEvent(1, true);
        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$created]])
            ->assertOk()->assertJsonPath('results.0.status', 'accepted');

        DB::connection('central')->table('tenant_memberships')
            ->where('user_id', $user->id)->where('tenant_id', $tenantId)
            ->update(['role' => 'cashier']);

        $deactivation = $makeEvent(2, false, [
            'from_active' => true,
            'to_active' => false,
            'reason' => 'Authorization regression test',
            'changed_at_utc' => now()->toIso8601String(),
        ]);
        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$deactivation]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'conflict')
            ->assertJsonPath('results.0.message',
                'Product status change rejected: active tenant membership role owner or manager is required.');

        $this->assertDatabaseHas('products', [
            'id' => $productId, 'is_active' => true, 'version' => 1,
        ], 'tenant');
        $this->assertDatabaseMissing('product_status_audits', [
            'event_id' => $deactivation['event_id'],
        ], 'tenant');
        $this->assertDatabaseMissing('sync_receipts', [
            'event_id' => $deactivation['event_id'],
        ], 'tenant');

        // The same durable event can be retried after an owner changes the
        // membership role to manager; authorization is re-evaluated at sync.
        DB::connection('central')->table('tenant_memberships')
            ->where('user_id', $user->id)->where('tenant_id', $tenantId)
            ->update(['role' => 'manager']);
        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$deactivation]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'accepted')
            ->assertJsonPath('results.0.version', 2);
        $this->assertDatabaseHas('products', [
            'id' => $productId, 'is_active' => false, 'version' => 2,
        ], 'tenant');
        $this->assertDatabaseHas('product_status_audits', [
            'event_id' => $deactivation['event_id'],
            'actor_user_id' => $user->id,
            'previous_is_active' => true,
            'is_active' => false,
        ], 'tenant');
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

    public function test_registry_cannot_redirect_a_tenant_to_another_tenants_database_or_role(): void
    {
        [$tenantId, , , $bearer] = $this->identityFixture(true);
        $otherTenantId = strtolower((string) Str::ulid());
        DB::connection('central')->table('tenant_database_registry')
            ->where('tenant_id', $tenantId)
            ->update([
                'database_name' => 'berkahpos_t_'.$otherTenantId,
                'runtime_username' => 'berkah_t_'.$otherTenantId.'_runtime',
            ]);

        $productId = 'cross-tenant-registry-'.Str::lower(Str::ulid());
        $eventId = 'outbox:product:'.Str::lower(Str::ulid());
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
                        'sku' => 'SKU-CROSS-TENANT',
                        'name_id' => 'Must remain uncommitted',
                        'price' => 100,
                        'ppn_exempt' => false,
                    ],
                ],
            ]],
        ]);

        $response->assertStatus(503)
            ->assertJsonPath('error.code', 'tenant_database_registry_invalid');
        $this->assertDatabaseMissing('products', ['id' => $productId], 'tenant');
    }

    public function test_secret_provider_exception_details_are_redacted_from_logs(): void
    {
        [$tenantId] = $this->identityFixture(true);

        $this->app->instance(
            TenantRuntimeCredentialResolver::class,
            new class implements TenantRuntimeCredentialResolver {
                public function resolve(string $tenantId, string $secretReference): string
                {
                    throw new \RuntimeException('provider-token=never-log-this-value');
                }
            }
        );

        Log::shouldReceive('warning')
            ->once()
            ->with(
                'Tenant runtime credential resolution failed.',
                \Mockery::on(static function (array $context) use ($tenantId): bool {
                    return ($context['tenant_id'] ?? null) === $tenantId
                        && ($context['exception_class'] ?? null) === \RuntimeException::class
                        && ! str_contains(json_encode($context, JSON_THROW_ON_ERROR), 'provider-token=never-log-this-value');
                })
            );

        try {
            app(TenantDatabaseRunner::class)->run($tenantId, static fn (): null => null);
            $this->fail('Credential resolution failure should block tenant database access.');
        } catch (\RuntimeException $exception) {
            $this->assertSame('tenant_database_credentials_unavailable', $exception->getMessage());
            $this->assertNull($exception->getPrevious());
            $this->assertStringNotContainsString('provider-token=never-log-this-value', $exception->getMessage());
        }
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

    public function test_partial_return_is_idempotent_creates_quarantine_stock_and_balanced_sales_return_journal(): void
    {
        [$tenantId, $deviceId, $user, $bearer] = $this->identityFixture(true);
        $fixture = $this->createPostedSaleFixture($deviceId, '2001-10-10', '2001-01-01', '2001-12-31');
        $returnId = 'return-test-'.Str::lower(Str::ulid());
        $event = $this->makeSaleReturnEvent($returnId, $fixture, 'return', '2001-10-12', 1);
        $event['payload']['return']['origin_actor_id'] = 'offline-origin-actor';

        $accepted = $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$event]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'accepted')
            ->assertJsonPath('results.0.return_type', 'return')
            ->assertJsonPath('results.0.refund_total', 11100)
            ->assertJsonPath('results.0.approval_mode', 'self');

        $returnRow = DB::connection('tenant')->table('sale_returns')->where('id', $returnId)->first();
        $this->assertNotNull($returnRow);
        $this->assertSame((string) $user->id, (string) $returnRow->actor_id);
        $this->assertSame('offline-origin-actor', (string) $returnRow->origin_actor_id);
        $this->assertSame((string) $user->id, (string) $returnRow->approved_by_user_id);
        $this->assertSame('self', $returnRow->approval_mode);
        $this->assertSame((string) $fixture['journal_id'], (string) $returnRow->original_journal_entry_id);

        $returnItem = DB::connection('tenant')->table('sale_return_items')
            ->where('sale_return_id', $returnId)->first();
        $this->assertNotNull($returnItem);
        $this->assertSame('1.000', number_format((float) $returnItem->quantity, 3, '.', ''));

        $quarantineLot = DB::connection('tenant')->table('inventory_lots')
            ->where('source_return_id', $returnId)->first();
        $this->assertNotNull($quarantineLot);
        $this->assertSame('quarantine', $quarantineLot->status);
        $this->assertSame((string) $fixture['lot_id'], (string) $quarantineLot->origin_lot_id);
        $this->assertSame('1.000', number_format((float) $quarantineLot->quantity_remaining, 3, '.', ''));

        $restoredLayer = DB::connection('tenant')->table('inventory_cost_layers')
            ->where('id', $fixture['cost_layer_id'])->first();
        $this->assertNotNull($restoredLayer);
        $this->assertSame('2.000', number_format((float) $restoredLayer->remaining_qty, 3, '.', ''));
        $this->assertDatabaseHas('sale_return_cost_layers', [
            'original_sale_id' => $fixture['sale_id'],
            'source_cost_layer_id' => $fixture['cost_layer_id'],
            'returned_cost_layer_id' => $fixture['cost_layer_id'],
            'quantity' => 1,
            'unit_cost' => 10000,
            'total_cost' => 10000,
        ], 'tenant');
        $this->assertDatabaseHas('stock_movements', [
            'source_event_id' => $event['event_id'],
            'reference_id' => $returnId,
            'movement_type' => 'return_fifo_cogs',
            'quantity_delta' => 1,
            'total_cost' => 10000,
        ], 'tenant');

        $journalLines = DB::connection('tenant')->table('journal_lines')
            ->where('journal_entry_id', $returnRow->journal_entry_id)->get();
        $this->assertSame(
            $journalLines->sum(fn ($line) => (int) $line->debit),
            $journalLines->sum(fn ($line) => (int) $line->credit)
        );
        $this->assertSame(10000, (int) $journalLines->where('account_code', '4-4030')->sum('debit'));
        $this->assertSame(1100, (int) $journalLines->where('account_code', '2-2010')->sum('debit'));
        $this->assertSame(10000, (int) $journalLines->where('account_code', '1-1040')->sum('debit'));
        $this->assertSame(10000, (int) $journalLines->where('account_code', '5-5010')->sum('credit'));

        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$event]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'replayed');
        $this->assertSame(1, DB::connection('tenant')->table('sale_returns')->where('id', $returnId)->count());
        $this->assertSame(1, DB::connection('tenant')->table('inventory_lots')->where('source_return_id', $returnId)->count());
        $this->assertSame(1, DB::connection('tenant')->table('sale_return_items')->where('sale_return_id', $returnId)->count());

        $conflicting = $event;
        $conflicting['payload']['return']['reason'] = 'Different reason under the same event ID';
        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$conflicting]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'conflict');
        $this->assertSame(1, DB::connection('tenant')->table('sale_returns')->where('id', $returnId)->count());
    }

    public function test_full_void_after_original_period_closes_posts_linked_exact_reversal_in_open_period(): void
    {
        [, $deviceId, , $bearer] = $this->identityFixture(true);
        $fixture = $this->createPostedSaleFixture($deviceId, '2002-06-10', '2002-01-01', '2002-12-31');

        DB::connection('tenant')->table('accounting_periods')->where('id', $fixture['period_id'])->update([
            'status' => 'closed',
            'closed_at' => now(),
            'closed_by' => 'test-accounting-owner',
            'updated_at' => now(),
        ]);
        $nextPeriodId = DB::connection('tenant')->table('accounting_periods')->insertGetId([
            'starts_on' => '2003-01-01',
            'ends_on' => '2003-12-31',
            'status' => 'open',
            'closed_at' => null,
            'closed_by' => null,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $returnId = 'void-test-'.Str::lower(Str::ulid());
        $event = $this->makeSaleReturnEvent($returnId, $fixture, 'void', '2003-01-02', 1);
        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$event]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'accepted')
            ->assertJsonPath('results.0.return_type', 'void')
            ->assertJsonPath('results.0.reversal_of_id', $fixture['journal_id']);

        $returnRow = DB::connection('tenant')->table('sale_returns')->where('id', $returnId)->first();
        $this->assertNotNull($returnRow);
        $reversal = DB::connection('tenant')->table('journal_entries')->where('id', $returnRow->journal_entry_id)->first();
        $this->assertSame((string) $fixture['journal_id'], (string) $reversal->reversal_of_id);
        $this->assertSame($nextPeriodId, (int) $reversal->period_id);
        $this->assertSame('posted', $reversal->status);

        $originalLines = DB::connection('tenant')->table('journal_lines')
            ->where('journal_entry_id', $fixture['journal_id'])->get()->keyBy('account_code');
        $reversalLines = DB::connection('tenant')->table('journal_lines')
            ->where('journal_entry_id', $reversal->id)->get()->keyBy('account_code');
        $this->assertSame($originalLines->count(), $reversalLines->count());
        foreach ($originalLines as $account => $line) {
            $this->assertSame((int) $line->debit, (int) $reversalLines[$account]->credit);
            $this->assertSame((int) $line->credit, (int) $reversalLines[$account]->debit);
        }
        $this->assertSame(1, DB::connection('tenant')->table('journal_entries')
            ->where('reversal_of_id', $fixture['journal_id'])->count());
    }

    public function test_stock_disposition_self_approval_is_audited_and_quantity_changes_fail_closed(): void
    {
        [, , $user, $bearer] = $this->identityFixture(true);
        $tenant = DB::connection('tenant');
        $productId = 'adjust-product-'.Str::lower(Str::ulid());
        $lotId = 'adjust-lot-'.Str::lower(Str::ulid());
        $now = now();
        $tenant->table('products')->insert([
            'id' => $productId,
            'sku' => 'SKU-ADJUST-'.Str::upper(Str::random(8)),
            'barcode' => null,
            'name' => 'Stock disposition test',
            'category_id' => null,
            'price' => 12000,
            'requires_review' => false,
            'is_active' => true,
            'stock_qty' => 2,
            'ppn_exempt' => false,
            'track_expiry' => false,
            'min_shelf_life_days' => 0,
            'version' => 1,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $tenant->table('inventory_lots')->insert([
            'id' => $lotId,
            'product_id' => $productId,
            'batch_code' => 'B-QUARANTINE',
            'expires_at' => '2030-12-31',
            'quantity_received' => 2,
            'quantity_remaining' => 2,
            'unit_cost' => 5000,
            'received_at' => '2026-10-01 00:00:00+00:00',
            'reserved_qty' => 0,
            'status' => 'quarantine',
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $adjustmentId = 'adjustment-test-'.Str::lower(Str::ulid());
        $eventId = 'outbox:stock_adjustment:'.$adjustmentId;
        $event = [
            'event_id' => $eventId,
            'entity_type' => 'stock_adjustment',
            'entity_id' => $adjustmentId,
            'payload' => [
                'event_id' => $eventId,
                'event_type' => 'stock_adjustment',
                'payload_version' => 1,
                'entity_id' => $adjustmentId,
                'adjustment' => [
                    'id' => $adjustmentId,
                    'product_id' => $productId,
                    'lot_id' => $lotId,
                    'action' => 'release_quarantine',
                    'from_status' => 'quarantine',
                    'to_status' => 'saleable',
                    'quantity_delta' => 0,
                    'reason' => 'Inspection approved for test',
                    'inspection_note' => 'Batch, packaging and expiry inspected',
                    'inspection_result' => 'passed',
                    'business_date' => '2026-10-24',
                    'occurred_at_utc' => '2026-10-24T03:00:00Z',
                    'timezone' => 'Asia/Jakarta',
                    'request_fingerprint' => hash('sha256', 'adjustment-request'),
                ],
            ],
        ];

        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$event]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'accepted')
            ->assertJsonPath('results.0.approval_mode', 'self')
            ->assertJsonPath('results.0.actor_id', (string) $user->id)
            ->assertJsonPath('results.0.approved_by_user_id', (string) $user->id);
        $this->assertDatabaseHas('inventory_lots', ['id' => $lotId, 'status' => 'saleable'], 'tenant');
        $this->assertDatabaseHas('stock_adjustments', [
            'id' => $adjustmentId,
            'actor_id' => (string) $user->id,
            'approved_by_user_id' => (string) $user->id,
            'approval_mode' => 'self',
            'quantity_delta' => 0,
        ], 'tenant');

        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$event]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'replayed');
        $this->assertSame(1, $tenant->table('stock_adjustments')->where('id', $adjustmentId)->count());

        $quantityEvent = $event;
        $quantityEvent['event_id'] = 'outbox:stock_adjustment:qty-'.$adjustmentId;
        $quantityEvent['payload']['event_id'] = $quantityEvent['event_id'];
        $quantityEvent['entity_id'] = 'qty-'.$adjustmentId;
        $quantityEvent['payload']['entity_id'] = 'qty-'.$adjustmentId;
        $quantityEvent['payload']['adjustment']['id'] = 'qty-'.$adjustmentId;
        $quantityEvent['payload']['adjustment']['quantity_delta'] = 1;
        $quantityEvent['payload']['adjustment']['request_fingerprint'] = hash('sha256', 'quantity-change');
        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$quantityEvent]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'conflict');
        $this->assertDatabaseHas('inventory_lots', ['id' => $lotId, 'status' => 'saleable'], 'tenant');
        $this->assertSame(1, $tenant->table('stock_adjustments')->where('id', $adjustmentId)->count());
    }

    /** @return array<string, mixed> */
    private function createPostedSaleFixture(
        string $deviceId,
        string $saleDate,
        string $periodStart,
        string $periodEnd
    ): array {
        $db = DB::connection('tenant');
        $now = now();
        $occurredAt = $saleDate.' 10:00:00+07:00';
        $saleId = 'sale:fixture:'.Str::lower(Str::ulid());
        $transactionId = 'fixture-'.Str::lower(Str::ulid());
        $productId = 'return-product-'.Str::lower(Str::ulid());
        $lotId = 'return-source-lot-'.Str::lower(Str::ulid());
        $costLayerId = 'return-source-cost-'.Str::lower(Str::ulid());
        $saleItemId = $saleId.':item:0';
        $sourceEventId = 'outbox:sale:'.$transactionId;
        $periodId = $db->table('accounting_periods')->insertGetId([
            'starts_on' => $periodStart,
            'ends_on' => $periodEnd,
            'status' => 'open',
            'closed_at' => null,
            'closed_by' => null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $db->table('products')->insert([
            'id' => $productId,
            'sku' => 'SKU-RETURN-'.Str::upper(Str::random(8)),
            'barcode' => null,
            'name' => 'Return test product',
            'category_id' => null,
            'price' => 10000,
            'requires_review' => false,
            'is_active' => true,
            'stock_qty' => 1,
            'ppn_exempt' => false,
            'track_expiry' => false,
            'min_shelf_life_days' => 0,
            'version' => 1,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $db->table('inventory_lots')->insert([
            'id' => $lotId,
            'product_id' => $productId,
            'batch_code' => 'B-RETURN-'.Str::upper(Str::random(8)),
            'expires_at' => '2035-12-31',
            'quantity_received' => 2,
            'quantity_remaining' => 1,
            'unit_cost' => 10000,
            'received_at' => $saleDate.' 08:00:00+07:00',
            'reserved_qty' => 0,
            'status' => 'saleable',
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $db->table('inventory_cost_layers')->insert([
            'id' => $costLayerId,
            'product_id' => $productId,
            'lot_id' => $lotId,
            'original_qty' => 2,
            'remaining_qty' => 1,
            'unit_cost' => 10000,
            'acquired_at' => $saleDate.' 08:00:00+07:00',
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $db->table('sales')->insert([
            'id' => $saleId,
            'device_id' => $deviceId,
            'source_event_id' => $sourceEventId,
            'status' => 'accepted',
            'payment_method' => 'cash',
            'subtotal' => 10000,
            'tax_amount' => 1100,
            'total_amount' => 11100,
            'occurred_at' => $occurredAt,
            'transaction_id' => $transactionId,
            'request_fingerprint' => hash('sha256', $transactionId),
            'business_date' => $saleDate,
            'timezone' => 'Asia/Jakarta',
            'gross_amount' => 10000,
            'item_discount_amount' => 0,
            'transaction_discount_amount' => 0,
            'discount_amount' => 0,
            'taxable_dpp' => 10000,
            'exempt_dpp' => 0,
            'dpp' => 10000,
            'ppn_amount' => 1100,
            'grand_total' => 11100,
            'cogs_amount' => 10000,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $db->table('sale_items')->insert([
            'sale_id' => $saleId,
            'client_line_id' => $saleItemId,
            'line_no' => 0,
            'product_id' => $productId,
            'product_name' => 'Return test product',
            'quantity' => 1,
            'unit_price' => 10000,
            'line_total' => 10000,
            'unit_cost' => 0,
            'gross_amount' => 10000,
            'item_discount_amount' => 0,
            'transaction_discount_amount' => 0,
            'discount_amount' => 0,
            'dpp' => 10000,
            'ppn_exempt' => false,
            'cogs_amount' => 10000,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $db->table('sale_lot_allocations')->insert([
            'sale_item_id' => $saleItemId,
            'allocation_no' => 0,
            'lot_id' => $lotId,
            'quantity' => 1,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $db->table('cost_layer_consumptions')->insert([
            'sale_item_id' => $saleItemId,
            'consumption_no' => 0,
            'cost_layer_id' => $costLayerId,
            'quantity' => 1,
            'unit_cost' => 10000,
            'total_cost' => 10000,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $db->table('inventory_movements')->insert([
            'source_event_id' => $sourceEventId,
            'product_id' => $productId,
            'lot_id' => $lotId,
            'movement_type' => 'sale_fefo',
            'quantity' => -1,
            'reference_id' => $transactionId,
            'occurred_at' => $occurredAt,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $db->table('stock_movements')->insert([
            'id' => 'fixture-stock:'.substr(hash('sha256', $transactionId), 0, 40),
            'source_event_id' => $sourceEventId,
            'product_id' => $productId,
            'reference_id' => $transactionId,
            'movement_type' => 'sale_fifo_cogs',
            'quantity_delta' => -1,
            'unit_cost' => 10000,
            'total_cost' => 10000,
            'occurred_at' => $occurredAt,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $journalId = 'journal:sale:'.$transactionId;
        $db->table('journal_entries')->insert([
            'id' => $journalId,
            'source_event_id' => $sourceEventId,
            'transaction_id' => $transactionId,
            'description' => 'POS sale '.$transactionId,
            'journal_date' => $saleDate,
            'occurred_at' => $occurredAt,
            'timezone' => 'Asia/Jakarta',
            'period_id' => $periodId,
            'status' => 'draft',
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $fixtureJournalLines = [
            ['account_code' => '1-1010', 'debit' => 11100, 'credit' => 0],
            ['account_code' => '4-4010', 'debit' => 0, 'credit' => 10000],
            ['account_code' => '2-2010', 'debit' => 0, 'credit' => 1100],
            ['account_code' => '5-5010', 'debit' => 10000, 'credit' => 0],
            ['account_code' => '1-1040', 'debit' => 0, 'credit' => 10000],
        ];
        foreach ($fixtureJournalLines as $lineNo => $line) {
            $db->table('journal_lines')->insert([
                'journal_entry_id' => $journalId,
                'line_no' => $lineNo,
                'account_code' => $line['account_code'],
                'debit' => $line['debit'],
                'credit' => $line['credit'],
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }
        $db->table('journal_entries')->where('id', $journalId)->update([
            'status' => 'posted',
            'posted_at' => $now,
            'posted_by' => 'fixture-owner',
            'device_id' => $deviceId,
            'app_version' => 'test-fixture',
            'period_id' => $periodId,
            'updated_at' => $now,
        ]);

        return [
            'sale_id' => $saleId,
            'transaction_id' => $transactionId,
            'product_id' => $productId,
            'lot_id' => $lotId,
            'cost_layer_id' => $costLayerId,
            'sale_item_id' => $saleItemId,
            'journal_id' => $journalId,
            'period_id' => $periodId,
            'source_event_id' => $sourceEventId,
        ];
    }

    /** @param array<string, mixed> $fixture */
    private function makeSaleReturnEvent(
        string $returnId,
        array $fixture,
        string $returnType,
        string $businessDate,
        int $quantity
    ): array {
        $eventId = 'outbox:sale_return:'.$returnId;
        $payload = [
            'event_id' => $eventId,
            'event_type' => 'sale_return',
            'payload_version' => 1,
            'entity_id' => $returnId,
            'return' => [
                'id' => $returnId,
                'original_sale_id' => $fixture['sale_id'],
                'return_type' => $returnType,
                'refund_method' => 'cash',
                'reason' => $returnType === 'void' ? 'Void full sale in test' : 'Customer return in test',
                'business_date' => $businessDate,
                'occurred_at_utc' => $businessDate.'T03:00:00Z',
                'timezone' => 'Asia/Jakarta',
                'request_fingerprint' => hash('sha256', $returnId.'|'.$returnType.'|'.$quantity),
            ],
            'items' => [
                ['sale_item_id' => $fixture['sale_item_id'], 'quantity' => $quantity],
            ],
        ];
        return [
            'event_id' => $eventId,
            'entity_type' => 'sale_return',
            'entity_id' => $returnId,
            'payload' => $payload,
        ];
    }




    public function test_authenticated_reconciliation_report_tracks_return_and_stock_cost_links(): void
    {
        [, $deviceId, , $bearer] = $this->identityFixture(true);
        $fixture = $this->createPostedSaleFixture(
            $deviceId,
            '2004-10-10',
            '2004-01-01',
            '2004-12-31'
        );

        $beforeResponse = $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->getJson('/api/v1/reports/reconciliation');
        $beforeResponse->assertOk()
            ->assertJsonPath('data.source', 'tenant_postgresql');
        $before = $beforeResponse->json('data');

        $returnId = 'report-return-'.Str::lower(Str::ulid());
        $event = $this->makeSaleReturnEvent(
            $returnId,
            $fixture,
            'return',
            '2004-10-12',
            1
        );
        $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->postJson('/api/v1/sync', ['events' => [$event]])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'accepted')
            ->assertJsonPath('results.0.refund_total', 11100);

        $afterResponse = $this->withHeader('Authorization', 'Bearer '.$bearer)
            ->getJson('/api/v1/reports/reconciliation?tenant_id=untrusted-caller-value');
        $afterResponse->assertOk()
            ->assertJsonPath('data.source', 'tenant_postgresql');
        $after = $afterResponse->json('data');

        $this->assertSame((int) $before['return_count'] + 1, (int) $after['return_count']);
        $this->assertSame(11100, (int) $after['refund_total'] - (int) $before['refund_total']);
        $this->assertSame(11100, (int) $before['net_revenue'] - (int) $after['net_revenue']);
        $this->assertSame(10000, (int) $before['net_cogs'] - (int) $after['net_cogs']);
        // The tenant-wide report can expose pre-existing, unrelated fixture
        // discrepancies. This operation must not introduce a new discrepancy.
        foreach ([
            'product_lot_mismatch_count',
            'lot_cost_layer_mismatch_count',
            'unbalanced_posted_journal_count',
            'missing_return_journal_count',
            'missing_return_receipt_count',
            'over_returned_line_count',
        ] as $metric) {
            $this->assertSame((int) $before[$metric], (int) $after[$metric], $metric);
        }
        $this->assertSame((bool) $before['is_reconciled'], (bool) $after['is_reconciled']);
    }


}
