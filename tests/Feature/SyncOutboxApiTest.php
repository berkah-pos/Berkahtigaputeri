<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\DB;
use Stancl\Tenancy\Facades\Tenancy;
use Tests\Support\ProvisionedTenantPair;
use Tests\TestCase;

class SyncOutboxApiTest extends TestCase
{
    use ProvisionedTenantPair;

    protected function setUp(): void
    {
        parent::setUp();
        config(['tenancy.central_domains' => ['localhost', 'central.test', 'app.central.test']]);
    }

    public function test_valid_sync_persists_one_sale_inventory_allocations_fifo_cogs_and_balanced_journal(): void
    {
        $pair = $this->attachTenantPrincipals($this->createProvisionedTenantPair('sync-valid'));
        $productId = 'sync-product-'.$pair['suffix'];
        $this->enablePosAndSeedInventory($pair, $productId);

        $response = $this->postSync($pair['tokenA'], $this->payload($pair, $productId, 'sync-sale-'.$pair['suffix']));
        $response->assertOk()
            ->assertJsonPath('results.0.status', 'accepted')
            ->assertJsonPath('accepted_event_ids.0', 'outbox:sale:'.$pair['suffix'])
            ->assertJsonPath('results.0.total_amount', 400)
            ->assertJsonPath('results.0.cogs_amount', 150);

        Tenancy::initialize($pair['tenantA']);
        try {
            $db = DB::connection('tenant');
            $this->assertSame(1, $db->table('sales')->count());
            $this->assertSame(1, $db->table('journal_entries')->count());
            $this->assertSame(8, (int) $db->table('inventory_lots')->where('id', 'sync-lot-near-'.$pair['suffix'])->value('quantity_remaining'));
            $this->assertSame(8, (int) $db->table('cost_layers')->where('id', 'sync-cost-old-'.$pair['suffix'])->value('quantity_remaining'));
            $this->assertSame(400, (int) $db->table('sales')->value('subtotal'));
            $this->assertSame(
                (int) $db->table('journal_lines')->sum('debit'),
                (int) $db->table('journal_lines')->sum('credit'),
                'Every synced sale must post balanced integer-Rupiah journal lines.'
            );
            $this->assertSame(1, $db->table('sync_receipts')->where('status', 'accepted')->count());
        } finally {
            Tenancy::end();
            DB::purge('tenant');
        }
    }

    public function test_duplicate_idempotent_retry_returns_existing_receipt_without_duplicate_effects(): void
    {
        $pair = $this->attachTenantPrincipals($this->createProvisionedTenantPair('sync-duplicate'));
        $productId = 'sync-product-'.$pair['suffix'];
        $this->enablePosAndSeedInventory($pair, $productId);
        $body = $this->payload($pair, $productId, 'sync-sale-'.$pair['suffix']);

        $this->postSync($pair['tokenA'], $body)->assertOk()->assertJsonPath('results.0.status', 'accepted');
        $retry = $this->postSync($pair['tokenA'], $body);
        $retry->assertOk()->assertJsonPath('results.0.status', 'duplicate_acknowledged');

        Tenancy::initialize($pair['tenantA']);
        try {
            $db = DB::connection('tenant');
            $this->assertSame(1, $db->table('sales')->count());
            $this->assertSame(1, $db->table('journal_entries')->count());
            $this->assertSame(1, $db->table('sync_receipts')->count());
            $this->assertSame(8, (int) $db->table('inventory_lots')->where('id', 'sync-lot-near-'.$pair['suffix'])->value('quantity_remaining'));
        } finally {
            Tenancy::end();
            DB::purge('tenant');
        }
    }

    public function test_cross_tenant_sync_is_forbidden_for_a_user_without_membership(): void
    {
        $pair = $this->attachTenantPrincipals($this->createProvisionedTenantPair('sync-cross'));
        $body = $this->payload($pair, 'not-used', 'sync-cross-sale-'.$pair['suffix']);
        $body['tenant_id'] = $pair['tenantBId'];
        $body['device_id'] = $pair['deviceBId'];

        $this->postSync($pair['tokenA'], $body)->assertForbidden();
    }

    public function test_invalid_sync_payload_fails_validation_without_mutating_tenant_data(): void
    {
        $pair = $this->attachTenantPrincipals($this->createProvisionedTenantPair('sync-invalid'));
        $body = [
            'tenant_id' => $pair['tenantAId'],
            'device_id' => $pair['deviceAId'],
            'batch_id' => 'sync-invalid-batch-'.$pair['suffix'],
            'events' => [[
                'id' => 'outbox:invalid:'.$pair['suffix'],
                'entity_id' => 'invalid-sale',
                'entity_type' => 'sale',
                'payload' => ['saleId' => 'invalid-sale'],
            ]],
        ];
        $this->postSync($pair['tokenA'], $body)->assertUnprocessable();
    }

    public function test_unknown_or_tenant_host_cannot_use_the_central_sync_route(): void
    {
        $pair = $this->attachTenantPrincipals($this->createProvisionedTenantPair('sync-host'));
        $body = $this->payload($pair, 'not-used', 'sync-host-sale-'.$pair['suffix']);
        $this->withServerVariables(['HTTP_HOST' => $pair['hostA']])
            ->withHeaders([
                'Authorization' => 'Bearer '.$pair['tokenA'],
                'Accept' => 'application/json',
            ])
            ->postJson('/api/v1/sync', $body)
            ->assertNotFound();
    }

    private function enablePosAndSeedInventory(array $pair, string $productId): void
    {
        DB::connection('central')->table('tenant_services')->updateOrInsert(
            ['tenant_id' => $pair['tenantAId'], 'service' => 'pos'],
            ['enabled' => true, 'created_at' => now(), 'updated_at' => now()]
        );

        $tenant = $pair['tenantA'];
        $tenant->refresh();
        Tenancy::initialize($tenant);
        try {
            $db = DB::connection('tenant');
            $db->table('products')->insert([
                'id' => $productId,
                'name' => 'Sync test product',
                'price' => 200,
                'is_active' => true,
                'requires_review' => false,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            $db->table('inventory_lots')->insert([
                'id' => 'sync-lot-near-'.$pair['suffix'],
                'product_id' => $productId,
                'batch_code' => 'FEFO-NEAR',
                'expires_at' => now()->addDays(7)->toDateString(),
                'quantity_received' => 10,
                'quantity_remaining' => 10,
                'unit_cost' => 99,
                'received_at' => now(),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            $db->table('inventory_lots')->insert([
                'id' => 'sync-lot-far-'.$pair['suffix'],
                'product_id' => $productId,
                'batch_code' => 'FEFO-FAR',
                'expires_at' => now()->addDays(30)->toDateString(),
                'quantity_received' => 10,
                'quantity_remaining' => 10,
                'unit_cost' => 111,
                'received_at' => now(),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            $db->table('cost_layers')->insert([
                'id' => 'sync-cost-old-'.$pair['suffix'],
                'product_id' => $productId,
                'quantity_remaining' => 10,
                'unit_cost' => 75,
                'received_at' => now()->subDays(10),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            $db->table('cost_layers')->insert([
                'id' => 'sync-cost-new-'.$pair['suffix'],
                'product_id' => $productId,
                'quantity_remaining' => 10,
                'unit_cost' => 90,
                'received_at' => now()->subDays(2),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        } finally {
            Tenancy::end();
            DB::purge('tenant');
        }
    }

    private function payload(array $pair, string $productId, string $saleId): array
    {
        return [
            'tenant_id' => $pair['tenantAId'],
            'device_id' => $pair['deviceAId'],
            'batch_id' => 'sync-batch-'.$pair['suffix'],
            'events' => [[
                'id' => 'outbox:sale:'.$pair['suffix'],
                'idempotency_key' => 'outbox:sale:'.$pair['suffix'],
                'entity_type' => 'sale',
                'entity_id' => $saleId,
                'payload' => [
                    'sale_id' => $saleId,
                    'transaction_id' => 'transaction-'.$pair['suffix'],
                    'payment_method' => 'cash',
                    'occurred_at_utc' => now()->toIso8601String(),
                    'business_date' => now()->toDateString(),
                    'grand_total' => 400,
                    'ppn_amount' => 0,
                    'transaction_discount_amount' => 0,
                    'items' => [[
                        'product_id' => $productId,
                        'quantity' => 2,
                        'unit_price' => 200,
                        'item_discount_amount' => 0,
                    ]],
                ],
            ]],
        ];
    }

    private function postSync(string $token, array $body)
    {
        return $this->withServerVariables(['HTTP_HOST' => 'central.test'])
            ->withHeaders([
                'Authorization' => 'Bearer '.$token,
                'Accept' => 'application/json',
            ])
            ->postJson('/api/v1/sync', $body);
    }
}
