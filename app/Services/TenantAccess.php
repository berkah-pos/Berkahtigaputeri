<?php

namespace App\Services;

use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

class TenantAccess
{
    /**
     * An active tenant must exist and have a current server-side entitlement.
     * A client-supplied tenant/device identifier is never used as proof of access.
     */
    public function hasActiveSubscription(?string $tenantId): bool
    {
        if ($tenantId === null || trim($tenantId) === '') {
            return false;
        }

        $central = DB::connection('central');
        if (! $central->table('tenants')->where('id', $tenantId)->exists()) {
            return false;
        }

        $subscription = $central->table('subscriptions')
            ->where('tenant_id', $tenantId)
            ->orderByDesc('id')
            ->first();

        if ($subscription === null || ! in_array($subscription->status, ['trial', 'active'], true)) {
            return false;
        }

        return $subscription->expires_at === null
            || Carbon::parse($subscription->expires_at)->isFuture();
    }
}
