<?php

use App\Models\Central\Tenant;
use Illuminate\Support\Facades\Schedule;

Schedule::call(function (): void {
    Tenant::query()->with('latestSubscription')->each(function (Tenant $tenant): void {
        $subscription = $tenant->latestSubscription;
        if ($subscription && $subscription->expires_at && $subscription->expires_at->isPast()) {
            $subscription->forceFill(['status' => 'suspended'])->save();
        }
    });
})->daily()->name('suspend-expired-tenants')->withoutOverlapping();
