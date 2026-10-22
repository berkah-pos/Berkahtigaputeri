<?php
return [
    'default' => env('DB_CONNECTION', 'central'),
    'connections' => [
        'central' => [
            'driver' => 'pgsql',
            'url' => env('CENTRAL_DB_URL', env('DATABASE_URL')),
            'host' => env('CENTRAL_DB_HOST', env('DB_HOST', '127.0.0.1')),
            'port' => env('CENTRAL_DB_PORT', env('DB_PORT', '5432')),
            'database' => env('CENTRAL_DB_DATABASE', env('DB_DATABASE', 'berkahpos_central')),
            'username' => env('CENTRAL_DB_USERNAME', env('DB_USERNAME', 'postgres')),
            'password' => env('CENTRAL_DB_PASSWORD', env('DB_PASSWORD', '')),
            'charset' => 'utf8', 'prefix' => '', 'prefix_indexes' => true,
            'search_path' => env('CENTRAL_DB_SCHEMA', 'public'),
            'sslmode' => env('CENTRAL_DB_SSLMODE', env('DB_SSLMODE', 'prefer')),
        ],
        'tenant' => [
            'driver' => 'pgsql',
            'url' => env('TENANT_DB_URL'),
            // Never inherit central connection host, database, or credentials.
            'host' => env('TENANT_DB_HOST', '127.0.0.1'),
            'port' => env('TENANT_DB_PORT', '5432'),
            'database' => env('TENANT_DB_DATABASE', 'berkahpos_tenant_unconfigured'),
            'username' => env('TENANT_DB_USERNAME', 'berkahpos_tenant_runtime'),
            'password' => env('TENANT_DB_PASSWORD', ''),
            'charset' => 'utf8', 'prefix' => '', 'prefix_indexes' => true,
            'search_path' => env('TENANT_DB_SCHEMA', 'public'),
            'sslmode' => env('TENANT_DB_SSLMODE', 'prefer'),
        ],
    ],
    'migrations' => ['table' => 'migrations', 'update_date_on_publish' => true],
];
