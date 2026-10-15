<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        // A provisioner credential is used only by the explicit Artisan workbook
        // import/provisioning process, never by a web request or unrelated command.
        $command = $_SERVER['argv'][1] ?? null;
        if ($this->app->runningInConsole() && $command === 'config:import-workbook') {
            $username = (string) env('TENANT_PROVISIONER_DB_USERNAME', '');
            $password = (string) env('TENANT_PROVISIONER_DB_PASSWORD', '');

            if ($username !== '' && $password !== '') {
                config([
                    'database.connections.tenant.username' => $username,
                    'database.connections.tenant.password' => $password,
                ]);
            }
        }
    }
}
