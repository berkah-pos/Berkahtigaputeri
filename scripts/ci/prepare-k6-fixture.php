<?php

declare(strict_types=1);

use App\Models\Central\DeviceRegistry;
use App\Models\Central\Tenant;
use App\Models\Central\User;
use App\Services\TenantDatabaseProvisioner;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Stancl\Tenancy\Facades\Tenancy;

require dirname(__DIR__, 2).'/vendor/autoload.php';
$app = require dirname(__DIR__, 2).'/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$tenantId = 'phase6-k6-'.Str::lower(Str::random(10));
$databaseUlid = strtolower((string) Str::ulid());
$databaseName = 'berkahpos_t_'.$databaseUlid;
$tenant = Tenant::on('central')->create([
    'id' => $tenantId,
    'template_id' => 'BASIC',
    'is_active' => true,
    'database_ulid' => $databaseUlid,
    'tenancy_db_name' => $databaseName,
]);
app(TenantDatabaseProvisioner::class)->provision($tenant);
$tenant->refresh();

DB::connection('central')->table('tenant_services')->updateOrInsert(
    ['tenant_id' => $tenantId, 'service' => 'pos'],
    ['enabled' => true, 'created_at' => now(), 'updated_at' => now()]
);

$suffix = Str::lower(Str::random(8));
$user = User::on('central')->create([
    'name' => 'Phase 6 k6 fixture',
    'email' => 'phase6-k6-'.$suffix.'@example.test',
    'password' => Hash::make(Str::random(48)),
    'tenant_id' => $tenantId,
    'is_super_admin' => false,
    'is_active' => true,
]);
DB::connection('central')->table('tenant_memberships')->insert([
    'tenant_id' => $tenantId,
    'user_id' => $user->getAuthIdentifier(),
    'is_active' => true,
    'role' => 'member',
    'created_at' => now(),
    'updated_at' => now(),
]);

$devicePrefix = 'phase6-k6-device-'.$suffix.'-';
for ($i = 1; $i <= 50; $i++) {
    DeviceRegistry::on('central')->create([
        'device_id' => $devicePrefix.$i,
        'tenant_id' => $tenantId,
        'owner_user_id' => $user->getAuthIdentifier(),
        'status' => 'active',
        'registered_at' => now(),
    ]);
}

$productId = 'phase6-k6-product-'.$suffix;
Tenancy::initialize($tenant);
try {
    $now = now();
    DB::connection('tenant')->table('products')->insert([
        'id' => $productId,
        'name' => 'Synthetic k6 fixture product',
        'price' => 1000,
        'is_active' => true,
        'requires_review' => false,
        'created_at' => $now,
        'updated_at' => $now,
    ]);
    DB::connection('tenant')->table('inventory_lots')->insert([
        'id' => 'phase6-k6-lot-'.$suffix,
        'product_id' => $productId,
        'batch_code' => 'PHASE6-K6',
        'expires_at' => '2099-12-31',
        'quantity_received' => 100000,
        'quantity_remaining' => 100000,
        'unit_cost' => 250,
        'received_at' => $now,
        'created_at' => $now,
        'updated_at' => $now,
    ]);
    DB::connection('tenant')->table('cost_layers')->insert([
        'id' => 'phase6-k6-cost-'.$suffix,
        'product_id' => $productId,
        'quantity_remaining' => 100000,
        'unit_cost' => 250,
        'received_at' => $now,
        'created_at' => $now,
        'updated_at' => $now,
    ]);
} finally {
    Tenancy::end();
    DB::purge('tenant');
}

$token = $user->createToken('phase6-k6-smoke', ['sync:write'])->plainTextToken;
echo "::add-mask::".$token.PHP_EOL;
$output = getenv('GITHUB_OUTPUT');
if ($output === false || $output === '') {
    fwrite(STDERR, "GITHUB_OUTPUT is required; refusing to print bearer tokens to standard output.".PHP_EOL);
    exit(2);
}
file_put_contents($output, implode(PHP_EOL, [
    'tenant_id='.$tenantId,
    'device_prefix='.$devicePrefix,
    'k6_token='.$token,
    'product_id='.$productId,
]).PHP_EOL, FILE_APPEND);
echo "Prepared disposable KVM2 CI fixture with one tenant, one product, 50 registered devices and a temporary sync:write token.".PHP_EOL;
