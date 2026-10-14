<?php

use Illuminate\\Support\\Str;

return [
    'default' => env('DB_CONNECTION', 'central'),
    'connections' => [
        'central' => [
            'driver' => 'mysql',
            'url' => env('CENTRAL_DATABASE_URL'),
            'host' => env('CENTRAL_DB_HOST', '127.0.0.1'),
            'port' => env('CENTRAL_DB_PORT', '3306'),
            'database' => env('CENTRAL_DB_DATABASE', 'berkahpos_central'),
            'username' => env('CENTRAL_DB_USERNAME', 'root'),
            'password' => env('CENTRAL_DB_PASSWORD', ''),
            'unix_socket' => env('CENTRAL_DB_SOCKET', ''),
            'charset' => 'utf8mb4',
            'collation' => 'utf8mb4_unicode_ci',
            'prefix' => '',
            'prefix_indexes' => true,
            'strict' => true,
            'engine' => null,
            'options' => extension_loaded('pdo_mysql') ? array_filter([
                PDO::MYSQL_ATTR_SSL_CA => env('MYSQL_ATTR_SSL_CA'),
            ]) : [],
        ],
        'tenant' => [
            'driver' => 'mysql',
            'host' => env('TENANT_DB_HOST', env('CENTRAL_DB_HOST', '127.0.0.1')),
            'port' => env('TENANT_DB_PORT', env('CENTRAL_DB_PORT', '3306')),
            'database' => null,
            'username' => env('TENANT_DB_USERNAME', env('CENTRAL_DB_USERNAME', 'root')),
            'password' => env('TENANT_DB_PASSWORD', env('CENTRAL_DB_PASSWORD', '')),
            'unix_socket' => env('TENANT_DB_SOCKET', ''),
            'charset' => 'utf8mb4',
            'collation' => 'utf8mb4_unicode_ci',
            'prefix' => '',
            'prefix_indexes' => true,
            'strict' => true,
            'engine' => null,
            'options' => extension_loaded('pdo_mysql') ? array_filter([
                PDO::MYSQL_ATTR_SSL_CA => env('MYSQL_ATTR_SSL_CA'),
            ]) : [],
        ],
    ],
    'migrations' => 'migrations',
    'redis' => [
        'client' => env('REDIS_CLIENT', 'phpredis'),
        'options' => ['cluster' => env('REDIS_CLUSTER', 'redis'), 'prefix' => env('REDIS_PREFIX', Str::slug(env('APP_NAME', 'berkah-pos')).'-database-')],
        'default' => ['url' => env('REDIS_URL'), 'host' => env('REDIS_HOST', '127.0.0.1'), 'username' => env('REDIS_USERNAME'), 'password' => env('REDIS_PASSWORD'), 'port' => env('REDIS_PORT', '6379'), 'database' => env('REDIS_DB', '0')],
        'cache' => ['url' => env('REDIS_URL'), 'host' => env('REDIS_HOST', '127.0.0.1'), 'username' => env('REDIS_USERNAME'), 'password' => env('REDIS_PASSWORD'), 'port' => env('REDIS_PORT', '6379'), 'database' => env('REDIS_CACHE_DB', '1')],
    ],
];
