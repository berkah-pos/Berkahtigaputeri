<?php

declare(strict_types=1);

use App\Models\Central\Tenant;
use App\Services\TenantDatabaseProvisioner;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\Support\Str;

require dirname(__DIR__, 2).'/vendor/autoload.php';
$app = require dirname(__DIR__, 2).'/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$provisioner = app(TenantDatabaseProvisioner::class);
$results = [];
for ($i = 1; $i <= 2; $i++) {
    $tenantId = 'phase6-restore-'.$i.'-'.Str::lower(Str::random(8));
    $ulid = strtolower((string) Str::ulid());
    $databaseName = $provisioner->databaseName($ulid);
    $tenant = Tenant::on('central')->create([
        'id' => $tenantId,
        'template_id' => 'BASIC',
        'is_active' => true,
        'database_ulid' => $ulid,
        'tenancy_db_name' => $databaseName,
    ]);
    $provisioner->provision($tenant);
    $tenant->refresh();
    if (($tenant->database_provisioning['status'] ?? null) !== 'provisioned') {
        throw new RuntimeException('Restore fixture tenant provisioning did not complete.');
    }
    $results[] = $databaseName;
}
$output = getenv('GITHUB_OUTPUT');
if ($output === false || $output === '') {
    fwrite(STDERR, "GITHUB_OUTPUT is required.".PHP_EOL);
    exit(2);
}
file_put_contents($output, 'tenant_a_db='.$results[0].PHP_EOL.'tenant_b_db='.$results[1].PHP_EOL, FILE_APPEND);
echo "Prepared exactly two additional disposable restore tenants with canonical lowercase ULID database names.".PHP_EOL;
