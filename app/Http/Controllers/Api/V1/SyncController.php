<?php

namespace App\Http\Controllers\Api\V1;

use App\Exceptions\SyncConflictException;
use App\Http\Controllers\Controller;
use App\Models\Central\User;
use App\Services\TenantDatabaseRunner;
use Carbon\Carbon;
use Illuminate\Database\Connection;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Throwable;

class SyncController extends Controller
{
    private const ENTITLED_SUBSCRIPTION_STATES = ['trial', 'active', 'grace', 'past_due'];
    private const GRACE_PERIOD_DAYS = 3;

    private const INVENTORY_COUNTER_ACCOUNTS = ['1-1010', '1-1020', '1-1030', '2-2020'];

    private const PAYMENT_ACCOUNTS = [
        'cash' => '1-1010',
        'qris' => '1-1020',
        'bankTransfer' => '1-1030',
        'bank_transfer' => '1-1030',
        'transfer' => '1-1030',
    ];

    public function sync(Request $request, TenantDatabaseRunner $runner): JsonResponse
    {
        if (strlen($request->getContent()) > 1_048_576) {
            return response()->json(['error' => ['code' => 'sync_payload_too_large']], 413);
        }

        $input = $request->validate([
            // device_id is optional for compatibility only. Authorization always
            // derives from identity.context and rejects a mismatching supplied value.
            'device_id' => ['sometimes', 'string', 'min:3', 'max:150', 'regex:/^[A-Za-z0-9_.:-]+$/'],
            'app_version' => ['sometimes', 'string', 'max:64'],
            'events' => ['required', 'array', 'min:1', 'max:20'],
            'events.*.event_id' => ['required', 'string', 'max:100'],
            'events.*.entity_type' => ['required', 'string', 'in:sale,product,inventory_receipt,sale_return,stock_adjustment'],
            'events.*.entity_id' => ['required', 'string', 'max:150'],
            'events.*.payload' => ['required', 'array'],
            'events.*.payload.items' => ['sometimes', 'array', 'max:100'],
            'events.*.payload.journal.lines' => ['sometimes', 'array', 'max:20'],
        ]);

        Validator::make($request->all(), [
            'events.*.payload.sale.request_fingerprint' => ['sometimes', 'string', 'max:65536'],
        ])->validate();

        // Laravel's validated() projection can omit nested fields that do not
        // have their own validation rules (for example product/receipt payloads).
        // The bounded request body and envelope are validated above; business
        // payloads must retain their full shape for canonical hashing and the
        // stricter entity-specific server-side validators below.
        $input['events'] = $request->input('events');

        $user = $request->user();
        $actorId = (int) $request->attributes->get('identity.user_id', 0);
        $tenantId = trim((string) $request->attributes->get('identity.tenant_id', ''));
        $deviceId = trim((string) $request->attributes->get('identity.device_id', ''));

        if (! $user instanceof User || ! $user->is_active || $actorId <= 0 || $tenantId === '' || $deviceId === '') {
            return response()->json(['error' => ['code' => 'identity_context_required']], 403);
        }

        if (isset($input['device_id']) && ! hash_equals($deviceId, (string) $input['device_id'])) {
            return response()->json(['error' => ['code' => 'device_identity_mismatch']], 403);
        }

        $subscription = DB::connection('central')->table('subscriptions')
            ->where('tenant_id', $tenantId)
            ->orderByDesc('id')
            ->first();

        if (! $this->hasEntitlement($subscription)) {
            return response()->json(['error' => ['code' => 'tenant_not_entitled']], 403);
        }

        $appVersion = trim((string) ($input['app_version'] ?? 'unknown')) ?: 'unknown';
        $results = [];
        foreach ($input['events'] as $event) {
            try {
                $results[] = $runner->run(
                    $tenantId,
                    fn (Connection $connection): array => $this->acceptEvent(
                        $connection,
                        $event,
                        $deviceId,
                        $actorId,
                        $appVersion
                    )
                );
            } catch (SyncConflictException $exception) {
                $results[] = [
                    'event_id' => (string) ($event['event_id'] ?? ''),
                    'status' => 'conflict',
                    'message' => $exception->getMessage(),
                ];
            } catch (Throwable $exception) {
                if ($exception instanceof \RuntimeException && in_array($exception->getMessage(), [
                    'tenant_database_not_provisioned',
                    'tenant_database_registry_invalid',
                    'tenant_database_credentials_unavailable',
                ], true)) {
                    return response()->json([
                        'error' => [
                            'code' => $exception->getMessage(),
                            'message' => 'Database tenant belum terdaftar atau runtime role tidak tersedia.',
                        ],
                    ], 503);
                }
                report($exception);
                $results[] = [
                    'event_id' => (string) ($event['event_id'] ?? ''),
                    'status' => 'retry',
                    'message' => 'Server belum dapat menerima event ini. Data lokal tetap disimpan; coba lagi.',
                ];
            }
        }

        return response()->json(['results' => $results])
            ->header('Cache-Control', 'private, no-store')
            ->header('Vary', 'Authorization');
    }

    private function hasEntitlement(?object $subscription): bool
    {
        if ($subscription === null
            || ! in_array((string) $subscription->status, self::ENTITLED_SUBSCRIPTION_STATES, true)) {
            return false;
        }

        $expiresAt = $subscription->expires_at ?? null;
        if ($expiresAt === null) {
            return ! in_array((string) $subscription->status, ['grace', 'past_due'], true);
        }

        return now()->lessThanOrEqualTo(Carbon::parse($expiresAt)->addDays(self::GRACE_PERIOD_DAYS));
    }

    private function acceptEvent(Connection $db, array $event, string $deviceId, int $actorId, string $appVersion): array
    {
        $eventId = (string) $event['event_id'];
        $payload = $event['payload'];

        $entityType = (string) ($event['entity_type'] ?? '');
        $envelopeMismatches = [];
        if (! in_array($entityType, ['sale', 'product', 'inventory_receipt', 'sale_return', 'stock_adjustment'], true)) $envelopeMismatches[] = 'entity_type';
        if (($payload['event_type'] ?? null) !== $entityType) $envelopeMismatches[] = 'event_type';
        if (($payload['payload_version'] ?? null) !== 1) $envelopeMismatches[] = 'payload_version';
        if (($payload['event_id'] ?? null) !== $eventId) $envelopeMismatches[] = 'event_id';
        if (($payload['entity_id'] ?? null) !== (string) $event['entity_id']) $envelopeMismatches[] = 'entity_id';
        if ($envelopeMismatches !== []) {
            throw new SyncConflictException('Event envelope tidak valid pada: '.implode(', ', $envelopeMismatches).'.');
        }

        $canonical = json_encode($this->canonicalize($payload),
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION | JSON_THROW_ON_ERROR);
        $payloadHash = hash('sha256', $canonical);

        // Serialize concurrent deliveries of the same event ID inside this
        // tenant transaction. This also protects the no-receipt-yet race,
        // where SELECT ... FOR UPDATE cannot lock a row that does not exist.
        $db->select('SELECT pg_advisory_xact_lock(hashtextextended(?, 0))', [$eventId]);
        $receipt = $db->table('sync_receipts')->where('event_id', $eventId)->lockForUpdate()->first();
        if ($receipt !== null) {
            if (! hash_equals((string) $receipt->payload_sha256, $payloadHash)
                || (string) $receipt->device_id !== $deviceId) {
                throw new SyncConflictException('ID event yang sama telah digunakan dengan payload atau perangkat berbeda.');
            }
            return [
                'event_id' => $eventId,
                'status' => 'replayed',
                'receipt_id' => $eventId,
                'accepted_at' => (string) $receipt->accepted_at,
            ];
        }

        if ($entityType === 'product') {
            return $this->acceptProductEvent($db, $event, $payload, $deviceId, $payloadHash, $actorId);
        }
        if ($entityType === 'inventory_receipt') {
            return $this->acceptInventoryReceiptEvent($db, $event, $payload, $deviceId, $payloadHash, $actorId, $appVersion);
        }

        if ($entityType === 'sale_return') {
            return $this->acceptSaleReturnEvent($db, $event, $payload, $deviceId, $payloadHash, $actorId, $appVersion);
        }
        if ($entityType === 'stock_adjustment') {
            return $this->acceptStockAdjustmentEvent($db, $event, $payload, $deviceId, $payloadHash, $actorId, $appVersion);
        }

        $sale = $payload['sale'] ?? null;
        $items = $payload['items'] ?? null;
        $journal = $payload['journal'] ?? null;
        if (! is_array($sale) || ! is_array($items) || count($items) < 1
            || ! is_array($journal) || ! is_array($journal['lines'] ?? null)) {
            throw new SyncConflictException('Payload penjualan tidak lengkap untuk rekonsiliasi server.');
        }

        $saleId = $this->requiredString($sale, 'id');
        $transactionId = $this->requiredString($sale, 'transaction_id');
        if ((string) ($payload['transaction_id'] ?? '') !== $transactionId
            || 'sale:'.$transactionId !== $saleId
            || 'outbox:sale:'.$transactionId !== $eventId) {
            throw new SyncConflictException('ID transaksi tidak konsisten.');
        }
        foreach (['occurred_at_utc', 'timezone', 'request_fingerprint', 'payment_method'] as $field) {
            $this->requiredString($sale, $field);
        }
        $businessDate = $this->requiredString($sale, 'business_date');
        try {
            $parsedBusinessDate = Carbon::createFromFormat('!Y-m-d', $businessDate);
        } catch (Throwable) {
            $parsedBusinessDate = false;
        }
        if ($parsedBusinessDate === false || $parsedBusinessDate->format('Y-m-d') !== $businessDate) {
            throw new SyncConflictException('Tanggal pembukuan harus berupa tanggal kalender YYYY-MM-DD yang valid.');
        }
        if ($db->table('accounting_periods')
            ->where('starts_on', '<=', $businessDate)
            ->where('ends_on', '>=', $businessDate)
            ->where('status', 'closed')
            ->exists()) {
            throw new SyncConflictException('Periode akuntansi sudah ditutup; transaksi perlu rekonsiliasi.');
        }
        $period = $db->table('accounting_periods')
            ->where('starts_on', '<=', $businessDate)
            ->where('ends_on', '>=', $businessDate)
            ->where('status', 'open')
            ->orderBy('starts_on')
            ->lockForUpdate()
            ->first();
        if ($period === null) {
            throw new SyncConflictException('Tidak ada periode akuntansi terbuka yang mencakup tanggal transaksi.');
        }
        if (! isset(self::PAYMENT_ACCOUNTS[$sale['payment_method']])) {
            throw new SyncConflictException('Metode pembayaran belum memiliki akun COA yang diizinkan.');
        }

        $money = [];
        foreach (['gross_amount', 'item_discount_amount', 'transaction_discount_amount',
            'discount_amount', 'taxable_dpp', 'exempt_dpp', 'dpp', 'ppn_amount', 'grand_total', 'cogs_amount'] as $field) {
            $money[$field] = $this->payloadMoney($sale, $field);
        }
        if ($money['discount_amount'] !== $money['item_discount_amount'] + $money['transaction_discount_amount']
            || $money['dpp'] !== $money['taxable_dpp'] + $money['exempt_dpp']
            || $money['grand_total'] !== $money['dpp'] + $money['ppn_amount']
            || $money['gross_amount'] - $money['discount_amount'] !== $money['dpp']) {
            throw new SyncConflictException('Invariant total, diskon, DPP, dan PPN tidak seimbang.');
        }
        if ($db->table('sales')->where('id', $saleId)->exists()
            || $db->table('journal_entries')->where('id', $journal['id'] ?? null)->exists()) {
            throw new SyncConflictException('Transaksi atau jurnal sudah ada tanpa receipt idempoten yang cocok.');
        }

        $sums = ['gross_amount' => 0, 'item_discount_amount' => 0, 'transaction_discount_amount' => 0,
            'discount_amount' => 0, 'dpp' => 0, 'taxable_dpp' => 0, 'exempt_dpp' => 0, 'cogs_amount' => 0];
        $prepared = [];
        foreach (array_values($items) as $lineNo => $item) {
            if (! is_array($item) || (int) ($item['line_no'] ?? -1) !== $lineNo
                || (string) ($item['sale_id'] ?? '') !== $saleId) {
                throw new SyncConflictException('Nomor baris atau induk item tidak cocok.');
            }
            $lineId = $this->requiredString($item, 'id');
            $productId = $this->requiredString($item, 'product_id');
            $quantity = $this->payloadQuantity($item, 'quantity');
            $unitPrice = $this->payloadMoney($item, 'unit_price');
            $gross = $this->payloadMoney($item, 'gross_amount');
            $itemDiscount = $this->payloadMoney($item, 'item_discount_amount');
            $transactionDiscount = $this->payloadMoney($item, 'transaction_discount_amount');
            $discount = $this->payloadMoney($item, 'discount_amount');
            $dpp = $this->payloadMoney($item, 'dpp');
            $cogs = $this->payloadMoney($item, 'cogs_amount');
            $taxExempt = $this->payloadBoolean($item['ppn_exempt'] ?? null);
            if ($gross !== $quantity * $unitPrice || $discount !== $itemDiscount + $transactionDiscount
                || $dpp !== $gross - $discount || $discount > $gross) {
                throw new SyncConflictException('Perhitungan nilai item tidak seimbang.');
            }

            $product = $db->table('products')->where('id', $productId)->lockForUpdate()->first();
            if ($product === null || ! $this->databaseBoolean($product->is_active)
                || $this->databaseBoolean($product->requires_review)) {
                throw new SyncConflictException('Produk belum tersedia, tidak aktif, atau masih memerlukan pemeriksaan.');
            }
            if ($this->databaseScaledInteger($product->price, 2) !== $unitPrice * 100
                || $this->databaseBoolean($product->ppn_exempt ?? false) !== $taxExempt) {
                throw new SyncConflictException('Harga atau perlakuan PPN produk berubah; kasir perlu meninjau ulang transaksi.');
            }

            $allocations = $item['allocations'] ?? null;
            $consumptions = $item['cost_consumptions'] ?? null;
            if (! is_array($allocations) || count($allocations) < 1
                || ! is_array($consumptions) || count($consumptions) < 1) {
                throw new SyncConflictException('Alokasi lot FEFO dan konsumsi biaya FIFO wajib dilampirkan.');
            }
            $expectedAllocations = $this->expectedFefoAllocations($db, $product, $quantity, $sale['business_date']);
            $providedAllocations = $this->normalizeAllocations($allocations);
            if ($expectedAllocations !== $providedAllocations) {
                throw new SyncConflictException('Ketersediaan/urutan lot server berbeda dari alokasi FEFO lokal.');
            }
            $expectedConsumptions = $this->expectedFifoConsumptions($db, $productId, $quantity);
            $providedConsumptions = $this->normalizeConsumptions($consumptions);
            if ($expectedConsumptions !== $providedConsumptions
                || array_sum(array_column($providedConsumptions, 'total_cost')) !== $cogs) {
                throw new SyncConflictException('Cost layer/urutan biaya server berbeda dari konsumsi FIFO lokal.');
            }
            $stock = $this->databaseScaledInteger($product->stock_qty, 3);
            if ($stock === null || $stock < $quantity * 1000) {
                throw new SyncConflictException('Stok agregat server tidak mencukupi untuk transaksi offline ini.');
            }

            $sums['gross_amount'] += $gross;
            $sums['item_discount_amount'] += $itemDiscount;
            $sums['transaction_discount_amount'] += $transactionDiscount;
            $sums['discount_amount'] += $discount;
            $sums['dpp'] += $dpp;
            $sums[$taxExempt ? 'exempt_dpp' : 'taxable_dpp'] += $dpp;
            $sums['cogs_amount'] += $cogs;
            $prepared[] = [
                'source' => $item, 'id' => $lineId, 'product_id' => $productId, 'quantity' => $quantity,
                'unit_price' => $unitPrice, 'gross' => $gross, 'item_discount' => $itemDiscount,
                'transaction_discount' => $transactionDiscount, 'discount' => $discount, 'dpp' => $dpp,
                'tax_exempt' => $taxExempt, 'cogs' => $cogs,
                'allocations' => $providedAllocations, 'consumptions' => $providedConsumptions,
            ];
        }
        foreach ($sums as $key => $sum) {
            if ($sum !== $money[$key]) throw new SyncConflictException('Header sale tidak cocok dengan total item: '.$key.'.');
        }

        $expectedJournal = $this->expectedJournal($sale);
        $providedJournal = $this->normalizeJournal($journal['lines'] ?? []);
        if ($expectedJournal !== $providedJournal) {
            throw new SyncConflictException('Jurnal tidak sesuai dengan mapping COA yang disetujui atau nilai sale.');
        }
        if ((string) ($journal['transaction_id'] ?? '') !== $transactionId
            || (string) ($journal['business_date'] ?? '') !== (string) $sale['business_date']) {
            throw new SyncConflictException('Scope transaksi jurnal tidak sesuai.');
        }

        $created = now();
        $occurredAt = (string) $sale['occurred_at_utc'];
        $db->table('sales')->insert([
            'id' => $saleId, 'device_id' => $deviceId, 'source_event_id' => $eventId, 'status' => 'accepted',
            'payment_method' => (string) $sale['payment_method'],
            'subtotal' => $money['dpp'], 'tax_amount' => $money['ppn_amount'], 'total_amount' => $money['grand_total'],
            'occurred_at' => $occurredAt, 'transaction_id' => $transactionId,
            'request_fingerprint' => (string) $sale['request_fingerprint'],
            'business_date' => (string) $sale['business_date'], 'timezone' => (string) $sale['timezone'],
            'gross_amount' => $money['gross_amount'], 'item_discount_amount' => $money['item_discount_amount'],
            'transaction_discount_amount' => $money['transaction_discount_amount'], 'discount_amount' => $money['discount_amount'],
            'taxable_dpp' => $money['taxable_dpp'], 'exempt_dpp' => $money['exempt_dpp'], 'dpp' => $money['dpp'],
            'ppn_amount' => $money['ppn_amount'], 'grand_total' => $money['grand_total'],
            'cogs_amount' => $money['cogs_amount'], 'created_at' => $created, 'updated_at' => $created,
        ]);

        foreach ($prepared as $entry) {
            $item = $entry['source'];
            $lineId = $entry['id'];
            $db->table('sale_items')->insert([
                'sale_id' => $saleId, 'client_line_id' => $lineId, 'line_no' => (int) $item['line_no'],
                'product_id' => $entry['product_id'], 'product_name' => (string) $db->table('products')->where('id', $entry['product_id'])->value('name'),
                'quantity' => $entry['quantity'], 'unit_price' => $entry['unit_price'], 'line_total' => $entry['dpp'], 'unit_cost' => 0,
                'gross_amount' => $entry['gross'], 'item_discount_amount' => $entry['item_discount'],
                'transaction_discount_amount' => $entry['transaction_discount'], 'discount_amount' => $entry['discount'],
                'dpp' => $entry['dpp'], 'ppn_exempt' => $entry['tax_exempt'], 'cogs_amount' => $entry['cogs'],
                'created_at' => $created, 'updated_at' => $created,
            ]);

            foreach ($entry['allocations'] as $allocation) {
                $lot = $db->table('inventory_lots')->where('id', $allocation['lot_id'])
                    ->where('product_id', $entry['product_id'])->lockForUpdate()->first();
                $lotRemaining = $lot === null ? null : $this->databaseScaledInteger($lot->quantity_remaining, 3);
                if ($lot === null || $lotRemaining === null || $lotRemaining < $allocation['quantity'] * 1000) {
                    throw new SyncConflictException('Lot tidak lagi tersedia saat commit.');
                }
                $changed = $db->table('inventory_lots')->where('id', $allocation['lot_id'])
                    ->where('product_id', $entry['product_id'])
                    ->where('quantity_remaining', '>=', $allocation['quantity'])
                    ->decrement('quantity_remaining', $allocation['quantity']);
                if ($changed !== 1) throw new SyncConflictException('Kuantitas lot berubah saat commit.');

                $db->table('sale_lot_allocations')->insert([
                    'sale_item_id' => $lineId, 'allocation_no' => $allocation['allocation_no'],
                    'lot_id' => $allocation['lot_id'], 'quantity' => $allocation['quantity'],
                    'created_at' => $created, 'updated_at' => $created,
                ]);
                $db->table('inventory_movements')->insert([
                    'source_event_id' => $eventId, 'product_id' => $entry['product_id'], 'lot_id' => $allocation['lot_id'],
                    'movement_type' => 'sale_fefo', 'quantity' => -$allocation['quantity'],
                    'reference_id' => $transactionId, 'occurred_at' => $occurredAt,
                    'created_at' => $created, 'updated_at' => $created,
                ]);
            }

            foreach ($entry['consumptions'] as $consumption) {
                $layer = $db->table('inventory_cost_layers')->where('id', $consumption['cost_layer_id'])
                    ->where('product_id', $entry['product_id'])->lockForUpdate()->first();
                $layerRemaining = $layer === null ? null : $this->databaseScaledInteger($layer->remaining_qty, 3);
                $layerUnitCost = $layer === null ? null : $this->databaseScaledInteger($layer->unit_cost, 2);
                if ($layer === null || $layerRemaining === null || $layerUnitCost === null
                    || $layerRemaining < $consumption['quantity'] * 1000 || $layerUnitCost !== $consumption['unit_cost'] * 100) {
                    throw new SyncConflictException('Cost layer tidak lagi cocok dengan konsumsi FIFO lokal.');
                }
                $changed = $db->table('inventory_cost_layers')->where('id', $consumption['cost_layer_id'])
                    ->where('product_id', $entry['product_id'])
                    ->where('remaining_qty', '>=', $consumption['quantity'])
                    ->decrement('remaining_qty', $consumption['quantity']);
                if ($changed !== 1) throw new SyncConflictException('Sisa cost layer berubah saat commit.');

                $db->table('cost_layer_consumptions')->insert([
                    'sale_item_id' => $lineId, 'consumption_no' => $consumption['consumption_no'],
                    'cost_layer_id' => $consumption['cost_layer_id'], 'quantity' => $consumption['quantity'],
                    'unit_cost' => $consumption['unit_cost'], 'total_cost' => $consumption['total_cost'],
                    'created_at' => $created, 'updated_at' => $created,
                ]);
                $db->table('stock_movements')->insert([
                    'id' => 'sync:'.substr(hash('sha256', $eventId.'|'.$lineId.'|'.$consumption['consumption_no']), 0, 48),
                    'source_event_id' => $eventId, 'product_id' => $entry['product_id'], 'reference_id' => $transactionId,
                    'movement_type' => 'sale_fifo_cogs', 'quantity_delta' => -$consumption['quantity'],
                    'unit_cost' => $consumption['unit_cost'], 'total_cost' => $consumption['total_cost'],
                    'occurred_at' => $occurredAt, 'created_at' => $created, 'updated_at' => $created,
                ]);
            }

            $updated = $db->table('products')->where('id', $entry['product_id'])
                ->where('stock_qty', '>=', $entry['quantity'])->decrement('stock_qty', $entry['quantity']);
            if ($updated !== 1) throw new SyncConflictException('Stok agregat produk berubah saat commit.');
        }

        $journalId = $this->requiredString($journal, 'id');
        $db->table('journal_entries')->insert([
            'id' => $journalId, 'source_event_id' => $eventId, 'transaction_id' => $transactionId,
            'description' => 'POS sale '.$transactionId, 'journal_date' => (string) $sale['business_date'],
            'occurred_at' => $occurredAt, 'timezone' => (string) $sale['timezone'],
            'period_id' => $period->id, 'status' => 'draft',
            'created_at' => $created, 'updated_at' => $created,
        ]);
        foreach ($expectedJournal as $line) {
            $db->table('journal_lines')->insert([
                'journal_entry_id' => $journalId, 'line_no' => $line['line_no'],
                'account_code' => $line['account_code'], 'debit' => $line['debit'], 'credit' => $line['credit'],
                'created_at' => $created, 'updated_at' => $created,
            ]);
        }

        // The PostgreSQL trigger validates that this journal is balanced and the
        // accounting period is open before the entry becomes immutable.
        $posted = $db->table('journal_entries')
            ->where('id', $journalId)
            ->where('status', 'draft')
            ->update([
                'status' => 'posted',
                'posted_at' => $created,
                'posted_by' => (string) $actorId,
                'device_id' => $deviceId,
                'app_version' => $appVersion,
                'period_id' => $period->id,
                'updated_at' => $created,
            ]);
        if ($posted !== 1) {
            throw new SyncConflictException('Jurnal tidak dapat diposting dalam status saat ini.');
        }

        // PostgreSQL's journal-posting trigger appends the immutable accounting_events row.

        $response = ['event_id' => $eventId, 'status' => 'accepted', 'receipt_id' => $eventId,
            'transaction_id' => $transactionId];
        $db->table('sync_receipts')->insert([
            'event_id' => $eventId, 'device_id' => $deviceId, 'payload_sha256' => $payloadHash,
            'response' => json_encode($response, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR),
            'accepted_at' => now(), 'created_at' => $created, 'updated_at' => $created,
        ]);

        return $response;
    }

    /**
     * Accepts full/partial customer returns and full voids on the authenticated
     * tenant DB. All effects and the idempotency receipt commit in the runner's
     * transaction. Returned goods are always new quarantine lots; the original
     * physical and financial records remain unchanged.
     */
    private function acceptSaleReturnEvent(
        Connection $db,
        array $event,
        array $payload,
        string $deviceId,
        string $payloadHash,
        int $actorId,
        string $appVersion
    ): array {
        $record = $payload['return'] ?? null;
        $requestedItems = $payload['items'] ?? null;
        if (! is_array($record) || ! is_array($requestedItems) || count($requestedItems) < 1 || count($requestedItems) > 100) {
            throw new SyncConflictException('Payload retur tidak lengkap atau melebihi batas.');
        }

        $returnId = trim($this->requiredString($record, 'id'));
        if (strlen($returnId) > 100 || (string) $event['entity_id'] !== $returnId
            || (string) $event['event_id'] !== 'outbox:sale_return:'.$returnId) {
            throw new SyncConflictException('ID retur tidak cocok dengan envelope idempoten.');
        }
        if ($db->table('sale_returns')->where('id', $returnId)->exists()) {
            throw new SyncConflictException('ID retur telah digunakan oleh event lain.');
        }

        $returnType = strtolower(trim($this->requiredString($record, 'return_type')));
        if (! in_array($returnType, ['return', 'void'], true)) {
            throw new SyncConflictException('Jenis operasi harus return atau void.');
        }
        $reason = trim($this->requiredString($record, 'reason'));
        if ($reason === '' || strlen($reason) > 500) {
            throw new SyncConflictException('Alasan retur wajib diisi dan maksimal 500 karakter.');
        }
        $requestFingerprint = trim($this->requiredString($record, 'request_fingerprint'));
        if (strlen($requestFingerprint) !== 64 || ! ctype_xdigit($requestFingerprint)) {
            throw new SyncConflictException('Fingerprint retur tidak valid.');
        }

        $originalSaleId = trim($this->requiredString($record, 'original_sale_id'));
        $businessDate = trim($this->requiredString($record, 'business_date'));
        try {
            $parsedBusinessDate = Carbon::createFromFormat('!Y-m-d', $businessDate);
        } catch (Throwable) {
            $parsedBusinessDate = false;
        }
        if ($parsedBusinessDate === false || $parsedBusinessDate->format('Y-m-d') !== $businessDate) {
            throw new SyncConflictException('Tanggal retur harus berupa YYYY-MM-DD yang valid.');
        }

        $occurredAtRaw = $this->requiredString($record, 'occurred_at_utc');
        $timezone = trim($this->requiredString($record, 'timezone'));
        if (strlen($timezone) > 64) throw new SyncConflictException('Zona waktu retur tidak valid.');
        try {
            $occurredAt = Carbon::parse($occurredAtRaw)->utc();
            $returnBusinessDate = $occurredAt->copy()->setTimezone($timezone)->toDateString();
        } catch (Throwable) {
            throw new SyncConflictException('Waktu atau zona waktu retur tidak valid.');
        }
        if ($returnBusinessDate !== $businessDate) {
            throw new SyncConflictException('Tanggal bisnis dan waktu kejadian retur tidak konsisten.');
        }

        $sale = $db->table('sales')->where('id', $originalSaleId)->lockForUpdate()->first();
        if ($sale === null || (string) $sale->status !== 'accepted') {
            throw new SyncConflictException('Penjualan asal tidak ditemukan atau tidak dapat diretur.');
        }
        $originalJournal = $db->table('journal_entries')
            ->where('transaction_id', (string) $sale->transaction_id)
            ->where('status', 'posted')
            ->lockForUpdate()
            ->first();
        if ($originalJournal === null) {
            throw new SyncConflictException('Jurnal penjualan asal tidak ditemukan dalam status posted.');
        }

        $refundMethod = trim($this->requiredString($record, 'refund_method'));
        if (! isset(self::PAYMENT_ACCOUNTS[(string) $sale->payment_method])
            || ! isset(self::PAYMENT_ACCOUNTS[$refundMethod])
            || self::PAYMENT_ACCOUNTS[(string) $sale->payment_method] !== self::PAYMENT_ACCOUNTS[$refundMethod]) {
            throw new SyncConflictException('Refund wajib memakai metode pembayaran penjualan asal.');
        }

        $saleItems = $db->table('sale_items')
            ->where('sale_id', $originalSaleId)
            ->orderBy('line_no')
            ->lockForUpdate()
            ->get();
        if ($saleItems->isEmpty()) throw new SyncConflictException('Penjualan asal tidak memiliki rincian item.');

        $alreadyReturnedQuery = $db->table('sale_returns')->where('original_sale_id', $originalSaleId);
        if ($returnType === 'void' && $alreadyReturnedQuery->exists()) {
            throw new SyncConflictException('Void penuh tidak diizinkan setelah ada retur pada penjualan ini.');
        }
        if ($returnType === 'void' && $db->table('journal_entries')
            ->where('reversal_of_id', (string) $originalJournal->id)->exists()) {
            throw new SyncConflictException('Jurnal penjualan asal sudah memiliki reversal penuh.');
        }

        $linesById = [];
        foreach ($saleItems as $saleItem) {
            $lineId = trim((string) ($saleItem->client_line_id ?? ''));
            if ($lineId === '') throw new SyncConflictException('Rincian penjualan tidak memiliki ID baris stabil.');
            $linesById[$lineId] = $saleItem;
        }

        $normalizedRequests = [];
        foreach (array_values($requestedItems) as $row) {
            if (! is_array($row)) throw new SyncConflictException('Rincian retur tidak valid.');
            $lineId = trim($this->requiredString($row, 'sale_item_id'));
            if (isset($normalizedRequests[$lineId]) || ! isset($linesById[$lineId])) {
                throw new SyncConflictException('ID item retur tidak ada pada penjualan asal atau duplikat.');
            }
            $quantity = $this->payloadQuantity($row, 'quantity');
            $normalizedRequests[$lineId] = $quantity;
        }

        if ($returnType === 'void' && count($normalizedRequests) !== count($linesById)) {
            throw new SyncConflictException('Void harus mencakup seluruh baris penjualan.');
        }

        $prepared = [];
        $refundGross = 0;
        $refundItemDiscount = 0;
        $refundTransactionDiscount = 0;
        $refundDiscount = 0;
        $refundDpp = 0;
        $refundTaxableDpp = 0;
        $refundExemptDpp = 0;
        $returnedQuantity = 0;
        $totalReturnedCogs = 0;

        foreach ($normalizedRequests as $lineId => $quantity) {
            $line = $linesById[$lineId];
            $soldQuantity = $this->databaseQuantity($line->quantity);
            $previousQuantity = $this->databaseQuantity(
                $db->table('sale_return_items')
                    ->where('original_sale_id', $originalSaleId)
                    ->where('sale_item_id', $lineId)
                    ->sum('quantity')
            );
            $cumulativeQuantity = $previousQuantity + $quantity;
            if ($soldQuantity <= 0 || $cumulativeQuantity > $soldQuantity) {
                throw new SyncConflictException('Jumlah retur melebihi jumlah yang benar-benar terjual.');
            }
            if ($returnType === 'void' && ($previousQuantity !== 0 || $cumulativeQuantity !== $soldQuantity)) {
                throw new SyncConflictException('Void harus membalik seluruh kuantitas penjualan tanpa retur sebelumnya.');
            }

            $previousGross = $this->databaseRupiah(
                $db->table('sale_return_items')->where('original_sale_id', $originalSaleId)
                    ->where('sale_item_id', $lineId)->sum('refund_gross')
            );
            $previousItemDiscount = $this->databaseRupiah(
                $db->table('sale_return_items')->where('original_sale_id', $originalSaleId)
                    ->where('sale_item_id', $lineId)->sum('refund_item_discount_amount')
            );
            $previousTransactionDiscount = $this->databaseRupiah(
                $db->table('sale_return_items')->where('original_sale_id', $originalSaleId)
                    ->where('sale_item_id', $lineId)->sum('refund_transaction_discount_amount')
            );
            $previousDpp = $this->databaseRupiah(
                $db->table('sale_return_items')->where('original_sale_id', $originalSaleId)
                    ->where('sale_item_id', $lineId)->sum('refund_dpp')
            );

            $targetGross = $this->proportionalAmount(
                $this->databaseRupiah($line->gross_amount), $soldQuantity, $cumulativeQuantity
            );
            $targetItemDiscount = $this->proportionalAmount(
                $this->databaseRupiah($line->item_discount_amount), $soldQuantity, $cumulativeQuantity
            );
            $targetTransactionDiscount = $this->proportionalAmount(
                $this->databaseRupiah($line->transaction_discount_amount), $soldQuantity, $cumulativeQuantity
            );
            $lineGross = $targetGross - $previousGross;
            $lineItemDiscount = $targetItemDiscount - $previousItemDiscount;
            $lineTransactionDiscount = $targetTransactionDiscount - $previousTransactionDiscount;
            $lineDiscount = $lineItemDiscount + $lineTransactionDiscount;
            $lineDpp = ($targetGross - $targetItemDiscount - $targetTransactionDiscount) - $previousDpp;
            if ($lineGross < 0 || $lineDiscount < 0 || $lineDpp < 0
                || $lineGross - $lineDiscount !== $lineDpp) {
                throw new SyncConflictException('Alokasi nilai item retur tidak konsisten dengan transaksi asal.');
            }

            $physicalRows = $db->table('sale_lot_allocations')
                ->where('sale_item_id', $lineId)
                ->orderBy('allocation_no')
                ->get();
            if ($physicalRows->isEmpty()) throw new SyncConflictException('Asal lot fisik penjualan tidak tersedia.');

            $physicalAllocations = [];
            $remainingPhysical = $quantity;
            foreach ($physicalRows as $physical) {
                if ($remainingPhysical <= 0) break;
                $soldFromLot = $this->databaseQuantity($physical->quantity);
                $previousFromLot = $this->databaseQuantity(
                    $db->table('sale_return_lot_allocations')
                        ->where('original_sale_id', $originalSaleId)
                        ->where('original_sale_item_id', $lineId)
                        ->where('source_lot_id', (string) $physical->lot_id)
                        ->sum('quantity')
                );
                $availableFromLot = max(0, $soldFromLot - $previousFromLot);
                $take = min($remainingPhysical, $availableFromLot);
                if ($take <= 0) continue;
                $sourceLot = $db->table('inventory_lots')
                    ->where('id', (string) $physical->lot_id)
                    ->where('product_id', (string) $line->product_id)
                    ->lockForUpdate()
                    ->first();
                if ($sourceLot === null) throw new SyncConflictException('Lot asal penjualan tidak tersedia untuk audit.');
                $physicalAllocations[] = [
                    'source_lot_id' => (string) $sourceLot->id,
                    'batch_code' => (string) ($sourceLot->batch_code ?? ''),
                    'expires_at' => $sourceLot->expires_at,
                    'unit_cost' => $this->databaseRupiah($sourceLot->unit_cost),
                    'quantity' => $take,
                    'allocation_no' => count($physicalAllocations),
                ];
                $remainingPhysical -= $take;
            }
            if ($remainingPhysical !== 0) {
                throw new SyncConflictException('Kuantitas retur tidak dapat ditelusuri ke alokasi lot fisik penjualan.');
            }

            $costRows = $db->table('cost_layer_consumptions')
                ->where('sale_item_id', $lineId)
                ->orderByDesc('consumption_no')
                ->get();
            if ($costRows->isEmpty()) throw new SyncConflictException('Asal cost layer FIFO penjualan tidak tersedia.');
            $costAllocations = [];
            $remainingCostQuantity = $quantity;
            $lineCogs = 0;
            foreach ($costRows as $costRow) {
                if ($remainingCostQuantity <= 0) break;
                $soldFromLayer = $this->databaseQuantity($costRow->quantity);
                $previousFromLayer = $this->databaseQuantity(
                    $db->table('sale_return_cost_layers')
                        ->where('original_sale_id', $originalSaleId)
                        ->where('original_sale_item_id', $lineId)
                        ->where('source_cost_layer_id', (string) $costRow->cost_layer_id)
                        ->sum('quantity')
                );
                $availableFromLayer = max(0, $soldFromLayer - $previousFromLayer);
                $take = min($remainingCostQuantity, $availableFromLayer);
                if ($take <= 0) continue;
                $unitCost = $this->databaseRupiah($costRow->unit_cost);
                if ($unitCost < 0 || ($unitCost > 0 && $take > intdiv(PHP_INT_MAX, $unitCost))) {
                    throw new SyncConflictException('Nilai biaya retur melebihi batas integer rupiah.');
                }
                $totalCost = $take * $unitCost;
                $sourceCostLayer = $db->table('inventory_cost_layers')
                    ->where('id', (string) $costRow->cost_layer_id)
                    ->where('product_id', (string) $line->product_id)
                    ->first();
                if ($sourceCostLayer === null) {
                    throw new SyncConflictException('Cost layer FIFO asal retur tidak ditemukan.');
                }
                $costAllocations[] = [
                    'source_cost_layer_id' => (string) $costRow->cost_layer_id,
                    'financial_lot_id' => $sourceCostLayer->lot_id,
                    'quantity' => $take,
                    'unit_cost' => $unitCost,
                    'total_cost' => $totalCost,
                    'consumption_no' => count($costAllocations),
                ];
                $lineCogs += $totalCost;
                $remainingCostQuantity -= $take;
            }
            if ($remainingCostQuantity !== 0) {
                throw new SyncConflictException('Kuantitas retur tidak dapat ditelusuri ke cost layer FIFO penjualan.');
            }

            $taxExempt = $this->databaseBoolean($line->ppn_exempt ?? false);
            $prepared[] = [
                'line_id' => $lineId,
                'line' => $line,
                'quantity' => $quantity,
                'returned_quantity' => $returnedQuantity + $quantity,
                'gross' => $lineGross,
                'item_discount' => $lineItemDiscount,
                'transaction_discount' => $lineTransactionDiscount,
                'discount' => $lineDiscount,
                'dpp' => $lineDpp,
                'ppn_exempt' => $taxExempt,
                'cogs' => $lineCogs,
                'physical_allocations' => $physicalAllocations,
                'cost_allocations' => $costAllocations,
            ];
            $refundGross += $lineGross;
            $refundItemDiscount += $lineItemDiscount;
            $refundTransactionDiscount += $lineTransactionDiscount;
            $refundDiscount += $lineDiscount;
            $refundDpp += $lineDpp;
            if ($taxExempt) $refundExemptDpp += $lineDpp;
            else $refundTaxableDpp += $lineDpp;
            $returnedQuantity += $quantity;
            $totalReturnedCogs += $lineCogs;
        }

        if ($returnType === 'void' && $returnedQuantity <= 0) {
            throw new SyncConflictException('Void penuh harus mencakup kuantitas penjualan.');
        }

        $originalTaxableDpp = $this->databaseRupiah($sale->taxable_dpp);
        $originalPpn = $this->databaseRupiah($sale->ppn_amount);
        $previousReturnedTaxableDpp = $this->databaseRupiah(
            $db->table('sale_returns')->where('original_sale_id', $originalSaleId)->sum('refund_taxable_dpp')
        );
        $previousReturnedPpn = $this->databaseRupiah(
            $db->table('sale_returns')->where('original_sale_id', $originalSaleId)->sum('refund_ppn_amount')
        );
        $cumulativeTaxableDpp = $previousReturnedTaxableDpp + $refundTaxableDpp;
        if ($cumulativeTaxableDpp > $originalTaxableDpp) {
            throw new SyncConflictException('DPP kena pajak yang diretur melebihi DPP penjualan asal.');
        }
        $targetRefundPpn = $originalTaxableDpp === 0 || $cumulativeTaxableDpp === 0
            ? 0
            : ($cumulativeTaxableDpp >= $originalTaxableDpp
                ? $originalPpn
                : $this->roundProportion($originalPpn, $cumulativeTaxableDpp, $originalTaxableDpp));
        $refundPpn = $targetRefundPpn - $previousReturnedPpn;
        if ($refundPpn < 0 || $refundPpn > $originalPpn) {
            throw new SyncConflictException('Alokasi PPN retur tidak konsisten dengan invoice asal.');
        }
        $refundTotal = $refundDpp + $refundPpn;
        $now = now();
        $period = $db->table('accounting_periods')
            ->where('starts_on', '<=', $businessDate)
            ->where('ends_on', '>=', $businessDate)
            ->where('status', 'open')
            ->orderBy('starts_on')
            ->lockForUpdate()
            ->first();
        if ($period === null) {
            throw new SyncConflictException('Retur/void memerlukan periode akuntansi terbuka untuk tanggal bisnis retur.');
        }
        if ($db->table('accounting_periods')
            ->where('starts_on', '<=', $businessDate)
            ->where('ends_on', '>=', $businessDate)
            ->where('status', 'closed')->exists()) {
            throw new SyncConflictException('Periode akuntansi retur sudah ditutup.');
        }

        $journalId = 'journal:return:'.substr(hash('sha256', $returnId), 0, 48);
        $journalTransactionId = 'return:'.$returnId;
        if ($db->table('journal_entries')->where('id', $journalId)
            ->orWhere('transaction_id', $journalTransactionId)->exists()) {
            throw new SyncConflictException('ID jurnal retur telah digunakan tanpa receipt yang cocok.');
        }

        // Create the parent inside the same DB transaction. A failure in any child,
        // lot, cost layer, journal or receipt operation rolls this row back too.
        $db->table('sale_returns')->insert([
            'id' => $returnId,
            'event_id' => (string) $event['event_id'],
            'original_sale_id' => $originalSaleId,
            'original_transaction_id' => (string) $sale->transaction_id,
            'return_type' => $returnType,
            'refund_method' => $refundMethod,
            'reason' => $reason,
            'business_date' => $businessDate,
            'occurred_at' => $occurredAt,
            'timezone' => $timezone,
            'actor_id' => (string) $actorId,
            'origin_actor_id' => isset($record['origin_actor_id']) && is_string($record['origin_actor_id']) ? trim($record['origin_actor_id']) : null,
            'approved_by_user_id' => (string) $actorId,
            'approval_mode' => 'self',
            'approved_at' => $now,
            'device_id' => $deviceId,
            'app_version' => $appVersion,
            'request_fingerprint' => strtolower($requestFingerprint),
            'refund_gross' => $refundGross,
            'refund_discount_amount' => $refundDiscount,
            'refund_dpp' => $refundDpp,
            'refund_taxable_dpp' => $refundTaxableDpp,
            'refund_exempt_dpp' => $refundExemptDpp,
            'refund_ppn_amount' => $refundPpn,
            'refund_total' => $refundTotal,
            'cogs_amount' => $totalReturnedCogs,
            'journal_entry_id' => null,
            'original_journal_entry_id' => (string) $originalJournal->id,
            'status' => 'accepted',
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $productQuantities = [];
        foreach ($prepared as $lineIndex => $entry) {
            $lineId = (string) $entry['line_id'];
            $returnItemId = 'return-item:'.substr(hash('sha256', $returnId.'|'.$lineId), 0, 48);
            $quarantineLots = [];
            foreach ($entry['physical_allocations'] as $allocIndex => $physical) {
                $quarantineLotId = 'return-lot:'.substr(
                    hash('sha256', (string) $event['event_id'].'|'.$lineId.'|'.$physical['source_lot_id'].'|'.$allocIndex),
                    0,
                    48
                );
                if ($db->table('inventory_lots')->where('id', $quarantineLotId)->exists()) {
                    throw new SyncConflictException('ID lot karantina retur telah digunakan tanpa receipt yang cocok.');
                }
                $batchCode = 'RET-'.substr(hash('sha256', $returnId.'|'.$physical['source_lot_id'].'|'.$allocIndex), 0, 32);
                $db->table('inventory_lots')->insert([
                    'id' => $quarantineLotId,
                    'product_id' => (string) $entry['line']->product_id,
                    'batch_code' => $batchCode,
                    'expires_at' => $physical['expires_at'],
                    'quantity_received' => $physical['quantity'],
                    'quantity_remaining' => $physical['quantity'],
                    'unit_cost' => $physical['unit_cost'],
                    'received_at' => $occurredAt,
                    'reserved_qty' => 0,
                    'status' => 'quarantine',
                    'origin_lot_id' => $physical['source_lot_id'],
                    'source_return_id' => $returnId,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
                $quarantineLots[] = [
                    'id' => $quarantineLotId,
                    'source_lot_id' => $physical['source_lot_id'],
                    'quantity' => $physical['quantity'],
                    'allocation_no' => $physical['allocation_no'],
                ];
            }

            $db->table('sale_return_items')->insert([
                'id' => $returnItemId,
                'sale_return_id' => $returnId,
                'original_sale_id' => $originalSaleId,
                'sale_item_id' => $lineId,
                'product_id' => (string) $entry['line']->product_id,
                'quantity' => $entry['quantity'],
                'refund_gross' => $entry['gross'],
                'refund_item_discount_amount' => $entry['item_discount'],
                'refund_transaction_discount_amount' => $entry['transaction_discount'],
                'refund_discount_amount' => $entry['discount'],
                'refund_dpp' => $entry['dpp'],
                'ppn_exempt' => $entry['ppn_exempt'],
                'cogs_amount' => $entry['cogs'],
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            foreach ($quarantineLots as $quarantineLot) {
                $db->table('sale_return_lot_allocations')->insert([
                    'sale_return_item_id' => $returnItemId,
                    'original_sale_id' => $originalSaleId,
                    'original_sale_item_id' => $lineId,
                    'source_lot_id' => $quarantineLot['source_lot_id'],
                    'quarantine_lot_id' => $quarantineLot['id'],
                    'quantity' => $quarantineLot['quantity'],
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
                $db->table('inventory_movements')->insert([
                    'source_event_id' => (string) $event['event_id'],
                    'product_id' => (string) $entry['line']->product_id,
                    'lot_id' => $quarantineLot['id'],
                    'movement_type' => $returnType === 'void' ? 'void_quarantine' : 'return_quarantine',
                    'quantity' => $quarantineLot['quantity'],
                    'reference_id' => $returnId,
                    'occurred_at' => $occurredAt,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
            }

            foreach ($entry['cost_allocations'] as $costIndex => $cost) {
                $sourceCostLayerId = (string) $cost['source_cost_layer_id'];
                $sourceCostLayer = $db->table('inventory_cost_layers')
                    ->where('id', $sourceCostLayerId)
                    ->where('product_id', (string) $entry['line']->product_id)
                    ->lockForUpdate()
                    ->first();
                if ($sourceCostLayer === null
                    || $this->databaseRupiah($sourceCostLayer->unit_cost) !== (int) $cost['unit_cost']) {
                    throw new SyncConflictException('Cost layer FIFO asal berubah; retur perlu rekonsiliasi.');
                }
                // Restore quantity to its original FIFO layer so its acquisition
                // age and approved unit cost remain unchanged. Physical FEFO
                // disposition is tracked independently in the quarantine lot.
                $changedLayer = $db->table('inventory_cost_layers')
                    ->where('id', $sourceCostLayerId)
                    ->where('product_id', (string) $entry['line']->product_id)
                    ->increment('remaining_qty', $cost['quantity'], ['updated_at' => $now]);
                if ($changedLayer !== 1) {
                    throw new SyncConflictException('Kuantitas layer FIFO asal tidak dapat dipulihkan.');
                }
                $returnedCostLayerId = $sourceCostLayerId;
                $db->table('sale_return_cost_layers')->insert([
                    'sale_return_item_id' => $returnItemId,
                    'original_sale_id' => $originalSaleId,
                    'original_sale_item_id' => $lineId,
                    'source_cost_layer_id' => $cost['source_cost_layer_id'],
                    'returned_cost_layer_id' => $returnedCostLayerId,
                    'quantity' => $cost['quantity'],
                    'unit_cost' => $cost['unit_cost'],
                    'total_cost' => $cost['total_cost'],
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
                $db->table('stock_movements')->insert([
                    'id' => 'sync:'.substr(hash('sha256', (string) $event['event_id'].'|return|'.$lineId.'|'.$costIndex), 0, 48),
                    'source_event_id' => (string) $event['event_id'],
                    'product_id' => (string) $entry['line']->product_id,
                    'reference_id' => $returnId,
                    'movement_type' => 'return_fifo_cogs',
                    'quantity_delta' => $cost['quantity'],
                    'unit_cost' => $cost['unit_cost'],
                    'total_cost' => $cost['total_cost'],
                    'occurred_at' => $occurredAt,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
            }

            $productId = (string) $entry['line']->product_id;
            $productQuantities[$productId] = ($productQuantities[$productId] ?? 0) + (int) $entry['quantity'];
        }

        foreach ($productQuantities as $productId => $quantity) {
            if ($db->table('products')->where('id', $productId)
                ->increment('stock_qty', $quantity, ['updated_at' => $now]) !== 1) {
                throw new SyncConflictException('Stok agregat produk tidak dapat dikembalikan.');
            }
        }

        if ($returnType === 'void') {
            $originalLines = $db->table('journal_lines')
                ->where('journal_entry_id', (string) $originalJournal->id)
                ->orderBy('line_no')
                ->get();
            if ($originalLines->count() < 2) {
                throw new SyncConflictException('Jurnal asal tidak memiliki baris yang dapat dibalik.');
            }
            $journalLines = [];
            foreach ($originalLines as $originalLine) {
                $debit = $this->databaseRupiah($originalLine->credit);
                $credit = $this->databaseRupiah($originalLine->debit);
                if ($debit === 0 && $credit === 0) continue;
                $journalLines[] = [
                    'line_no' => count($journalLines),
                    'account_code' => (string) $originalLine->account_code,
                    'debit' => $debit,
                    'credit' => $credit,
                ];
            }
            if (array_sum(array_column($journalLines, 'debit')) !== array_sum(array_column($journalLines, 'credit'))) {
                throw new SyncConflictException('Jurnal reversal hasil perhitungan tidak seimbang.');
            }
        } else {
            $journalLines = [];
            $appendLine = static function (array &$lines, string $account, int $debit, int $credit): void {
                if ($debit === 0 && $credit === 0) return;
                $lines[] = [
                    'line_no' => count($lines),
                    'account_code' => $account,
                    'debit' => $debit,
                    'credit' => $credit,
                ];
            };
            $appendLine($journalLines, '4-4030', $refundDpp, 0);
            $appendLine($journalLines, '2-2010', $refundPpn, 0);
            $paymentCredit = $refundTotal;
            $appendLine($journalLines, self::PAYMENT_ACCOUNTS[$refundMethod], 0, $paymentCredit);
            $appendLine($journalLines, '1-1040', $totalReturnedCogs, 0);
            $appendLine($journalLines, '5-5010', 0, $totalReturnedCogs);

            if (array_sum(array_column($journalLines, 'debit')) !== array_sum(array_column($journalLines, 'credit'))) {
                throw new SyncConflictException('Jurnal retur tidak seimbang; tidak ada perubahan yang diterapkan.');
            }
        }
        if (count($journalLines) < 2) {
            throw new SyncConflictException('Jurnal retur kosong atau tidak memenuhi entri ganda.');
        }

        $db->table('journal_entries')->insert([
            'id' => $journalId,
            'source_event_id' => (string) $event['event_id'],
            'transaction_id' => $journalTransactionId,
            'description' => ($returnType === 'void' ? 'POS void ' : 'POS return ').(string) $sale->transaction_id.' / '.$returnId,
            'journal_date' => $businessDate,
            'occurred_at' => $occurredAt,
            'timezone' => $timezone,
            'period_id' => $period->id,
            'status' => 'draft',
            'reversal_of_id' => $returnType === 'void' ? (string) $originalJournal->id : null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        foreach ($journalLines as $journalLine) {
            $db->table('journal_lines')->insert([
                'journal_entry_id' => $journalId,
                'line_no' => $journalLine['line_no'],
                'account_code' => $journalLine['account_code'],
                'debit' => $journalLine['debit'],
                'credit' => $journalLine['credit'],
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }
        $posted = $db->table('journal_entries')->where('id', $journalId)->where('status', 'draft')
            ->update([
                'status' => 'posted',
                'posted_at' => $now,
                'posted_by' => (string) $actorId,
                'device_id' => $deviceId,
                'app_version' => $appVersion,
                'period_id' => $period->id,
                'updated_at' => $now,
            ]);
        if ($posted !== 1) throw new SyncConflictException('Jurnal retur/reversal tidak dapat diposting.');

        $db->table('sale_returns')->where('id', $returnId)->update([
            'journal_entry_id' => $journalId,
            'updated_at' => $now,
        ]);

        $response = [
            'event_id' => (string) $event['event_id'],
            'status' => 'accepted',
            'receipt_id' => (string) $event['event_id'],
            'return_id' => $returnId,
            'original_sale_id' => $originalSaleId,
            'return_type' => $returnType,
            'refund_total' => $refundTotal,
            'cogs_amount' => $totalReturnedCogs,
            'journal_entry_id' => $journalId,
            'reversal_of_id' => $returnType === 'void' ? (string) $originalJournal->id : null,
            'quarantine_required' => true,
            'approval_mode' => 'self',
        ];
        $this->saveSyncReceipt($db, (string) $event['event_id'], $deviceId, $payloadHash, $response, $now);
        return $response;
    }

    /**
     * Stock disposition-only operations are permitted without a new COA mapping.
     * Quantity adjustments/write-offs are rejected until the owner approves the
     * existing account mapping for their valuation effect.
     */
    private function acceptStockAdjustmentEvent(
        Connection $db,
        array $event,
        array $payload,
        string $deviceId,
        string $payloadHash,
        int $actorId,
        string $appVersion
    ): array {
        $adjustment = $payload['adjustment'] ?? null;
        if (! is_array($adjustment)) throw new SyncConflictException('Payload penyesuaian stok tidak lengkap.');

        $adjustmentId = trim($this->requiredString($adjustment, 'id'));
        if (strlen($adjustmentId) > 100 || (string) $event['entity_id'] !== $adjustmentId
            || (string) $event['event_id'] !== 'outbox:stock_adjustment:'.$adjustmentId) {
            throw new SyncConflictException('ID penyesuaian stok tidak cocok dengan envelope.');
        }
        if ($db->table('stock_adjustments')->where('id', $adjustmentId)->exists()) {
            throw new SyncConflictException('ID penyesuaian stok telah digunakan oleh event lain.');
        }
        $reason = trim($this->requiredString($adjustment, 'reason'));
        if ($reason === '' || strlen($reason) > 500) {
            throw new SyncConflictException('Alasan penyesuaian stok wajib diisi dan maksimal 500 karakter.');
        }
        $requestFingerprint = trim($this->requiredString($adjustment, 'request_fingerprint'));
        if (strlen($requestFingerprint) !== 64 || ! ctype_xdigit($requestFingerprint)) {
            throw new SyncConflictException('Fingerprint penyesuaian stok tidak valid.');
        }
        $quantityDelta = $adjustment['quantity_delta'] ?? null;
        if (! is_int($quantityDelta) || $quantityDelta !== 0) {
            throw new SyncConflictException(
                'Koreksi kuantitas/write-off ditolak: akun lawan valuasi stok belum disetujui owner.'
            );
        }
        $businessDate = trim($this->requiredString($adjustment, 'business_date'));
        try {
            $parsedBusinessDate = Carbon::createFromFormat('!Y-m-d', $businessDate);
            $occurredAt = Carbon::parse($this->requiredString($adjustment, 'occurred_at_utc'))->utc();
            $timezone = trim($this->requiredString($adjustment, 'timezone'));
            $occurrenceDate = $occurredAt->copy()->setTimezone($timezone)->toDateString();
        } catch (Throwable) {
            throw new SyncConflictException('Tanggal, waktu, atau zona waktu penyesuaian stok tidak valid.');
        }
        if ($parsedBusinessDate === false || $parsedBusinessDate->format('Y-m-d') !== $businessDate
            || $occurrenceDate !== $businessDate || strlen($timezone) > 64) {
            throw new SyncConflictException('Tanggal bisnis dan waktu penyesuaian stok tidak konsisten.');
        }

        $productId = trim($this->requiredString($adjustment, 'product_id'));
        $lotId = trim($this->requiredString($adjustment, 'lot_id'));
        $action = trim($this->requiredString($adjustment, 'action'));
        $fromStatus = trim($this->requiredString($adjustment, 'from_status'));
        $toStatus = trim($this->requiredString($adjustment, 'to_status'));
        $allowed = [
            'quarantine' => ['saleable', 'quarantine'],
            'release_quarantine' => ['quarantine', 'saleable'],
            'mark_damaged' => ['saleable', 'damaged'],
            'mark_recall' => ['saleable', 'recall'],
            'mark_expired' => ['saleable', 'expired'],
        ];
        if (! isset($allowed[$action]) || $allowed[$action] !== [$fromStatus, $toStatus]) {
            // Also allow the documented status-to-damage/recall/expiry transition from quarantine.
            $secondaryAllowed = [
                'mark_damaged' => ['quarantine', 'damaged'],
                'mark_recall' => ['quarantine', 'recall'],
                'mark_expired' => ['quarantine', 'expired'],
            ];
            if (! isset($secondaryAllowed[$action]) || $secondaryAllowed[$action] !== [$fromStatus, $toStatus]) {
                throw new SyncConflictException('Transisi status stok tidak diizinkan.');
            }
        }
        if ($action === 'release_quarantine') {
            if (strtolower(trim((string) ($adjustment['inspection_result'] ?? ''))) !== 'passed'
                || trim((string) ($adjustment['inspection_note'] ?? '')) === '') {
                throw new SyncConflictException('Pelepasan karantina wajib memiliki hasil lulus dan catatan inspeksi.');
            }
        }
        if ($db->table('stock_adjustments')->where('id', $adjustmentId)->exists()) {
            throw new SyncConflictException('ID penyesuaian stok sudah pernah digunakan.');
        }
        $product = $db->table('products')->where('id', $productId)->lockForUpdate()->first();
        $lot = $db->table('inventory_lots')->where('id', $lotId)->where('product_id', $productId)->lockForUpdate()->first();
        if ($product === null || $lot === null) throw new SyncConflictException('Produk/lot tidak ditemukan untuk penyesuaian stok.');
        if ((string) ($lot->status ?? 'saleable') !== $fromStatus) {
            throw new SyncConflictException('Status lot berubah; penyesuaian harus diperiksa ulang.');
        }
        if ($this->databaseScaledInteger($lot->reserved_qty ?? 0, 3) > 0) {
            throw new SyncConflictException('Lot memiliki reservasi aktif dan tidak dapat diubah statusnya.');
        }
        if ($action === 'mark_expired') {
            if ($lot->expires_at === null || Carbon::parse($lot->expires_at)->toDateString() >= $businessDate) {
                throw new SyncConflictException('Lot hanya dapat ditandai expired setelah tanggal kedaluwarsanya.');
            }
        }
        if ($action === 'release_quarantine') {
            if ($lot->expires_at !== null && Carbon::parse($lot->expires_at)->toDateString() < $businessDate) {
                throw new SyncConflictException('Lot kedaluwarsa tidak boleh dilepas dari karantina.');
            }
            if ($this->databaseBoolean($product->track_expiry ?? false)) {
                if ($lot->expires_at === null) throw new SyncConflictException('Produk terlacak kedaluwarsa wajib memiliki tanggal lot.');
                $minimumDate = Carbon::parse($businessDate)
                    ->addDays((int) ($product->min_shelf_life_days ?? 0))->toDateString();
                if (Carbon::parse($lot->expires_at)->toDateString() < $minimumDate) {
                    throw new SyncConflictException('Lot tidak memenuhi minimum sisa umur simpan untuk kembali saleable.');
                }
            }
        }

        $now = now();
        $updated = $db->table('inventory_lots')->where('id', $lotId)
            ->where('product_id', $productId)
            ->where('status', $fromStatus)
            ->update(['status' => $toStatus, 'updated_at' => $now]);
        if ($updated !== 1) throw new SyncConflictException('Status lot berubah saat penyesuaian diterapkan.');

        $db->table('stock_adjustments')->insert([
            'id' => $adjustmentId,
            'event_id' => (string) $event['event_id'],
            'product_id' => $productId,
            'lot_id' => $lotId,
            'action' => $action,
            'from_status' => $fromStatus,
            'to_status' => $toStatus,
            'quantity_delta' => 0,
            'reason' => $reason,
            'inspection_note' => isset($adjustment['inspection_note']) ? trim((string) $adjustment['inspection_note']) : null,
            'inspection_result' => isset($adjustment['inspection_result']) ? trim((string) $adjustment['inspection_result']) : null,
            'business_date' => $businessDate,
            'occurred_at' => $occurredAt,
            'timezone' => $timezone,
            'actor_id' => (string) $actorId,
            'origin_actor_id' => isset($adjustment['origin_actor_id']) && is_string($adjustment['origin_actor_id']) ? trim($adjustment['origin_actor_id']) : null,
            'approved_by_user_id' => (string) $actorId,
            'approval_mode' => 'self',
            'approved_at' => $now,
            'device_id' => $deviceId,
            'app_version' => $appVersion,
            'request_fingerprint' => strtolower($requestFingerprint),
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $response = [
            'event_id' => (string) $event['event_id'],
            'status' => 'accepted',
            'receipt_id' => (string) $event['event_id'],
            'adjustment_id' => $adjustmentId,
            'product_id' => $productId,
            'lot_id' => $lotId,
            'from_status' => $fromStatus,
            'to_status' => $toStatus,
            'quantity_delta' => 0,
            'actor_id' => (string) $actorId,
            'approved_by_user_id' => (string) $actorId,
            'approval_mode' => 'self',
        ];
        $this->saveSyncReceipt($db, (string) $event['event_id'], $deviceId, $payloadHash, $response, $now);
        return $response;
    }

    private function databaseRupiah(mixed $value): int
    {
        $scaled = $this->databaseScaledInteger($value ?? 0, 2);
        if ($scaled === null || $scaled % 100 !== 0) {
            throw new SyncConflictException('Nominal database harus berupa integer rupiah.');
        }
        return intdiv($scaled, 100);
    }

    private function databaseQuantity(mixed $value): int
    {
        $scaled = $this->databaseScaledInteger($value ?? 0, 3);
        if ($scaled === null || $scaled % 1000 !== 0) {
            throw new SyncConflictException('Kuantitas retur harus berupa unit utuh sesuai transaksi asal.');
        }
        return intdiv($scaled, 1000);
    }

    private function proportionalAmount(int $total, int $quantity, int $cumulativeQuantity): int
    {
        if ($total < 0 || $quantity <= 0 || $cumulativeQuantity < 0 || $cumulativeQuantity > $quantity) {
            throw new SyncConflictException('Proporsi nilai retur tidak valid.');
        }
        if ($cumulativeQuantity === $quantity) return $total;
        if ($cumulativeQuantity > 0 && $total > intdiv(PHP_INT_MAX, $cumulativeQuantity)) {
            throw new SyncConflictException('Nilai retur melebihi batas integer rupiah.');
        }
        return intdiv($total * $cumulativeQuantity, $quantity);
    }

    private function roundProportion(int $total, int $part, int $whole): int
    {
        if ($total < 0 || $part < 0 || $whole <= 0 || $part > $whole) {
            throw new SyncConflictException('Proporsi PPN retur tidak valid.');
        }
        if ($part === $whole) return $total;
        if ($part > 0 && $total > intdiv(PHP_INT_MAX, $part)) {
            throw new SyncConflictException('Alokasi PPN retur melebihi batas integer rupiah.');
        }
        $numerator = $total * $part;
        $half = intdiv($whole, 2);
        if ($numerator > PHP_INT_MAX - $half) {
            throw new SyncConflictException('Alokasi PPN retur melebihi batas integer rupiah.');
        }
        return intdiv($numerator + $half, $whole);
    }

    private function acceptProductEvent(
        Connection $db,
        array $event,
        array $payload,
        string $deviceId,
        string $payloadHash,
        int $actorId
    ): array {
        $product = $payload['product'] ?? null;
        if (! is_array($product)) throw new SyncConflictException('Payload master produk tidak lengkap.');

        $productId = $this->requiredString($product, 'id');
        $eventEntityId = (string) ($event['entity_id'] ?? '');
        if (strlen($productId) > 100 || $productId !== $eventEntityId) {
            throw new SyncConflictException('ID master produk tidak valid atau tidak cocok dengan envelope.');
        }

        // Serialize separate event IDs for the same product so concurrent
        // creates/updates cannot race around the version compare-and-swap.
        $db->select('SELECT pg_advisory_xact_lock(hashtextextended(?, 0))', ['product:'.$productId]);
        $sku = trim($this->requiredString($product, 'sku'));
        $name = trim($this->requiredString($product, 'name_id'));
        if (strlen($sku) > 100 || strlen($name) > 255) {
            throw new SyncConflictException('SKU atau nama produk melebihi batas.');
        }
        $barcode = $product['barcode'] ?? null;
        if ($barcode !== null && (! is_string($barcode) || trim($barcode) === '' || strlen($barcode) > 100)) {
            throw new SyncConflictException('Barcode produk tidak valid.');
        }
        $price = $this->payloadMoney($product, 'price');
        $ppnExempt = $this->payloadBoolean($product['ppn_exempt'] ?? null);
        $trackExpiry = $this->payloadBoolean($product['track_expiry'] ?? false);
        $requiresReview = $this->payloadBoolean($product['requires_review'] ?? false);
        $statusSpecified = array_key_exists('is_active', $product);
        $versionSpecified = array_key_exists('version', $product);
        $incomingVersion = $product['version'] ?? null;
        if ($versionSpecified && (! is_int($incomingVersion) || $incomingVersion < 1)) {
            throw new SyncConflictException('Versi produk tidak valid.');
        }
        $minShelfLifeDays = $product['min_shelf_life_days'] ?? 0;
        if (! is_int($minShelfLifeDays) || $minShelfLifeDays < 0 || $minShelfLifeDays > 3650) {
            throw new SyncConflictException('Minimum shelf life produk tidak valid.');
        }

        $duplicateSku = $db->table('products')->where('sku', $sku)->where('id', '<>', $productId)->exists();
        if ($duplicateSku) throw new SyncConflictException('SKU sudah digunakan produk lain pada tenant ini.');
        if ($barcode !== null) {
            $duplicateBarcode = $db->table('products')->where('barcode', trim($barcode))
                ->where('id', '<>', $productId)->exists();
            if ($duplicateBarcode) throw new SyncConflictException('Barcode sudah digunakan produk lain pada tenant ini.');
        }

        $now = now();
        $existing = $db->table('products')->where('id', $productId)->lockForUpdate()->first();
        if ($existing !== null && $this->databaseBoolean($existing->track_expiry ?? false) !== $trackExpiry
            && $db->table('inventory_lots')->where('product_id', $productId)->exists()) {
            throw new SyncConflictException('Kebijakan kedaluwarsa tidak dapat diubah setelah lot persediaan tercatat.');
        }

        $currentIsActive = $existing === null
            ? true
            : $this->databaseBoolean($existing->is_active ?? true);
        $isActive = $statusSpecified
            ? $this->payloadBoolean($product['is_active'])
            : $currentIsActive;

        if ($existing === null) {
            if ($versionSpecified && $incomingVersion !== 1) {
                throw new SyncConflictException('Produk baru harus dimulai dari versi 1.');
            }
            if (! $isActive) {
                throw new SyncConflictException('Produk baru harus dibuat aktif; gunakan transisi status yang diaudit.');
            }
            $persistedVersion = 1;
        } else {
            $currentVersion = (int) ($existing->version ?? 1);
            if ($versionSpecified) {
                if ($incomingVersion !== $currentVersion + 1) {
                    throw new SyncConflictException(
                        'Versi produk usang atau melompati revisi; muat ulang status dan sinkronkan ulang.'
                    );
                }
                $persistedVersion = $incomingVersion;
            } else {
                // Backward compatibility for old clients only permits master
                // edits that do not change activity. In particular, a delayed
                // legacy event cannot reactivate an inactive product.
                if ($statusSpecified && $isActive !== $currentIsActive) {
                    throw new SyncConflictException('Perubahan status memerlukan versi produk dan audit transisi.');
                }
                $isActive = $currentIsActive;
                $persistedVersion = $currentVersion;
            }
        }

        $hasStatusChange = $existing !== null && $isActive !== $currentIsActive;
        $statusAudit = null;
        if ($hasStatusChange) {
            // Product lifecycle authorization is evaluated against the current
            // central membership at acceptance time, not the offline event's
            // creation time. The durable local event remains pending for review
            // if this policy rejects it.
            $membershipRole = DB::connection('central')->table('tenant_memberships')
                ->join('device_registry', 'device_registry.tenant_id', '=', 'tenant_memberships.tenant_id')
                ->where('tenant_memberships.user_id', $actorId)
                ->where('tenant_memberships.status', 'active')
                ->where('device_registry.device_id', $deviceId)
                ->where('device_registry.owner_user_id', $actorId)
                ->where('device_registry.status', 'active')
                ->whereNull('device_registry.revoked_at')
                ->value('tenant_memberships.role');
            if (! in_array($membershipRole, ['owner', 'manager'], true)) {
                throw new SyncConflictException(
                    'Product status change rejected: active tenant membership role owner or manager is required.'
                );
            }
            if (! $versionSpecified) {
                throw new SyncConflictException('Perubahan status memerlukan versi produk.');
            }
            $transition = $product['status_change'] ?? null;
            if (! is_array($transition)) {
                throw new SyncConflictException('Alasan dan metadata audit perubahan status wajib dilampirkan.');
            }
            $fromActive = $this->payloadBoolean($transition['from_active'] ?? null);
            $toActive = $this->payloadBoolean($transition['to_active'] ?? null);
            $reason = $transition['reason'] ?? null;
            $changedAtRaw = $transition['changed_at_utc'] ?? null;
            if (! is_string($reason) || trim($reason) === '' || strlen(trim($reason)) > 500) {
                throw new SyncConflictException('Alasan perubahan status wajib diisi maksimal 500 karakter.');
            }
            if ($fromActive !== $currentIsActive || $toActive !== $isActive) {
                throw new SyncConflictException('Transisi status tidak sesuai dengan versi aktif yang tersimpan.');
            }
            if (! is_string($changedAtRaw) || trim($changedAtRaw) === '') {
                throw new SyncConflictException('Waktu perubahan status tidak valid.');
            }
            try {
                $changedAt = Carbon::parse($changedAtRaw);
            } catch (Throwable) {
                throw new SyncConflictException('Waktu perubahan status tidak valid.');
            }
            $statusAudit = [
                'event_id' => (string) $event['event_id'],
                'product_id' => $productId,
                'version' => $persistedVersion,
                'previous_is_active' => $currentIsActive,
                'is_active' => $isActive,
                'reason' => trim($reason),
                'actor_user_id' => $actorId,
                'device_id' => $deviceId,
                'changed_at' => $changedAt,
                'created_at' => $now,
                'updated_at' => $now,
            ];
        }

        $values = [
            'sku' => $sku,
            'barcode' => $barcode === null ? null : trim($barcode),
            'name' => $name,
            'price' => $price,
            'ppn_exempt' => $ppnExempt,
            'track_expiry' => $trackExpiry,
            'min_shelf_life_days' => $minShelfLifeDays,
            'requires_review' => $requiresReview,
            'is_active' => $isActive,
            'version' => $persistedVersion,
            'updated_at' => $now,
        ];
        if ($existing === null) {
            // Stock is ledger-owned. A catalog event can never create inventory.
            $db->table('products')->insert(array_merge([
                'id' => $productId,
                'category_id' => null,
                'stock_qty' => 0,
                'created_at' => $now,
            ], $values));
        } else {
            // Update only the product master; never trust client stock_qty.
            $db->table('products')->where('id', $productId)->update($values);
        }
        if ($statusAudit !== null) {
            $db->table('product_status_audits')->insert($statusAudit);
        }

        $response = [
            'event_id' => (string) $event['event_id'],
            'status' => 'accepted',
            'receipt_id' => (string) $event['event_id'],
            'entity_id' => $productId,
            'version' => $persistedVersion,
        ];
        $this->saveSyncReceipt($db, (string) $event['event_id'], $deviceId, $payloadHash, $response, $now);
        return $response;
    }

    private function acceptInventoryReceiptEvent(
        Connection $db,
        array $event,
        array $payload,
        string $deviceId,
        string $payloadHash,
        int $actorId,
        string $appVersion
    ): array {
        $receipt = $payload['receipt'] ?? null;
        if (! is_array($receipt)) throw new SyncConflictException('Payload penerimaan persediaan tidak lengkap.');

        $productId = $this->requiredString($receipt, 'product_id');
        if ($productId !== (string) ($event['entity_id'] ?? '')) {
            throw new SyncConflictException('Penerimaan persediaan tidak sesuai dengan produk pada envelope.');
        }
        $lotId = $this->requiredString($receipt, 'lot_id');
        $costLayerId = $this->requiredString($receipt, 'cost_layer_id');
        if (strlen($lotId) > 100 || strlen($costLayerId) > 150) {
            throw new SyncConflictException('ID lot atau layer biaya melebihi batas skema.');
        }
        $quantity = $this->payloadQuantity($receipt, 'quantity');
        $unitCost = $this->payloadMoney($receipt, 'unit_cost');
        $counterAccountCode = $receipt['counter_account_code'] ?? null;
        $batchNo = trim($this->requiredString($receipt, 'batch_no'));
        if ($batchNo === '' || strlen($batchNo) > 120) throw new SyncConflictException('Nomor batch tidak valid.');

        $acquiredAtRaw = $this->requiredString($receipt, 'acquired_at_utc');
        try {
            $acquiredAt = Carbon::parse($acquiredAtRaw)->utc();
        } catch (Throwable) {
            throw new SyncConflictException('Waktu penerimaan persediaan tidak valid.');
        }
        $expiryDate = $receipt['expiry_date'] ?? null;
        if ($expiryDate !== null) {
            if (! is_string($expiryDate) || ! preg_match('/^\d{4}-\d{2}-\d{2}$/', $expiryDate)) {
                throw new SyncConflictException('Tanggal kedaluwarsa harus berupa YYYY-MM-DD atau null.');
            }
            try {
                $parsedExpiry = Carbon::createFromFormat('!Y-m-d', $expiryDate);
            } catch (Throwable) {
                $parsedExpiry = false;
            }
            if ($parsedExpiry === false || $parsedExpiry->format('Y-m-d') !== $expiryDate) {
                throw new SyncConflictException('Tanggal kedaluwarsa tidak valid.');
            }
        }

        $product = $db->table('products')->where('id', $productId)->lockForUpdate()->first();
        if ($product === null || ! $this->databaseBoolean($product->is_active ?? true)
            || $this->databaseBoolean($product->requires_review ?? false)) {
            throw new SyncConflictException('Penerimaan ditolak karena produk belum tersedia, nonaktif, atau memerlukan pemeriksaan.');
        }
        if ($this->databaseBoolean($product->track_expiry ?? false) && $expiryDate === null) {
            throw new SyncConflictException('Produk yang melacak kedaluwarsa wajib memiliki tanggal kedaluwarsa.');
        }

        $timezone = $receipt['timezone'] ?? 'Asia/Jakarta';
        if (! is_string($timezone) || trim($timezone) === '' || strlen($timezone) > 64) {
            throw new SyncConflictException('Zona waktu penerimaan tidak valid.');
        }
        try {
            $businessDate = Carbon::parse($acquiredAtRaw)->setTimezone($timezone)->toDateString();
        } catch (Throwable) {
            throw new SyncConflictException('Zona waktu/tanggal penerimaan tidak valid.');
        }
        if ($expiryDate !== null && $expiryDate < $businessDate) {
            throw new SyncConflictException('Tanggal kedaluwarsa tidak boleh sebelum tanggal penerimaan.');
        }

        if ($unitCost > 0 && $quantity > intdiv(PHP_INT_MAX, $unitCost)) {
            throw new SyncConflictException('Nilai penerimaan melebihi batas integer rupiah.');
        }
        $receiptTotalCost = $quantity * $unitCost;
        if ($receiptTotalCost > 9_999_999_999_999_999) {
            throw new SyncConflictException('Nilai penerimaan melebihi presisi moneter skema.');
        }
        if ($receiptTotalCost > 0
            && (! is_string($counterAccountCode)
                || ! in_array($counterAccountCode, self::INVENTORY_COUNTER_ACCOUNTS, true))) {
            throw new SyncConflictException(
                'Akun lawan penerimaan wajib dipilih: kas, QRIS, transfer bank, atau utang supplier.'
            );
        }

        $period = null;
        if ($receiptTotalCost > 0) {
            if ($db->table('accounting_periods')
                ->where('starts_on', '<=', $businessDate)
                ->where('ends_on', '>=', $businessDate)
                ->where('status', 'closed')
                ->exists()) {
                throw new SyncConflictException('Periode akuntansi penerimaan sudah ditutup.');
            }
            $period = $db->table('accounting_periods')
                ->where('starts_on', '<=', $businessDate)
                ->where('ends_on', '>=', $businessDate)
                ->where('status', 'open')
                ->orderBy('starts_on')
                ->lockForUpdate()
                ->first();
            if ($period === null) {
                throw new SyncConflictException('Tidak ada periode akuntansi terbuka untuk penerimaan persediaan.');
            }
        }

        if ($db->table('inventory_cost_layers')->where('id', $costLayerId)->exists()) {
            throw new SyncConflictException('ID layer biaya sudah digunakan.');
        }

        $now = now();
        $expiredAtSync = $expiryDate !== null && $expiryDate < $now->toDateString();
        $existingLot = $db->table('inventory_lots')->where('id', $lotId)->lockForUpdate()->first();
        $sameBatchQuery = $db->table('inventory_lots')
            ->where('product_id', $productId)
            ->where('batch_code', $batchNo)
            ->where('id', '<>', $lotId);
        if ($expiryDate === null) $sameBatchQuery->whereNull('expires_at');
        else $sameBatchQuery->whereDate('expires_at', $expiryDate);
        if ($sameBatchQuery->exists()) {
            throw new SyncConflictException('Batch/tanggal kedaluwarsa sudah memiliki lot lain; gunakan ID lot yang sama untuk penerimaan tambahan.');
        }

        if ($existingLot === null) {
            $db->table('inventory_lots')->insert([
                'id' => $lotId,
                'product_id' => $productId,
                'batch_code' => $batchNo,
                'expires_at' => $expiryDate,
                'quantity_received' => $quantity,
                'quantity_remaining' => $quantity,
                'unit_cost' => $unitCost,
                'received_at' => $acquiredAt,
                'reserved_qty' => 0,
                'status' => $expiredAtSync ? 'expired' : 'saleable',
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        } else {
            $existingStatus = (string) ($existingLot->status ?? 'saleable');
            $allowedStatuses = $expiredAtSync ? ['saleable', 'expired'] : ['saleable'];
            if ((string) $existingLot->product_id !== $productId
                || (string) ($existingLot->batch_code ?? '') !== $batchNo
                || (($existingLot->expires_at === null) !== ($expiryDate === null))
                || ($expiryDate !== null && Carbon::parse($existingLot->expires_at)->toDateString() !== $expiryDate)
                || ! in_array($existingStatus, $allowedStatuses, true)) {
                throw new SyncConflictException('Penerimaan tidak cocok dengan lot yang ada atau lot tidak lagi saleable.');
            }
            $db->table('inventory_lots')->where('id', $lotId)->increment('quantity_received', $quantity, ['updated_at' => $now]);
            $db->table('inventory_lots')->where('id', $lotId)->increment('quantity_remaining', $quantity, ['updated_at' => $now]);
            if ($expiredAtSync && $existingStatus === 'saleable') {
                $db->table('inventory_lots')->where('id', $lotId)->update([
                    'status' => 'expired',
                    'updated_at' => $now,
                ]);
            }
        }

        $db->table('inventory_cost_layers')->insert([
            'id' => $costLayerId,
            'product_id' => $productId,
            'lot_id' => $lotId,
            'original_qty' => $quantity,
            'remaining_qty' => $quantity,
            'unit_cost' => $unitCost,
            'acquired_at' => $acquiredAt,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $updated = $db->table('products')->where('id', $productId)
            ->increment('stock_qty', $quantity, ['updated_at' => $now]);
        if ($updated !== 1) throw new SyncConflictException('Stok agregat produk tidak dapat diperbarui.');

        $db->table('inventory_movements')->insert([
            'source_event_id' => (string) $event['event_id'],
            'product_id' => $productId,
            'lot_id' => $lotId,
            'movement_type' => 'receipt',
            'quantity' => $quantity,
            'reference_id' => $costLayerId,
            'occurred_at' => $acquiredAt,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $db->table('stock_movements')->insert([
            'id' => 'sync:'.substr(hash('sha256', (string) $event['event_id']), 0, 48),
            'source_event_id' => (string) $event['event_id'],
            'product_id' => $productId,
            'reference_id' => $costLayerId,
            'movement_type' => 'purchase_receipt',
            'quantity_delta' => $quantity,
            'unit_cost' => $unitCost,
            'total_cost' => $quantity * $unitCost,
            'occurred_at' => $acquiredAt,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $journalId = null;
        if ($receiptTotalCost > 0) {
            // The operator explicitly selects the counter-account; never infer
            // supplier credit for a purchase paid by cash, QRIS, or bank transfer.
            $journalId = 'journal:receipt:'.substr(hash('sha256', (string) $event['event_id']), 0, 48);
            $journalTransactionId = 'receipt:'.substr(hash('sha256', (string) $event['event_id']), 0, 48);
            $db->table('journal_entries')->insert([
                'id' => $journalId,
                'source_event_id' => (string) $event['event_id'],
                'transaction_id' => $journalTransactionId,
                'description' => 'Inventory receipt '.$costLayerId,
                'journal_date' => $businessDate,
                'occurred_at' => $acquiredAt,
                'timezone' => $timezone,
                'period_id' => $period->id,
                'status' => 'draft',
                'created_at' => $now,
                'updated_at' => $now,
            ]);
            $db->table('journal_lines')->insert([
                [
                    'journal_entry_id' => $journalId, 'line_no' => 0,
                    'account_code' => '1-1040', 'debit' => $receiptTotalCost, 'credit' => 0,
                    'created_at' => $now, 'updated_at' => $now,
                ],
                [
                    'journal_entry_id' => $journalId, 'line_no' => 1,
                    'account_code' => (string) $counterAccountCode, 'debit' => 0, 'credit' => $receiptTotalCost,
                    'created_at' => $now, 'updated_at' => $now,
                ],
            ]);
            $posted = $db->table('journal_entries')
                ->where('id', $journalId)
                ->where('status', 'draft')
                ->update([
                    'status' => 'posted',
                    'posted_at' => $now,
                    'posted_by' => (string) $actorId,
                    'device_id' => $deviceId,
                    'app_version' => $appVersion,
                    'period_id' => $period->id,
                    'updated_at' => $now,
                ]);
            if ($posted !== 1) {
                throw new SyncConflictException('Jurnal penerimaan tidak dapat diposting.');
            }
        }

        $response = [
            'event_id' => (string) $event['event_id'],
            'status' => 'accepted',
            'receipt_id' => (string) $event['event_id'],
            'product_id' => $productId,
            'lot_id' => $lotId,
            'journal_entry_id' => $journalId,
        ];
        $this->saveSyncReceipt($db, (string) $event['event_id'], $deviceId, $payloadHash, $response, $now);
        return $response;
    }

    private function saveSyncReceipt(
        Connection $db,
        string $eventId,
        string $deviceId,
        string $payloadHash,
        array $response,
        mixed $acceptedAt
    ): void {
        $db->table('sync_receipts')->insert([
            'event_id' => $eventId,
            'device_id' => $deviceId,
            'payload_sha256' => $payloadHash,
            'response' => json_encode($response, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR),
            'accepted_at' => $acceptedAt,
            'created_at' => $acceptedAt,
            'updated_at' => $acceptedAt,
        ]);
    }

    private function expectedFefoAllocations(Connection $db, object $product, int $quantity, string $businessDate): array
    {
        $query = $db->table('inventory_lots')
            ->where('product_id', $product->id)
            ->where('status', 'saleable')
            ->whereRaw('(quantity_remaining - reserved_qty) > 0');

        // The server must enforce any recorded expiry date against the sale's
        // business date, even when product-level expiry tracking is disabled.
        // This mirrors the offline FEFO contract and prevents stale maintenance
        // status from making an expired lot appear eligible.
        $query->where(function ($expiry) use ($businessDate): void {
            $expiry->whereNull('expires_at')
                ->orWhereDate('expires_at', '>=', $businessDate);
        });

        $minimumExpiry = Carbon::parse($businessDate)
            ->addDays((int) ($product->min_shelf_life_days ?? 0))->toDateString();
        $now = now();
        $query->whereNotExists(function ($holds) use ($now): void {
            $holds->selectRaw('1')->from('lot_holds')
                ->whereColumn('lot_holds.lot_id', 'inventory_lots.id')
                ->where('lot_holds.status', 'active')
                ->where(function ($starts) use ($now): void {
                    $starts->whereNull('lot_holds.starts_at')->orWhere('lot_holds.starts_at', '<=', $now);
                })
                ->where(function ($ends) use ($now): void {
                    $ends->whereNull('lot_holds.ends_at')->orWhere('lot_holds.ends_at', '>=', $now);
                });
        });
        if ($this->databaseBoolean($product->track_expiry ?? false)) {
            $query->whereNotNull('expires_at')->whereDate('expires_at', '>=', $minimumExpiry)
                ->orderBy('expires_at');
        } else {
            $query->orderBy('received_at');
        }

        $lots = $query->orderBy('received_at')->orderBy('id')->lockForUpdate()->get();
        $remaining = $quantity;
        $expected = [];
        foreach ($lots as $lot) {
            if ($remaining <= 0) break;
            $available = $this->databaseScaledInteger($lot->quantity_remaining, 3);
            $reserved = $this->databaseScaledInteger($lot->reserved_qty ?? 0, 3);
            $availableUnits = intdiv(max(0, (int) $available - (int) $reserved), 1000);
            $take = min($remaining, $availableUnits);
            if ($take <= 0) continue;
            $expected[] = ['allocation_no' => count($expected), 'lot_id' => (string) $lot->id, 'quantity' => $take];
            $remaining -= $take;
        }
        if ($remaining !== 0) throw new SyncConflictException('Lot FEFO server tidak mencukupi; sinkronisasi memerlukan rekonsiliasi.');
        return $expected;
    }

    private function expectedFifoConsumptions(Connection $db, string $productId, int $quantity): array
    {
        $layers = $db->table('inventory_cost_layers')->where('product_id', $productId)
            ->where('remaining_qty', '>', 0)->orderBy('acquired_at')->orderBy('id')->lockForUpdate()->get();
        $remaining = $quantity;
        $expected = [];
        foreach ($layers as $layer) {
            if ($remaining <= 0) break;
            $qty = $this->databaseScaledInteger($layer->remaining_qty, 3);
            $availableUnits = intdiv(max(0, (int) $qty), 1000);
            $take = min($remaining, $availableUnits);
            if ($take <= 0) continue;
            $costCents = $this->databaseScaledInteger($layer->unit_cost, 2);
            if ($costCents === null || $costCents % 100 !== 0) throw new SyncConflictException('Cost layer must use whole-rupiah unit cost.');
            $unitCost = intdiv($costCents, 100);
            $expected[] = ['consumption_no' => count($expected), 'cost_layer_id' => (string) $layer->id,
                'quantity' => $take, 'unit_cost' => $unitCost, 'total_cost' => $take * $unitCost];
            $remaining -= $take;
        }
        if ($remaining !== 0) throw new SyncConflictException('Cost layer FIFO server tidak mencukupi; sinkronisasi memerlukan rekonsiliasi.');
        return $expected;
    }

    private function normalizeAllocations(array $rows): array
    {
        $out = [];
        foreach (array_values($rows) as $i => $row) {
            if (! is_array($row) || (int) ($row['allocation_no'] ?? -1) !== $i) throw new SyncConflictException('Urutan alokasi FEFO tidak valid.');
            $out[] = ['allocation_no' => $i, 'lot_id' => $this->requiredString($row, 'lot_id'),
                'quantity' => $this->payloadQuantity($row, 'quantity')];
        }
        return $out;
    }

    private function normalizeConsumptions(array $rows): array
    {
        $out = [];
        foreach (array_values($rows) as $i => $row) {
            if (! is_array($row) || (int) ($row['consumption_no'] ?? -1) !== $i) throw new SyncConflictException('Urutan konsumsi FIFO tidak valid.');
            $out[] = ['consumption_no' => $i, 'cost_layer_id' => $this->requiredString($row, 'cost_layer_id'),
                'quantity' => $this->payloadQuantity($row, 'quantity'),
                'unit_cost' => $this->payloadMoney($row, 'unit_cost'), 'total_cost' => $this->payloadMoney($row, 'total_cost')];
        }
        return $out;
    }

    private function expectedJournal(array $sale): array
    {
        $grand = $this->payloadMoney($sale, 'grand_total');
        $gross = $this->payloadMoney($sale, 'gross_amount');
        $discount = $this->payloadMoney($sale, 'discount_amount');
        $ppn = $this->payloadMoney($sale, 'ppn_amount');
        $cogs = $this->payloadMoney($sale, 'cogs_amount');
        $lines = [];
        $add = static function (string $account, int $debit, int $credit) use (&$lines): void {
            $lines[] = ['line_no' => count($lines), 'account_code' => $account, 'debit' => $debit, 'credit' => $credit];
        };
        if ($grand > 0) $add(self::PAYMENT_ACCOUNTS[(string) $sale['payment_method']], $grand, 0);
        if ($discount > 0) $add('4-4020', $discount, 0);
        $add('4-4010', 0, $gross);
        if ($ppn > 0) $add('2-2010', 0, $ppn);
        if ($cogs > 0) {
            $add('5-5010', $cogs, 0);
            $add('1-1040', 0, $cogs);
        }
        return $lines;
    }

    private function normalizeJournal(array $lines): array
    {
        $result = [];
        foreach (array_values($lines) as $index => $line) {
            if (! is_array($line) || (int) ($line['line_no'] ?? -1) !== $index) throw new SyncConflictException('Urutan baris jurnal tidak valid.');
            $result[] = ['line_no' => $index, 'account_code' => $this->requiredString($line, 'account_code'),
                'debit' => $this->payloadMoney($line, 'debit'), 'credit' => $this->payloadMoney($line, 'credit')];
        }
        return $result;
    }

    private function payloadMoney(array $row, string $field): int
    {
        $value = $row[$field] ?? null;
        if (! is_int($value) || $value < 0) throw new SyncConflictException('Nilai uang '.$field.' wajib integer rupiah non-negatif.');
        return $value;
    }

    private function payloadQuantity(array $row, string $field): int
    {
        $value = $row[$field] ?? null;
        if (! is_int($value) || $value <= 0) throw new SyncConflictException('Kuantitas '.$field.' wajib integer positif.');
        return $value;
    }

    private function requiredString(array $row, string $field): string
    {
        $value = $row[$field] ?? null;
        if (! is_string($value) || trim($value) === '') throw new SyncConflictException('Field wajib tidak valid: '.$field.'.');
        return $value;
    }

    private function payloadBoolean(mixed $value): bool
    {
        if (is_bool($value)) return $value;
        if (is_int($value)) return $value !== 0;
        if (is_string($value)) return in_array(strtolower($value), ['1', 't', 'true', 'yes', 'on'], true);
        throw new SyncConflictException('Flag boolean pada payload tidak valid.');
    }

    private function databaseBoolean(mixed $value): bool
    {
        if (is_bool($value)) return $value;
        if (is_int($value) || is_float($value)) return $value !== 0;
        return in_array(strtolower(trim((string) $value)), ['1', 't', 'true', 'yes', 'on'], true);
    }

    private function databaseScaledInteger(mixed $value, int $scale): ?int
    {
        $text = trim((string) $value);
        if (! preg_match('/^([0-9]+)(?:\.([0-9]+))?$/', $text, $parts)) return null;
        $fraction = $parts[2] ?? '';
        if (strlen($fraction) > $scale && trim(substr($fraction, $scale), '0') !== '') return null;
        $fraction = substr(str_pad($fraction, $scale, '0'), 0, $scale);
        return ((int) $parts[1] * (10 ** $scale)) + (int) ($fraction === '' ? '0' : $fraction);
    }

    private function canonicalize(mixed $value): mixed
    {
        if (! is_array($value)) return $value;
        if (array_is_list($value)) return array_map(fn (mixed $item): mixed => $this->canonicalize($item), $value);
        ksort($value, SORT_STRING);
        foreach ($value as $key => $item) $value[$key] = $this->canonicalize($item);
        return $value;
    }
}
