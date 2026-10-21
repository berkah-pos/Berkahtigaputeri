<?php

namespace App\Http\Controllers\Api\V1;

use App\Exceptions\SyncConflictException;
use App\Http\Controllers\Controller;
use App\Models\Central\User;
use App\Services\TenantAccess;
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
    private const PAYMENT_ACCOUNTS = [
        'cash' => '1-1010',
        'qris' => '1-1020',
        'bankTransfer' => '1-1030',
        'bank_transfer' => '1-1030',
        'transfer' => '1-1030',
    ];

    public function sync(Request $request, TenantAccess $access, TenantDatabaseRunner $runner): JsonResponse
    {
        $input = $request->validate([
            'device_id' => ['required', 'string', 'min:3', 'max:150', 'regex:/^[A-Za-z0-9_.:-]+$/'],
            'app_version' => ['sometimes', 'string', 'max:64'],
            'events' => ['required', 'array', 'min:1', 'max:20'],
            'events.*.event_id' => ['required', 'string', 'max:100'],
            'events.*.entity_type' => ['required', 'string', 'in:sale,product,inventory_receipt'],
            'events.*.entity_id' => ['required', 'string', 'max:150'],
            'events.*.payload' => ['required', 'array'],
        ]);

        // Validate the nested fingerprint separately but retain the complete event
        // envelope. Mixing one dotted child rule into an array-valued payload can
        // cause validated() to narrow sibling keys that the sync contract needs.
        Validator::make($request->all(), [
            'events.*.payload.sale.request_fingerprint' => ['sometimes', 'string', 'max:65536'],
        ])->validate();

        $user = $request->user();
        if (! $user instanceof User || ! $user->is_active || $user->tenant_id === null) {
            return response()->json(['error' => ['code' => 'inactive_user_or_missing_tenant']], 403);
        }
        if (! $access->hasActiveMembership($user)) {
            return response()->json(['error' => ['code' => 'tenant_membership_required']], 403);
        }

        $tenantId = (string) $user->tenant_id;
        if (! $access->hasActiveSubscription($tenantId)) {
            return response()->json(['error' => ['code' => 'tenant_not_entitled']], 403);
        }

        $deviceId = (string) $input['device_id'];
        $device = DB::connection('central')->table('device_registry')
            ->where('device_id', $deviceId)
            ->where('tenant_id', $tenantId)
            ->where('owner_user_id', $user->id)
            ->where('status', 'active')
            ->first();

        if ($device === null) {
            return response()->json(['error' => ['code' => 'device_not_authorized']], 403);
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
                        (int) $user->id,
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
                            'message' => 'Database tenant belum siap atau tidak dapat diakses dengan role runtime yang dibatasi.',
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

        return response()->json(['results' => $results]);
    }

    private function acceptEvent(Connection $db, array $event, string $deviceId, int $actorId, string $appVersion): array
    {
        $eventId = (string) $event['event_id'];
        $payload = $event['payload'];

        $entityType = (string) ($event['entity_type'] ?? '');
        $envelopeMismatches = [];
        if (! in_array($entityType, ['sale', 'product', 'inventory_receipt'], true)) $envelopeMismatches[] = 'entity_type';
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
            return $this->acceptProductEvent($db, $event, $payload, $deviceId, $payloadHash);
        }
        if ($entityType === 'inventory_receipt') {
            return $this->acceptInventoryReceiptEvent($db, $event, $payload, $deviceId, $payloadHash);
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
        $periodKey = substr($businessDate, 0, 7);
        if ($db->table('accounting_periods')
            ->where('period_key', $periodKey)
            ->where('status', 'closed')
            ->exists()) {
            throw new SyncConflictException('Periode akuntansi sudah ditutup; transaksi perlu rekonsiliasi.');
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
            'occurred_at' => $occurredAt, 'timezone' => (string) $sale['timezone'], 'status' => 'draft',
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
            ->update(['status' => 'posted', 'updated_at' => $created]);
        if ($posted !== 1) {
            throw new SyncConflictException('Jurnal tidak dapat diposting dalam status saat ini.');
        }

        $db->table('accounting_events')->insert([
            'event_id' => $eventId, 'journal_entry_id' => $journalId, 'actor_user_id' => $actorId,
            'device_id' => $deviceId, 'app_version' => $appVersion, 'action' => 'post',
            'occurred_at' => $occurredAt, 'created_at' => $created, 'updated_at' => $created,
        ]);

        $response = ['event_id' => $eventId, 'status' => 'accepted', 'receipt_id' => $eventId,
            'transaction_id' => $transactionId];
        $db->table('sync_receipts')->insert([
            'event_id' => $eventId, 'device_id' => $deviceId, 'payload_sha256' => $payloadHash,
            'response' => json_encode($response, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR),
            'accepted_at' => now(), 'created_at' => $created, 'updated_at' => $created,
        ]);

        return $response;
    }

    private function acceptProductEvent(Connection $db, array $event, array $payload, string $deviceId, string $payloadHash): array
    {
        $product = $payload['product'] ?? null;
        if (! is_array($product)) throw new SyncConflictException('Payload master produk tidak lengkap.');

        $productId = $this->requiredString($product, 'id');
        $eventEntityId = (string) ($event['entity_id'] ?? '');
        if ($productId !== $eventEntityId) throw new SyncConflictException('ID master produk tidak cocok dengan envelope.');
        $sku = trim($this->requiredString($product, 'sku'));
        $name = trim($this->requiredString($product, 'name_id'));
        if (strlen($sku) > 100 || strlen($name) > 255) throw new SyncConflictException('SKU atau nama produk melebihi batas.');
        $barcode = $product['barcode'] ?? null;
        if ($barcode !== null && (! is_string($barcode) || trim($barcode) === '' || strlen($barcode) > 100)) {
            throw new SyncConflictException('Barcode produk tidak valid.');
        }
        $price = $this->payloadMoney($product, 'price');
        $ppnExempt = $this->payloadBoolean($product['ppn_exempt'] ?? null);
        $trackExpiry = $this->payloadBoolean($product['track_expiry'] ?? false);
        $requiresReview = $this->payloadBoolean($product['requires_review'] ?? false);
        $isActive = $this->payloadBoolean($product['is_active'] ?? true);
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

        $response = [
            'event_id' => (string) $event['event_id'],
            'status' => 'accepted',
            'receipt_id' => (string) $event['event_id'],
            'entity_id' => $productId,
        ];
        $this->saveSyncReceipt($db, (string) $event['event_id'], $deviceId, $payloadHash, $response, $now);
        return $response;
    }

    private function acceptInventoryReceiptEvent(
        Connection $db,
        array $event,
        array $payload,
        string $deviceId,
        string $payloadHash
    ): array {
        $receipt = $payload['receipt'] ?? null;
        if (! is_array($receipt)) throw new SyncConflictException('Payload penerimaan persediaan tidak lengkap.');

        $productId = $this->requiredString($receipt, 'product_id');
        if ($productId !== (string) ($event['entity_id'] ?? '')) {
            throw new SyncConflictException('Penerimaan persediaan tidak sesuai dengan produk pada envelope.');
        }
        $lotId = $this->requiredString($receipt, 'lot_id');
        $costLayerId = $this->requiredString($receipt, 'cost_layer_id');
        $quantity = $this->payloadQuantity($receipt, 'quantity');
        $unitCost = $this->payloadMoney($receipt, 'unit_cost');
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
            if ($parsedExpiry === false || $parsedExpiry->format('Y-m-d') !== $expiryDate
                || $parsedExpiry->toDateString() < now()->toDateString()) {
                throw new SyncConflictException('Tanggal kedaluwarsa tidak valid atau sudah lewat.');
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
        if ($db->table('inventory_cost_layers')->where('id', $costLayerId)->exists()) {
            throw new SyncConflictException('ID layer biaya sudah digunakan.');
        }

        $now = now();
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
                'status' => 'saleable',
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        } else {
            if ((string) $existingLot->product_id !== $productId
                || (string) ($existingLot->batch_code ?? '') !== $batchNo
                || (($existingLot->expires_at === null) !== ($expiryDate === null))
                || ($expiryDate !== null && Carbon::parse($existingLot->expires_at)->toDateString() !== $expiryDate)
                || (string) ($existingLot->status ?? 'saleable') !== 'saleable') {
                throw new SyncConflictException('Penerimaan tidak cocok dengan lot yang ada atau lot tidak lagi saleable.');
            }
            $db->table('inventory_lots')->where('id', $lotId)->increment('quantity_received', $quantity, ['updated_at' => $now]);
            $db->table('inventory_lots')->where('id', $lotId)->increment('quantity_remaining', $quantity, ['updated_at' => $now]);
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

        $response = [
            'event_id' => (string) $event['event_id'],
            'status' => 'accepted',
            'receipt_id' => (string) $event['event_id'],
            'product_id' => $productId,
            'lot_id' => $lotId,
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
