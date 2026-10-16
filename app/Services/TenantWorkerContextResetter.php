<?php

namespace App\Services;

use Illuminate\Support\Facades\Auth;
use Stancl\Tenancy\Facades\Tenancy;

class TenantWorkerContextResetter
{
    private array $baseline;

    public function __construct()
    {
        $this->baseline = [
            'database' => config('database'),
            'cache' => config('cache'),
            'guard' => (string) config('auth.defaults.guard', 'web'),
            'locale' => (string) config('app.locale', 'en'),
        ];
    }

    public function reset(): void
    {
        try {
            if (Tenancy::initialized()) {
                Tenancy::end();
            }
        } finally {
            $databaseManager = app('db');
            foreach (array_keys($databaseManager->getConnections()) as $connectionName) {
                $databaseManager->purge($connectionName);
            }

            config([
                'database' => $this->baseline['database'],
                'cache' => $this->baseline['cache'],
                'auth.defaults.guard' => $this->baseline['guard'],
                'app.locale' => $this->baseline['locale'],
            ]);

            Auth::forgetGuards();
            Auth::shouldUse($this->baseline['guard']);

            $cacheManager = app('cache');
            if (method_exists($cacheManager, 'forgetDriver')) {
                foreach (array_keys($this->baseline['cache']['stores'] ?? []) as $storeName) {
                    $cacheManager->forgetDriver($storeName);
                }
            }
        }
    }
}
