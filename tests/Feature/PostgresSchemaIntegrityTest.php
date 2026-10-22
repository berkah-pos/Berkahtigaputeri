<?php

namespace Tests\Feature;

use Illuminate\Database\Connection;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class PostgresSchemaIntegrityTest extends TestCase
{
    public function test_importer_models_exist_and_pin_the_correct_connection(): void
    {
        foreach ([
            \App\Models\Central\User::class, \App\Models\Central\Tenant::class, \App\Models\Central\Domain::class,
            \App\Models\Central\Subscription::class, \App\Models\Central\GlobalConfig::class,
            \App\Models\Central\Template::class, \App\Models\Central\TenantConfig::class,
            \App\Models\Central\DeviceRegistry::class, \App\Models\Central\AuditEvent::class,
        ] as $class) {
            $this->assertTrue(class_exists($class), "Missing model {$class}");
            $this->assertSame('central', (new $class())->getConnectionName(), "{$class} must use central");
        }
        foreach ([
            \App\Models\Tenant\Product::class, \App\Models\Tenant\InventoryLot::class, \App\Models\Tenant\Sale::class,
            \App\Models\Tenant\SaleItem::class, \App\Models\Tenant\InventoryMovement::class,
            \App\Models\Tenant\JournalEntry::class, \App\Models\Tenant\JournalLine::class,
            \App\Models\Tenant\AccountingEvent::class, \App\Models\Tenant\AccountingPeriod::class,
            \App\Models\Tenant\CoaAccount::class, \App\Models\Tenant\SyncReceipt::class, \App\Models\Tenant\DeviceConfig::class,
        ] as $class) {
            $this->assertTrue(class_exists($class), "Missing model {$class}");
            $this->assertSame('tenant', (new $class())->getConnectionName(), "{$class} must use tenant");
        }
        $this->assertSame('pgsql', DB::connection('central')->getDriverName());
        $this->assertSame('pgsql', DB::connection('tenant')->getDriverName());
    }

    public function test_central_constraints_reject_noncanonical_templates_and_mixed_service_scopes(): void
    {
        $db = DB::connection('central');
        $now = now();
        $db->table('templates')->insertOrIgnore([
            'id' => 'BASIC', 'config' => '{}', 'version' => 1, 'created_at' => $now, 'updated_at' => $now,
        ]);
        $this->fails(function () use ($db, $now): void {
            $db->table('tenants')->insert([
                'id' => 'bad-template-'.Str::uuid(), 'template_id' => 'CUSTOM', 'data' => '{}',
                'created_at' => $now, 'updated_at' => $now,
            ]);
        }, 'tenants_canonical_template_check');

        $tenantId = 'schema-test-'.Str::uuid();
        $db->table('tenants')->insert([
            'id' => $tenantId, 'template_id' => 'BASIC', 'data' => '{}', 'created_at' => $now, 'updated_at' => $now,
        ]);
        $this->fails(function () use ($db, $tenantId, $now): void {
            $db->table('tenant_configs')->insert([
                'tenant_id' => $tenantId, 'service' => 'pos', 'service_scope' => 'akuntansi',
                'template_id' => 'BASIC', 'config' => '{}', 'version' => 1,
                'created_at' => $now, 'updated_at' => $now,
            ]);
        }, 'tenant_configs_service_scope_check');
    }

    public function test_the_24_locked_coa_codes_exist_and_database_rejects_mutation(): void
    {
        $db = DB::connection('tenant');
        $expected = [
            '1-1010','1-1020','1-1030','1-1040','1-1050','1-1060','1-1070',
            '2-2010','2-2020','2-2030','3-3010','3-3020','3-3030',
            '4-4010','4-4020','4-4030','4-4040','5-5010',
            '6-6010','6-6020','6-6030','6-6040','6-6050','6-6060',
        ];
        sort($expected);
        $actual = $db->table('coa_accounts')->orderBy('code')->pluck('code')->all();
        $this->assertSame($expected, $actual);
        $this->assertCount(24, $actual);

        $this->fails(function () use ($db): void {
            $db->table('coa_accounts')->insert([
                'code' => '9-9999', 'name_id' => 'Forbidden', 'name_en' => 'Forbidden',
                'account_type' => 'expense', 'normal_balance' => 'debit', 'created_at' => now(), 'updated_at' => now(),
            ]);
        }, 'approved chart of accounts is immutable');
        $this->fails(fn () => $db->table('coa_accounts')->where('code', '1-1040')->update(['name_id' => 'mutated']),
            'approved chart of accounts is immutable');
    }

    public function test_foreign_keys_and_whole_rupiah_constraints_reject_invalid_pos_rows(): void
    {
        $db = DB::connection('tenant');
        $this->fails(function () use ($db): void {
            $db->table('products')->insert([
                'id' => (string) Str::uuid(), 'name' => 'Fractional Rupiah', 'price' => 100.50,
                'requires_review' => false, 'is_active' => true, 'created_at' => now(), 'updated_at' => now(),
            ]);
        }, 'products_price_whole_rupiah_nonnegative_check');
        $this->fails(function () use ($db): void {
            $db->table('inventory_lots')->insert([
                'id' => (string) Str::uuid(), 'product_id' => 'missing-product',
                'quantity_received' => 1, 'quantity_remaining' => 1, 'unit_cost' => 10,
                'received_at' => now(), 'created_at' => now(), 'updated_at' => now(),
            ]);
        }, 'inventory_lots_product_id_fk');
    }

    public function test_balanced_posting_emits_audit_and_unbalanced_posting_is_rejected(): void
    {
        $this->withTenantTx(function (Connection $db): void {
            $period = $this->period($db);
            $journal = $this->draft($db, $period);
            $this->line($db, $journal, '1-1010', 100, 0);
            $this->line($db, $journal, '4-4010', 0, 100);
            $this->post($db, $journal);
            $db->statement('SET CONSTRAINTS ALL IMMEDIATE');
            $event = $db->table('accounting_events')->where('journal_entry_id', $journal)->first();
            $this->assertNotNull($event);
            $this->assertSame('test-user', $event->actor_id);
            $this->assertSame('test-device', $event->device_id);
            $this->assertSame('1.0.0-test', $event->app_version);
        });

        $this->failsDeferred(function (Connection $db): void {
            $period = $this->period($db);
            $journal = $this->draft($db, $period);
            $this->line($db, $journal, '1-1010', 100, 0);
            $this->post($db, $journal);
        }, 'must contain at least two lines and satisfy debit = credit');
    }

    public function test_posted_journals_and_lines_are_immutable(): void
    {
        $this->failsDeferred(function (Connection $db): void {
            $period = $this->period($db);
            $journal = $this->draft($db, $period);
            $this->balancedLines($db, $journal, 100);
            $this->post($db, $journal);
            $db->statement('SET CONSTRAINTS ALL IMMEDIATE');
            $db->table('journal_entries')->where('id', $journal)->update(['description' => 'mutated']);
        }, 'posted journal entries are immutable');

        $this->failsDeferred(function (Connection $db): void {
            $period = $this->period($db);
            $journal = $this->draft($db, $period);
            $this->balancedLines($db, $journal, 100);
            $this->post($db, $journal);
            $db->statement('SET CONSTRAINTS ALL IMMEDIATE');
            $db->table('journal_lines')->where('journal_entry_id', $journal)->where('account_code', '1-1010')->update(['debit' => 101]);
        }, 'journal lines for a posted journal are immutable');
    }

    public function test_closed_periods_reject_posts_and_reversals_must_match_original_totals(): void
    {
        $this->failsDeferred(function (Connection $db): void {
            $period = $this->period($db, true);
            $journal = $this->draft($db, $period);
            $this->balancedLines($db, $journal, 100);
            $this->post($db, $journal);
        }, 'posted journal must reference an open period containing its journal date');

        $this->failsDeferred(function (Connection $db): void {
            $period = $this->period($db);
            $original = $this->draft($db, $period);
            $this->balancedLines($db, $original, 100);
            $this->post($db, $original);
            $db->statement('SET CONSTRAINTS ALL IMMEDIATE');
            $reversal = $this->draft($db, $period, $original);
            $this->line($db, $reversal, '4-4010', 0, 50);
            $this->line($db, $reversal, '1-1010', 50, 0);
            $this->post($db, $reversal);
        }, 'reversal journal must exactly reverse the original account totals');
    }

    private function fails(callable $operation, string $message): void
    {
        try {
            $operation();
            $this->fail("Expected PostgreSQL to reject: {$message}");
        } catch (QueryException $exception) {
            $this->assertStringContainsString(strtolower($message), strtolower($exception->getMessage()));
        }
    }

    private function failsDeferred(callable $operation, string $message): void
    {
        $db = DB::connection('tenant');
        $db->beginTransaction();
        try {
            $operation($db);
            $db->statement('SET CONSTRAINTS ALL IMMEDIATE');
            $this->fail("Expected PostgreSQL transaction to reject: {$message}");
        } catch (QueryException $exception) {
            $this->assertStringContainsString(strtolower($message), strtolower($exception->getMessage()));
        } finally {
            while ($db->transactionLevel() > 0) $db->rollBack();
        }
    }

    private function withTenantTx(callable $operation): void
    {
        $db = DB::connection('tenant');
        $db->beginTransaction();
        try { $operation($db); }
        finally { while ($db->transactionLevel() > 0) $db->rollBack(); }
    }

    private function period(Connection $db, bool $closed = false): int
    {
        return (int) $db->table('accounting_periods')->insertGetId([
            'starts_on' => '2026-10-01', 'ends_on' => '2026-10-31',
            'status' => $closed ? 'closed' : 'open', 'closed_at' => $closed ? now() : null,
            'closed_by' => $closed ? 'test-closer' : null, 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function draft(Connection $db, int $period, ?string $reversalOf = null): string
    {
        $id = (string) Str::uuid();
        $db->table('journal_entries')->insert([
            'id' => $id, 'source_event_id' => (string) Str::uuid(), 'description' => 'Integrity test',
            'journal_date' => '2026-10-22', 'status' => 'draft', 'period_id' => $period,
            'reversal_of_id' => $reversalOf, 'created_at' => now(), 'updated_at' => now(),
        ]);
        return $id;
    }

    private function balancedLines(Connection $db, string $id, int $amount): void
    {
        $this->line($db, $id, '1-1010', $amount, 0);
        $this->line($db, $id, '4-4010', 0, $amount);
    }

    private function line(Connection $db, string $id, string $account, int $debit, int $credit): void
    {
        $db->table('journal_lines')->insert([
            'journal_entry_id' => $id, 'account_code' => $account, 'debit' => $debit, 'credit' => $credit,
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function post(Connection $db, string $id): void
    {
        $db->table('journal_entries')->where('id', $id)->update([
            'status' => 'posted', 'posted_at' => now(), 'posted_by' => 'test-user',
            'device_id' => 'test-device', 'app_version' => '1.0.0-test', 'updated_at' => now(),
        ]);
    }
}
