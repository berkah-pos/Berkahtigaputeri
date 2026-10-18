<?php

namespace App\Services\Tenant;

use Carbon\CarbonImmutable;
use Illuminate\Database\Connection;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;
use RuntimeException;
use Throwable;

/**
 * Internal domain boundary for accepting one synchronized sale into one tenant database.
 *
 * Caller MUST derive actorReference, deviceId and appVersion from authenticated
 * server-side identity/device/build context. This class is intentionally not
 * exposed by an HTTP route until the central authentication + tenant/device
 * authorization middleware exists.
 *
 * Tax, discounts, fractional-unit sales, and sale refund workflows are not
 * implemented here. Current policy is whole-IDR amounts and whole-unit
 * quantities, and the service rejects unsupported fractional stock values.
 */
class AtomicSalePostingService
{
    public function post(
        array $command,
        string $actorReference,
        string $deviceId,
        string $appVersion,
    ): array {
        $context = [
            'actor_reference' => $this->requiredText($actorReference, 'actorReference', 150),
            'device_id' => $this->requiredText($deviceId, 'deviceId', 150),
            'app_version' => $this->requiredText($appVersion, 'appVersion', 80),
        ];
        $normalized = $this->normalizeCommand($command);
        $fingerprint = hash('sha256', json_encode($normalized, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES));
        $eventId = $normalized['event_id'];

        try {
            return DB::connection('tenant')->transaction(function (Connection $db) use ($normalized, $fingerprint, $context, $eventId): array {
                $existing = $db->table('sync_receipts')
                    ->where('event_id', $eventId)
                    ->lockForUpdate()
                    ->first();

                if ($existing !== null) {
                    return $this->returnExistingReceipt($existing, $fingerprint, $context['device_id']);
                }

                // An older/unreconciled sale without a durable receipt must never be replayed.
                if ($db->table('sales')->where('source_event_id', $eventId)->exists()) {
                    throw new SalePostingException('Sale event exists without a matching durable sync receipt; manual reconciliation is required.');
                }

                $productIds = array_column($normalized['lines'], 'product_id');
                $products = $db->table('products')
                    ->whereIn('id', $productIds)
                    ->orderBy('id')
                    ->lockForUpdate()
                    ->get()
                    ->keyBy('id');

                foreach ($normalized['lines'] as $line) {
                    $product = $products->get($line['product_id']);
                    if ($product === null) {
                        throw new SalePostingException('Product not found: '.$line['product_id']);
                    }
                    if (!$this->dbBoolean($product->is_active)) {
                        throw new SalePostingException('Inactive product cannot be sold: '.$line['product_id']);
                    }
                    if ($this->dbBoolean($product->requires_review)) {
                        throw new SalePostingException('Product requires review before checkout: '.$line['product_id']);
                    }
                    if (($product->currency_code ?? 'IDR') !== 'IDR') {
                        throw new SalePostingException('Only IDR currency is supported.');
                    }
                    $price = $this->wholeNonNegativeInteger($product->price, 'product price');
                    if ($price < 1) {
                        throw new SalePostingException('Zero-value line items are unsupported until a business pricing policy is approved.');
                    }
                }

                // Lock stock and costing rows in deterministic order. Every stock-receipt path
                // must also lock the product row; the DB trigger reinforces this serialization.
                $lots = $db->table('inventory_lots')
                    ->whereIn('product_id', $productIds)
                    ->where('quantity_remaining', '>', 0)
                    ->orderBy('product_id')
                    ->orderByRaw('expires_at ASC NULLS LAST')
                    ->orderBy('received_at')
                    ->orderBy('id')
                    ->lockForUpdate()
                    ->get();

                $costLayers = $db->table('inventory_cost_layers')
                    ->whereIn('product_id', $productIds)
                    ->where('quantity_remaining', '>', 0)
                    ->orderBy('product_id')
                    ->orderBy('acquired_at')
                    ->orderBy('id')
                    ->lockForUpdate()
                    ->get();

                $lotsByProduct = [];
                foreach ($lots as $lot) {
                    $lotsByProduct[$lot->product_id][] = $lot;
                }
                $layersByProduct = [];
                foreach ($costLayers as $layer) {
                    $layersByProduct[$layer->product_id][] = $layer;
                }

                $businessDate = CarbonImmutable::parse($normalized['occurred_at_utc'])
                    ->setTimezone('Asia/Jakarta')
                    ->toDateString();
                $lotRemaining = [];
                $costRemaining = [];
                $physicalAllocations = [];
                $costAllocations = [];
                $lineFinancials = [];
                $subtotal = 0;
                $totalCogs = 0;

                foreach ($normalized['lines'] as $lineIndex => $line) {
                    $product = $products->get($line['product_id']);
                    $quantity = $line['quantity'];
                    $price = $this->wholeNonNegativeInteger($product->price, 'product price');
                    $lineTotal = $this->checkedMultiply($price, $quantity, 'sale line total');
                    $subtotal = $this->checkedAdd($subtotal, $lineTotal, 'sale subtotal');

                    $shelfLife = (int) $product->min_shelf_life_days;
                    $minimumExpiry = CarbonImmutable::parse($businessDate)->addDays($shelfLife)->toDateString();
                    $trackExpiry = $this->dbBoolean($product->track_expiry ?? false);
                    $physicalCandidates = [];

                    foreach ($lotsByProduct[$line['product_id']] ?? [] as $lot) {
                        $available = $lotRemaining[$lot->id] ?? $this->wholeQuantity($lot->quantity_remaining, 'physical lot quantity');
                        $lotRemaining[$lot->id] = $available;
                        if ($available <= 0) {
                            continue;
                        }
                        $expiresAt = $lot->expires_at === null ? null : substr((string) $lot->expires_at, 0, 10);
                        if ($expiresAt !== null && $expiresAt < $businessDate) {
                            continue;
                        }
                        if ($trackExpiry && ($expiresAt === null || $expiresAt < $minimumExpiry)) {
                            continue;
                        }
                        $physicalCandidates[] = $lot;
                    }

                    $availablePhysical = array_sum(array_map(
                        fn (object $lot): int => $lotRemaining[$lot->id],
                        $physicalCandidates,
                    ));
                    if ($availablePhysical < $quantity) {
                        throw new SalePostingException(
                            "Insufficient eligible FEFO stock for product {$line['product_id']}: available {$availablePhysical}, requested {$quantity}."
                        );
                    }

                    $left = $quantity;
                    $linePhysical = [];
                    foreach ($physicalCandidates as $lot) {
                        if ($left === 0) {
                            break;
                        }
                        $take = min($left, $lotRemaining[$lot->id]);
                        if ($take <= 0) {
                            continue;
                        }
                        $linePhysical[] = ['lot_id' => (string) $lot->id, 'quantity' => $take];
                        $lotRemaining[$lot->id] -= $take;
                        $left -= $take;
                    }
                    $physicalAllocations[$lineIndex] = $linePhysical;

                    $costCandidates = [];
                    foreach ($layersByProduct[$line['product_id']] ?? [] as $layer) {
                        $available = $costRemaining[$layer->id] ?? $this->wholeQuantity($layer->quantity_remaining, 'FIFO cost-layer quantity');
                        $costRemaining[$layer->id] = $available;
                        if ($available > 0) {
                            $costCandidates[] = $layer;
                        }
                    }
                    $availableCost = array_sum(array_map(
                        fn (object $layer): int => $costRemaining[$layer->id],
                        $costCandidates,
                    ));
                    if ($availableCost < $quantity) {
                        throw new SalePostingException(
                            "Insufficient FIFO cost layers for product {$line['product_id']}: available {$availableCost}, requested {$quantity}."
                        );
                    }

                    $left = $quantity;
                    $lineCost = 0;
                    $lineCosts = [];
                    foreach ($costCandidates as $layer) {
                        if ($left === 0) {
                            break;
                        }
                        $take = min($left, $costRemaining[$layer->id]);
                        if ($take <= 0) {
                            continue;
                        }
                        $unitCost = $this->wholeNonNegativeInteger($layer->unit_cost, 'FIFO unit cost');
                        $cost = $this->checkedMultiply($unitCost, $take, 'FIFO consumption total');
                        $lineCost = $this->checkedAdd($lineCost, $cost, 'line COGS');
                        $lineCosts[] = [
                            'cost_layer_id' => (string) $layer->id,
                            'quantity' => $take,
                            'unit_cost' => $unitCost,
                            'total_cost' => $cost,
                        ];
                        $costRemaining[$layer->id] -= $take;
                        $left -= $take;
                    }

                    $totalCogs = $this->checkedAdd($totalCogs, $lineCost, 'sale COGS');
                    $costAllocations[$lineIndex] = $lineCosts;
                    $lineFinancials[$lineIndex] = [
                        'product_id' => $line['product_id'],
                        'product_name' => (string) $product->name,
                        'quantity' => $quantity,
                        'unit_price' => $price,
                        'line_total' => $lineTotal,
                        'cogs_amount' => $lineCost,
                    ];
                }

                if ($subtotal < 1) {
                    throw new SalePostingException('A zero-value sale cannot be posted.');
                }

                $this->checkpoint('after_allocation');

                $timestamp = CarbonImmutable::now('UTC');
                $timestampNaive = $timestamp->format('Y-m-d H:i:s');
                $occurred = CarbonImmutable::parse($normalized['occurred_at_utc'])->utc();
                $occurredNaive = $occurred->format('Y-m-d H:i:s');
                $saleId = 'sale:'.$eventId;
                $journalId = 'journal:'.$eventId;

                // Apply physical FEFO stock movements and separate FIFO cost consumption under
                // the same tenant database transaction as sale, journal, audit and receipt.
                foreach ($physicalAllocations as $lineIndex => $allocations) {
                    $productId = $normalized['lines'][$lineIndex]['product_id'];
                    foreach ($allocations as $allocationIndex => $allocation) {
                        $changed = $db->table('inventory_lots')
                            ->where('id', $allocation['lot_id'])
                            ->where('quantity_remaining', '>=', $allocation['quantity'])
                            ->decrement('quantity_remaining', $allocation['quantity']);
                        if ($changed !== 1) {
                            throw new SalePostingException('Inventory changed concurrently; retry with the same idempotency key.');
                        }
                        $movementKey = $eventId.':physical:'.$lineIndex.':'.$allocationIndex;
                        $db->table('inventory_movements')->insert([
                            'source_event_id' => $eventId,
                            'movement_key' => $movementKey,
                            'product_id' => $productId,
                            'lot_id' => $allocation['lot_id'],
                            'movement_type' => 'sale_out',
                            'quantity' => -$allocation['quantity'],
                            'reference_id' => $saleId,
                            'occurred_at' => $occurredNaive,
                            'created_at' => $timestampNaive,
                            'updated_at' => $timestampNaive,
                        ]);
                    }
                }

                foreach ($costAllocations as $lineIndex => $allocations) {
                    foreach ($allocations as $allocationIndex => $allocation) {
                        $changed = $db->table('inventory_cost_layers')
                            ->where('id', $allocation['cost_layer_id'])
                            ->where('quantity_remaining', '>=', $allocation['quantity'])
                            ->decrement('quantity_remaining', $allocation['quantity']);
                        if ($changed !== 1) {
                            throw new SalePostingException('FIFO cost layer changed concurrently; transaction rolled back.');
                        }
                    }
                }
                $this->checkpoint('after_stock_decrement');

                $db->table('sales')->insert([
                    'id' => $saleId,
                    'device_id' => $context['device_id'],
                    'source_event_id' => $eventId,
                    'status' => 'accepted',
                    'payment_method' => $normalized['payment_method'],
                    'subtotal' => $subtotal,
                    'tax_amount' => 0,
                    'total_amount' => $subtotal,
                    'currency_code' => 'IDR',
                    'occurred_at' => $occurredNaive,
                    'occurred_at_utc' => $occurred->format('Y-m-d H:i:sP'),
                    'business_date' => $businessDate,
                    'request_fingerprint' => $fingerprint,
                    'created_at' => $timestampNaive,
                    'updated_at' => $timestampNaive,
                ]);
                $this->checkpoint('after_sale_header');

                $saleItemIds = [];
                foreach ($lineFinancials as $lineIndex => $financial) {
                    $saleItemId = $db->table('sale_items')->insertGetId([
                        'sale_id' => $saleId,
                        'product_id' => $financial['product_id'],
                        'product_name' => $financial['product_name'],
                        'quantity' => $financial['quantity'],
                        'unit_price' => $financial['unit_price'],
                        'line_total' => $financial['line_total'],
                        'unit_cost' => null,
                        'cogs_amount' => $financial['cogs_amount'],
                        'line_no' => $lineIndex,
                        'created_at' => $timestampNaive,
                        'updated_at' => $timestampNaive,
                    ], 'id');
                    $saleItemIds[$lineIndex] = $saleItemId;

                    foreach ($physicalAllocations[$lineIndex] as $allocationIndex => $allocation) {
                        $db->table('sale_lot_allocations')->insert([
                            'sale_item_id' => $saleItemId,
                            'allocation_no' => $allocationIndex,
                            'lot_id' => $allocation['lot_id'],
                            'quantity' => $allocation['quantity'],
                        ]);
                    }

                    foreach ($costAllocations[$lineIndex] as $consumptionIndex => $allocation) {
                        $db->table('cost_layer_consumptions')->insert([
                            'sale_item_id' => $saleItemId,
                            'consumption_no' => $consumptionIndex,
                            'cost_layer_id' => $allocation['cost_layer_id'],
                            'quantity' => $allocation['quantity'],
                            'unit_cost' => $allocation['unit_cost'],
                            'total_cost' => $allocation['total_cost'],
                        ]);
                    }
                }
                $this->checkpoint('after_sale_items');

                $paymentAccount = match ($normalized['payment_method']) {
                    'cash' => '1-1010',
                    'qris' => '1-1020',
                    'transfer' => '1-1030',
                };
                $db->table('journal_entries')->insert([
                    'id' => $journalId,
                    'source_event_id' => $eventId,
                    'description' => 'Sale '.$saleId,
                    'journal_date' => $businessDate,
                    'status' => 'draft',
                    'entry_type' => 'sale',
                    'currency_code' => 'IDR',
                    'actor_reference' => $context['actor_reference'],
                    'device_id' => $context['device_id'],
                    'app_version' => $context['app_version'],
                    'transaction_reference' => $eventId,
                    'idempotency_key' => $eventId,
                    'payload_sha256' => $fingerprint,
                    'created_at' => $timestampNaive,
                    'updated_at' => $timestampNaive,
                ]);

                $journalLines = [
                    ['account_code' => $paymentAccount, 'debit' => $subtotal, 'credit' => 0],
                    ['account_code' => '4-4010', 'debit' => 0, 'credit' => $subtotal],
                ];
                if ($totalCogs > 0) {
                    $journalLines[] = ['account_code' => '5-5010', 'debit' => $totalCogs, 'credit' => 0];
                    $journalLines[] = ['account_code' => '1-1040', 'debit' => 0, 'credit' => $totalCogs];
                }
                foreach ($journalLines as $lineNo => $journalLine) {
                    $db->table('journal_lines')->insert($journalLine + [
                        'journal_entry_id' => $journalId,
                        'line_no' => $lineNo,
                        'created_at' => $timestampNaive,
                        'updated_at' => $timestampNaive,
                    ]);
                }
                $this->checkpoint('after_journal_lines');

                $db->table('journal_entries')
                    ->where('id', $journalId)
                    ->update([
                        'status' => 'posted',
                        'posted_at' => $timestamp->format('Y-m-d H:i:sP'),
                        'updated_at' => $timestampNaive,
                    ]);
                $this->checkpoint('after_journal_posted');

                $db->table('accounting_events')->insert([
                    'id' => 'accounting-post:'.$eventId,
                    'journal_entry_id' => $journalId,
                    'event_type' => 'journal.posted',
                    'actor_reference' => $context['actor_reference'],
                    'occurred_at' => $timestamp->format('Y-m-d H:i:sP'),
                    'device_id' => $context['device_id'],
                    'app_version' => $context['app_version'],
                    'transaction_reference' => $eventId,
                    'idempotency_key' => $eventId,
                    'context' => json_encode([
                        'source' => 'laravel_tenant_atomic_sale',
                        'currency_unit' => 'IDR_integer_rupiah',
                    ], JSON_THROW_ON_ERROR),
                ]);
                $this->checkpoint('after_accounting_event');

                $response = [
                    'status' => 'accepted',
                    'event_id' => $eventId,
                    'sale_id' => $saleId,
                    'journal_entry_id' => $journalId,
                    'currency_code' => 'IDR',
                    'subtotal' => $subtotal,
                    'tax_amount' => 0,
                    'total_amount' => $subtotal,
                    'cogs_amount' => $totalCogs,
                    'business_date' => $businessDate,
                    'journal_total_debit' => $subtotal + $totalCogs,
                    'journal_total_credit' => $subtotal + $totalCogs,
                ];

                $db->table('sync_receipts')->insert([
                    'event_id' => $eventId,
                    'device_id' => $context['device_id'],
                    'payload_sha256' => $fingerprint,
                    'response' => json_encode($response, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES),
                    'accepted_at' => $timestamp->format('Y-m-d H:i:sP'),
                    'created_at' => $timestampNaive,
                    'updated_at' => $timestampNaive,
                ]);
                $this->checkpoint('after_sync_receipt');

                return $response;
            }, 3);
        } catch (QueryException $exception) {
            // Two identical concurrent retries may race on the event primary key.
            // The losing transaction is fully rolled back before the durable receipt is re-read.
            if (!$this->isUniqueViolation($exception)) {
                throw $exception;
            }

            $existing = DB::connection('tenant')->table('sync_receipts')->where('event_id', $eventId)->first();
            if ($existing !== null) {
                return $this->returnExistingReceipt($existing, $fingerprint, $context['device_id']);
            }

            throw new SalePostingException('A uniqueness conflict occurred without a matching idempotency receipt; transaction state requires review.', previous: $exception);
        }
    }

    /**
     * Test-only fault injection seam. Production callers cannot set this from a request.
     * Any exception raised here is inside the DB transaction and must roll back every write.
     */
    protected function checkpoint(string $stage): void
    {
    }

    private function normalizeCommand(array $command): array
    {
        $eventId = $this->requiredText((string) ($command['event_id'] ?? ''), 'event_id', 80);
        if (!preg_match('/^[A-Za-z0-9._:-]+$/', $eventId)) {
            throw new InvalidArgumentException('event_id contains unsupported characters.');
        }
        $occurredAt = (string) ($command['occurred_at'] ?? '');
        if (!preg_match('/(?:Z|[+-][0-9]{2}:[0-9]{2})$/i', $occurredAt)) {
            throw new InvalidArgumentException('occurred_at must include an explicit timezone offset or Z.');
        }
        try {
            $occurredAtUtc = CarbonImmutable::parse($occurredAt)->utc()->format('Y-m-d\TH:i:sP');
        } catch (Throwable $exception) {
            throw new InvalidArgumentException('occurred_at is invalid.', previous: $exception);
        }

        $paymentMethod = (string) ($command['payment_method'] ?? '');
        if (!in_array($paymentMethod, ['cash', 'qris', 'transfer'], true)) {
            throw new InvalidArgumentException('payment_method must be cash, qris or transfer.');
        }
        $inputLines = $command['lines'] ?? null;
        if (!is_array($inputLines) || count($inputLines) < 1 || count($inputLines) > 100) {
            throw new InvalidArgumentException('A sale must contain between 1 and 100 lines.');
        }

        $lines = [];
        $seenProducts = [];
        foreach ($inputLines as $line) {
            if (!is_array($line)) {
                throw new InvalidArgumentException('Each sale line must be an object.');
            }
            $productId = $this->requiredText((string) ($line['product_id'] ?? ''), 'product_id', 100);
            if (isset($seenProducts[$productId])) {
                throw new InvalidArgumentException('Duplicate product lines are not supported; aggregate the product quantity first.');
            }
            $seenProducts[$productId] = true;
            $quantity = $line['quantity'] ?? null;
            if (!is_int($quantity) || $quantity < 1) {
                throw new InvalidArgumentException('Sale quantity must be a positive whole-unit integer.');
            }
            $lines[] = ['product_id' => $productId, 'quantity' => $quantity];
        }

        return [
            'event_id' => $eventId,
            'occurred_at_utc' => $occurredAtUtc,
            'payment_method' => $paymentMethod,
            'lines' => $lines,
        ];
    }

    private function returnExistingReceipt(object $receipt, string $fingerprint, string $deviceId): array
    {
        if (!hash_equals((string) $receipt->payload_sha256, $fingerprint)
            || (string) $receipt->device_id !== $deviceId) {
            throw new IdempotencyConflictException('The idempotency key is already bound to a different payload or device.');
        }

        return json_decode((string) $receipt->response, true, 512, JSON_THROW_ON_ERROR);
    }

    private function requiredText(string $value, string $field, int $maxLength): string
    {
        $value = trim($value);
        if ($value === '' || mb_strlen($value) > $maxLength) {
            throw new InvalidArgumentException("{$field} must contain 1 to {$maxLength} characters.");
        }

        return $value;
    }

    private function wholeQuantity(mixed $value, string $field): int
    {
        $text = trim((string) $value);
        if (!preg_match('/^\d+(?:\.0+)?$/', $text)) {
            throw new UnsupportedFractionalQuantityException("{$field} contains a fractional quantity; this backend release only supports whole-unit quantities.");
        }
        $whole = explode('.', $text, 2)[0];
        $parsed = filter_var($whole, FILTER_VALIDATE_INT);
        if ($parsed === false || $parsed < 0) {
            throw new SalePostingException("{$field} is outside the supported integer range.");
        }

        return $parsed;
    }

    private function wholeNonNegativeInteger(mixed $value, string $field): int
    {
        if (is_int($value)) {
            if ($value < 0) {
                throw new SalePostingException("{$field} must not be negative.");
            }
            return $value;
        }
        $text = (string) $value;
        if (!preg_match('/^\d+(?:\.0+)?$/', $text)) {
            throw new SalePostingException("{$field} must be an integer amount in whole Rupiah.");
        }
        $parsed = filter_var(explode('.', $text, 2)[0], FILTER_VALIDATE_INT);
        if ($parsed === false || $parsed < 0) {
            throw new SalePostingException("{$field} is outside the supported integer range.");
        }

        return $parsed;
    }

    private function checkedMultiply(int $amount, int $quantity, string $field): int
    {
        if ($quantity > 0 && $amount > intdiv(PHP_INT_MAX, $quantity)) {
            throw new SalePostingException("{$field} exceeds the supported integer range.");
        }
        return $amount * $quantity;
    }

    private function checkedAdd(int $left, int $right, string $field): int
    {
        if ($right > 0 && $left > PHP_INT_MAX - $right) {
            throw new SalePostingException("{$field} exceeds the supported integer range.");
        }
        return $left + $right;
    }

    private function dbBoolean(mixed $value): bool
    {
        return in_array($value, [true, 1, '1', 't', 'true'], true);
    }

    private function isUniqueViolation(QueryException $exception): bool
    {
        $state = (string) $exception->getCode();
        $previous = $exception->getPrevious();
        if ($previous instanceof \PDOException && isset($previous->errorInfo[0])) {
            $state = (string) $previous->errorInfo[0];
        }

        return $state === '23505';
    }
}

class SalePostingException extends RuntimeException
{
}

class IdempotencyConflictException extends SalePostingException
{
}

class UnsupportedFractionalQuantityException extends SalePostingException
{
}
