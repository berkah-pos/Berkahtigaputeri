<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'tenant';

    public function up(): void
    {
        if (DB::connection('tenant')->table('journal_entries')->exists()) {
            throw new RuntimeException(
                'Existing journal_entries need a reviewed status/period/audit mapping before the accounting integrity migration can run.'
            );
        }

        Schema::connection('tenant')->create('coa_accounts', function (Blueprint $table): void {
            $table->string('code', 20)->primary();
            $table->string('name_id', 150);
            $table->string('name_en', 150)->nullable();
            $table->string('account_type', 20);
            $table->string('normal_balance', 10);
            $table->timestampsTz();
        });

        $accounts = [
            ['code' => '1-1010', 'name_id' => 'Kas Tunai', 'name_en' => 'Cash on Hand', 'account_type' => 'asset', 'normal_balance' => 'debit'],
            ['code' => '1-1020', 'name_id' => 'QRIS Clearing', 'name_en' => 'QRIS Clearing', 'account_type' => 'asset', 'normal_balance' => 'debit'],
            ['code' => '1-1030', 'name_id' => 'Bank Transfer', 'name_en' => 'Bank Transfer', 'account_type' => 'asset', 'normal_balance' => 'debit'],
            ['code' => '1-1040', 'name_id' => 'Persediaan Barang', 'name_en' => 'Inventory', 'account_type' => 'asset', 'normal_balance' => 'debit'],
            ['code' => '1-1050', 'name_id' => 'Piutang Usaha', 'name_en' => 'Accounts Receivable', 'account_type' => 'asset', 'normal_balance' => 'debit'],
            ['code' => '1-1060', 'name_id' => 'Peralatan Toko', 'name_en' => 'Store Equipment', 'account_type' => 'asset', 'normal_balance' => 'debit'],
            ['code' => '1-1070', 'name_id' => 'Akumulasi Penyusutan Peralatan', 'name_en' => 'Accumulated Depreciation', 'account_type' => 'asset', 'normal_balance' => 'credit'],
            ['code' => '2-2010', 'name_id' => 'Utang PPN 11%', 'name_en' => 'PPN Payable 11%', 'account_type' => 'liability', 'normal_balance' => 'credit'],
            ['code' => '2-2020', 'name_id' => 'Utang Supplier', 'name_en' => 'Supplier Payable', 'account_type' => 'liability', 'normal_balance' => 'credit'],
            ['code' => '2-2030', 'name_id' => 'Utang Gaji', 'name_en' => 'Salary Payable', 'account_type' => 'liability', 'normal_balance' => 'credit'],
            ['code' => '3-3010', 'name_id' => 'Modal Pemilik', 'name_en' => 'Owner Capital', 'account_type' => 'equity', 'normal_balance' => 'credit'],
            ['code' => '3-3020', 'name_id' => 'Laba Ditahan', 'name_en' => 'Retained Earnings', 'account_type' => 'equity', 'normal_balance' => 'credit'],
            ['code' => '3-3030', 'name_id' => 'Prive', 'name_en' => 'Owner Drawings', 'account_type' => 'equity', 'normal_balance' => 'debit'],
            ['code' => '4-4010', 'name_id' => 'Penjualan', 'name_en' => 'Sales', 'account_type' => 'revenue', 'normal_balance' => 'credit'],
            ['code' => '4-4020', 'name_id' => 'Diskon Penjualan', 'name_en' => 'Sales Discounts', 'account_type' => 'revenue', 'normal_balance' => 'debit'],
            ['code' => '4-4030', 'name_id' => 'Retur Penjualan', 'name_en' => 'Sales Returns', 'account_type' => 'revenue', 'normal_balance' => 'debit'],
            ['code' => '4-4040', 'name_id' => 'Selisih Kas Lebih', 'name_en' => 'Cash Overage Income', 'account_type' => 'revenue', 'normal_balance' => 'credit'],
            ['code' => '5-5010', 'name_id' => 'Harga Pokok Penjualan', 'name_en' => 'Cost of Goods Sold', 'account_type' => 'cogs', 'normal_balance' => 'debit'],
            ['code' => '6-6010', 'name_id' => 'Beban Gaji', 'name_en' => 'Salary Expense', 'account_type' => 'expense', 'normal_balance' => 'debit'],
            ['code' => '6-6020', 'name_id' => 'Beban Selisih Kas Kurang', 'name_en' => 'Cash Shortage Expense', 'account_type' => 'expense', 'normal_balance' => 'debit'],
            ['code' => '6-6030', 'name_id' => 'Beban Operasional Toko', 'name_en' => 'Store Operational', 'account_type' => 'expense', 'normal_balance' => 'debit'],
            ['code' => '6-6040', 'name_id' => 'Beban Sewa', 'name_en' => 'Rent Expense', 'account_type' => 'expense', 'normal_balance' => 'debit'],
            ['code' => '6-6050', 'name_id' => 'Beban Listrik dan Air', 'name_en' => 'Utilities Expense', 'account_type' => 'expense', 'normal_balance' => 'debit'],
            ['code' => '6-6060', 'name_id' => 'Beban Penyusutan', 'name_en' => 'Depreciation Expense', 'account_type' => 'expense', 'normal_balance' => 'debit'],
        ];
        $now = now();
        foreach ($accounts as &$account) {
            $account['created_at'] = $now;
            $account['updated_at'] = $now;
        }
        unset($account);
        DB::connection('tenant')->table('coa_accounts')->insert($accounts);

        Schema::connection('tenant')->create('accounting_periods', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->date('starts_on');
            $table->date('ends_on');
            $table->string('status', 10)->default('open');
            $table->timestampTz('closed_at')->nullable();
            $table->string('closed_by', 150)->nullable();
            $table->timestampsTz();
            $table->unique(['starts_on', 'ends_on'], 'accounting_periods_bounds_unique');
        });

        Schema::connection('tenant')->table('journal_entries', function (Blueprint $table): void {
            $table->string('status', 16)->default('draft');
            $table->timestampTz('posted_at')->nullable();
            $table->string('posted_by', 150)->nullable();
            $table->string('device_id', 150)->nullable();
            $table->string('app_version', 64)->nullable();
            $table->foreignId('period_id')->nullable();
            $table->string('reversal_of_id', 100)->nullable();
            $table->foreign('period_id', 'journal_entries_period_id_fk')
                ->references('id')->on('accounting_periods')->restrictOnDelete();
            $table->foreign('reversal_of_id', 'journal_entries_reversal_of_id_fk')
                ->references('id')->on('journal_entries')->restrictOnDelete();
        });

        Schema::connection('tenant')->create('accounting_events', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('journal_entry_id', 100);
            $table->string('actor_id', 150);
            $table->string('device_id', 150);
            $table->string('app_version', 64);
            $table->string('action', 40);
            $table->timestampTz('occurred_at')->useCurrent();
            $table->jsonb('metadata')->nullable();
            $table->foreign('journal_entry_id', 'accounting_events_journal_entry_id_fk')
                ->references('id')->on('journal_entries')->restrictOnDelete();
            $table->index(['journal_entry_id', 'occurred_at'], 'accounting_events_journal_occurred_idx');
        });

        Schema::connection('tenant')->table('inventory_lots', function (Blueprint $table): void {
            $table->foreign('product_id', 'inventory_lots_product_id_fk')
                ->references('id')->on('products')->restrictOnDelete();
        });
        Schema::connection('tenant')->table('sale_items', function (Blueprint $table): void {
            $table->foreign('sale_id', 'sale_items_sale_id_fk')
                ->references('id')->on('sales')->restrictOnDelete();
            $table->foreign('product_id', 'sale_items_product_id_fk')
                ->references('id')->on('products')->restrictOnDelete();
        });
        Schema::connection('tenant')->table('inventory_movements', function (Blueprint $table): void {
            $table->foreign('product_id', 'inventory_movements_product_id_fk')
                ->references('id')->on('products')->restrictOnDelete();
        });
        Schema::connection('tenant')->table('journal_lines', function (Blueprint $table): void {
            $table->foreign('journal_entry_id', 'journal_lines_journal_entry_id_fk')
                ->references('id')->on('journal_entries')->restrictOnDelete();
            $table->foreign('account_code', 'journal_lines_account_code_fk')
                ->references('code')->on('coa_accounts')->restrictOnDelete();
        });

        DB::connection('tenant')->unprepared(<<<'SQL'
ALTER TABLE coa_accounts
    ADD CONSTRAINT coa_accounts_type_check CHECK (account_type IN ('asset', 'liability', 'equity', 'revenue', 'cogs', 'expense')),
    ADD CONSTRAINT coa_accounts_normal_balance_check CHECK (normal_balance IN ('debit', 'credit'));

ALTER TABLE accounting_periods
    ADD CONSTRAINT accounting_periods_bounds_check CHECK (starts_on <= ends_on),
    ADD CONSTRAINT accounting_periods_status_check CHECK (status IN ('open', 'closed')),
    ADD CONSTRAINT accounting_periods_close_metadata_check
        CHECK ((status = 'open' AND closed_at IS NULL AND closed_by IS NULL)
            OR (status = 'closed' AND closed_at IS NOT NULL AND closed_by IS NOT NULL AND length(btrim(closed_by)) > 0));

ALTER TABLE products
    ADD CONSTRAINT products_price_whole_rupiah_nonnegative_check CHECK (price >= 0 AND price = trunc(price));

ALTER TABLE inventory_lots
    ADD CONSTRAINT inventory_lots_quantity_bounds_check
        CHECK (quantity_received > 0 AND quantity_remaining >= 0 AND quantity_remaining <= quantity_received),
    ADD CONSTRAINT inventory_lots_unit_cost_whole_rupiah_check CHECK (unit_cost >= 0 AND unit_cost = trunc(unit_cost));

ALTER TABLE sales
    ADD CONSTRAINT sales_money_whole_rupiah_check
        CHECK (subtotal >= 0 AND tax_amount >= 0 AND total_amount >= 0
            AND subtotal = trunc(subtotal) AND tax_amount = trunc(tax_amount) AND total_amount = trunc(total_amount));

ALTER TABLE sale_items
    ADD CONSTRAINT sale_items_quantity_positive_check CHECK (quantity > 0),
    ADD CONSTRAINT sale_items_money_whole_rupiah_check
        CHECK (unit_price >= 0 AND line_total >= 0 AND unit_cost >= 0
            AND unit_price = trunc(unit_price) AND line_total = trunc(line_total) AND unit_cost = trunc(unit_cost));

ALTER TABLE inventory_movements
    ADD CONSTRAINT inventory_movements_quantity_nonzero_check CHECK (quantity <> 0);

ALTER TABLE journal_entries
    ADD CONSTRAINT journal_entries_status_check CHECK (status IN ('draft', 'posted')),
    ADD CONSTRAINT journal_entries_posted_metadata_check
        CHECK (status = 'draft' OR
            (posted_at IS NOT NULL AND posted_by IS NOT NULL AND length(btrim(posted_by)) > 0
                AND device_id IS NOT NULL AND length(btrim(device_id)) > 0
                AND app_version IS NOT NULL AND length(btrim(app_version)) > 0 AND period_id IS NOT NULL)),
    ADD CONSTRAINT journal_entries_not_self_reversal_check CHECK (reversal_of_id IS NULL OR reversal_of_id <> id);

CREATE UNIQUE INDEX journal_entries_single_reversal_idx
    ON journal_entries (reversal_of_id) WHERE reversal_of_id IS NOT NULL;

ALTER TABLE journal_lines
    ADD CONSTRAINT journal_lines_one_sided_whole_rupiah_check
        CHECK (debit >= 0 AND credit >= 0 AND
            ((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0))
            AND debit = trunc(debit) AND credit = trunc(credit));

ALTER TABLE accounting_periods
    ADD CONSTRAINT accounting_periods_no_overlap
    EXCLUDE USING gist (daterange(starts_on, ends_on, '[]') WITH &&);

CREATE OR REPLACE FUNCTION btp_guard_posted_journal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    period_row_id bigint;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status = 'posted' THEN
            RAISE EXCEPTION 'posted journal entries are immutable; use a reversal entry'
                USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;

    IF TG_OP <> 'INSERT' THEN
        IF OLD.status = 'posted' THEN
            RAISE EXCEPTION 'posted journal entries are immutable; use a reversal entry'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    IF NEW.status = 'posted' THEN
        IF NEW.posted_at IS NULL OR NEW.posted_by IS NULL OR length(btrim(NEW.posted_by)) = 0
            OR NEW.device_id IS NULL OR length(btrim(NEW.device_id)) = 0
            OR NEW.app_version IS NULL OR length(btrim(NEW.app_version)) = 0
            OR NEW.period_id IS NULL THEN
            RAISE EXCEPTION 'posting requires actor, device, app version, timestamp and accounting period'
                USING ERRCODE = '23514';
        END IF;

        SELECT id INTO period_row_id
        FROM accounting_periods
        WHERE id = NEW.period_id
          AND status = 'open'
          AND NEW.journal_date BETWEEN starts_on AND ends_on
        FOR SHARE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'posted journal must reference an open period containing its journal date'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER journal_entries_guard_posted
    BEFORE INSERT OR UPDATE OR DELETE ON journal_entries
    FOR EACH ROW EXECUTE FUNCTION btp_guard_posted_journal();

CREATE OR REPLACE FUNCTION btp_guard_journal_line_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    parent_status varchar(16);
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT status INTO parent_status FROM journal_entries WHERE id = OLD.journal_entry_id;
        IF parent_status = 'posted' THEN
            RAISE EXCEPTION 'journal lines for a posted journal are immutable'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        SELECT status INTO parent_status FROM journal_entries WHERE id = NEW.journal_entry_id;
        IF parent_status = 'posted' THEN
            RAISE EXCEPTION 'journal lines for a posted journal are immutable'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$;

CREATE TRIGGER journal_lines_guard_posted
    BEFORE INSERT OR UPDATE OR DELETE ON journal_lines
    FOR EACH ROW EXECUTE FUNCTION btp_guard_journal_line_mutation();

CREATE OR REPLACE FUNCTION btp_reject_accounting_truncate()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'TRUNCATE is prohibited for accounting integrity and audit tables'
        USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER journal_entries_reject_truncate
    BEFORE TRUNCATE ON journal_entries
    FOR EACH STATEMENT EXECUTE FUNCTION btp_reject_accounting_truncate();
CREATE TRIGGER journal_lines_reject_truncate
    BEFORE TRUNCATE ON journal_lines
    FOR EACH STATEMENT EXECUTE FUNCTION btp_reject_accounting_truncate();
CREATE TRIGGER accounting_events_reject_truncate
    BEFORE TRUNCATE ON accounting_events
    FOR EACH STATEMENT EXECUTE FUNCTION btp_reject_accounting_truncate();
CREATE TRIGGER accounting_periods_reject_truncate
    BEFORE TRUNCATE ON accounting_periods
    FOR EACH STATEMENT EXECUTE FUNCTION btp_reject_accounting_truncate();
CREATE TRIGGER coa_accounts_reject_truncate
    BEFORE TRUNCATE ON coa_accounts
    FOR EACH STATEMENT EXECUTE FUNCTION btp_reject_accounting_truncate();

CREATE OR REPLACE FUNCTION btp_reject_accounting_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'accounting_events is append-only'
        USING ERRCODE = '55000';
END;
$$;

CREATE OR REPLACE FUNCTION btp_reject_coa_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'the approved chart of accounts is immutable; use a reviewed migration'
        USING ERRCODE = '55000';
END;
$$;

CREATE TRIGGER accounting_events_append_only
    BEFORE UPDATE OR DELETE ON accounting_events
    FOR EACH ROW EXECUTE FUNCTION btp_reject_accounting_audit_mutation();

CREATE TRIGGER coa_accounts_locked
    BEFORE INSERT OR UPDATE OR DELETE ON coa_accounts
    FOR EACH ROW EXECUTE FUNCTION btp_reject_coa_mutation();

CREATE OR REPLACE FUNCTION btp_guard_accounting_period()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status = 'closed' OR EXISTS (SELECT 1 FROM journal_entries WHERE period_id = OLD.id) THEN
            RAISE EXCEPTION 'closed or journal-referenced accounting periods cannot be deleted'
                USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.status = 'closed' THEN
        RAISE EXCEPTION 'closed accounting periods are immutable'
            USING ERRCODE = '55000';
    END IF;

    IF NEW.status = 'closed' THEN
        IF NEW.closed_by IS NULL OR length(btrim(NEW.closed_by)) = 0 THEN
            RAISE EXCEPTION 'closing an accounting period requires closed_by'
                USING ERRCODE = '23514';
        END IF;
        NEW.closed_at := COALESCE(NEW.closed_at, CURRENT_TIMESTAMP);
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER accounting_periods_guard
    BEFORE UPDATE OR DELETE ON accounting_periods
    FOR EACH ROW EXECUTE FUNCTION btp_guard_accounting_period();

CREATE OR REPLACE FUNCTION btp_record_journal_posting()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    was_posted boolean := false;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        was_posted := OLD.status = 'posted';
    END IF;

    IF NEW.status = 'posted' AND NOT was_posted THEN
        INSERT INTO accounting_events
            (journal_entry_id, actor_id, device_id, app_version, action, occurred_at, metadata)
        VALUES
            (NEW.id, NEW.posted_by, NEW.device_id, NEW.app_version, 'journal.posted', NEW.posted_at,
             jsonb_build_object('journal_date', NEW.journal_date, 'period_id', NEW.period_id,
                                'reversal_of_id', NEW.reversal_of_id));
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER journal_entries_record_posting
    AFTER INSERT OR UPDATE ON journal_entries
    FOR EACH ROW EXECUTE FUNCTION btp_record_journal_posting();

CREATE OR REPLACE FUNCTION btp_validate_posted_journal_balance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    journal_id varchar(100);
    journal_status varchar(16);
    reversal_id varchar(100);
    line_count bigint;
    total_debit numeric;
    total_credit numeric;
    original_status varchar(16);
BEGIN
    IF TG_TABLE_NAME = 'journal_entries' THEN
        journal_id := NEW.id;
    ELSIF TG_OP = 'DELETE' THEN
        journal_id := OLD.journal_entry_id;
    ELSE
        journal_id := NEW.journal_entry_id;
    END IF;

    SELECT status, reversal_of_id INTO journal_status, reversal_id
    FROM journal_entries WHERE id = journal_id;

    IF NOT FOUND OR journal_status <> 'posted' THEN
        RETURN NULL;
    END IF;

    SELECT count(*), COALESCE(sum(debit), 0), COALESCE(sum(credit), 0)
        INTO line_count, total_debit, total_credit
    FROM journal_lines WHERE journal_entry_id = journal_id;

    IF line_count < 2 OR total_debit <> total_credit THEN
        RAISE EXCEPTION 'posted journal % must contain at least two lines and satisfy debit = credit', journal_id
            USING ERRCODE = '23514';
    END IF;

    IF reversal_id IS NOT NULL THEN
        SELECT status INTO original_status FROM journal_entries WHERE id = reversal_id;
        IF original_status IS DISTINCT FROM 'posted' THEN
            RAISE EXCEPTION 'a reversal must reference an existing posted journal'
                USING ERRCODE = '23514';
        END IF;

        IF EXISTS (
            SELECT 1
            FROM (
                SELECT account_code, sum(debit) AS debit, sum(credit) AS credit
                FROM journal_lines WHERE journal_entry_id = journal_id GROUP BY account_code
            ) reversal_lines
            FULL OUTER JOIN (
                SELECT account_code, sum(debit) AS debit, sum(credit) AS credit
                FROM journal_lines WHERE journal_entry_id = reversal_id GROUP BY account_code
            ) original_lines USING (account_code)
            WHERE COALESCE(reversal_lines.debit, 0) <> COALESCE(original_lines.credit, 0)
               OR COALESCE(reversal_lines.credit, 0) <> COALESCE(original_lines.debit, 0)
        ) THEN
            RAISE EXCEPTION 'reversal journal must exactly reverse the original account totals'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER journal_entries_balance_check
    AFTER INSERT OR UPDATE ON journal_entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION btp_validate_posted_journal_balance();

CREATE CONSTRAINT TRIGGER journal_lines_balance_check
    AFTER INSERT OR UPDATE OR DELETE ON journal_lines
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION btp_validate_posted_journal_balance();
SQL);
    }

    public function down(): void
    {
        $connection = DB::connection('tenant');
        if ($connection->table('journal_entries')->exists()
            || $connection->table('accounting_events')->exists()
            || $connection->table('accounting_periods')->exists()) {
            throw new RuntimeException(
                'Refusing to remove accounting integrity objects after journal/period data exists. Restore via a separately reviewed forward plan.'
            );
        }

        $connection->unprepared(<<<'SQL'
DROP TRIGGER IF EXISTS journal_lines_balance_check ON journal_lines;
DROP TRIGGER IF EXISTS journal_entries_balance_check ON journal_entries;
DROP TRIGGER IF EXISTS journal_entries_record_posting ON journal_entries;
DROP TRIGGER IF EXISTS accounting_periods_guard ON accounting_periods;
DROP TRIGGER IF EXISTS coa_accounts_locked ON coa_accounts;
DROP TRIGGER IF EXISTS accounting_events_append_only ON accounting_events;
DROP TRIGGER IF EXISTS accounting_events_reject_truncate ON accounting_events;
DROP TRIGGER IF EXISTS accounting_periods_reject_truncate ON accounting_periods;
DROP TRIGGER IF EXISTS coa_accounts_reject_truncate ON coa_accounts;
DROP TRIGGER IF EXISTS journal_lines_reject_truncate ON journal_lines;
DROP TRIGGER IF EXISTS journal_entries_reject_truncate ON journal_entries;
DROP TRIGGER IF EXISTS journal_lines_guard_posted ON journal_lines;
DROP TRIGGER IF EXISTS journal_entries_guard_posted ON journal_entries;

DROP FUNCTION IF EXISTS btp_validate_posted_journal_balance();
DROP FUNCTION IF EXISTS btp_record_journal_posting();
DROP FUNCTION IF EXISTS btp_guard_accounting_period();
DROP FUNCTION IF EXISTS btp_reject_coa_mutation();
DROP FUNCTION IF EXISTS btp_reject_accounting_audit_mutation();
DROP FUNCTION IF EXISTS btp_reject_accounting_truncate();
DROP FUNCTION IF EXISTS btp_guard_journal_line_mutation();
DROP FUNCTION IF EXISTS btp_guard_posted_journal();

ALTER TABLE journal_lines
    DROP CONSTRAINT IF EXISTS journal_lines_one_sided_whole_rupiah_check,
    DROP CONSTRAINT IF EXISTS journal_lines_account_code_fk,
    DROP CONSTRAINT IF EXISTS journal_lines_journal_entry_id_fk;
ALTER TABLE journal_entries
    DROP CONSTRAINT IF EXISTS journal_entries_not_self_reversal_check,
    DROP CONSTRAINT IF EXISTS journal_entries_posted_metadata_check,
    DROP CONSTRAINT IF EXISTS journal_entries_status_check,
    DROP CONSTRAINT IF EXISTS journal_entries_period_id_fk,
    DROP CONSTRAINT IF EXISTS journal_entries_reversal_of_id_fk;
ALTER TABLE inventory_movements DROP CONSTRAINT IF EXISTS inventory_movements_quantity_nonzero_check;
ALTER TABLE sale_items
    DROP CONSTRAINT IF EXISTS sale_items_money_whole_rupiah_check,
    DROP CONSTRAINT IF EXISTS sale_items_quantity_positive_check,
    DROP CONSTRAINT IF EXISTS sale_items_product_id_fk,
    DROP CONSTRAINT IF EXISTS sale_items_sale_id_fk;
ALTER TABLE sales DROP CONSTRAINT IF EXISTS sales_money_whole_rupiah_check;
ALTER TABLE inventory_lots
    DROP CONSTRAINT IF EXISTS inventory_lots_unit_cost_whole_rupiah_check,
    DROP CONSTRAINT IF EXISTS inventory_lots_quantity_bounds_check,
    DROP CONSTRAINT IF EXISTS inventory_lots_product_id_fk;
ALTER TABLE products DROP CONSTRAINT IF EXISTS products_price_whole_rupiah_nonnegative_check;
DROP INDEX IF EXISTS journal_entries_single_reversal_idx;

DROP TABLE IF EXISTS accounting_events;
DROP TABLE IF EXISTS accounting_periods;
DROP TABLE IF EXISTS coa_accounts;

ALTER TABLE journal_entries
    DROP COLUMN IF EXISTS reversal_of_id,
    DROP COLUMN IF EXISTS period_id,
    DROP COLUMN IF EXISTS app_version,
    DROP COLUMN IF EXISTS device_id,
    DROP COLUMN IF EXISTS posted_by,
    DROP COLUMN IF EXISTS posted_at,
    DROP COLUMN IF EXISTS status;
SQL);
    }
};
