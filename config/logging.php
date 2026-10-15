<?php

use Monolog\Handler\NullHandler;
use Monolog\Handler\StreamHandler;
use Monolog\Handler\SyslogUdpHandler;

return [
    'default' => env('LOG_CHANNEL', 'stderr'),
    'deprecations' => ['channel' => env('LOG_DEPRECATIONS_CHANNEL', 'null'), 'trace' => false],
    'channels' => [
        'stack' => ['driver' => 'stack', 'channels' => explode(',', env('LOG_STACK', 'stderr')), 'ignore_exceptions' => false],
        'single' => ['driver' => 'single', 'path' => storage_path('logs/laravel.log'), 'level' => env('LOG_LEVEL', 'info'), 'replace_placeholders' => true],
        'stderr' => ['driver' => 'monolog', 'level' => env('LOG_LEVEL', 'info'), 'handler' => StreamHandler::class, 'with' => ['stream' => 'php://stderr'], 'formatter' => env('LOG_STDERR_FORMATTER')],
        'syslog' => ['driver' => 'syslog', 'level' => env('LOG_LEVEL', 'info'), 'facility' => LOG_USER, 'replace_placeholders' => true],
        'errorlog' => ['driver' => 'errorlog', 'level' => env('LOG_LEVEL', 'info'), 'replace_placeholders' => true],
        'null' => ['driver' => 'monolog', 'handler' => NullHandler::class],
        'emergency' => ['path' => storage_path('logs/laravel.log')],
    ],
];
