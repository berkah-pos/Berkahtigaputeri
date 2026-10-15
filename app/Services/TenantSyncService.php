<?php

namespace App\Services;

use App\Models\Central\Tenant;
use Carbon\CarbonImmutable;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use JsonException;
use RuntimeException;
use Stancl\Tenancy\Facades\Tenancy;
use Throwable;

class TenantSyncService
{
    public function sync(Tenant $tenant, string $deviceId, string $batchId, array $events): array
    {
        try {
            Tenancy::initialize($tenant);
            $database = (string) DB::connection('tenant')->selectOne('SELECT DATABASE() AS db_name')->db_name;
            $expected = (string) $tenant->tenancy_db_name;
            abort_unless(
                $expected !== ''
                    && hash_equals($expected, $database)
                    && preg_match('/^berkahpos_t_[0-9abcdefghjkmnpqrstvwxyz]{26}$/', $database),
                500,
                'Verified tenant connection does not match its canonical database name.'
            );

            $results = [];
            $acceptedIds = [];
            $conflicts = [];

            foreach ($events as $event) {
                try {
                    $result = DB::connection('tenant')->transaction(
                        fn (): array => $this->processEvent($tenant, $deviceId, $batchId, $event)
                    );
                } catch (TenantSyncConflict $exception) {
                    $result = [
                        'event_id' => (string) ($event['id'] ?? ''),
                        'idempotency_key' => (string) ($event['idempotency_key'] ?? $event['id'] ?? ''),
                        'status' => 'conflict',
                        'reason' => $exception->getMessage(),
                    ];
                } catch (QueryException $exception) {
                    // Handles a concurrent retry winning the unique idempotency receipt race.
                    $existing = DB::connection('tenant')->table('sync_receipts')
                        ->where('idempotency_key', (string) ($event['idempotency_key'] ?? $event['id'] ?? ''))
                        ->orWhere('event_id', (string) ($event['id'] ?? ''))
                        ->first();
                    if ($existing === null) {
                        throw $exception;
                    }
                    $result = $this->duplicateOrConflict($existing, $event, $deviceId, $this->payloadHash($event['payload']));
                }

                $results[] = $result;
                if (in_array($result['status'], ['accepted', 'duplicate_acknowledged'], true)) {
                    $acceptedIds[] = (string) $event['id'];
                } elseif ($result['status'] === 'conflict') {
                    $conflicts[] = [
                        'event_id' => (string) $event['id'],
                        'reason' => (string) $result['reason'],
                    ];
                }
            }

            return [
                'batch_id' => $batchId,
                'tenant_id' => (string) $tenant->getTenantKey(),
                'device_id' => $deviceId,
                'accepted_event_ids' => array_values(array_unique($acceptedIds)),
                'conflicts' => $conflicts,
                'results' => $results,
            ];
        } finally {
            Tenancy::end();
            DB::purge('tenant');
        }
    }

    private function processEvent(Tenant $tenant, string $deviceId, string $batchId, array $event): array
    {
        $db = DB::connection('tenant');
        $eventId = (string) $event['id'];
        $idempotencyKey = (string) ($event['idempotency_key'] ?? $eventId);
        $payload = $event['payload'];
        $payloadHash = $this->payloadHash($payload);

        $existing = $db->table('sync_receipts')
            ->where('idempotency_key', $idempotencyKey)
            ->orWhere('event_id', $eventId)
            ->lockForUpdate()
            ->first();
        if ($existing !== null) {
            return $this->duplicateOrConflict($existing, $event, $deviceId, $payloadHash);
        }

        if ((string) $event['entity_id'] !== (string) $payload['sale_id']) {
            throw new TenantSyncConflict('Outbox entity_id must match payload sale_id.');
        }
        if ($db->table('sales')->where('id', $payload['sale_id'])->exists()
            || $db->table('sales')->where('source_event_id', $eventId)->exists()) {
            throw new TenantSyncConflict('A sale with this ID or source event already exists without a matching durable receipt.');
        }

        $occurredAt = CarbonImmutable::parse((string) $payload['occurred_at_utc'])->utc();
        $businessDate = (string) ($payload['business_date'] ?? $occurredAt->toDateString());
        $paymentMethod = (string) $payload['payment_method'];
        $grossAmount = 0;
        $itemDiscount = 0;
        $preparedLines = [];

        foreach ($payload['items'] as $index => $line) {
            $productId = (string) $line['product_id'];
            $quantity = (int) $line['quantity'];
            $unitPrice = (int) $line['unit_price'];
            $discountAmount = (int) ($line['item_discount_amount'] ?? 0);

            $product = $db->table('products')
                ->where('id', $productId)
                ->where('is_active', true)
                ->lockForUpdate()
                ->first();
            if ($product === null) {
                throw new TenantSyncConflict('A sale product is missing or inactive.');
            }
            if ((int) $product->price !== $unitPrice) {
                throw new TenantSyncConflict('Offline unit price differs from the current canonical product price.');
            }
            if ($unitPrice > 0 && $quantity > intdiv(PHP_INT_MAX, $unitPrice)) {
                throw new TenantSyncConflict('Sale amount exceeds supported integer Rupiah range.');
            }

            $lineGross = $unitPrice * $quantity;
            if ($discountAmount > $lineGross) {
                throw new TenantSyncConflict('Item discount exceeds the line gross amount.');
            }
            $grossAmount = $this->safeAdd($grossAmount, $lineGross);
            $itemDiscount = $this->safeAdd($itemDiscount, $discountAmount);
            $preparedLines[] = [
                'index' => $index,
                'product' => $product,
                'product_id' => $productId,
                'quantity' => $quantity,
                'unit_price' => $unitPrice,
                'gross_amount' => $lineGross,
                'item_discount_amount' => $discountAmount,
            ];
        }

        $transactionDiscount = (int) ($payload['transaction_discount_amount'] ?? 0);
        $discountAmount = $this->safeAdd($itemDiscount, $transactionDiscount);
        if ($discountAmount > $grossAmount) {
            throw new TenantSyncConflict('Total discounts exceed the sale gross amount.');
        }
        $subtotal = $grossAmount - $discountAmount;
        $transactionDiscountAllocations = [];
        $remainingTransactionDiscount = $transactionDiscount;
        $remainingDiscountBase = 0;
        foreach ($preparedLines as $line) {
            $remainingDiscountBase = $this->safeAdd(
                $remainingDiscountBase,
                (int) $line['gross_amount'] - (int) $line['item_discount_amount']
            );
        }
        foreach ($preparedLines as $lineIndex => $line) {
            $lineBase = (int) $line['gross_amount'] - (int) $line['item_discount_amount'];
            if ($lineIndex === array_key_last($preparedLines)) {
                $allocation = $remainingTransactionDiscount;
            } elseif ($transactionDiscount === 0 || $lineBase === 0 || $remainingDiscountBase === 0) {
                $allocation = 0;
            } else {
                if ($transactionDiscount > intdiv(PHP_INT_MAX, max(1, $lineBase))) {
                    throw new TenantSyncConflict('Discount allocation exceeds the supported integer Rupiah range.');
                }
                $allocation = intdiv($transactionDiscount * $lineBase, $remainingDiscountBase);
            }
            $transactionDiscountAllocations[$lineIndex] = $allocation;
            $remainingTransactionDiscount -= $allocation;
        }
        $taxAmount = (int) $payload['ppn_amount'];
        $totalAmount = $this->safeAdd($subtotal, $taxAmount);
        if ($totalAmount !== (int) $payload['grand_total']) {
            throw new TenantSyncConflict('grand_total does not equal validated integer subtotal plus ppn_amount.');
        }

        // Physical inventory uses FEFO lots (earliest non-expired expiry first).
        // Financial COGS is computed independently from FIFO cost layers (oldest received first).
        $allocations = [];
        $costConsumptions = [];
        $totalCogs = 0;
        foreach ($preparedLines as $lineIndex => $line) {
            $allocations[$lineIndex] = $this->consumeFefo(
                (string) $line['product_id'],
                (int) $line['quantity'],
                $businessDate,
                $occurredAt->toDateTimeString(),
                $eventId,
                (string) $payload['sale_id']
            );
            [$consumptions, $lineCost] = $this->consumeFifo(
                (string) $line['product_id'],
                (int) $line['quantity'],
                $occurredAt->toDateTimeString()
            );
            $costConsumptions[$lineIndex] = $consumptions;
            $totalCogs = $this->safeAdd($totalCogs, $lineCost);
        }

        $now = now();
        $db->table('sales')->insert([
            'id' => (string) $payload['sale_id'],
            'device_id' => $deviceId,
            'source_event_id' => $eventId,
            'status' => 'accepted',
            'payment_method' => $paymentMethod,
            'subtotal' => $subtotal,
            'tax_amount' => $taxAmount,
            'total_amount' => $totalAmount,
            'gross_amount' => $grossAmount,
            'discount_amount' => $discountAmount,
            'transaction_discount_amount' => $transactionDiscount,
            'cogs_amount' => $totalCogs,
            'occurred_at' => $occurredAt->toDateTimeString(),
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $saleItemIds = [];
        foreach ($preparedLines as $lineIndex => $line) {
            $lineTransactionDiscount = (int) ($transactionDiscountAllocations[$lineIndex] ?? 0);
            $lineDiscountAmount = $this->safeAdd((int) $line['item_discount_amount'], $lineTransactionDiscount);
            $saleItemId = (int) $db->table('sale_items')->insertGetId([
                'sale_id' => (string) $payload['sale_id'],
                'product_id' => (string) $line['product_id'],
                'product_name' => (string) $line['product']->name,
                'quantity' => (int) $line['quantity'],
                'unit_price' => (int) $line['unit_price'],
                'line_total' => (int) $line['gross_amount'] - $lineDiscountAmount,
                'unit_cost' => count($costConsumptions[$lineIndex]) > 0
                    ? (int) intdiv($this->sumCost($costConsumptions[$lineIndex]), (int) $line['quantity'])
                    : 0,
                'discount_amount' => $lineDiscountAmount,
                'cogs_amount' => $this->sumCost($costConsumptions[$lineIndex]),
                'created_at' => $now,
                'updated_at' => $now,
            ]);
            $saleItemIds[$lineIndex] = $saleItemId;

            foreach ($allocations[$lineIndex] as $allocationIndex => $allocation) {
                $db->table('sale_lot_allocations')->insert([
                    'sale_item_id' => $saleItemId,
                    'allocation_no' => $allocationIndex,
                    'lot_id' => $allocation['lot_id'],
                    'quantity' => $allocation['quantity'],
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
            }
            foreach ($costConsumptions[$lineIndex] as $consumptionIndex => $consumption) {
                $db->table('cost_layer_consumptions')->insert([
                    'sale_item_id' => $saleItemId,
                    'consumption_no' => $consumptionIndex,
                    'cost_layer_id' => $consumption['cost_layer_id'],
                    'quantity' => $consumption['quantity'],
                    'unit_cost' => $consumption['unit_cost'],
                    'total_cost' => $consumption['total_cost'],
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
            }
            foreach ($allocations[$lineIndex] as $allocation) {
                $db->table('inventory_movements')->insert([
                    'source_event_id' => $eventId,
                    'product_id' => (string) $line['product_id'],
                    'movement_type' => 'sale',
                    'quantity' => -1 * (int) $allocation['quantity'],
                    'reference_id' => (string) $payload['sale_id'],
                    'occurred_at' => $occurredAt->toDateTimeString(),
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
            }
        }

        $journalId = (string) Str::ulid();
        $db->table('journal_entries')->insert([
            'id' => $journalId,
            'source_event_id' => $eventId,
            'description' => 'Offline sale sync '.$payload['sale_id'],
            'journal_date' => $businessDate,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $cashAccount = match ($paymentMethod) {
            'cash' => '1010-CASH',
            'qris' => '1020-QRIS-RECEIVABLE',
            'transfer' => '1030-BANK-RECEIVABLE',
            default => throw new TenantSyncConflict('Unsupported payment method.'),
        };
        $journalLines = [
            [$cashAccount, $totalAmount, 0],
            ['4000-SALES', 0, $subtotal],
            ['2110-PPN-PAYABLE', 0, $taxAmount],
            ['5000-COGS', $totalCogs, 0],
            ['1300-INVENTORY', 0, $totalCogs],
        ];
        foreach ($journalLines as [$account, $debit, $credit]) {
            $db->table('journal_lines')->insert([
                'journal_entry_id' => $journalId,
                'account_code' => $account,
                'debit' => $debit,
                'credit' => $credit,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }

        $receipt = [
            'event_id' => $eventId,
            'idempotency_key' => $idempotencyKey,
            'receipt_id' => (string) Str::uuid(),
            'sale_id' => (string) $payload['sale_id'],
            'status' => 'accepted',
            'subtotal' => $subtotal,
            'tax_amount' => $taxAmount,
            'total_amount' => $totalAmount,
            'cogs_amount' => $totalCogs,
            'accepted_at' => now()->toIso8601String(),
        ];
        $db->table('sync_receipts')->insert([
            'event_id' => $eventId,
            'idempotency_key' => $idempotencyKey,
            'batch_id' => $batchId,
            'status' => 'accepted',
            'device_id' => $deviceId,
            'payload_sha256' => $payloadHash,
            'response' => json_encode($receipt, JSON_THROW_ON_ERROR),
            'accepted_at' => now(),
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        return $receipt;
    }

    private function consumeFefo(
        string $productId,
        int $quantity,
        string $businessDate,
        string $occurredAt,
        string $eventId,
        string $saleId
    ): array {
        $db = DB::connection('tenant');
        $lots = $db->table('inventory_lots')
            ->where('product_id', $productId)
            ->where('quantity_remaining', '>', 0)
            ->where(function ($query) use ($businessDate): void {
                $query->whereNull('expires_at')->orWhereDate('expires_at', '>=', $businessDate);
            })
            ->orderByRaw('expires_at IS NULL ASC')
            ->orderBy('expires_at')
            ->orderBy('received_at')
            ->orderBy('id')
            ->lockForUpdate()
            ->get();

        $remaining = $quantity;
        $allocations = [];
        foreach ($lots as $lot) {
            if ($remaining === 0) {
                break;
            }
            $available = (int) floor((float) $lot->quantity_remaining);
            if ($available <= 0) {
                continue;
            }
            $allocated = min($available, $remaining);
            $newRemaining = (float) $lot->quantity_remaining - $allocated;
            $db->table('inventory_lots')->where('id', $lot->id)->update([
                'quantity_remaining' => number_format($newRemaining, 3, '.', ''),
                'updated_at' => now(),
            ]);
            $allocations[] = ['lot_id' => (string) $lot->id, 'quantity' => $allocated];
            $remaining -= $allocated;
        }
        if ($remaining > 0) {
            throw new TenantSyncConflict('Insufficient non-expired FEFO inventory lots.');
        }

        return $allocations;
    }

    private function consumeFifo(string $productId, int $quantity, string $occurredAt): array
    {
        $db = DB::connection('tenant');
        $layers = $db->table('cost_layers')
            ->where('product_id', $productId)
            ->where('quantity_remaining', '>', 0)
            ->orderBy('received_at')
            ->orderBy('id')
            ->lockForUpdate()
            ->get();

        $remaining = $quantity;
        $cost = 0;
        $consumptions = [];
        foreach ($layers as $layer) {
            if ($remaining === 0) {
                break;
            }
            $available = (int) floor((float) $layer->quantity_remaining);
            if ($available <= 0) {
                continue;
            }
            $used = min($available, $remaining);
            $unitCost = (int) $layer->unit_cost;
            if ($unitCost > 0 && $used > intdiv(PHP_INT_MAX, $unitCost)) {
                throw new TenantSyncConflict('FIFO COGS exceeds supported integer Rupiah range.');
            }
            $totalCost = $unitCost * $used;
            $newRemaining = (float) $layer->quantity_remaining - $used;
            $db->table('cost_layers')->where('id', $layer->id)->update([
                'quantity_remaining' => number_format($newRemaining, 3, '.', ''),
                'updated_at' => now(),
            ]);
            $consumptions[] = [
                'cost_layer_id' => (string) $layer->id,
                'quantity' => $used,
                'unit_cost' => $unitCost,
                'total_cost' => $totalCost,
            ];
            $cost = $this->safeAdd($cost, $totalCost);
            $remaining -= $used;
        }
        if ($remaining > 0) {
            throw new TenantSyncConflict('Insufficient FIFO cost layers; refusing to invent COGS.');
        }

        return [$consumptions, $cost];
    }

    private function duplicateOrConflict(object $existing, array $event, string $deviceId, string $payloadHash): array
    {
        $sameEventId = (string) $existing->event_id === (string) $event['id'];
        $sameIdempotencyKey = (string) $existing->idempotency_key === (string) ($event['idempotency_key'] ?? $event['id']);
        $sameIdentity = (string) $existing->device_id === $deviceId
            && ($sameEventId || $sameIdempotencyKey);
        if (! $sameIdentity || ! hash_equals((string) $existing->payload_sha256, $payloadHash)) {
            return [
                'event_id' => (string) $event['id'],
                'idempotency_key' => (string) ($event['idempotency_key'] ?? $event['id']),
                'status' => 'conflict',
                'reason' => 'Idempotency key/event ID was previously used with different payload, device, or identity.',
            ];
        }

        $receipt = json_decode((string) $existing->response, true);
        return [
            ...(is_array($receipt) ? $receipt : []),
            'event_id' => (string) $event['id'],
            'idempotency_key' => (string) ($event['idempotency_key'] ?? $event['id']),
            'status' => 'duplicate_acknowledged',
        ];
    }

    private function payloadHash(array $payload): string
    {
        $canonical = $this->canonicalize($payload);
        try {
            return hash('sha256', json_encode($canonical, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR));
        } catch (JsonException $exception) {
            throw new RuntimeException('Cannot serialize sync payload for idempotency.', previous: $exception);
        }
    }

    private function canonicalize(array $value): array
    {
        foreach ($value as $key => $item) {
            if (is_array($item)) {
                $value[$key] = $this->canonicalize($item);
            }
        }
        if (! array_is_list($value)) {
            ksort($value, SORT_STRING);
        }
        return $value;
    }

    private function safeAdd(int $left, int $right): int
    {
        if ($right > 0 && $left > PHP_INT_MAX - $right) {
            throw new TenantSyncConflict('Money amount exceeds the supported integer Rupiah range.');
        }
        return $left + $right;
    }

    private function sumCost(array $consumptions): int
    {
        $sum = 0;
        foreach ($consumptions as $consumption) {
            $sum = $this->safeAdd($sum, (int) $consumption['total_cost']);
        }
        return $sum;
    }
}
