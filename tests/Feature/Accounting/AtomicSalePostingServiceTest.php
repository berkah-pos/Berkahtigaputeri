<?php

namespace Tests\Feature\Accounting;

use App\Services\Tenant\AtomicSalePostingService;
use App\Services\Tenant\IdempotencyConflictException;
use App\Services\Tenant\JournalReversalService;
use App\Services\Tenant\SalePostingException;
use Carbon\CarbonImmutable;
use Illuminate\Database\Connection;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;
use Throwable;

class AtomicSalePostingServiceTest extends TestCase
{
    private Connection $db;

    private Connection $ownerDb;

    protected function setUp(): void
    {
        parent::setUp();

        $tenantConfig = config('database.connections.tenant');
        $ownerConfig = $tenantConfig;
        $ownerConfig['username'] = getenv('TENANT_DB_USERNAME') ?: ($tenantConfig['username'] ?? 'postgres');
        $ownerConfig['password'] = getenv('TENANT_DB_PASSWORD') ?: ($tenantConfig['password'] ?? 'postgres');
        Config::set('database.connections.tenant_owner_test', $ownerConfig);

        $runtimeConfig = $tenantConfig;
        $runtimeConfig['username'] = getenv('TENANT_RUNTIME_DB_USERNAME') ?: 'berkahpos_tenant_runtime_test';
        $runtimeConfig['password'] = getenv('TENANT_RUNTIME_DB_PASSWORD') ?: 'tenant-runtime-ci-only';
        Config::set('database.connections.tenant', $runtimeConfig);

        DB::purge('tenant');
        DB::purge('tenant_owner_test');

        $this->db = DB::connection('tenant');
        $this->ownerDb = DB::connection('tenant_owner_test');
    }

    #[Test]
    public function checkout_commits_fefo_fifo_sale_journal_audit_and_receipt_atomically(): void
    {
        $fixture = $this->fixture(3);
        $command = $this->command($fixture['product_id'], 2, $this->eventId());

        $result = (new AtomicSalePostingService())->post($command, 'actor-test-01', 'device-test-01', '1.0.0-test');

        self::assertSame('accepted', $result['status']);
        self::assertSame(20000, $result['subtotal']);
        self::assertSame(0, $result['tax_amount']); // Tax is intentionally unsupported, not silently calculated.
        self::assertSame(7000, $result['cogs_amount']);
        self::assertSame(27000, $result['journal_total_debit']);
        self::assertSame($result['journal_total_debit'], $result['journal_total_credit']);

        $sale = $this->db->table('sales')->where('source_event_id', $command['event_id'])->first();
        self::assertNotNull($sale);
        self::assertSame('IDR', $sale->currency_code);
        self::assertSame($sale->subtotal, $sale->total_amount);

        $items = $this->db->table('sale_items')->where('sale_id', $sale->id)->get();
        self::assertCount(1, $items);
        self::assertSame('20000', (string) $items[0]->line_total);
        self::assertSame('7000', (string) $items[0]->cogs_amount);
        self::assertSame('2.000', number_format((float) $items[0]->quantity, 3, '.', ''));

        $allocations = $this->db->table('sale_lot_allocations')
            ->where('sale_item_id', $items[0]->id)
            ->orderBy('allocation_no')
            ->get();
        self::assertCount(2, $allocations);
        self::assertSame($fixture['lot_soon'], $allocations[0]->lot_id); // FEFO chooses earliest expiry first.
        self::assertSame(1, (int) $allocations[0]->quantity);
        self::assertSame($fixture['lot_later'], $allocations[1]->lot_id);
        self::assertSame(1, (int) $allocations[1]->quantity); // Partial consumption of second physical lot.

        self::assertSame('0.000', $this->decimal($this->db->table('inventory_lots')->where('id', $fixture['lot_soon'])->value('quantity_remaining')));
        self::assertSame('1.000', $this->decimal($this->db->table('inventory_lots')->where('id', $fixture['lot_later'])->value('quantity_remaining')));
        self::assertSame('0.000', $this->decimal($this->db->table('inventory_cost_layers')->where('id', $fixture['layer_fifo'])->value('quantity_remaining')));
        self::assertSame('1.000', $this->decimal($this->db->table('inventory_cost_layers')->where('id', $fixture['layer_next'])->value('quantity_remaining')));

        $movements = $this->db->table('inventory_movements')->where('source_event_id', $command['event_id'])->get();
        self::assertCount(2, $movements);
        self::assertSame(-2, (int) $movements->sum('quantity'));

        $journal = $this->db->table('journal_entries')->where('source_event_id', $command['event_id'])->first();
        self::assertNotNull($journal);
        self::assertSame('posted', $journal->status);
        self::assertSame('sale', $journal->entry_type);
        $lines = $this->db->table('journal_lines')->where('journal_entry_id', $journal->id)->orderBy('line_no')->get();
        self::assertCount(4, $lines);
        self::assertSame(27000, (int) $lines->sum('debit'));
        self::assertSame(27000, (int) $lines->sum('credit'));
        self::assertSame('1-1010', $lines[0]->account_code);
        self::assertSame('4-4010', $lines[1]->account_code);
        self::assertSame('5-5010', $lines[2]->account_code);
        self::assertSame('1-1040', $lines[3]->account_code);

        $event = $this->db->table('accounting_events')->where('journal_entry_id', $journal->id)->first();
        self::assertNotNull($event);
        self::assertSame('actor-test-01', $event->actor_reference);
        self::assertSame('device-test-01', $event->device_id);
        self::assertSame('1.0.0-test', $event->app_version);
        self::assertSame($command['event_id'], $event->transaction_reference);
        self::assertSame($command['event_id'], $event->idempotency_key);
        self::assertSame('journal.posted', $event->event_type);
        self::assertSame($command['event_id'], $this->db->table('sync_receipts')->where('event_id', $command['event_id'])->value('event_id'));
        self::assertSame($sale->request_fingerprint, $journal->payload_sha256);
    }

    #[Test]
    public function idempotent_retry_returns_the_original_receipt_and_does_not_duplicate_effects(): void
    {
        $fixture = $this->fixture(2);
        $command = $this->command($fixture['product_id'], 1, $this->eventId());
        $service = new AtomicSalePostingService();

        $first = $service->post($command, 'actor-test', 'device-test', '1.0.0-test');
        $retry = $service->post($command, 'actor-test', 'device-test', '1.0.0-test');

        self::assertSame($first, $retry);
        self::assertSame(1, $this->db->table('sales')->where('source_event_id', $command['event_id'])->count());
        self::assertSame(1, $this->db->table('journal_entries')->where('source_event_id', $command['event_id'])->count());
        self::assertSame(1, $this->db->table('accounting_events')->where('idempotency_key', $command['event_id'])->count());
        self::assertSame(1, $this->db->table('sync_receipts')->where('event_id', $command['event_id'])->count());
        self::assertSame(1, $this->db->table('sale_items')->where('sale_id', $first['sale_id'])->count());
        self::assertSame(1, $this->db->table('inventory_movements')->where('source_event_id', $command['event_id'])->count());
    }

    #[Test]
    public function same_idempotency_key_with_different_payload_is_rejected(): void
    {
        $fixture = $this->fixture(3);
        $eventId = $this->eventId();
        $service = new AtomicSalePostingService();
        $service->post($this->command($fixture['product_id'], 1, $eventId), 'actor-test', 'device-test', '1.0.0-test');

        $this->expectException(IdempotencyConflictException::class);
        $service->post($this->command($fixture['product_id'], 2, $eventId), 'actor-test', 'device-test', '1.0.0-test');
    }

    #[Test]
    public function injected_failure_at_each_write_stage_rolls_back_order_stock_journal_audit_and_receipt(): void
    {
        $stages = [
            'after_allocation',
            'after_stock_decrement',
            'after_sale_header',
            'after_sale_items',
            'after_journal_lines',
            'after_journal_posted',
            'after_accounting_event',
            'after_sync_receipt',
        ];

        foreach ($stages as $stage) {
            $fixture = $this->fixture(3);
            $eventId = $this->eventId();
            $service = new class($stage) extends AtomicSalePostingService {
                public function __construct(private readonly string $failAt)
                {
                }

                protected function checkpoint(string $stage): void
                {
                    if ($stage === $this->failAt) {
                        throw new RuntimeException('injected-'.$stage);
                    }
                }
            };

            try {
                $service->post($this->command($fixture['product_id'], 2, $eventId), 'actor-test', 'device-test', '1.0.0-test');
                self::fail('Expected injected failure at '.$stage);
            } catch (RuntimeException $exception) {
                self::assertSame('injected-'.$stage, $exception->getMessage());
            }

            self::assertSame(0, $this->db->table('sales')->where('source_event_id', $eventId)->count(), $stage);
            self::assertSame(0, $this->db->table('sale_items')->where('sale_id', 'sale:'.$eventId)->count(), $stage);
            self::assertSame(0, $this->db->table('inventory_movements')->where('source_event_id', $eventId)->count(), $stage);
            self::assertSame(0, $this->db->table('journal_entries')->where('source_event_id', $eventId)->count(), $stage);
            self::assertSame(0, $this->db->table('accounting_events')->where('idempotency_key', $eventId)->count(), $stage);
            self::assertSame(0, $this->db->table('sync_receipts')->where('event_id', $eventId)->count(), $stage);
            self::assertSame('1.000', $this->decimal($this->db->table('inventory_lots')->where('id', $fixture['lot_soon'])->value('quantity_remaining')), $stage);
            self::assertSame('2.000', $this->decimal($this->db->table('inventory_lots')->where('id', $fixture['lot_later'])->value('quantity_remaining')), $stage);
            self::assertSame('1.000', $this->decimal($this->db->table('inventory_cost_layers')->where('id', $fixture['layer_fifo'])->value('quantity_remaining')), $stage);
            self::assertSame('2.000', $this->decimal($this->db->table('inventory_cost_layers')->where('id', $fixture['layer_next'])->value('quantity_remaining')), $stage);
        }
    }

    #[Test]
    public function expired_lot_is_not_saleable_and_no_stock_or_order_is_written(): void
    {
        $fixture = $this->fixture(1);
        $this->db->table('inventory_lots')->where('id', $fixture['lot_soon'])->update([
            'expires_at' => CarbonImmutable::now('Asia/Jakarta')->subDay()->toDateString(),
        ]);
        $command = $this->command($fixture['product_id'], 1, $this->eventId());

        try {
            (new AtomicSalePostingService())->post($command, 'actor-test', 'device-test', '1.0.0-test');
            self::fail('Expected expired stock to be rejected');
        } catch (SalePostingException $exception) {
            self::assertStringContainsString('Insufficient eligible FEFO stock', $exception->getMessage());
        }

        self::assertSame(0, $this->db->table('sales')->where('source_event_id', $command['event_id'])->count());
        self::assertSame(0, $this->db->table('inventory_movements')->where('source_event_id', $command['event_id'])->count());
        self::assertSame('1.000', $this->decimal($this->db->table('inventory_lots')->where('id', $fixture['lot_soon'])->value('quantity_remaining')));
    }

    #[Test]
    public function missing_fifo_cost_layer_fails_closed_without_mutating_physical_stock(): void
    {
        $fixture = $this->fixture(1);
        $this->db->table('inventory_cost_layers')->where('id', $fixture['layer_fifo'])->delete();
        $command = $this->command($fixture['product_id'], 1, $this->eventId());

        try {
            (new AtomicSalePostingService())->post($command, 'actor-test', 'device-test', '1.0.0-test');
            self::fail('Expected missing FIFO cost layer to be rejected');
        } catch (SalePostingException $exception) {
            self::assertStringContainsString('Insufficient FIFO cost layers', $exception->getMessage());
        }

        self::assertSame('1.000', $this->decimal($this->db->table('inventory_lots')->where('id', $fixture['lot_soon'])->value('quantity_remaining')));
        self::assertSame(0, $this->db->table('sales')->where('source_event_id', $command['event_id'])->count());
    }

    #[Test]
    public function posted_journal_and_its_lines_cannot_be_mutated_or_deleted(): void
    {
        $fixture = $this->fixture(1);
        $command = $this->command($fixture['product_id'], 1, $this->eventId());
        $result = (new AtomicSalePostingService())->post($command, 'actor-test', 'device-test', '1.0.0-test');

        try {
            $this->db->table('journal_entries')->where('id', $result['journal_entry_id'])->update(['description' => 'tampered']);
            self::fail('Posted journal header update must be rejected');
        } catch (QueryException $exception) {
            self::assertStringContainsString('Posted journal is immutable', $exception->getMessage());
        }

        try {
            $this->db->table('journal_lines')->where('journal_entry_id', $result['journal_entry_id'])->delete();
            self::fail('Posted journal line deletion must be rejected');
        } catch (QueryException $exception) {
            self::assertStringContainsString('Posted journal lines are immutable', $exception->getMessage());
        }

        $now = CarbonImmutable::now('UTC')->format('Y-m-d H:i:s');
        try {
            $this->db->table('journal_lines')->insert([
                'journal_entry_id' => $result['journal_entry_id'],
                'line_no' => 99,
                'account_code' => '1-1010',
                'debit' => 1,
                'credit' => 0,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
            self::fail('Posted journal must not accept an appended line');
        } catch (QueryException $exception) {
            self::assertStringContainsString('Posted journal lines are immutable', $exception->getMessage());
        }

        self::assertSame('posted', $this->db->table('journal_entries')->where('id', $result['journal_entry_id'])->value('status'));
        self::assertSame(4, $this->db->table('journal_lines')->where('journal_entry_id', $result['journal_entry_id'])->count());
    }

    #[Test]
    public function postgres_deferrable_constraint_rejects_unbalanced_posted_journal(): void
    {
        $journalId = 'bad-journal-'.$this->randomSuffix();
        $eventKey = 'bad-event-'.$this->randomSuffix();
        $date = CarbonImmutable::now('Asia/Jakarta')->toDateString();
        $now = CarbonImmutable::now('UTC')->format('Y-m-d H:i:s');

        try {
            $this->db->transaction(function (Connection $db) use ($journalId, $eventKey, $date, $now): void {
                $db->table('journal_entries')->insert([
                    'id' => $journalId,
                    'source_event_id' => null,
                    'description' => 'Intentional unbalanced test journal',
                    'journal_date' => $date,
                    'status' => 'draft',
                    'entry_type' => 'manual',
                    'currency_code' => 'IDR',
                    'actor_reference' => 'actor-test',
                    'device_id' => 'device-test',
                    'app_version' => '1.0.0-test',
                    'transaction_reference' => $eventKey,
                    'idempotency_key' => $eventKey,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
                $db->table('journal_lines')->insert([
                    ['journal_entry_id' => $journalId, 'line_no' => 0, 'account_code' => '1-1010', 'debit' => 10000, 'credit' => 0, 'created_at' => $now, 'updated_at' => $now],
                    ['journal_entry_id' => $journalId, 'line_no' => 1, 'account_code' => '4-4010', 'debit' => 0, 'credit' => 9000, 'created_at' => $now, 'updated_at' => $now],
                ]);
                $db->table('journal_entries')->where('id', $journalId)->update(['status' => 'posted', 'posted_at' => $now, 'updated_at' => $now]);
                $db->table('accounting_events')->insert([
                    'id' => 'audit-'.$eventKey,
                    'journal_entry_id' => $journalId,
                    'event_type' => 'journal.posted',
                    'actor_reference' => 'actor-test',
                    'occurred_at' => CarbonImmutable::now('UTC')->format('Y-m-d H:i:sP'),
                    'device_id' => 'device-test',
                    'app_version' => '1.0.0-test',
                    'transaction_reference' => $eventKey,
                    'idempotency_key' => $eventKey,
                    'context' => json_encode(['source' => 'negative-test'], JSON_THROW_ON_ERROR),
                ]);
            });
            self::fail('Unbalanced posting must fail at PostgreSQL transaction commit');
        } catch (Throwable $exception) {
            self::assertStringContainsString('Posted journal must have', $exception->getMessage());
        }

        self::assertSame(0, $this->db->table('journal_entries')->where('id', $journalId)->count());
    }

    #[Test]
    public function locked_coa_cannot_be_changed_by_runtime_role(): void
    {
        try {
            $this->db->table('chart_of_accounts')->where('account_code', '4-4010')->update(['name_id' => 'Tampered']);
            self::fail('Runtime must not be able to mutate the locked COA');
        } catch (QueryException $exception) {
            self::assertStringContainsString('permission denied', strtolower($exception->getMessage()));
        }

        self::assertSame('Penjualan', $this->db->table('chart_of_accounts')->where('account_code', '4-4010')->value('name_id'));
    }

    #[Test]
    public function posting_in_a_closed_period_is_rejected_and_transaction_is_rolled_back(): void
    {
        $fixture = $this->fixture(1);
        $closedMonth = '2025-08-01';
        $now = CarbonImmutable::now('UTC')->format('Y-m-d H:i:sP');
        $this->ownerDb->table('accounting_periods')->insertOrIgnore([
            'period_month' => $closedMonth,
            'status' => 'closed',
            'closed_at' => $now,
            'closed_by' => 'owner-test',
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $eventId = $this->eventId();
        $command = $this->commandAt($fixture['product_id'], 1, $eventId, '2025-08-15T10:00:00+07:00');

        try {
            (new AtomicSalePostingService())->post($command, 'actor-test', 'device-test', '1.0.0-test');
            self::fail('Closed period posting must fail');
        } catch (QueryException $exception) {
            self::assertStringContainsString('Journal date is outside an open accounting period', $exception->getMessage());
        }

        self::assertSame(0, $this->db->table('sales')->where('source_event_id', $eventId)->count());
        self::assertSame(0, $this->db->table('inventory_movements')->where('source_event_id', $eventId)->count());
        self::assertSame('1.000', $this->decimal($this->db->table('inventory_lots')->where('id', $fixture['lot_soon'])->value('quantity_remaining')));
    }

    #[Test]
    public function journal_only_reversal_exactly_inverts_a_non_sale_entry_and_is_idempotent(): void
    {
        $originalId = $this->createManualPostedJournal();
        $key = 'reverse-'.$this->randomSuffix();
        $service = new JournalReversalService();

        $first = $service->reverse(
            $originalId, $key, CarbonImmutable::now('Asia/Jakarta')->toDateString(),
            'correction', 'actor-test', 'device-test', '1.0.0-test',
        );
        $retry = $service->reverse(
            $originalId, $key, CarbonImmutable::now('Asia/Jakarta')->toDateString(),
            'correction', 'actor-test', 'device-test', '1.0.0-test',
        );

        self::assertSame($first, $retry);
        self::assertSame($originalId, $first['reversal_of_entry_id']);
        self::assertSame($first['total_debit'], $first['total_credit']);
        $lines = $this->db->table('journal_lines')->where('journal_entry_id', $first['journal_entry_id'])->orderBy('line_no')->get();
        self::assertSame(['0', '10000'], [(string) $lines[0]->debit, (string) $lines[0]->credit]);
        self::assertSame(['10000', '0'], [(string) $lines[1]->debit, (string) $lines[1]->credit]);
    }

    #[Test]
    public function parallel_last_stock_requests_cannot_both_commit(): void
    {
        if (!function_exists('proc_open')) {
            self::fail('proc_open is required for independent PostgreSQL worker concurrency evidence.');
        }

        $fixture = $this->fixture(1);
        $eventA = $this->eventId();
        $eventB = $this->eventId();
        $commands = [
            $this->command($fixture['product_id'], 1, $eventA),
            $this->command($fixture['product_id'], 1, $eventB),
        ];
        DB::purge('tenant');
        DB::purge('tenant_owner_test');

        $barrier = sys_get_temp_dir().'/btp-posting-start-'.$this->randomSuffix();
        $resultPaths = [
            sys_get_temp_dir().'/btp-posting-result-'.$this->randomSuffix(),
            sys_get_temp_dir().'/btp-posting-result-'.$this->randomSuffix(),
        ];
        $processes = [];
        $pipesByProcess = [];

        foreach ($commands as $index => $command) {
            $appPath = base_path();
            $autoloadLiteral = var_export($appPath.'/vendor/autoload.php', true);
            $bootstrapLiteral = var_export($appPath.'/bootstrap/app.php', true);
            $commandEncoded = base64_encode(json_encode($command, JSON_THROW_ON_ERROR));
            $barrierLiteral = var_export($barrier, true);
            $commandLiteral = var_export($commandEncoded, true);
            $resultLiteral = var_export($resultPaths[$index], true);
            $script = <<<PHP
require {$autoloadLiteral};
\$app = require {$bootstrapLiteral};
\$app->make(Illuminate\\Contracts\\Console\\Kernel::class)->bootstrap();
\$tenant = config('database.connections.tenant');
\$tenant['username'] = getenv('TENANT_RUNTIME_DB_USERNAME') ?: 'berkahpos_tenant_runtime_test';
\$tenant['password'] = getenv('TENANT_RUNTIME_DB_PASSWORD') ?: 'tenant-runtime-ci-only';
config(['database.connections.tenant' => \$tenant]);
Illuminate\\Support\\Facades\\DB::purge('tenant');
\$barrier = {$barrierLiteral};
while (!is_file(\$barrier)) { usleep(1000); }
\$command = json_decode(base64_decode({$commandLiteral}), true, 512, JSON_THROW_ON_ERROR);
try {
  \$result = (new App\\Services\\Tenant\\AtomicSalePostingService())->post(\$command, 'actor-concurrency', 'device-concurrency', '1.0.0-test');
  \$out = ['ok' => true, 'result' => \$result];
} catch (Throwable \$e) {
  \$out = ['ok' => false, 'exception' => \$e::class, 'message' => \$e->getMessage()];
}
file_put_contents({$resultLiteral}, json_encode(\$out, JSON_THROW_ON_ERROR));
PHP;
            $pipes = [];
            $process = proc_open([PHP_BINARY, '-r', $script], [
                0 => ['pipe', 'r'],
                1 => ['pipe', 'w'],
                2 => ['pipe', 'w'],
            ], $pipes, base_path());
            if (!is_resource($process)) {
                self::fail('Unable to start independent PostgreSQL worker process.');
            }
            fclose($pipes[0]);
            $processes[] = $process;
            $pipesByProcess[] = $pipes;
        }

        touch($barrier);
        foreach ($processes as $index => $process) {
            $stdout = stream_get_contents($pipesByProcess[$index][1]);
            $stderr = stream_get_contents($pipesByProcess[$index][2]);
            fclose($pipesByProcess[$index][1]);
            fclose($pipesByProcess[$index][2]);
            $exitCode = proc_close($process);
            self::assertSame(0, $exitCode, 'Worker error: '.$stderr.' '.$stdout);
        }
        @unlink($barrier);

        $results = [];
        foreach ($resultPaths as $path) {
            self::assertFileExists($path);
            $results[] = json_decode((string) file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
            @unlink($path);
        }
        self::assertSame(1, count(array_filter($results, fn (array $r): bool => $r['ok'] === true)), json_encode($results));
        self::assertSame(1, $this->db->table('sales')->whereIn('source_event_id', [$eventA, $eventB])->count());
        self::assertSame(1, $this->db->table('inventory_movements')->whereIn('source_event_id', [$eventA, $eventB])->count());
        self::assertSame('0.000', $this->decimal($this->db->table('inventory_lots')->where('id', $fixture['lot_soon'])->value('quantity_remaining')));
        self::assertSame('0.000', $this->decimal($this->db->table('inventory_cost_layers')->where('id', $fixture['layer_fifo'])->value('quantity_remaining')));
    }

    private function fixture(int $stockQuantity): array
    {
        $suffix = $this->randomSuffix();
        $productId = 'test-product-'.$suffix;
        $lotSoon = 'lot-soon-'.$suffix;
        $lotLater = 'lot-later-'.$suffix;
        $layerFifo = 'layer-fifo-'.$suffix;
        $layerNext = 'layer-next-'.$suffix;
        $now = CarbonImmutable::now('UTC');
        $timestamp = $now->format('Y-m-d H:i:s');
        $soonQty = $stockQuantity > 1 ? 1 : $stockQuantity;
        $laterQty = max(0, $stockQuantity - $soonQty);

        $this->db->table('products')->insert([
            'id' => $productId,
            'sku' => 'SKU-'.$suffix,
            'barcode' => null,
            'name' => 'Test Product '.$suffix,
            'category_id' => null,
            'price' => 10000,
            'requires_review' => false,
            'is_active' => true,
            'track_expiry' => true,
            'min_shelf_life_days' => 0,
            'currency_code' => 'IDR',
            'created_at' => $timestamp,
            'updated_at' => $timestamp,
        ]);

        $this->db->table('inventory_lots')->insert([
            [
                'id' => $lotSoon,
                'product_id' => $productId,
                'batch_code' => 'BATCH-SOON-'.$suffix,
                'expires_at' => $now->setTimezone('Asia/Jakarta')->addDays(20)->toDateString(),
                'quantity_received' => $soonQty,
                'quantity_remaining' => $soonQty,
                'unit_cost' => 3000,
                'received_at' => $now->subDays(20)->format('Y-m-d H:i:s'),
                'created_at' => $timestamp,
                'updated_at' => $timestamp,
            ],
            ...($laterQty > 0 ? [[
                'id' => $lotLater,
                'product_id' => $productId,
                'batch_code' => 'BATCH-LATER-'.$suffix,
                'expires_at' => $now->setTimezone('Asia/Jakarta')->addDays(40)->toDateString(),
                'quantity_received' => $laterQty,
                'quantity_remaining' => $laterQty,
                'unit_cost' => 4000,
                'received_at' => $now->subDays(10)->format('Y-m-d H:i:s'),
                'created_at' => $timestamp,
                'updated_at' => $timestamp,
            ]] : []),
        ]);

        $this->db->table('inventory_cost_layers')->insert([
            [
                'id' => $layerFifo,
                'product_id' => $productId,
                'lot_id' => $lotSoon,
                'source_event_id' => null,
                'quantity_received' => $soonQty,
                'quantity_remaining' => $soonQty,
                'unit_cost' => 3000,
                'acquired_at' => $now->subDays(30)->format('Y-m-d H:i:sP'),
                'created_at' => $timestamp,
                'updated_at' => $timestamp,
            ],
            ...($laterQty > 0 ? [[
                'id' => $layerNext,
                'product_id' => $productId,
                'lot_id' => $lotLater,
                'source_event_id' => null,
                'quantity_received' => $laterQty,
                'quantity_remaining' => $laterQty,
                'unit_cost' => 4000,
                'acquired_at' => $now->subDays(10)->format('Y-m-d H:i:sP'),
                'created_at' => $timestamp,
                'updated_at' => $timestamp,
            ]] : []),
        ]);

        return [
            'product_id' => $productId,
            'lot_soon' => $lotSoon,
            'lot_later' => $laterQty > 0 ? $lotLater : $lotSoon,
            'layer_fifo' => $layerFifo,
            'layer_next' => $laterQty > 0 ? $layerNext : $layerFifo,
            'initial_qty' => $stockQuantity,
        ];
    }

    private function command(string $productId, int $quantity, string $eventId): array
    {
        return $this->commandAt($productId, $quantity, $eventId, CarbonImmutable::now('UTC')->toIso8601String());
    }

    private function commandAt(string $productId, int $quantity, string $eventId, string $occurredAt): array
    {
        return [
            'event_id' => $eventId,
            'occurred_at' => $occurredAt,
            'payment_method' => 'cash',
            'lines' => [['product_id' => $productId, 'quantity' => $quantity]],
        ];
    }

    private function createManualPostedJournal(): string
    {
        $journalId = 'manual-'.$this->randomSuffix();
        $eventId = 'manual-key-'.$this->randomSuffix();
        $date = CarbonImmutable::now('Asia/Jakarta')->toDateString();
        $now = CarbonImmutable::now('UTC');
        $timestamp = $now->format('Y-m-d H:i:s');

        $this->db->transaction(function (Connection $db) use ($journalId, $eventId, $date, $now, $timestamp): void {
            $db->table('journal_entries')->insert([
                'id' => $journalId,
                'source_event_id' => null,
                'description' => 'Manual journal fixture',
                'journal_date' => $date,
                'status' => 'draft',
                'entry_type' => 'manual',
                'currency_code' => 'IDR',
                'actor_reference' => 'actor-fixture',
                'device_id' => 'device-fixture',
                'app_version' => '1.0.0-test',
                'transaction_reference' => $eventId,
                'idempotency_key' => $eventId,
                'created_at' => $timestamp,
                'updated_at' => $timestamp,
            ]);
            $db->table('journal_lines')->insert([
                ['journal_entry_id' => $journalId, 'line_no' => 0, 'account_code' => '1-1010', 'debit' => 10000, 'credit' => 0, 'created_at' => $timestamp, 'updated_at' => $timestamp],
                ['journal_entry_id' => $journalId, 'line_no' => 1, 'account_code' => '4-4010', 'debit' => 0, 'credit' => 10000, 'created_at' => $timestamp, 'updated_at' => $timestamp],
            ]);
            $db->table('journal_entries')->where('id', $journalId)->update([
                'status' => 'posted',
                'posted_at' => $now->format('Y-m-d H:i:sP'),
                'updated_at' => $timestamp,
            ]);
            $db->table('accounting_events')->insert([
                'id' => 'audit-'.$eventId,
                'journal_entry_id' => $journalId,
                'event_type' => 'journal.posted',
                'actor_reference' => 'actor-fixture',
                'occurred_at' => $now->format('Y-m-d H:i:sP'),
                'device_id' => 'device-fixture',
                'app_version' => '1.0.0-test',
                'transaction_reference' => $eventId,
                'idempotency_key' => $eventId,
                'context' => json_encode(['source' => 'test-fixture'], JSON_THROW_ON_ERROR),
            ]);
        });

        return $journalId;
    }

    private function eventId(): string
    {
        return 'event-'.$this->randomSuffix();
    }

    private function randomSuffix(): string
    {
        return substr(bin2hex(random_bytes(10)), 0, 18);
    }

    private function decimal(mixed $value): string
    {
        return number_format((float) $value, 3, '.', '');
    }

}
