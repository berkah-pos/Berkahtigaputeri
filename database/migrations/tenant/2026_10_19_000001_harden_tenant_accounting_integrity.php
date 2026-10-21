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
        $db = DB::connection('tenant');

        if ($db->getDriverName() !== 'pgsql') {
            throw new RuntimeException('Accounting integrity requires PostgreSQL 17; wrong database driver.');
        }

        // Fail before any DDL if prior business transactions need an explicit,
        // reconciled migration. Never retrofit triggers and then silently accept
        // history whose posted/stock/event state cannot be proven.
        foreach (['sales', 'sale_items', 'inventory_movements', 'journal_entries', 'journal_lines', 'sync_receipts'] as $table) {
            if ($db->table($table)->exists()) {
                throw new RuntimeException("Migration stopped: existing {$table} records require a separate owner-approved offline reconciliation and migration plan.");
            }
        }

        if ($db->table('inventory_lots')->whereRaw('quantity_remaining <> quantity_received')->exists()) {
            throw new RuntimeException('Migration stopped: existing lot balances differ from received quantities and cannot be reconciled without source movement history.');
        }

        if (Schema::connection('tenant')->hasTable('inventory_cost_layers')
            && $db->table('inventory_cost_layers')->exists()) {
            throw new RuntimeException('Migration stopped: existing cost layers require an explicit migration and reconciliation plan.');
        }

        foreach ([
            ['products', 'price'],
            ['inventory_lots', 'unit_cost'],
            ['sales', 'subtotal'],
            ['sales', 'tax_amount'],
            ['sales', 'total_amount'],
            ['sale_items', 'unit_price'],
            ['sale_items', 'line_total'],
            ['sale_items', 'unit_cost'],
            ['journal_lines', 'debit'],
            ['journal_lines', 'credit'],
        ] as [$table, $column]) {
            $fractional = $db->table($table)
                ->whereRaw("\"{$column}\" <> trunc(\"{$column}\")")
                ->exists();
            if ($fractional) {
                throw new RuntimeException("Migration stopped: {$table}.{$column} contains fractional Rupiah. Reconcile the owner-controlled offline data before migration.");
            }
        }

        Schema::connection('tenant')->create('chart_of_accounts', function (Blueprint $table): void {
            $table->string('account_code', 50)->primary();
            $table->string('name_id', 160);
            $table->string('account_type', 20);
            $table->boolean('is_locked')->default(true);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        $now = now('UTC')->format('Y-m-d H:i:s');
        $accounts = [
            ['1-1010', 'Kas Tunai', 'asset'],
            ['1-1020', 'QRIS Clearing', 'asset'],
            ['1-1030', 'Bank Transfer', 'asset'],
            ['1-1040', 'Persediaan Barang', 'asset'],
            ['1-1050', 'Piutang Usaha', 'asset'],
            ['1-1060', 'Peralatan Toko', 'asset'],
            ['1-1070', 'Akumulasi Penyusutan Peralatan', 'asset'],
            ['2-2010', 'Utang PPN 11%', 'liability'],
            ['2-2020', 'Utang Supplier', 'liability'],
            ['2-2030', 'Utang Gaji', 'liability'],
            ['3-3010', 'Modal Pemilik', 'equity'],
            ['3-3020', 'Laba Ditahan', 'equity'],
            ['3-3030', 'Prive', 'equity'],
            ['4-4010', 'Penjualan', 'revenue'],
            ['4-4020', 'Diskon Penjualan', 'revenue'],
            ['4-4030', 'Retur Penjualan', 'revenue'],
            ['4-4040', 'Selisih Kas Lebih', 'revenue'],
            ['5-5010', 'Harga Pokok Penjualan', 'cogs'],
            ['6-6010', 'Beban Gaji', 'expense'],
            ['6-6020', 'Beban Selisih Kas Kurang', 'expense'],
            ['6-6030', 'Beban Operasional Toko', 'expense'],
            ['6-6040', 'Beban Sewa', 'expense'],
            ['6-6050', 'Beban Listrik dan Air', 'expense'],
            ['6-6060', 'Beban Penyusutan', 'expense'],
        ];

        foreach ($accounts as [$code, $name, $type]) {
            $db->table('chart_of_accounts')->insert([
                'account_code' => $code,
                'name_id' => $name,
                'account_type' => $type,
                'is_locked' => true,
                'is_active' => true,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }

        $unknownCodes = $db->table('journal_lines')
            ->whereNotIn('account_code', array_column($accounts, 0))
            ->exists();
        if ($unknownCodes) {
            throw new RuntimeException('Migration stopped: historical journal lines reference an account outside the locked COA.');
        }

        // All authoritative currency values in this backend are whole Indonesian Rupiah.
        foreach ([
            'ALTER TABLE products ALTER COLUMN price TYPE BIGINT USING price::BIGINT',
            'ALTER TABLE inventory_lots ALTER COLUMN unit_cost TYPE BIGINT USING unit_cost::BIGINT',
            'ALTER TABLE sales ALTER COLUMN subtotal TYPE BIGINT USING subtotal::BIGINT',
            'ALTER TABLE sales ALTER COLUMN tax_amount TYPE BIGINT USING tax_amount::BIGINT',
            'ALTER TABLE sales ALTER COLUMN total_amount TYPE BIGINT USING total_amount::BIGINT',
            'ALTER TABLE sale_items ALTER COLUMN unit_price TYPE BIGINT USING unit_price::BIGINT',
            'ALTER TABLE sale_items ALTER COLUMN line_total TYPE BIGINT USING line_total::BIGINT',
            'ALTER TABLE sale_items ALTER COLUMN unit_cost TYPE BIGINT USING unit_cost::BIGINT',
            'ALTER TABLE journal_lines ALTER COLUMN debit TYPE BIGINT USING debit::BIGINT',
            'ALTER TABLE journal_lines ALTER COLUMN credit TYPE BIGINT USING credit::BIGINT',
        ] as $statement) {
            $db->unprepared($statement);
        }

        Schema::connection('tenant')->table('products', function (Blueprint $table): void {
            $table->boolean('track_expiry')->default(false);
            $table->unsignedSmallInteger('min_shelf_life_days')->default(0);
            $table->char('currency_code', 3)->default('IDR');
        });

        Schema::connection('tenant')->table('sales', function (Blueprint $table): void {
            $table->char('currency_code', 3)->default('IDR');
            $table->timestampTz('occurred_at_utc')->nullable();
            $table->date('business_date')->nullable();
            $table->char('request_fingerprint', 64)->nullable();
        });

        $db->unprepared(<<<'SQL'
            UPDATE sales
            SET occurred_at_utc = occurred_at AT TIME ZONE 'UTC',
                business_date = (occurred_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Jakarta')::date
            WHERE occurred_at_utc IS NULL OR business_date IS NULL
        SQL);

        Schema::connection('tenant')->table('sale_items', function (Blueprint $table): void {
            $table->bigInteger('cogs_amount')->default(0);
            $table->unsignedInteger('line_no')->default(0);
        });
        $db->unprepared('ALTER TABLE sale_items ALTER COLUMN unit_cost DROP NOT NULL');
        $db->unprepared(<<<'SQL'
            WITH ranked AS (
              SELECT id, row_number() OVER (PARTITION BY sale_id ORDER BY id) - 1 AS n
              FROM sale_items
            )
            UPDATE sale_items AS si SET line_no = ranked.n FROM ranked WHERE ranked.id = si.id
        SQL);

        Schema::connection('tenant')->table('inventory_movements', function (Blueprint $table): void {
            $table->string('movement_key', 220)->nullable();
            $table->string('lot_id', 100)->nullable();
        });

        Schema::connection('tenant')->table('journal_lines', function (Blueprint $table): void {
            $table->unsignedInteger('line_no')->default(0);
        });

        Schema::connection('tenant')->table('journal_entries', function (Blueprint $table): void {
            $table->string('status', 12)->default('draft');
            $table->string('entry_type', 16)->default('manual');
            $table->char('currency_code', 3)->default('IDR');
            $table->timestampTz('posted_at')->nullable();
            $table->string('actor_reference', 150)->nullable();
            $table->string('device_id', 150)->nullable();
            $table->string('app_version', 80)->nullable();
            $table->string('transaction_reference', 150)->nullable();
            $table->string('idempotency_key', 150)->nullable();
            $table->char('payload_sha256', 64)->nullable();
            $table->string('reversal_of_entry_id', 100)->nullable();
        });

        Schema::connection('tenant')->create('accounting_periods', function (Blueprint $table): void {
            $table->date('period_month')->primary();
            $table->string('status', 8)->default('open');
            $table->timestampTz('closed_at')->nullable();
            $table->string('closed_by', 150)->nullable();
            $table->timestamps();
        });

        Schema::connection('tenant')->create('accounting_events', function (Blueprint $table): void {
            $table->string('id', 180)->primary();
            $table->string('journal_entry_id', 100)->unique();
            $table->string('event_type', 40);
            $table->string('actor_reference', 150);
            $table->timestampTz('occurred_at');
            $table->string('device_id', 150);
            $table->string('app_version', 80);
            $table->string('transaction_reference', 150);
            $table->string('idempotency_key', 150)->unique();
            $table->jsonb('context');
            $table->timestampTz('created_at')->useCurrent();
            $table->foreign('journal_entry_id', 'accounting_events_journal_fk')
                ->references('id')->on('journal_entries');
        });

        Schema::connection('tenant')->create('inventory_cost_layers', function (Blueprint $table): void {
            $table->string('id', 150)->primary();
            $table->string('product_id', 100);
            $table->string('lot_id', 100);
            $table->string('source_event_id', 100)->nullable();
            $table->decimal('quantity_received', 18, 3);
            $table->decimal('quantity_remaining', 18, 3);
            $table->bigInteger('unit_cost');
            $table->timestampTz('acquired_at');
            $table->timestamps();
            $table->foreign('product_id', 'cost_layers_product_fk')->references('id')->on('products');
            $table->foreign('lot_id', 'cost_layers_lot_fk')->references('id')->on('inventory_lots');
            $table->index(['product_id', 'acquired_at', 'id'], 'cost_layers_fifo_idx');
        });

        // Preserve reconciled opening lots by creating matching FIFO layers.
        // The preflight above guarantees no historical movement/sale requires
        // interpretation; changed lot balances were rejected.
        $db->unprepared(<<<'SQL'
            INSERT INTO inventory_cost_layers (
                id, product_id, lot_id, source_event_id, quantity_received,
                quantity_remaining, unit_cost, acquired_at, created_at, updated_at
            )
            SELECT
                'opening:' || id, product_id, id, NULL, quantity_received,
                quantity_remaining, unit_cost, received_at AT TIME ZONE 'UTC',
                now(), now()
            FROM inventory_lots
        SQL);

        Schema::connection('tenant')->create('sale_lot_allocations', function (Blueprint $table): void {
            $table->bigInteger('sale_item_id');
            $table->unsignedInteger('allocation_no');
            $table->string('lot_id', 100);
            $table->decimal('quantity', 18, 3);
            $table->primary(['sale_item_id', 'allocation_no']);
            $table->foreign('sale_item_id', 'sale_lot_allocations_item_fk')->references('id')->on('sale_items');
            $table->foreign('lot_id', 'sale_lot_allocations_lot_fk')->references('id')->on('inventory_lots');
        });

        Schema::connection('tenant')->create('cost_layer_consumptions', function (Blueprint $table): void {
            $table->bigInteger('sale_item_id');
            $table->unsignedInteger('consumption_no');
            $table->string('cost_layer_id', 150);
            $table->decimal('quantity', 18, 3);
            $table->bigInteger('unit_cost');
            $table->bigInteger('total_cost');
            $table->primary(['sale_item_id', 'consumption_no']);
            $table->foreign('sale_item_id', 'cost_consumptions_item_fk')->references('id')->on('sale_items');
            $table->foreign('cost_layer_id', 'cost_consumptions_layer_fk')->references('id')->on('inventory_cost_layers');
        });

        $db->unprepared(<<<'SQL'
            ALTER TABLE products
              ADD CONSTRAINT products_price_nonnegative CHECK (price >= 0),
              ADD CONSTRAINT products_currency_idr CHECK (currency_code = 'IDR'),
              ADD CONSTRAINT products_shelf_life_nonnegative CHECK (min_shelf_life_days >= 0);
            ALTER TABLE sales
              ADD CONSTRAINT sales_money_nonnegative CHECK (subtotal >= 0 AND tax_amount >= 0 AND total_amount >= 0),
              ADD CONSTRAINT sales_total_matches CHECK (total_amount = subtotal + tax_amount),
              ADD CONSTRAINT sales_currency_idr CHECK (currency_code = 'IDR');
            ALTER TABLE journal_entries
              ADD CONSTRAINT journal_status_valid CHECK (status IN ('draft', 'posted')),
              ADD CONSTRAINT journal_type_valid CHECK (entry_type IN ('manual', 'adjustment', 'sale', 'reversal')),
              ADD CONSTRAINT journal_currency_idr CHECK (currency_code = 'IDR'),
              ADD CONSTRAINT journal_reversal_not_self CHECK (reversal_of_entry_id IS NULL OR reversal_of_entry_id <> id);
            ALTER TABLE journal_lines
              ADD CONSTRAINT journal_line_amounts_valid CHECK (debit >= 0 AND credit >= 0 AND ((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0)));
            ALTER TABLE inventory_lots
              ADD CONSTRAINT inventory_lot_quantities_valid CHECK (quantity_received > 0 AND quantity_remaining >= 0 AND quantity_remaining <= quantity_received),
              ADD CONSTRAINT inventory_lot_cost_nonnegative CHECK (unit_cost >= 0);
            ALTER TABLE inventory_cost_layers
              ADD CONSTRAINT cost_layer_quantities_valid CHECK (quantity_received > 0 AND quantity_remaining >= 0 AND quantity_remaining <= quantity_received),
              ADD CONSTRAINT cost_layer_unit_cost_nonnegative CHECK (unit_cost >= 0);
            ALTER TABLE sale_items
              ADD CONSTRAINT sale_item_money_nonnegative CHECK (unit_price >= 0 AND line_total >= 0 AND cogs_amount >= 0),
              ADD CONSTRAINT sale_item_quantity_positive_integer CHECK (quantity > 0 AND quantity = trunc(quantity)),
              ADD CONSTRAINT sale_item_line_total_integrity CHECK (line_total = unit_price * quantity);
            ALTER TABLE sale_lot_allocations
              ADD CONSTRAINT sale_lot_allocation_quantity_valid CHECK (quantity > 0 AND quantity = trunc(quantity));
            ALTER TABLE cost_layer_consumptions
              ADD CONSTRAINT cost_consumption_values_valid CHECK (quantity > 0 AND quantity = trunc(quantity) AND unit_cost >= 0 AND total_cost = quantity * unit_cost);
            ALTER TABLE inventory_movements
              ADD CONSTRAINT sale_out_movement_valid CHECK (
                movement_type <> 'sale_out'
                OR (source_event_id IS NOT NULL AND movement_key IS NOT NULL AND lot_id IS NOT NULL AND quantity < 0 AND quantity = trunc(quantity))
              );
            ALTER TABLE accounting_periods
              ADD CONSTRAINT period_month_is_first CHECK (period_month = date_trunc('month', period_month)::date),
              ADD CONSTRAINT period_status_valid CHECK (status IN ('open', 'closed')),
              ADD CONSTRAINT period_closed_metadata CHECK ((status = 'open' AND closed_at IS NULL AND closed_by IS NULL) OR (status = 'closed' AND closed_at IS NOT NULL AND closed_by IS NOT NULL));
            ALTER TABLE journal_entries
              ADD CONSTRAINT journal_reversal_fk FOREIGN KEY (reversal_of_entry_id) REFERENCES journal_entries(id);
            ALTER TABLE journal_lines
              ADD CONSTRAINT journal_lines_entry_fk FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id),
              ADD CONSTRAINT journal_lines_account_fk FOREIGN KEY (account_code) REFERENCES chart_of_accounts(account_code),
              ADD CONSTRAINT journal_lines_entry_line_unique UNIQUE (journal_entry_id, line_no);
            ALTER TABLE inventory_lots
              ADD CONSTRAINT inventory_lot_product_fk FOREIGN KEY (product_id) REFERENCES products(id);
            ALTER TABLE sale_items
              ADD CONSTRAINT sale_item_sale_fk FOREIGN KEY (sale_id) REFERENCES sales(id),
              ADD CONSTRAINT sale_item_product_fk FOREIGN KEY (product_id) REFERENCES products(id);
            ALTER TABLE inventory_movements
              ADD CONSTRAINT inventory_movement_product_fk FOREIGN KEY (product_id) REFERENCES products(id),
              ADD CONSTRAINT inventory_movement_lot_fk FOREIGN KEY (lot_id) REFERENCES inventory_lots(id),
              ADD CONSTRAINT inventory_movement_key_unique UNIQUE (movement_key);
            CREATE UNIQUE INDEX journal_entry_one_full_reversal_idx ON journal_entries(reversal_of_entry_id) WHERE reversal_of_entry_id IS NOT NULL;
            CREATE UNIQUE INDEX sale_items_sale_line_unique_idx ON sale_items(sale_id, line_no);
            CREATE INDEX inventory_movement_event_idx ON inventory_movements(source_event_id);
            CREATE INDEX accounting_period_status_idx ON accounting_periods(status, period_month);
        SQL);

        $db->statement(
            "INSERT INTO accounting_periods (period_month, status, created_at, updated_at) VALUES (date_trunc('month', CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Jakarta')::date, 'open', now(), now()) ON CONFLICT (period_month) DO NOTHING"
        );

        $this->installTriggers($db);
    }

    private function installTriggers($db): void
    {
        $statements = [
            <<<'SQL'
            CREATE OR REPLACE FUNCTION btp_guard_locked_coa() RETURNS trigger AS $$
            DECLARE owner_name text;
            BEGIN
              SELECT pg_get_userbyid(datdba) INTO owner_name FROM pg_database WHERE datname = current_database();
              IF current_user <> owner_name THEN
                RAISE EXCEPTION 'Chart of Accounts is locked; use a reviewed database-owner migration';
              END IF;
              IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
              RETURN NEW;
            END;
            $$ LANGUAGE plpgsql
            SQL,
            "CREATE TRIGGER btp_locked_coa_guard BEFORE INSERT OR UPDATE OR DELETE ON chart_of_accounts FOR EACH ROW EXECUTE FUNCTION btp_guard_locked_coa()",
            <<<'SQL'
            CREATE OR REPLACE FUNCTION btp_guard_period_close() RETURNS trigger AS $$
            DECLARE owner_name text;
            BEGIN
              SELECT pg_get_userbyid(datdba) INTO owner_name FROM pg_database WHERE datname = current_database();
              IF current_user <> owner_name THEN RAISE EXCEPTION 'Only the database owner may administer accounting periods'; END IF;
              IF TG_OP = 'DELETE' THEN
                IF OLD.status = 'closed' THEN RAISE EXCEPTION 'Closed accounting period is immutable'; END IF;
                RETURN OLD;
              END IF;
              IF TG_OP = 'INSERT' THEN
                IF NEW.status NOT IN ('open', 'closed') THEN RAISE EXCEPTION 'Invalid accounting period status'; END IF;
                IF NEW.status = 'closed' AND (NEW.closed_at IS NULL OR COALESCE(NULLIF(NEW.closed_by, ''), '') = '') THEN
                  RAISE EXCEPTION 'Closing a period requires closed_at and closed_by';
                END IF;
                RETURN NEW;
              END IF;
              IF OLD.status = 'closed' THEN RAISE EXCEPTION 'Closed accounting period is immutable'; END IF;
              IF NEW.status NOT IN ('open', 'closed') THEN RAISE EXCEPTION 'Invalid accounting period status'; END IF;
              IF NEW.status = 'closed' AND (NEW.closed_at IS NULL OR COALESCE(NULLIF(NEW.closed_by, ''), '') = '') THEN
                RAISE EXCEPTION 'Closing a period requires closed_at and closed_by';
              END IF;
              RETURN NEW;
            END;
            $$ LANGUAGE plpgsql
            SQL,
            "CREATE TRIGGER btp_period_close_guard BEFORE INSERT OR UPDATE OR DELETE ON accounting_periods FOR EACH ROW EXECUTE FUNCTION btp_guard_period_close()",
            <<<'SQL'
            CREATE OR REPLACE FUNCTION btp_guard_journal_header() RETURNS trigger AS $$
            DECLARE period_status text;
            BEGIN
              IF TG_OP = 'INSERT' THEN
                IF NEW.status <> 'draft' THEN RAISE EXCEPTION 'Journal must be inserted as draft before posting'; END IF;
                SELECT status INTO period_status FROM accounting_periods
                  WHERE period_month = date_trunc('month', NEW.journal_date)::date FOR UPDATE;
                IF NOT FOUND OR period_status <> 'open' THEN RAISE EXCEPTION 'Journal date is outside an open accounting period'; END IF;
                RETURN NEW;
              END IF;
              IF TG_OP = 'DELETE' THEN
                IF OLD.status = 'posted' THEN RAISE EXCEPTION 'Posted journal is immutable; use a reversing entry'; END IF;
                RETURN OLD;
              END IF;
              IF OLD.status = 'posted' THEN RAISE EXCEPTION 'Posted journal is immutable; use a reversing entry'; END IF;
              SELECT status INTO period_status FROM accounting_periods
                WHERE period_month = date_trunc('month', NEW.journal_date)::date FOR UPDATE;
              IF NOT FOUND OR period_status <> 'open' THEN RAISE EXCEPTION 'Closed or missing period cannot be changed or posted'; END IF;
              IF NEW.status = 'posted' THEN
                IF COALESCE(NULLIF(NEW.actor_reference, ''), '') = ''
                   OR COALESCE(NULLIF(NEW.device_id, ''), '') = ''
                   OR COALESCE(NULLIF(NEW.app_version, ''), '') = ''
                   OR COALESCE(NULLIF(NEW.transaction_reference, ''), '') = ''
                   OR COALESCE(NULLIF(NEW.idempotency_key, ''), '') = '' THEN
                  RAISE EXCEPTION 'Posting requires actor, device, app version, transaction reference and idempotency key';
                END IF;
                IF NEW.entry_type = 'sale' AND (NEW.source_event_id IS NULL OR NEW.reversal_of_entry_id IS NOT NULL OR NEW.payload_sha256 IS NULL OR length(NEW.payload_sha256) <> 64) THEN
                  RAISE EXCEPTION 'Sale journal requires source_event_id, canonical payload hash and cannot be a reversal';
                END IF;
                IF NEW.entry_type = 'reversal' AND NEW.reversal_of_entry_id IS NULL THEN
                  RAISE EXCEPTION 'Reversal journal requires reversal_of_entry_id';
                END IF;
                IF NEW.entry_type <> 'reversal' AND NEW.reversal_of_entry_id IS NOT NULL THEN
                  RAISE EXCEPTION 'Only reversal journals may reference an original entry';
                END IF;
                NEW.posted_at := COALESCE(NEW.posted_at, now());
              END IF;
              RETURN NEW;
            END;
            $$ LANGUAGE plpgsql
            SQL,
            "CREATE TRIGGER btp_journal_header_guard BEFORE INSERT OR UPDATE OR DELETE ON journal_entries FOR EACH ROW EXECUTE FUNCTION btp_guard_journal_header()",
            <<<'SQL'
            CREATE OR REPLACE FUNCTION btp_guard_journal_line() RETURNS trigger AS $$
            DECLARE target_id text; parent_status text; journal_day date; period_status text;
            BEGIN
              IF TG_OP = 'DELETE' THEN target_id := OLD.journal_entry_id;
              ELSE target_id := NEW.journal_entry_id; END IF;
              IF TG_OP = 'UPDATE' AND OLD.journal_entry_id <> NEW.journal_entry_id THEN
                SELECT status, journal_date INTO parent_status, journal_day FROM journal_entries WHERE id = OLD.journal_entry_id;
                IF parent_status = 'posted' THEN RAISE EXCEPTION 'Posted journal lines are immutable'; END IF;
              END IF;
              SELECT status, journal_date INTO parent_status, journal_day FROM journal_entries WHERE id = target_id FOR UPDATE;
              IF parent_status = 'posted' THEN RAISE EXCEPTION 'Posted journal lines are immutable'; END IF;
              IF journal_day IS NOT NULL THEN
                SELECT status INTO period_status FROM accounting_periods
                  WHERE period_month = date_trunc('month', journal_day)::date;
                IF NOT FOUND OR period_status <> 'open' THEN RAISE EXCEPTION 'Journal lines in a closed or missing period are immutable'; END IF;
              END IF;
              IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
              RETURN NEW;
            END;
            $$ LANGUAGE plpgsql
            SQL,
            "CREATE TRIGGER btp_journal_line_guard BEFORE INSERT OR UPDATE OR DELETE ON journal_lines FOR EACH ROW EXECUTE FUNCTION btp_guard_journal_line()",
            <<<'SQL'
            CREATE OR REPLACE FUNCTION btp_guard_inventory_quantity() RETURNS trigger AS $$
            DECLARE product_exists boolean;
            BEGIN
              IF TG_OP = 'UPDATE' AND NEW.product_id <> OLD.product_id THEN
                RAISE EXCEPTION 'Inventory item ownership cannot change';
              END IF;
              PERFORM 1 FROM products WHERE id = NEW.product_id FOR UPDATE;
              IF NOT FOUND THEN RAISE EXCEPTION 'Inventory references an unknown product'; END IF;
              IF NEW.quantity_received <= 0 OR NEW.quantity_remaining < 0 OR NEW.quantity_remaining > NEW.quantity_received THEN
                RAISE EXCEPTION 'Inventory quantity invariant violated';
              END IF;
              RETURN NEW;
            END;
            $$ LANGUAGE plpgsql
            SQL,
            "CREATE TRIGGER btp_inventory_quantity_guard BEFORE INSERT OR UPDATE ON inventory_lots FOR EACH ROW EXECUTE FUNCTION btp_guard_inventory_quantity()",
            <<<'SQL'
            CREATE OR REPLACE FUNCTION btp_guard_cost_layer_quantity() RETURNS trigger AS $$
            DECLARE lot_product text;
            BEGIN
              IF TG_OP = 'UPDATE' AND (NEW.product_id <> OLD.product_id OR NEW.lot_id <> OLD.lot_id) THEN
                RAISE EXCEPTION 'Cost layer identity cannot change';
              END IF;
              PERFORM 1 FROM products WHERE id = NEW.product_id FOR UPDATE;
              IF NOT FOUND THEN RAISE EXCEPTION 'Cost layer references an unknown product'; END IF;
              SELECT product_id INTO lot_product FROM inventory_lots WHERE id = NEW.lot_id FOR UPDATE;
              IF NOT FOUND OR lot_product <> NEW.product_id THEN
                RAISE EXCEPTION 'Cost layer lot must belong to the same product';
              END IF;
              IF NEW.quantity_received <= 0 OR NEW.quantity_remaining < 0 OR NEW.quantity_remaining > NEW.quantity_received OR NEW.unit_cost < 0 THEN
                RAISE EXCEPTION 'Cost layer invariant violated';
              END IF;
              RETURN NEW;
            END;
            $$ LANGUAGE plpgsql
            SQL,
            "CREATE TRIGGER btp_cost_layer_quantity_guard BEFORE INSERT OR UPDATE ON inventory_cost_layers FOR EACH ROW EXECUTE FUNCTION btp_guard_cost_layer_quantity()",

            <<<'SQL'
            CREATE OR REPLACE FUNCTION btp_guard_inventory_movement() RETURNS trigger AS $btpm$
            DECLARE lot_product text;
            BEGIN
              IF NEW.lot_id IS NOT NULL THEN
                SELECT product_id INTO lot_product FROM inventory_lots WHERE id = NEW.lot_id FOR UPDATE;
                IF NOT FOUND OR lot_product <> NEW.product_id THEN
                  RAISE EXCEPTION 'Inventory movement lot must belong to the same product';
                END IF;
              END IF;
              IF NEW.movement_type = 'sale_out' THEN
                IF NEW.source_event_id IS NULL OR NEW.movement_key IS NULL OR NEW.lot_id IS NULL
                   OR NEW.quantity >= 0 OR NEW.quantity <> trunc(NEW.quantity) THEN
                  RAISE EXCEPTION 'Sale-out movement requires an event, unique key, lot and negative whole-unit quantity';
                END IF;
              END IF;
              RETURN NEW;
            END;
            $btpm$ LANGUAGE plpgsql
            SQL,
            "CREATE TRIGGER btp_inventory_movement_guard BEFORE INSERT OR UPDATE ON inventory_movements FOR EACH ROW EXECUTE FUNCTION btp_guard_inventory_movement()",
            <<<'SQL'
            CREATE OR REPLACE FUNCTION btp_guard_sale_lot_allocation() RETURNS trigger AS $btpa$
            DECLARE expected_product text; lot_product text;
            BEGIN
              SELECT product_id INTO expected_product FROM sale_items WHERE id = NEW.sale_item_id FOR UPDATE;
              IF NOT FOUND THEN RAISE EXCEPTION 'Lot allocation references an unknown sale item'; END IF;
              SELECT product_id INTO lot_product FROM inventory_lots WHERE id = NEW.lot_id FOR UPDATE;
              IF NOT FOUND OR lot_product <> expected_product THEN
                RAISE EXCEPTION 'FEFO allocation lot must belong to the sale item product';
              END IF;
              IF NEW.quantity <= 0 OR NEW.quantity <> trunc(NEW.quantity) THEN
                RAISE EXCEPTION 'FEFO allocation requires a positive whole-unit quantity';
              END IF;
              RETURN NEW;
            END;
            $btpa$ LANGUAGE plpgsql
            SQL,
            "CREATE TRIGGER btp_sale_lot_allocation_guard BEFORE INSERT OR UPDATE ON sale_lot_allocations FOR EACH ROW EXECUTE FUNCTION btp_guard_sale_lot_allocation()",
            <<<'SQL'
            CREATE OR REPLACE FUNCTION btp_guard_cost_layer_consumption() RETURNS trigger AS $btpc$
            DECLARE expected_product text; layer_product text;
            BEGIN
              SELECT product_id INTO expected_product FROM sale_items WHERE id = NEW.sale_item_id FOR UPDATE;
              IF NOT FOUND THEN RAISE EXCEPTION 'FIFO consumption references an unknown sale item'; END IF;
              SELECT product_id INTO layer_product FROM inventory_cost_layers WHERE id = NEW.cost_layer_id FOR UPDATE;
              IF NOT FOUND OR layer_product <> expected_product THEN
                RAISE EXCEPTION 'FIFO cost layer must belong to the sale item product';
              END IF;
              IF NEW.quantity <= 0 OR NEW.quantity <> trunc(NEW.quantity)
                 OR NEW.unit_cost < 0 OR NEW.total_cost <> NEW.quantity * NEW.unit_cost THEN
                RAISE EXCEPTION 'FIFO consumption values are invalid';
              END IF;
              RETURN NEW;
            END;
            $btpc$ LANGUAGE plpgsql
            SQL,
            "CREATE TRIGGER btp_cost_layer_consumption_guard BEFORE INSERT OR UPDATE ON cost_layer_consumptions FOR EACH ROW EXECUTE FUNCTION btp_guard_cost_layer_consumption()",
            <<<'SQL'
            CREATE OR REPLACE FUNCTION btp_prevent_posted_mutation() RETURNS trigger AS $$
            BEGIN
              RAISE EXCEPTION '% records are append-only; use a compensating entry', TG_TABLE_NAME;
            END;
            $$ LANGUAGE plpgsql
            SQL,
            "CREATE TRIGGER btp_sales_immutable BEFORE UPDATE OR DELETE ON sales FOR EACH ROW EXECUTE FUNCTION btp_prevent_posted_mutation()",
            "CREATE TRIGGER btp_sale_items_immutable BEFORE UPDATE OR DELETE ON sale_items FOR EACH ROW EXECUTE FUNCTION btp_prevent_posted_mutation()",
            "CREATE TRIGGER btp_inventory_movements_immutable BEFORE UPDATE OR DELETE ON inventory_movements FOR EACH ROW EXECUTE FUNCTION btp_prevent_posted_mutation()",
            "CREATE TRIGGER btp_sale_lot_allocations_immutable BEFORE UPDATE OR DELETE ON sale_lot_allocations FOR EACH ROW EXECUTE FUNCTION btp_prevent_posted_mutation()",
            "CREATE TRIGGER btp_cost_consumptions_immutable BEFORE UPDATE OR DELETE ON cost_layer_consumptions FOR EACH ROW EXECUTE FUNCTION btp_prevent_posted_mutation()",
            "CREATE TRIGGER btp_accounting_events_immutable BEFORE UPDATE OR DELETE ON accounting_events FOR EACH ROW EXECUTE FUNCTION btp_prevent_posted_mutation()",
            "CREATE TRIGGER btp_sync_receipts_immutable BEFORE UPDATE OR DELETE ON sync_receipts FOR EACH ROW EXECUTE FUNCTION btp_prevent_posted_mutation()",
            <<<'SQL'
            CREATE OR REPLACE FUNCTION btp_assert_posted_journal_integrity() RETURNS trigger AS $$
            DECLARE
              target_id text;
              entry_row journal_entries%ROWTYPE;
              line_count bigint;
              total_debit numeric;
              total_credit numeric;
              event_count bigint;
              item_count bigint;
              movement_count bigint;
              receipt_count bigint;
              sale_total bigint;
              sale_subtotal bigint;
              sale_tax bigint;
              original_status text;
              original_type text;
            BEGIN
              IF TG_TABLE_NAME = 'journal_entries' THEN
                IF TG_OP = 'DELETE' THEN target_id := OLD.id; ELSE target_id := NEW.id; END IF;
              ELSE
                IF TG_OP = 'DELETE' THEN target_id := OLD.journal_entry_id; ELSE target_id := NEW.journal_entry_id; END IF;
              END IF;
              SELECT * INTO entry_row FROM journal_entries WHERE id = target_id;
              IF NOT FOUND OR entry_row.status <> 'posted' THEN RETURN NULL; END IF;

              SELECT count(*), COALESCE(sum(debit), 0), COALESCE(sum(credit), 0)
                INTO line_count, total_debit, total_credit
                FROM journal_lines WHERE journal_entry_id = target_id;
              IF line_count < 2 OR total_debit <= 0 OR total_debit <> total_credit THEN
                RAISE EXCEPTION 'Posted journal must have at least two lines and equal positive debit/credit totals';
              END IF;
              IF EXISTS (
                SELECT 1 FROM journal_lines l JOIN chart_of_accounts c ON c.account_code = l.account_code
                WHERE l.journal_entry_id = target_id AND NOT c.is_active
              ) THEN
                RAISE EXCEPTION 'Posted journal contains an inactive COA account';
              END IF;

              SELECT count(*) INTO event_count FROM accounting_events e
                WHERE e.journal_entry_id = target_id
                  AND e.actor_reference = entry_row.actor_reference
                  AND e.device_id = entry_row.device_id
                  AND e.app_version = entry_row.app_version
                  AND e.transaction_reference = entry_row.transaction_reference
                  AND e.idempotency_key = entry_row.idempotency_key
                  AND e.event_type = 'journal.posted';
              IF event_count <> 1 THEN RAISE EXCEPTION 'Posted journal requires one complete immutable accounting event'; END IF;

              IF entry_row.entry_type = 'sale' THEN
                SELECT count(*), COALESCE(max(total_amount), 0), COALESCE(max(subtotal), 0), COALESCE(max(tax_amount), 0)
                  INTO event_count, sale_total, sale_subtotal, sale_tax
                  FROM sales WHERE source_event_id = entry_row.source_event_id
                    AND currency_code = 'IDR' AND device_id = entry_row.device_id
                    AND request_fingerprint = entry_row.payload_sha256;
                IF event_count <> 1 THEN RAISE EXCEPTION 'Sale journal must have exactly one matching sale header'; END IF;
                SELECT count(*) INTO item_count FROM sale_items si
                  JOIN sales s ON s.id = si.sale_id
                  WHERE s.source_event_id = entry_row.source_event_id;
                SELECT count(*) INTO movement_count FROM inventory_movements
                  WHERE source_event_id = entry_row.source_event_id AND movement_type = 'sale_out';
                SELECT count(*) INTO receipt_count FROM sync_receipts
                  WHERE event_id = entry_row.source_event_id
                    AND device_id = entry_row.device_id
                    AND payload_sha256 = entry_row.payload_sha256;
                IF item_count < 1 OR movement_count < 1 OR receipt_count <> 1 THEN
                  RAISE EXCEPTION 'Sale, items, stock movements, journal, audit event and sync receipt must commit together';
                END IF;
                IF sale_total <> sale_subtotal + sale_tax THEN
                  RAISE EXCEPTION 'Sale total must equal subtotal plus tax';
                END IF;
                IF EXISTS (
                  SELECT 1 FROM sales s
                  WHERE s.source_event_id = entry_row.source_event_id
                    AND s.subtotal <> (SELECT COALESCE(sum(line_total), 0) FROM sale_items WHERE sale_id = s.id)
                ) THEN
                  RAISE EXCEPTION 'Sale subtotal does not match persisted sale item lines';
                END IF;
              ELSIF entry_row.entry_type = 'reversal' THEN
                SELECT status, entry_type INTO original_status, original_type
                  FROM journal_entries WHERE id = entry_row.reversal_of_entry_id;
                IF original_status <> 'posted' OR original_type = 'sale' THEN
                  RAISE EXCEPTION 'Only an existing non-sale posted journal may be reversed by this journal-only procedure';
                END IF;
                IF EXISTS (
                  SELECT 1
                  FROM (
                    SELECT account_code, sum(debit) AS debit, sum(credit) AS credit
                    FROM journal_lines WHERE journal_entry_id = entry_row.reversal_of_entry_id GROUP BY account_code
                  ) o
                  FULL JOIN (
                    SELECT account_code, sum(debit) AS debit, sum(credit) AS credit
                    FROM journal_lines WHERE journal_entry_id = target_id GROUP BY account_code
                  ) r USING (account_code)
                  WHERE COALESCE(o.debit, 0) <> COALESCE(r.credit, 0)
                     OR COALESCE(o.credit, 0) <> COALESCE(r.debit, 0)
                ) THEN
                  RAISE EXCEPTION 'Reversal lines must exactly invert the original journal by account';
                END IF;
              END IF;
              RETURN NULL;
            END;
            $$ LANGUAGE plpgsql
            SQL,
            "CREATE CONSTRAINT TRIGGER btp_posted_journal_integrity_header AFTER INSERT OR UPDATE ON journal_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION btp_assert_posted_journal_integrity()",
            "CREATE CONSTRAINT TRIGGER btp_posted_journal_integrity_lines AFTER INSERT OR UPDATE OR DELETE ON journal_lines DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION btp_assert_posted_journal_integrity()",

            <<<'SQL'
            CREATE OR REPLACE FUNCTION btp_assert_sale_event_integrity() RETURNS trigger AS $btp$
            DECLARE
              event_key text;
              sale_row sales%ROWTYPE;
              source_sale_id text;
              item_count bigint;
              movement_count bigint;
              receipt_count bigint;
              journal_count bigint;
              audit_count bigint;
              line_subtotal bigint;
              expected_cogs bigint;
              payment_account text;
              payment_debit numeric;
              payment_credit numeric;
              revenue_debit numeric;
              revenue_credit numeric;
              cogs_debit numeric;
              cogs_credit numeric;
              inventory_debit numeric;
              inventory_credit numeric;
            BEGIN
              IF TG_TABLE_NAME = 'sales' THEN
                IF TG_OP = 'DELETE' THEN event_key := OLD.source_event_id; ELSE event_key := NEW.source_event_id; END IF;
              ELSIF TG_TABLE_NAME = 'inventory_movements' THEN
                IF TG_OP = 'DELETE' THEN
                  IF OLD.movement_type <> 'sale_out' THEN RETURN NULL; END IF;
                  event_key := OLD.source_event_id;
                ELSE
                  IF NEW.movement_type <> 'sale_out' THEN RETURN NULL; END IF;
                  event_key := NEW.source_event_id;
                END IF;
              ELSIF TG_TABLE_NAME = 'sync_receipts' THEN
                IF TG_OP = 'DELETE' THEN event_key := OLD.event_id; ELSE event_key := NEW.event_id; END IF;
              ELSIF TG_TABLE_NAME = 'sale_items' THEN
                IF TG_OP = 'DELETE' THEN source_sale_id := OLD.sale_id; ELSE source_sale_id := NEW.sale_id; END IF;
                SELECT source_event_id INTO event_key FROM sales WHERE id = source_sale_id;
              ELSIF TG_TABLE_NAME = 'sale_lot_allocations' THEN
                IF TG_OP = 'DELETE' THEN
                  SELECT s.source_event_id INTO event_key FROM sale_items si JOIN sales s ON s.id = si.sale_id WHERE si.id = OLD.sale_item_id;
                ELSE
                  SELECT s.source_event_id INTO event_key FROM sale_items si JOIN sales s ON s.id = si.sale_id WHERE si.id = NEW.sale_item_id;
                END IF;
              ELSIF TG_TABLE_NAME = 'cost_layer_consumptions' THEN
                IF TG_OP = 'DELETE' THEN
                  SELECT s.source_event_id INTO event_key FROM sale_items si JOIN sales s ON s.id = si.sale_id WHERE si.id = OLD.sale_item_id;
                ELSE
                  SELECT s.source_event_id INTO event_key FROM sale_items si JOIN sales s ON s.id = si.sale_id WHERE si.id = NEW.sale_item_id;
                END IF;
              ELSE
                RETURN NULL;
              END IF;

              IF event_key IS NULL THEN RETURN NULL; END IF;
              SELECT * INTO sale_row FROM sales WHERE source_event_id = event_key;
              IF NOT FOUND THEN
                RAISE EXCEPTION 'Sale-related movement/receipt references an event without a sale header';
              END IF;
              IF sale_row.currency_code <> 'IDR' OR sale_row.tax_amount <> 0 OR sale_row.total_amount <> sale_row.subtotal THEN
                RAISE EXCEPTION 'Only IDR whole-unit, zero-tax sales are currently supported; tax policy requires owner approval';
              END IF;

              SELECT count(*), COALESCE(sum(line_total), 0), COALESCE(sum(cogs_amount), 0)
                INTO item_count, line_subtotal, expected_cogs
                FROM sale_items WHERE sale_id = sale_row.id;
              IF item_count < 1 OR line_subtotal <> sale_row.subtotal THEN
                RAISE EXCEPTION 'Sale line items must be present and sum exactly to subtotal';
              END IF;
              IF EXISTS (SELECT 1 FROM sale_items WHERE sale_id = sale_row.id AND line_total <> unit_price * quantity) THEN
                RAISE EXCEPTION 'Sale line total must equal integer unit price multiplied by quantity';
              END IF;

              IF EXISTS (
                SELECT 1 FROM sale_items si
                WHERE si.sale_id = sale_row.id
                  AND si.quantity <> COALESCE((SELECT sum(a.quantity) FROM sale_lot_allocations a WHERE a.sale_item_id = si.id), 0)
              ) THEN
                RAISE EXCEPTION 'FEFO lot allocations must equal each sold line quantity';
              END IF;
              IF EXISTS (
                SELECT 1 FROM sale_items si
                WHERE si.sale_id = sale_row.id
                  AND (si.quantity <> COALESCE((SELECT sum(c.quantity) FROM cost_layer_consumptions c WHERE c.sale_item_id = si.id), 0)
                    OR si.cogs_amount <> COALESCE((SELECT sum(c.total_cost) FROM cost_layer_consumptions c WHERE c.sale_item_id = si.id), 0))
              ) THEN
                RAISE EXCEPTION 'FIFO layer consumption and COGS must reconcile for every sale line';
              END IF;

              IF EXISTS (
                SELECT 1
                FROM (SELECT product_id, sum(quantity) AS sold_qty FROM sale_items WHERE sale_id = sale_row.id GROUP BY product_id) si
                LEFT JOIN (SELECT product_id, -sum(quantity) AS moved_qty FROM inventory_movements WHERE source_event_id = event_key AND movement_type = 'sale_out' GROUP BY product_id) im USING (product_id)
                WHERE si.sold_qty <> COALESCE(im.moved_qty, 0)
              ) THEN
                RAISE EXCEPTION 'Per-product stock movements must equal sold quantities';
              END IF;
              IF EXISTS (
                SELECT 1
                FROM sale_lot_allocations a
                JOIN sale_items si ON si.id = a.sale_item_id
                LEFT JOIN inventory_movements m ON m.source_event_id = event_key AND m.lot_id = a.lot_id AND m.product_id = si.product_id AND m.movement_type = 'sale_out'
                WHERE si.sale_id = sale_row.id
                GROUP BY a.lot_id, si.product_id
                HAVING sum(a.quantity) <> -COALESCE(sum(m.quantity), 0)
              ) THEN
                RAISE EXCEPTION 'Per-lot FEFO allocations must reconcile to immutable inventory movements';
              END IF;
              IF EXISTS (
                SELECT 1 FROM inventory_lots l
                WHERE l.id IN (SELECT a.lot_id FROM sale_lot_allocations a JOIN sale_items si ON si.id = a.sale_item_id WHERE si.sale_id = sale_row.id)
                  AND l.quantity_remaining <> l.quantity_received + COALESCE((SELECT sum(m.quantity) FROM inventory_movements m WHERE m.lot_id = l.id AND m.movement_type = 'sale_out'), 0)
              ) THEN
                RAISE EXCEPTION 'Physical lot balance does not reconcile to immutable stock movements';
              END IF;
              IF EXISTS (
                SELECT 1 FROM inventory_cost_layers l
                WHERE l.id IN (SELECT c.cost_layer_id FROM cost_layer_consumptions c JOIN sale_items si ON si.id = c.sale_item_id WHERE si.sale_id = sale_row.id)
                  AND l.quantity_remaining <> l.quantity_received - COALESCE((SELECT sum(c.quantity) FROM cost_layer_consumptions c WHERE c.cost_layer_id = l.id), 0)
              ) THEN
                RAISE EXCEPTION 'FIFO cost-layer balance does not reconcile to immutable consumptions';
              END IF;

              SELECT count(*) INTO movement_count FROM inventory_movements WHERE source_event_id = event_key AND movement_type = 'sale_out';
              SELECT count(*) INTO receipt_count FROM sync_receipts WHERE event_id = event_key AND device_id = sale_row.device_id AND payload_sha256 = sale_row.request_fingerprint;
              SELECT count(*) INTO journal_count FROM journal_entries WHERE source_event_id = event_key AND status = 'posted' AND entry_type = 'sale';
              SELECT count(*) INTO audit_count FROM accounting_events e JOIN journal_entries j ON j.id = e.journal_entry_id
                WHERE j.source_event_id = event_key AND e.event_type = 'journal.posted' AND e.device_id = sale_row.device_id AND e.idempotency_key = event_key;
              IF movement_count < 1 OR receipt_count <> 1 OR journal_count <> 1 OR audit_count <> 1 THEN
                RAISE EXCEPTION 'Sale, stock, balanced journal, accounting event and idempotent sync receipt must commit together';
              END IF;

              SELECT CASE sale_row.payment_method WHEN 'cash' THEN '1-1010' WHEN 'qris' THEN '1-1020' WHEN 'transfer' THEN '1-1030' ELSE NULL END
                INTO payment_account;
              IF payment_account IS NULL THEN RAISE EXCEPTION 'Unsupported payment method for sale posting'; END IF;
              SELECT COALESCE(sum(debit), 0), COALESCE(sum(credit), 0) INTO payment_debit, payment_credit
                FROM journal_lines l JOIN journal_entries j ON j.id = l.journal_entry_id WHERE j.source_event_id = event_key AND l.account_code = payment_account;
              SELECT COALESCE(sum(debit), 0), COALESCE(sum(credit), 0) INTO revenue_debit, revenue_credit
                FROM journal_lines l JOIN journal_entries j ON j.id = l.journal_entry_id WHERE j.source_event_id = event_key AND l.account_code = '4-4010';
              SELECT COALESCE(sum(debit), 0), COALESCE(sum(credit), 0) INTO cogs_debit, cogs_credit
                FROM journal_lines l JOIN journal_entries j ON j.id = l.journal_entry_id WHERE j.source_event_id = event_key AND l.account_code = '5-5010';
              SELECT COALESCE(sum(debit), 0), COALESCE(sum(credit), 0) INTO inventory_debit, inventory_credit
                FROM journal_lines l JOIN journal_entries j ON j.id = l.journal_entry_id WHERE j.source_event_id = event_key AND l.account_code = '1-1040';
              IF payment_debit <> sale_row.total_amount OR payment_credit <> 0
                OR revenue_debit <> 0 OR revenue_credit <> sale_row.subtotal
                OR cogs_debit <> expected_cogs OR cogs_credit <> 0
                OR inventory_debit <> 0 OR inventory_credit <> expected_cogs THEN
                RAISE EXCEPTION 'Sale journal lines do not match payment, revenue, COGS and inventory values';
              END IF;
              IF EXISTS (
                SELECT 1 FROM journal_lines l JOIN journal_entries j ON j.id = l.journal_entry_id
                WHERE j.source_event_id = event_key AND l.account_code NOT IN (payment_account, '4-4010', '5-5010', '1-1040')
              ) THEN
                RAISE EXCEPTION 'Sale journal contains an unapproved COA posting';
              END IF;
              RETURN NULL;
            END;
            $btp$ LANGUAGE plpgsql
            SQL,
            "CREATE CONSTRAINT TRIGGER btp_sale_integrity_sales AFTER INSERT OR UPDATE OR DELETE ON sales DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION btp_assert_sale_event_integrity()",
            "CREATE CONSTRAINT TRIGGER btp_sale_integrity_items AFTER INSERT OR UPDATE OR DELETE ON sale_items DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION btp_assert_sale_event_integrity()",
            "CREATE CONSTRAINT TRIGGER btp_sale_integrity_movements AFTER INSERT OR UPDATE OR DELETE ON inventory_movements DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION btp_assert_sale_event_integrity()",
            "CREATE CONSTRAINT TRIGGER btp_sale_integrity_allocations AFTER INSERT OR UPDATE OR DELETE ON sale_lot_allocations DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION btp_assert_sale_event_integrity()",
            "CREATE CONSTRAINT TRIGGER btp_sale_integrity_consumptions AFTER INSERT OR UPDATE OR DELETE ON cost_layer_consumptions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION btp_assert_sale_event_integrity()",
            "CREATE CONSTRAINT TRIGGER btp_sale_integrity_receipts AFTER INSERT OR UPDATE OR DELETE ON sync_receipts DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION btp_assert_sale_event_integrity()",
        ];

        foreach ($statements as $statement) {
            $db->unprepared($statement);
        }
    }

    public function down(): void
    {
        $db = DB::connection('tenant');
        if ($db->table('journal_entries')->where('status', 'posted')->exists()
            || $db->table('sales')->exists()
            || $db->table('sale_items')->exists()
            || $db->table('inventory_movements')->exists()
            || $db->table('inventory_cost_layers')->exists()
            || $db->table('accounting_events')->exists()
            || $db->table('accounting_periods')->where('status', 'closed')->exists()) {
            throw new RuntimeException('Refusing rollback after transactional/accounting records exist; use a reviewed forward migration and compensating entries.');
        }

        foreach ([
            'btp_sale_integrity_receipts',
            'btp_sale_integrity_consumptions',
            'btp_sale_integrity_allocations',
            'btp_sale_integrity_movements',
            'btp_sale_integrity_items',
            'btp_sale_integrity_sales',
            'btp_posted_journal_integrity_lines',
            'btp_posted_journal_integrity_header',
            'btp_sync_receipts_immutable',
            'btp_accounting_events_immutable',
            'btp_cost_consumptions_immutable',
            'btp_sale_lot_allocations_immutable',
            'btp_inventory_movements_immutable',
            'btp_sale_items_immutable',
            'btp_sales_immutable',
            'btp_cost_layer_consumption_guard',
            'btp_sale_lot_allocation_guard',
            'btp_inventory_movement_guard',
            'btp_cost_layer_quantity_guard',
            'btp_inventory_quantity_guard',
            'btp_journal_line_guard',
            'btp_journal_header_guard',
            'btp_period_close_guard',
            'btp_locked_coa_guard',
        ] as $trigger) {
            $db->unprepared("DROP TRIGGER IF EXISTS {$trigger} ON ".match ($trigger) {
                'btp_sale_integrity_receipts' => 'sync_receipts',
                'btp_sale_integrity_consumptions' => 'cost_layer_consumptions',
                'btp_sale_integrity_allocations' => 'sale_lot_allocations',
                'btp_sale_integrity_movements' => 'inventory_movements',
                'btp_sale_integrity_items' => 'sale_items',
                'btp_sale_integrity_sales' => 'sales',
                'btp_posted_journal_integrity_lines' => 'journal_lines',
                'btp_posted_journal_integrity_header' => 'journal_entries',
                'btp_sync_receipts_immutable' => 'sync_receipts',
                'btp_accounting_events_immutable' => 'accounting_events',
                'btp_cost_consumptions_immutable' => 'cost_layer_consumptions',
                'btp_sale_lot_allocations_immutable' => 'sale_lot_allocations',
                'btp_inventory_movements_immutable' => 'inventory_movements',
                'btp_sale_items_immutable' => 'sale_items',
                'btp_sales_immutable' => 'sales',
                'btp_cost_layer_consumption_guard' => 'cost_layer_consumptions',
                'btp_sale_lot_allocation_guard' => 'sale_lot_allocations',
                'btp_inventory_movement_guard' => 'inventory_movements',
                'btp_cost_layer_quantity_guard' => 'inventory_cost_layers',
                'btp_inventory_quantity_guard' => 'inventory_lots',
                'btp_journal_line_guard' => 'journal_lines',
                'btp_journal_header_guard' => 'journal_entries',
                'btp_period_close_guard' => 'accounting_periods',
                'btp_locked_coa_guard' => 'chart_of_accounts',
            });
        }
        foreach ([
            'btp_guard_cost_layer_consumption',
            'btp_guard_sale_lot_allocation',
            'btp_guard_inventory_movement',
            'btp_assert_sale_event_integrity',
            'btp_assert_posted_journal_integrity',
            'btp_prevent_posted_mutation',
            'btp_guard_cost_layer_quantity',
            'btp_guard_inventory_quantity',
            'btp_guard_journal_line',
            'btp_guard_journal_header',
            'btp_guard_period_close',
            'btp_guard_locked_coa',
        ] as $function) {
            $db->unprepared("DROP FUNCTION IF EXISTS {$function}() CASCADE");
        }

        foreach (['cost_layer_consumptions', 'sale_lot_allocations', 'inventory_cost_layers', 'accounting_events', 'accounting_periods', 'chart_of_accounts'] as $table) {
            Schema::connection('tenant')->dropIfExists($table);
        }

        $db->unprepared('DROP INDEX IF EXISTS journal_entry_one_full_reversal_idx');
        $db->unprepared('DROP INDEX IF EXISTS sale_items_sale_line_unique_idx');
        $db->unprepared('DROP INDEX IF EXISTS inventory_movement_event_idx');
        $db->unprepared('DROP INDEX IF EXISTS accounting_period_status_idx');
        $db->unprepared('ALTER TABLE inventory_movements DROP CONSTRAINT IF EXISTS inventory_movement_key_unique, DROP CONSTRAINT IF EXISTS inventory_movement_lot_fk, DROP CONSTRAINT IF EXISTS inventory_movement_product_fk');
        $db->unprepared('ALTER TABLE sale_items DROP CONSTRAINT IF EXISTS sale_item_sale_fk, DROP CONSTRAINT IF EXISTS sale_item_product_fk, DROP CONSTRAINT IF EXISTS sale_item_money_nonnegative, DROP CONSTRAINT IF EXISTS sale_item_quantity_positive_integer, DROP CONSTRAINT IF EXISTS sale_item_line_total_integrity');
        $db->unprepared('ALTER TABLE inventory_lots DROP CONSTRAINT IF EXISTS inventory_lot_product_fk, DROP CONSTRAINT IF EXISTS inventory_lot_quantities_valid, DROP CONSTRAINT IF EXISTS inventory_lot_cost_nonnegative');
        $db->unprepared('ALTER TABLE sale_lot_allocations DROP CONSTRAINT IF EXISTS sale_lot_allocation_quantity_valid');
        $db->unprepared('ALTER TABLE cost_layer_consumptions DROP CONSTRAINT IF EXISTS cost_consumption_values_valid');
        $db->unprepared('ALTER TABLE inventory_movements DROP CONSTRAINT IF EXISTS sale_out_movement_valid');
        $db->unprepared('ALTER TABLE journal_lines DROP CONSTRAINT IF EXISTS journal_lines_entry_fk, DROP CONSTRAINT IF EXISTS journal_lines_account_fk, DROP CONSTRAINT IF EXISTS journal_lines_entry_line_unique, DROP CONSTRAINT IF EXISTS journal_line_amounts_valid');
        $db->unprepared('ALTER TABLE journal_entries DROP CONSTRAINT IF EXISTS journal_reversal_fk, DROP CONSTRAINT IF EXISTS journal_reversal_not_self, DROP CONSTRAINT IF EXISTS journal_currency_idr, DROP CONSTRAINT IF EXISTS journal_type_valid, DROP CONSTRAINT IF EXISTS journal_status_valid');
        $db->unprepared('ALTER TABLE sales DROP CONSTRAINT IF EXISTS sales_currency_idr, DROP CONSTRAINT IF EXISTS sales_total_matches, DROP CONSTRAINT IF EXISTS sales_money_nonnegative');
        $db->unprepared('ALTER TABLE products DROP CONSTRAINT IF EXISTS products_shelf_life_nonnegative, DROP CONSTRAINT IF EXISTS products_currency_idr, DROP CONSTRAINT IF EXISTS products_price_nonnegative');

        Schema::connection('tenant')->table('journal_lines', function (Blueprint $table): void {
            $table->dropColumn('line_no');
        });
        Schema::connection('tenant')->table('journal_entries', function (Blueprint $table): void {
            $table->dropColumn(['status', 'entry_type', 'currency_code', 'posted_at', 'actor_reference', 'device_id', 'app_version', 'transaction_reference', 'idempotency_key', 'payload_sha256', 'reversal_of_entry_id']);
        });
        Schema::connection('tenant')->table('inventory_movements', function (Blueprint $table): void {
            $table->dropColumn(['movement_key', 'lot_id']);
        });
        Schema::connection('tenant')->table('sale_items', function (Blueprint $table): void {
            $table->dropColumn(['cogs_amount', 'line_no']);
        });
        Schema::connection('tenant')->table('sales', function (Blueprint $table): void {
            $table->dropColumn(['currency_code', 'occurred_at_utc', 'business_date', 'request_fingerprint']);
        });
        Schema::connection('tenant')->table('products', function (Blueprint $table): void {
            $table->dropColumn(['track_expiry', 'min_shelf_life_days', 'currency_code']);
        });

        foreach ([
            'ALTER TABLE products ALTER COLUMN price TYPE NUMERIC(18,2) USING price::NUMERIC(18,2)',
            'ALTER TABLE inventory_lots ALTER COLUMN unit_cost TYPE NUMERIC(18,2) USING unit_cost::NUMERIC(18,2)',
            'ALTER TABLE sales ALTER COLUMN subtotal TYPE NUMERIC(18,2) USING subtotal::NUMERIC(18,2)',
            'ALTER TABLE sales ALTER COLUMN tax_amount TYPE NUMERIC(18,2) USING tax_amount::NUMERIC(18,2)',
            'ALTER TABLE sales ALTER COLUMN total_amount TYPE NUMERIC(18,2) USING total_amount::NUMERIC(18,2)',
            'ALTER TABLE sale_items ALTER COLUMN unit_price TYPE NUMERIC(18,2) USING unit_price::NUMERIC(18,2)',
            'ALTER TABLE sale_items ALTER COLUMN line_total TYPE NUMERIC(18,2) USING line_total::NUMERIC(18,2)',
            'ALTER TABLE sale_items ALTER COLUMN unit_cost TYPE NUMERIC(18,2) USING unit_cost::NUMERIC(18,2)',
            'ALTER TABLE journal_lines ALTER COLUMN debit TYPE NUMERIC(18,2) USING debit::NUMERIC(18,2)',
            'ALTER TABLE journal_lines ALTER COLUMN credit TYPE NUMERIC(18,2) USING credit::NUMERIC(18,2)',
            'ALTER TABLE sale_items ALTER COLUMN unit_cost SET NOT NULL',
        ] as $statement) {
            $db->unprepared($statement);
        }
    }
};