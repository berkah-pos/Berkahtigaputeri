<?php

use App\\Models\\Central\\Domain;
use App\\Models\\Central\\Tenant;
use Stancl\\Tenancy\\Bootstrappers\\DatabaseTenancyBootstrapper;
use Stancl\\Tenancy\\Events\\TenantCreated;
use Stancl\\Tenancy\\Jobs\\CreateDatabase;
use Stancl\\Tenancy\\Jobs\\MigrateDatabase;
use Stancl\\JobPipeline\\JobPipeline;

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
    'database' => [
        'central_connection' => 'central',
        'template_tenant_connection' => 'tenant',
        'prefix' => env('TENANT_DB_PREFIX', 'berkahpos_tenant_'),
        'suffix' => '',
        'managers' => [
            'mysql' => Stancl\\Tenancy\\TenantDatabaseManagers\\MySQLDatabaseManager::class,
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
