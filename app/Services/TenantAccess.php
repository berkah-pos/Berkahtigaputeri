<?php

namespace App\Services;

use App\Models\Central\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

class TenantAccess
{
    /**
     * Membership is a distinct authority record; users.tenant_id is only
     * their default tenant selector and is not authorization by itself.
     */
    public function hasActiveMembership(?User $user): bool
    {
        if ($user === null || ! $user->is_active || $user->tenant_id === null) {
            return false;
        }

        return DB::connection('central')->table('tenant_memberships')
            ->where('user_id', $user->id)
            ->where('tenant_id', (string) $user->tenant_id)
            ->where('status', 'active')
            ->exists();
    }

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
