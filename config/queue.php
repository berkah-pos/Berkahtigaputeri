<?php

return [
    'default' => env('QUEUE_CONNECTION', 'sync'),
    'connections' => [
        'sync' => ['driver' => 'sync'],
        'database' => [
            'driver' => 'database',
            'connection' => 'central',
            'table' => 'jobs',
            'queue' => env('DB_QUEUE', 'default'),
            'retry_after' => 90,
            'after_commit' => true,
        ],
    ],
    'batching' => [
        'database' => env('DB_CONNECTION', 'central'),
        'table' => 'job_batches',
    ],
    'failed' => [
        'driver' => env('QUEUE_FAILED_DRIVER', 'database-uuids'),
        'database' => env('DB_CONNECTION', 'central'),
        'table' => 'failed_jobs',
    ],
];
