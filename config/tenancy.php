<?php

use App\Models\Central\Domain;
use App\Models\Central\Tenant;
use App\Database\TenantDatabaseManager;
use Stancl\Tenancy\Bootstrappers\DatabaseTenancyBootstrapper;

return [
    'tenant_model' => Tenant::class,
    'id_generator' => null,
    'domain_model' => Domain::class,
    'central_domains' => array_values(array_filter(array_map(
        'trim',
        explode(',', env('CENTRAL_DOMAINS', 'berkahtigaputeri.co.id,app.berkahtigaputeri.co.id'))
    ))),
    'bootstrappers' => [
        DatabaseTenancyBootstrapper::class,
    ],
    // TenantCreated is handled by AppServiceProvider and a durable queued job.
    // Never run database creation/migrations synchronously in a public request.
    'database' => [
        'central_connection' => 'central',
        'template_tenant_connection' => 'tenant_template',
        'prefix' => env('TENANT_DB_PREFIX', 'berkahpos_tenant_'),
        'suffix' => '',
        'managers' => [
            'mysql' => TenantDatabaseManager::class,
        ],
    ],
    'migration_parameters' => [
        '--force' => true,
        '--path' => [database_path('migrations/tenant')],
        '--realpath' => true,
    ],
    'seeder_parameters' => [
        '--class' => 'Database\\Seeders\\TenantDatabaseSeeder',
        '--force' => true,
    ],
];
