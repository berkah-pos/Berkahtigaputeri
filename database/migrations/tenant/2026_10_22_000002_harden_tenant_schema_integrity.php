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
        $db->unprepared(<<<'SQL'
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM journal_entries) THEN
        RAISE EXCEPTION 'Schema hardening blocked: existing journals need an explicitly reviewed backfill.';
    END IF;
    IF EXISTS (SELECT 1 FROM products WHERE price <> trunc(price))
       OR EXISTS (SELECT 1 FROM inventory_lots WHERE unit_cost <> trunc(unit_cost))
       OR EXISTS (SELECT 1 FROM sales WHERE subtotal <> trunc(subtotal) OR tax_amount <> trunc(tax_amount) OR total_amount <> trunc(total_amount))
       OR EXISTS (SELECT 1 FROM sale_items WHERE unit_price <> trunc(unit_price) OR line_total <> trunc(line_total) OR unit_cost <> trunc(unit_cost))
       OR EXISTS (SELECT 1 FROM journal_lines WHERE debit <> trunc(debit) OR credit <> trunc(credit)) THEN
        RAISE EXCEPTION 'Schema hardening blocked: fractional Rupiah values need reviewed conversion.';
    END IF;
END;
$$;
SQL);
        $db->unprepared(<<<'SQL'
ALTER TABLE products ALTER COLUMN price DROP DEFAULT;
ALTER TABLE products ALTER COLUMN price TYPE bigint USING price::bigint;
ALTER TABLE products ALTER COLUMN price SET DEFAULT 0;
ALTER TABLE inventory_lots ALTER COLUMN unit_cost TYPE bigint USING unit_cost::bigint;
ALTER TABLE sales ALTER COLUMN subtotal TYPE bigint USING subtotal::bigint;
ALTER TABLE sales ALTER COLUMN tax_amount DROP DEFAULT;
ALTER TABLE sales ALTER COLUMN tax_amount TYPE bigint USING tax_amount::bigint;
ALTER TABLE sales ALTER COLUMN tax_amount SET DEFAULT 0;
ALTER TABLE sales ALTER COLUMN total_amount TYPE bigint USING total_amount::bigint;
ALTER TABLE sale_items ALTER COLUMN unit_price TYPE bigint USING unit_price::bigint;
ALTER TABLE sale_items ALTER COLUMN line_total TYPE bigint USING line_total::bigint;
ALTER TABLE sale_items ALTER COLUMN unit_cost DROP DEFAULT;
ALTER TABLE sale_items ALTER COLUMN unit_cost TYPE bigint USING unit_cost::bigint;
ALTER TABLE sale_items ALTER COLUMN unit_cost SET DEFAULT 0;
ALTER TABLE journal_lines ALTER COLUMN debit DROP DEFAULT;
ALTER TABLE journal_lines ALTER COLUMN debit TYPE bigint USING debit::bigint;
ALTER TABLE journal_lines ALTER COLUMN debit SET DEFAULT 0;
ALTER TABLE journal_lines ALTER COLUMN credit DROP DEFAULT;
ALTER TABLE journal_lines ALTER COLUMN credit TYPE bigint USING credit::bigint;
ALTER TABLE journal_lines ALTER COLUMN credit SET DEFAULT 0;
ALTER TABLE products ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC';
ALTER TABLE products ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC';
ALTER TABLE inventory_lots ALTER COLUMN received_at TYPE timestamptz USING received_at AT TIME ZONE 'UTC';
ALTER TABLE inventory_lots ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC';
ALTER TABLE inventory_lots ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC';
ALTER TABLE sales ALTER COLUMN occurred_at TYPE timestamptz USING occurred_at AT TIME ZONE 'UTC';
ALTER TABLE sales ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC';
ALTER TABLE sales ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC';
ALTER TABLE sale_items ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC';
ALTER TABLE sale_items ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC';
ALTER TABLE inventory_movements ALTER COLUMN occurred_at TYPE timestamptz USING occurred_at AT TIME ZONE 'UTC';
ALTER TABLE inventory_movements ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC';
ALTER TABLE inventory_movements ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC';
ALTER TABLE journal_entries ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC';
ALTER TABLE journal_entries ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC';
ALTER TABLE journal_lines ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC';
ALTER TABLE journal_lines ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC';
ALTER TABLE sync_receipts ALTER COLUMN accepted_at TYPE timestamptz USING accepted_at AT TIME ZONE 'UTC';
ALTER TABLE sync_receipts ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC';
ALTER TABLE sync_receipts ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC';
ALTER TABLE device_configs ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC';
ALTER TABLE device_configs ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC';
SQL);

        Schema::connection('tenant')->create('chart_of_accounts', function (Blueprint $t): void {
            $t->string('code',10)->primary(); $t->string('name',120); $t->string('account_type',12);
            $t->string('normal_balance',6); $t->boolean('is_locked')->default(true); $t->timestampsTz();
        });
        Schema::connection('tenant')->create('accounting_periods', function (Blueprint $t): void {
            $t->id(); $t->string('period_key',32)->unique(); $t->date('starts_on'); $t->date('ends_on');
            $t->string('status',10)->default('open'); $t->timestampTz('closed_at')->nullable();
            $t->unsignedBigInteger('closed_by_user_id')->nullable(); $t->timestampsTz();
        });
        $accounts = [
            ['1-1010','Kas Tunai','asset','debit'],['1-1020','QRIS Clearing','asset','debit'],
            ['1-1030','Bank Transfer','asset','debit'],['1-1040','Persediaan Barang','asset','debit'],
            ['1-1050','Piutang Usaha','asset','debit'],['1-1060','Peralatan Toko','asset','debit'],
            ['1-1070','Akumulasi Penyusutan Peralatan','asset','credit'],['2-2010','Utang PPN 11%','liability','credit'],
            ['2-2020','Utang Supplier','liability','credit'],['2-2030','Utang Gaji','liability','credit'],
            ['3-3010','Modal Pemilik','equity','credit'],['3-3020','Laba Ditahan','equity','credit'],
            ['3-3030','Prive','equity','debit'],['4-4010','Penjualan','revenue','credit'],
            ['4-4020','Diskon Penjualan','revenue','debit'],['4-4030','Retur Penjualan','revenue','debit'],
            ['4-4040','Selisih Kas Lebih','revenue','credit'],['5-5010','Harga Pokok Penjualan','cogs','debit'],
            ['6-6010','Beban Gaji','expense','debit'],['6-6020','Beban Selisih Kas Kurang','expense','debit'],
            ['6-6030','Beban Operasional Toko','expense','debit'],['6-6040','Beban Sewa','expense','debit'],
            ['6-6050','Beban Listrik dan Air','expense','debit'],['6-6060','Beban Penyusutan','expense','debit'],
        ];
        $now = now()->utc();
        $db->table('chart_of_accounts')->insert(array_map(static fn($a) => [
            'code'=>$a[0],'name'=>$a[1],'account_type'=>$a[2],'normal_balance'=>$a[3],
            'is_locked'=>true,'created_at'=>$now,'updated_at'=>$now,
        ], $accounts));
        Schema::connection('tenant')->create('accounting_events', function (Blueprint $t): void {
            $t->id(); $t->string('journal_entry_id',100); $t->string('event_type',40);
            $t->unsignedBigInteger('actor_user_id'); $t->string('device_id',150); $t->string('app_version',50);
            $t->timestampTz('occurred_at'); $t->jsonb('metadata')->nullable(); $t->timestampsTz();
            $t->foreign('journal_entry_id')->references('id')->on('journal_entries')->restrictOnDelete();
            $t->unique(['journal_entry_id','event_type']);
        });
        Schema::connection('tenant')->table('journal_entries', function (Blueprint $t): void {
            $t->string('status',12)->default('draft'); $t->timestampTz('posted_at')->nullable();
            $t->unsignedBigInteger('posted_by_user_id')->nullable(); $t->string('posted_by_device_id',150)->nullable();
            $t->string('app_version',50)->nullable(); $t->unsignedBigInteger('accounting_period_id')->nullable();
            $t->string('reversal_of_entry_id',100)->nullable(); $t->string('reversal_reason',500)->nullable();
            $t->foreign('accounting_period_id')->references('id')->on('accounting_periods')->restrictOnDelete();
            $t->foreign('reversal_of_entry_id')->references('id')->on('journal_entries')->restrictOnDelete();
            $t->unique('reversal_of_entry_id');
        });

        $db->unprepared(<<<'SQL'
ALTER TABLE chart_of_accounts ADD CONSTRAINT coa_code_allowlist_check CHECK (code IN ('1-1010','1-1020','1-1030','1-1040','1-1050','1-1060','1-1070','2-2010','2-2020','2-2030','3-3010','3-3020','3-3030','4-4010','4-4020','4-4030','4-4040','5-5010','6-6010','6-6020','6-6030','6-6040','6-6050','6-6060'));
ALTER TABLE chart_of_accounts ADD CONSTRAINT coa_type_check CHECK (account_type IN ('asset','liability','equity','revenue','cogs','expense'));
ALTER TABLE chart_of_accounts ADD CONSTRAINT coa_balance_check CHECK (normal_balance IN ('debit','credit'));
ALTER TABLE chart_of_accounts ADD CONSTRAINT coa_locked_check CHECK (is_locked);
ALTER TABLE accounting_periods ADD CONSTRAINT accounting_period_dates_check CHECK (starts_on <= ends_on);
ALTER TABLE accounting_periods ADD CONSTRAINT accounting_period_status_check CHECK (status IN ('open','closed'));
ALTER TABLE accounting_periods ADD CONSTRAINT accounting_period_closed_at_check CHECK ((status='open' AND closed_at IS NULL) OR (status='closed' AND closed_at IS NOT NULL));
ALTER TABLE products ADD CONSTRAINT products_price_nonnegative_check CHECK (price >= 0);
ALTER TABLE inventory_lots ADD CONSTRAINT inventory_lot_quantities_check CHECK (quantity_received > 0 AND quantity_remaining >= 0 AND quantity_remaining <= quantity_received);
ALTER TABLE inventory_lots ADD CONSTRAINT inventory_lot_cost_check CHECK (unit_cost >= 0);
ALTER TABLE sales ADD CONSTRAINT sales_amounts_nonnegative_check CHECK (subtotal >= 0 AND tax_amount >= 0 AND total_amount >= 0);
ALTER TABLE sale_items ADD CONSTRAINT sale_items_values_check CHECK (quantity > 0 AND unit_price >= 0 AND line_total >= 0 AND unit_cost >= 0);
ALTER TABLE inventory_movements ADD CONSTRAINT inventory_movement_quantity_check CHECK (quantity <> 0);
ALTER TABLE journal_entries ADD CONSTRAINT journal_entry_status_check CHECK (status IN ('draft','posted'));
ALTER TABLE journal_entries ADD CONSTRAINT journal_entry_reversal_not_self_check CHECK (reversal_of_entry_id IS NULL OR reversal_of_entry_id <> id);
ALTER TABLE journal_lines ADD CONSTRAINT journal_line_one_sided_amount_check CHECK ((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0));
ALTER TABLE sync_receipts ADD CONSTRAINT sync_receipt_hash_check CHECK (payload_sha256 ~ '^[0-9a-f]{64}$');
ALTER TABLE inventory_lots ADD CONSTRAINT inventory_lots_product_fk FOREIGN KEY (product_id) REFERENCES products(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE inventory_movements ADD CONSTRAINT inventory_movements_product_fk FOREIGN KEY (product_id) REFERENCES products(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE sale_items ADD CONSTRAINT sale_items_sale_fk FOREIGN KEY (sale_id) REFERENCES sales(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE sale_items ADD CONSTRAINT sale_items_product_fk FOREIGN KEY (product_id) REFERENCES products(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE journal_lines ADD CONSTRAINT journal_lines_entry_fk FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE journal_lines ADD CONSTRAINT journal_lines_account_fk FOREIGN KEY (account_code) REFERENCES chart_of_accounts(code) ON UPDATE RESTRICT ON DELETE RESTRICT;
CREATE UNIQUE INDEX products_sku_unique_nonblank ON products(sku) WHERE sku IS NOT NULL AND btrim(sku) <> '';
CREATE UNIQUE INDEX products_barcode_unique_nonblank ON products(barcode) WHERE barcode IS NOT NULL AND btrim(barcode) <> '';
SQL);

        $db->unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION btp_reject_locked_coa_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Canonical chart of accounts is locked; use a reviewed migration.'; END; $$;
CREATE TRIGGER btp_coa_immutable BEFORE UPDATE OR DELETE ON chart_of_accounts FOR EACH ROW EXECUTE FUNCTION btp_reject_locked_coa_mutation();
CREATE OR REPLACE FUNCTION btp_protect_accounting_period() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(20261022,404);
    IF TG_OP='DELETE' THEN IF OLD.status='closed' THEN RAISE EXCEPTION 'Closed periods cannot be deleted.'; END IF; RETURN OLD; END IF;
    IF TG_OP='UPDATE' AND OLD.status='closed' THEN RAISE EXCEPTION 'Closed periods are immutable.'; END IF;
    IF NEW.starts_on>NEW.ends_on THEN RAISE EXCEPTION 'Invalid period date range.'; END IF;
    IF EXISTS(SELECT 1 FROM accounting_periods p WHERE p.id<>COALESCE(NEW.id,0) AND p.starts_on<=NEW.ends_on AND p.ends_on>=NEW.starts_on) THEN RAISE EXCEPTION 'Accounting periods must not overlap.'; END IF;
    IF NEW.status='closed' THEN NEW.closed_at:=COALESCE(NEW.closed_at,clock_timestamp()); ELSE NEW.closed_at:=NULL; END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER btp_period_protection BEFORE INSERT OR UPDATE OR DELETE ON accounting_periods FOR EACH ROW EXECUTE FUNCTION btp_protect_accounting_period();
CREATE OR REPLACE FUNCTION btp_prepare_journal_posting() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p accounting_periods%ROWTYPE; original_status varchar(12);
BEGIN
    IF NEW.status<>'posted' THEN RETURN NEW; END IF;
    IF NEW.posted_by_user_id IS NULL OR NEW.posted_by_device_id IS NULL OR btrim(NEW.posted_by_device_id)='' OR NEW.app_version IS NULL OR btrim(NEW.app_version)='' THEN RAISE EXCEPTION 'Posting requires user, device and app-version audit metadata.'; END IF;
    SELECT * INTO p FROM accounting_periods WHERE NEW.journal_date BETWEEN starts_on AND ends_on FOR UPDATE;
    IF NOT FOUND OR p.status<>'open' THEN RAISE EXCEPTION 'No open accounting period for journal date %.',NEW.journal_date; END IF;
    IF NEW.accounting_period_id IS NOT NULL AND NEW.accounting_period_id<>p.id THEN RAISE EXCEPTION 'Accounting period does not match journal date.'; END IF;
    NEW.accounting_period_id:=p.id; NEW.posted_at:=COALESCE(NEW.posted_at,clock_timestamp());
    IF NEW.reversal_of_entry_id IS NOT NULL THEN
        IF NEW.reversal_reason IS NULL OR btrim(NEW.reversal_reason)='' THEN RAISE EXCEPTION 'Reversal requires correction reason.'; END IF;
        SELECT status INTO original_status FROM journal_entries WHERE id=NEW.reversal_of_entry_id FOR UPDATE;
        IF NOT FOUND OR original_status<>'posted' THEN RAISE EXCEPTION 'Only a posted journal can be reversed.'; END IF;
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER btp_prepare_posting BEFORE INSERT OR UPDATE ON journal_entries FOR EACH ROW EXECUTE FUNCTION btp_prepare_journal_posting();
CREATE OR REPLACE FUNCTION btp_reject_posted_journal_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF OLD.status='posted' THEN RAISE EXCEPTION 'Posted journals are immutable; use a reversal entry.'; END IF; IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW; END; $$;
CREATE TRIGGER btp_journal_immutable BEFORE UPDATE OR DELETE ON journal_entries FOR EACH ROW EXECUTE FUNCTION btp_reject_posted_journal_mutation();
CREATE OR REPLACE FUNCTION btp_reject_posted_line_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP<>'INSERT' AND EXISTS(SELECT 1 FROM journal_entries WHERE id=OLD.journal_entry_id AND status='posted') THEN RAISE EXCEPTION 'Posted journal lines are immutable.'; END IF;
 IF TG_OP<>'DELETE' AND EXISTS(SELECT 1 FROM journal_entries WHERE id=NEW.journal_entry_id AND status='posted') THEN RAISE EXCEPTION 'Posted journal lines are immutable.'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END; $$;
CREATE TRIGGER btp_journal_lines_immutable BEFORE INSERT OR UPDATE OR DELETE ON journal_lines FOR EACH ROW EXECUTE FUNCTION btp_reject_posted_line_mutation();
CREATE OR REPLACE FUNCTION btp_enforce_posted_journal_integrity() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE n bigint; deb numeric; cred numeric; pstatus varchar(10);
BEGIN
 IF NEW.status<>'posted' THEN RETURN NULL; END IF;
 SELECT count(*),COALESCE(sum(debit),0),COALESCE(sum(credit),0) INTO n,deb,cred FROM journal_lines WHERE journal_entry_id=NEW.id;
 IF n<2 OR deb<=0 OR deb<>cred THEN RAISE EXCEPTION 'Posted journal must have two or more lines with equal positive debit and credit totals.'; END IF;
 SELECT status INTO pstatus FROM accounting_periods WHERE id=NEW.accounting_period_id;
 IF pstatus IS DISTINCT FROM 'open' THEN RAISE EXCEPTION 'Journal period is missing or closed.'; END IF;
 IF NEW.reversal_of_entry_id IS NOT NULL AND EXISTS(
   SELECT 1 FROM (SELECT account_code,sum(debit) debit,sum(credit) credit FROM journal_lines WHERE journal_entry_id=NEW.reversal_of_entry_id GROUP BY account_code) o
   FULL OUTER JOIN (SELECT account_code,sum(credit) debit,sum(debit) credit FROM journal_lines WHERE journal_entry_id=NEW.id GROUP BY account_code) r USING(account_code)
   WHERE o.account_code IS NULL OR r.account_code IS NULL OR o.debit IS DISTINCT FROM r.debit OR o.credit IS DISTINCT FROM r.credit
 ) THEN RAISE EXCEPTION 'A reversal must exactly swap debit and credit by account.'; END IF;
 INSERT INTO accounting_events(journal_entry_id,event_type,actor_user_id,device_id,app_version,occurred_at,metadata,created_at,updated_at)
 VALUES(NEW.id,'journal_posted',NEW.posted_by_user_id,NEW.posted_by_device_id,NEW.app_version,NEW.posted_at,
 jsonb_build_object('source_event_id',NEW.source_event_id,'accounting_period_id',NEW.accounting_period_id,'reversal_of_entry_id',NEW.reversal_of_entry_id),clock_timestamp(),clock_timestamp())
 ON CONFLICT(journal_entry_id,event_type) DO NOTHING;
 RETURN NULL;
END; $$;
CREATE CONSTRAINT TRIGGER btp_posted_journal_integrity AFTER INSERT OR UPDATE ON journal_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION btp_enforce_posted_journal_integrity();
CREATE OR REPLACE FUNCTION btp_reject_accounting_event_mutation() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'accounting_events is append-only.'; END; $$;
CREATE TRIGGER btp_accounting_events_immutable BEFORE UPDATE OR DELETE ON accounting_events FOR EACH ROW EXECUTE FUNCTION btp_reject_accounting_event_mutation();
CREATE OR REPLACE FUNCTION btp_reject_integrity_truncate() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'TRUNCATE is prohibited for accounting-integrity tables.'; END; $$;
CREATE TRIGGER btp_no_truncate_coa BEFORE TRUNCATE ON chart_of_accounts FOR EACH STATEMENT EXECUTE FUNCTION btp_reject_integrity_truncate();
CREATE TRIGGER btp_no_truncate_periods BEFORE TRUNCATE ON accounting_periods FOR EACH STATEMENT EXECUTE FUNCTION btp_reject_integrity_truncate();
CREATE TRIGGER btp_no_truncate_entries BEFORE TRUNCATE ON journal_entries FOR EACH STATEMENT EXECUTE FUNCTION btp_reject_integrity_truncate();
CREATE TRIGGER btp_no_truncate_lines BEFORE TRUNCATE ON journal_lines FOR EACH STATEMENT EXECUTE FUNCTION btp_reject_integrity_truncate();
CREATE TRIGGER btp_no_truncate_events BEFORE TRUNCATE ON accounting_events FOR EACH STATEMENT EXECUTE FUNCTION btp_reject_integrity_truncate();
SQL);
    }

    public function down(): void
    {
        $db=DB::connection('tenant');
        $db->unprepared(<<<'SQL'
DROP TRIGGER IF EXISTS btp_no_truncate_events ON accounting_events;
DROP TRIGGER IF EXISTS btp_no_truncate_lines ON journal_lines;
DROP TRIGGER IF EXISTS btp_no_truncate_entries ON journal_entries;
DROP TRIGGER IF EXISTS btp_no_truncate_periods ON accounting_periods;
DROP TRIGGER IF EXISTS btp_no_truncate_coa ON chart_of_accounts;
DROP FUNCTION IF EXISTS btp_reject_integrity_truncate();
DROP TRIGGER IF EXISTS btp_accounting_events_immutable ON accounting_events;
DROP FUNCTION IF EXISTS btp_reject_accounting_event_mutation();
DROP TRIGGER IF EXISTS btp_posted_journal_integrity ON journal_entries;
DROP FUNCTION IF EXISTS btp_enforce_posted_journal_integrity();
DROP TRIGGER IF EXISTS btp_journal_lines_immutable ON journal_lines;
DROP FUNCTION IF EXISTS btp_reject_posted_line_mutation();
DROP TRIGGER IF EXISTS btp_journal_immutable ON journal_entries;
DROP FUNCTION IF EXISTS btp_reject_posted_journal_mutation();
DROP TRIGGER IF EXISTS btp_prepare_posting ON journal_entries;
DROP FUNCTION IF EXISTS btp_prepare_journal_posting();
DROP TRIGGER IF EXISTS btp_period_protection ON accounting_periods;
DROP FUNCTION IF EXISTS btp_protect_accounting_period();
DROP TRIGGER IF EXISTS btp_coa_immutable ON chart_of_accounts;
DROP FUNCTION IF EXISTS btp_reject_locked_coa_mutation();
ALTER TABLE journal_lines DROP CONSTRAINT IF EXISTS journal_lines_account_fk;
ALTER TABLE journal_lines DROP CONSTRAINT IF EXISTS journal_lines_entry_fk;
ALTER TABLE sale_items DROP CONSTRAINT IF EXISTS sale_items_product_fk;
ALTER TABLE sale_items DROP CONSTRAINT IF EXISTS sale_items_sale_fk;
ALTER TABLE inventory_movements DROP CONSTRAINT IF EXISTS inventory_movements_product_fk;
ALTER TABLE inventory_lots DROP CONSTRAINT IF EXISTS inventory_lots_product_fk;
DROP INDEX IF EXISTS products_barcode_unique_nonblank;
DROP INDEX IF EXISTS products_sku_unique_nonblank;
ALTER TABLE sync_receipts DROP CONSTRAINT IF EXISTS sync_receipt_hash_check;
ALTER TABLE journal_lines DROP CONSTRAINT IF EXISTS journal_line_one_sided_amount_check;
ALTER TABLE journal_entries DROP CONSTRAINT IF EXISTS journal_entry_reversal_not_self_check;
ALTER TABLE journal_entries DROP CONSTRAINT IF EXISTS journal_entry_status_check;
ALTER TABLE inventory_movements DROP CONSTRAINT IF EXISTS inventory_movement_quantity_check;
ALTER TABLE sale_items DROP CONSTRAINT IF EXISTS sale_items_values_check;
ALTER TABLE sales DROP CONSTRAINT IF EXISTS sales_amounts_nonnegative_check;
ALTER TABLE inventory_lots DROP CONSTRAINT IF EXISTS inventory_lot_cost_check;
ALTER TABLE inventory_lots DROP CONSTRAINT IF EXISTS inventory_lot_quantities_check;
ALTER TABLE products DROP CONSTRAINT IF EXISTS products_price_nonnegative_check;
ALTER TABLE accounting_periods DROP CONSTRAINT IF EXISTS accounting_period_closed_at_check;
ALTER TABLE accounting_periods DROP CONSTRAINT IF EXISTS accounting_period_status_check;
ALTER TABLE accounting_periods DROP CONSTRAINT IF EXISTS accounting_period_dates_check;
ALTER TABLE chart_of_accounts DROP CONSTRAINT IF EXISTS coa_locked_check;
ALTER TABLE chart_of_accounts DROP CONSTRAINT IF EXISTS coa_balance_check;
ALTER TABLE chart_of_accounts DROP CONSTRAINT IF EXISTS coa_type_check;
ALTER TABLE chart_of_accounts DROP CONSTRAINT IF EXISTS coa_code_allowlist_check;
SQL);
        Schema::connection('tenant')->table('journal_entries',function(Blueprint $t):void{
            $t->dropForeign('journal_entries_accounting_period_id_foreign');
            $t->dropForeign('journal_entries_reversal_of_entry_id_foreign');
            $t->dropUnique('journal_entries_reversal_of_entry_id_unique');
            $t->dropColumn(['status','posted_at','posted_by_user_id','posted_by_device_id','app_version','accounting_period_id','reversal_of_entry_id','reversal_reason']);
        });
        Schema::connection('tenant')->dropIfExists('accounting_events');
        Schema::connection('tenant')->dropIfExists('accounting_periods');
        Schema::connection('tenant')->dropIfExists('chart_of_accounts');
        $db->unprepared(<<<'SQL'
ALTER TABLE products ALTER COLUMN price TYPE numeric(18,2) USING price::numeric(18,2);
ALTER TABLE products ALTER COLUMN price SET DEFAULT 0;
ALTER TABLE inventory_lots ALTER COLUMN unit_cost TYPE numeric(18,2) USING unit_cost::numeric(18,2);
ALTER TABLE sales ALTER COLUMN subtotal TYPE numeric(18,2) USING subtotal::numeric(18,2);
ALTER TABLE sales ALTER COLUMN tax_amount TYPE numeric(18,2) USING tax_amount::numeric(18,2);
ALTER TABLE sales ALTER COLUMN tax_amount SET DEFAULT 0;
ALTER TABLE sales ALTER COLUMN total_amount TYPE numeric(18,2) USING total_amount::numeric(18,2);
ALTER TABLE sale_items ALTER COLUMN unit_price TYPE numeric(18,2) USING unit_price::numeric(18,2);
ALTER TABLE sale_items ALTER COLUMN line_total TYPE numeric(18,2) USING line_total::numeric(18,2);
ALTER TABLE sale_items ALTER COLUMN unit_cost TYPE numeric(18,2) USING unit_cost::numeric(18,2);
ALTER TABLE sale_items ALTER COLUMN unit_cost SET DEFAULT 0;
ALTER TABLE journal_lines ALTER COLUMN debit TYPE numeric(18,2) USING debit::numeric(18,2);
ALTER TABLE journal_lines ALTER COLUMN debit SET DEFAULT 0;
ALTER TABLE journal_lines ALTER COLUMN credit TYPE numeric(18,2) USING credit::numeric(18,2);
ALTER TABLE journal_lines ALTER COLUMN credit SET DEFAULT 0;
SQL);
        $columns=['products'=>['created_at','updated_at'],'inventory_lots'=>['received_at','created_at','updated_at'],
        'sales'=>['occurred_at','created_at','updated_at'],'sale_items'=>['created_at','updated_at'],
        'inventory_movements'=>['occurred_at','created_at','updated_at'],'journal_entries'=>['created_at','updated_at'],
        'journal_lines'=>['created_at','updated_at'],'sync_receipts'=>['accepted_at','created_at','updated_at'],
        'device_configs'=>['created_at','updated_at']];
        foreach($columns as $table=>$fields) foreach($fields as $field)
            $db->statement(sprintf('ALTER TABLE "%s" ALTER COLUMN "%s" TYPE timestamp without time zone USING "%s" AT TIME ZONE \'UTC\'',$table,$field,$field));
    }
};
