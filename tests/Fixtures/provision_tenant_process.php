<?php

declare(strict_types=1);

use App\Services\PostgresTenantProvisioner;
use Illuminate\Contracts\Console\Kernel;

$root = dirname(__DIR__, 2);
require $root . '/vendor/autoload.php';

$app = require $root . '/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$tenantId = $argv[1] ?? '';
$barrierDir = $argv[2] ?? '';
$slot = $argv[3] ?? '';
$delayMilliseconds = (int) ($argv[4] ?? 0);

if (! in_array($slot, ['0', '1'], true) || ! is_dir($barrierDir)) {
    fwrite(STDERR, "Invalid concurrency test arguments.\n");
    exit(2);
}

if (file_put_contents($barrierDir . '/' . $slot . '.ready', 'ready', LOCK_EX) === false) {
    fwrite(STDERR, "Unable to signal concurrency test readiness.\n");
    exit(2);
}

$deadline = microtime(true) + 20;
while (! is_file($barrierDir . '/release')) {
    if (microtime(true) >= $deadline) {
        fwrite(STDERR, "Timed out waiting for concurrency barrier release.\n");
        exit(2);
    }
    usleep(10_000);
}

$storeCalls = 0;

try {
    $result = (new PostgresTenantProvisioner())->provision(
        $tenantId,
        function (string $key, string $password) use (&$storeCalls, $delayMilliseconds): string {
            $storeCalls++;
            if ($delayMilliseconds > 0) {
                usleep($delayMilliseconds * 1000);
            }

            // Disposable test reference only; never persist the generated password.
            return 'ci-secret-ref://' . hash('sha256', $key);
        },
        static function (string $key): void {}
    );

    fwrite(STDOUT, 'PROVISION_RESULT:' . json_encode([
        'ok' => true,
        'database' => $result['database'],
        'store_calls' => $storeCalls,
    ], JSON_THROW_ON_ERROR) . PHP_EOL);
    exit(0);
} catch (Throwable $exception) {
    fwrite(STDOUT, 'PROVISION_RESULT:' . json_encode([
        'ok' => false,
        'message' => $exception->getMessage(),
        'previous' => $exception->getPrevious()?->getMessage(),
        'store_calls' => $storeCalls,
    ], JSON_THROW_ON_ERROR) . PHP_EOL);
    exit(1);
}
