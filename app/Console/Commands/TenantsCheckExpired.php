<?php

namespace App\Console\Commands;

use App\Models\Central\Tenant;
use Illuminate\Console\Command;

class TenantsCheckExpired extends Command
{
    protected $signature = 'tenants:check-expired';
    protected $description = 'Suspend subscriptions that have passed their expiry time.';

    public function handle(): int
    {
        $count = 0;
        Tenant::query()->with('latestSubscription')->each(function (Tenant $tenant) use (&$count): void {
            $subscription = $tenant->latestSubscription;
            if ($subscription && $subscription->expires_at && $subscription->expires_at->isPast()
                && $subscription->status !== 'suspended') {
                $subscription->forceFill(['status' => 'suspended'])->save();
                $count++;
            }
        });
        $this->info("Suspended {$count} expired tenant subscription(s).");
        return self::SUCCESS;
    }
}
