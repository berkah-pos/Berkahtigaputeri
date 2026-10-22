<?php

namespace Tests\Feature;

use App\Models\Central\AuditEvent;
use App\Models\Central\DeviceRegistry;
use App\Models\Central\Domain;
use App\Models\Central\GlobalConfig;
use App\Models\Central\Subscription;
use App\Models\Central\Tenant;
use App\Models\Central\TenantConfig;
use App\Models\Central\Template;
use App\Models\Central\User;
use App\Models\Tenant\AccountingEvent;
use App\Models\Tenant\AccountingPeriod;
use App\Models\Tenant\ChartOfAccount;
use App\Models\Tenant\DeviceConfig;
use App\Models\Tenant\InventoryLot;
use App\Models\Tenant\InventoryMovement;
use App\Models\Tenant\JournalEntry;
use App\Models\Tenant\JournalLine;
use App\Models\Tenant\Product;
use App\Models\Tenant\Sale;
use App\Models\Tenant\SaleItem;
use App\Models\Tenant\SyncReceipt;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class PostgresSchemaIntegrityTest extends TestCase
{
    public function test_eloquent_models_and_connections_are_explicit_and_separate(): void
    {
        foreach ([Tenant::class,Domain::class,User::class,DeviceRegistry::class,GlobalConfig::class,Subscription::class,TenantConfig::class,Template::class,AuditEvent::class] as $model)
            $this->assertSame('central',(new $model())->getConnectionName(),$model);
        foreach ([DeviceConfig::class,Product::class,InventoryLot::class,InventoryMovement::class,Sale::class,SaleItem::class,JournalEntry::class,JournalLine::class,SyncReceipt::class,ChartOfAccount::class,AccountingPeriod::class,AccountingEvent::class] as $model)
            $this->assertSame('tenant',(new $model())->getConnectionName(),$model);
        $this->assertSame('pgsql',DB::connection('central')->getDriverName());
        $this->assertSame('pgsql',DB::connection('tenant')->getDriverName());
        $this->assertNotSame(DB::connection('central')->getDatabaseName(),DB::connection('tenant')->getDatabaseName());
    }

    public function test_money_is_bigint_rupiah_and_stock_quantity_remains_scale_three(): void
    {
        $cols=DB::connection('tenant')->table('information_schema.columns')->select(['table_name','column_name','data_type','numeric_scale'])
            ->where('table_schema','public')->whereIn('table_name',['products','inventory_lots','sales','sale_items','journal_lines'])->get()->keyBy(fn($c)=>$c->table_name.'.'.$c->column_name);
        foreach(['products.price','inventory_lots.unit_cost','sales.subtotal','sales.tax_amount','sales.total_amount','sale_items.unit_price','sale_items.line_total','sale_items.unit_cost','journal_lines.debit','journal_lines.credit'] as $key)
            $this->assertSame('bigint',$cols[$key]->data_type ?? null,$key);
        $this->assertSame('numeric',$cols['inventory_lots.quantity_received']->data_type ?? null);
        $this->assertSame(3,(int)$cols['inventory_lots.quantity_received']->numeric_scale);
        $this->assertSame(3,(int)$cols['sale_items.quantity']->numeric_scale);
    }

    public function test_the_locked_coa_contains_exactly_the_24_approved_codes(): void
    {
        $expected=['1-1010','1-1020','1-1030','1-1040','1-1050','1-1060','1-1070','2-2010','2-2020','2-2030','3-3010','3-3020','3-3030','4-4010','4-4020','4-4030','4-4040','5-5010','6-6010','6-6020','6-6030','6-6040','6-6050','6-6060'];
        sort($expected);
        $this->assertSame($expected,DB::connection('tenant')->table('chart_of_accounts')->orderBy('code')->pluck('code')->all());
        $this->assertSame(24,DB::connection('tenant')->table('chart_of_accounts')->where('is_locked',true)->count());
        $this->assertRejected(fn()=>DB::connection('tenant')->table('chart_of_accounts')->where('code','1-1040')->update(['name'=>'tampered']));
        $this->assertSame('Persediaan Barang',DB::connection('tenant')->table('chart_of_accounts')->where('code','1-1040')->value('name'));
    }

    public function test_central_schema_rejects_bad_template_and_noncanonical_domain(): void
    {
        $this->assertRejected(fn()=>DB::connection('central')->table('tenants')->insert(['id'=>'invalid-'.Str::random(12),'template_id'=>'UNKNOWN','created_at'=>now()->utc(),'updated_at'=>now()->utc()]));
        $this->assertRejected(fn()=>DB::connection('central')->table('domains')->insert(['domain'=>'MixedCase.Example.com','tenant_id'=>'missing-tenant','created_at'=>now()->utc(),'updated_at'=>now()->utc()]));
    }

    public function test_operational_fk_and_amount_checks_reject_invalid_rows(): void
    {
        $this->assertRejected(fn()=>DB::connection('tenant')->table('products')->insert(['id'=>'negative-'.Str::random(10),'name'=>'bad','price'=>-1,'created_at'=>now()->utc(),'updated_at'=>now()->utc()]));
        $id='sale-'.Str::random(12); $now=now()->utc();
        DB::connection('tenant')->table('sales')->insert(['id'=>$id,'device_id'=>'schema-test-device','status'=>'accepted','payment_method'=>'cash','subtotal'=>100,'tax_amount'=>0,'total_amount'=>100,'occurred_at'=>$now,'created_at'=>$now,'updated_at'=>$now]);
        $this->assertRejected(fn()=>DB::connection('tenant')->table('sale_items')->insert(['sale_id'=>$id,'product_id'=>'missing-product','product_name'=>'missing','quantity'=>'1.000','unit_price'=>100,'line_total'=>100,'unit_cost'=>0,'created_at'=>$now,'updated_at'=>$now]));
        DB::connection('tenant')->table('sales')->where('id',$id)->delete();
    }

    public function test_unbalanced_journal_is_rejected_at_commit(): void
    {
        $this->expectException(QueryException::class);
        $this->postJournal((string)Str::uuid(),'2001-02-10',null,null,[['1-1010',10000,0],['4-4010',0,9000]]);
    }

    public function test_balanced_posting_is_audited_and_posted_rows_are_immutable(): void
    {
        $id=(string)Str::uuid();
        $this->postJournal($id,'2001-01-10',null,null,[['1-1010',10000,0],['4-4010',0,10000]]);
        $this->assertSame(1,DB::connection('tenant')->table('accounting_events')->where('journal_entry_id',$id)->where('event_type','journal_posted')->count());
        $this->assertRejected(fn()=>DB::connection('tenant')->table('journal_entries')->where('id',$id)->update(['description'=>'tampered']));
        $this->assertRejected(fn()=>DB::connection('tenant')->table('journal_lines')->insert(['journal_entry_id'=>$id,'account_code'=>'1-1010','debit'=>1,'credit'=>0,'created_at'=>now()->utc(),'updated_at'=>now()->utc()]));
        $this->assertRejected(fn()=>DB::connection('tenant')->table('accounting_events')->where('journal_entry_id',$id)->delete());
    }

    public function test_reversal_must_exactly_swap_debits_and_credits_per_account(): void
    {
        $id=(string)Str::uuid();
        $this->postJournal($id,'2001-01-11',null,null,[['1-1010',2500,0],['4-4010',0,2500]]);
        $this->expectException(QueryException::class);
        $this->postJournal((string)Str::uuid(),'2001-01-12',$id,'Correct erroneous posting',[['1-1010',2500,0],['4-4010',0,2500]]);
    }

    public function test_closed_period_cannot_be_changed_or_used_for_posting(): void
    {
        $pid=$this->ensurePeriod('schema-test-closed-2001-03','2001-03-01','2001-03-31');
        if(DB::connection('tenant')->table('accounting_periods')->where('id',$pid)->value('status')!=='closed')
            DB::connection('tenant')->table('accounting_periods')->where('id',$pid)->update(['status'=>'closed']);
        $this->assertRejected(fn()=>DB::connection('tenant')->table('accounting_periods')->where('id',$pid)->update(['ends_on'=>'2001-03-30']));
        $this->expectException(QueryException::class);
        $this->postJournal((string)Str::uuid(),'2001-03-10',null,null,[['1-1010',100,0],['4-4010',0,100]]);
    }

    public function test_period_ranges_must_not_overlap(): void
    {
        $this->ensurePeriod('schema-test-overlap-base-2001-04','2001-04-01','2001-04-30');
        $this->assertRejected(fn()=>DB::connection('tenant')->table('accounting_periods')->insert(['period_key'=>'overlap-'.Str::random(8),'starts_on'=>'2001-04-15','ends_on'=>'2001-05-15','status'=>'open','created_at'=>now()->utc(),'updated_at'=>now()->utc()]));
    }

    public function test_central_audit_events_reject_update_delete_and_truncate(): void
    {
        $id=DB::connection('central')->table('audit_events')->insertGetId(['scope_type'=>'test','scope_id'=>(string)Str::uuid(),'action'=>'created','metadata'=>json_encode(['test'=>true]),'created_at'=>now()->utc()]);
        $this->assertRejected(fn()=>DB::connection('central')->table('audit_events')->where('id',$id)->update(['action'=>'tampered']));
        $this->assertRejected(fn()=>DB::connection('central')->table('audit_events')->where('id',$id)->delete());
        $this->assertRejected(fn()=>DB::connection('central')->table('audit_events')->truncate());
    }

    private function postJournal(string $id,string $date,?string $reversal,?string $reason,array $lines): void
    {
        $period=DB::connection('tenant')->table('accounting_periods')->where('starts_on','<=',$date)->where('ends_on','>=',$date)->first();
        if(!$period){$month=substr($date,0,7);$periodId=$this->ensurePeriod('schema-test-period-'.str_replace('-','',$month),$month.'-01',date('Y-m-t',strtotime($date)));} else {$periodId=(int)$period->id;}
        $now=now()->utc();
        DB::connection('tenant')->transaction(function() use($id,$date,$reversal,$reason,$lines,$periodId,$now):void{
            DB::connection('tenant')->table('journal_entries')->insert(['id'=>$id,'source_event_id'=>'schema-event-'.$id,'description'=>$reversal?'reversal test':'journal test','journal_date'=>$date,'status'=>'posted','posted_by_user_id'=>1,'posted_by_device_id'=>'schema-test-device','app_version'=>'schema-test/1','accounting_period_id'=>$periodId,'reversal_of_entry_id'=>$reversal,'reversal_reason'=>$reason,'created_at'=>$now,'updated_at'=>$now]);
            foreach($lines as [$account,$debit,$credit]) DB::connection('tenant')->table('journal_lines')->insert(['journal_entry_id'=>$id,'account_code'=>$account,'debit'=>$debit,'credit'=>$credit,'created_at'=>$now,'updated_at'=>$now]);
        },1);
    }

    private function ensurePeriod(string $key,string $start,string $end): int
    {
        $row=DB::connection('tenant')->table('accounting_periods')->where('period_key',$key)->first();
        if($row)return (int)$row->id;
        return (int)DB::connection('tenant')->table('accounting_periods')->insertGetId(['period_key'=>$key,'starts_on'=>$start,'ends_on'=>$end,'status'=>'open','created_at'=>now()->utc(),'updated_at'=>now()->utc()]);
    }

    private function assertRejected(callable $fn): void
    {
        try{$fn();$this->fail('PostgreSQL accepted an operation that violates schema integrity.');}
        catch(QueryException){$this->assertTrue(true);}
    }
}
