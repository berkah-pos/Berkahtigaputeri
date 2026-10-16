<?php

namespace App\Http\Middleware;

use App\Models\Central\Tenant;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

class EnsureTenantSubscriptionIsActive
{
    public function handle(Request $request, Closure $next): Response
    {
        // The host resolver, not a request parameter or user's primary tenant,
        // determines the tenant whose entitlement controls this request.
        $tenantId = (string) $request->attributes->get('host_tenant_id', '');
        if ($tenantId === '') {
            abort(404);
        }

        $tenant = Tenant::on('central')->find($tenantId);
        if ($tenant === null || ! (bool) $tenant->is_active) {
            abort(404);
        }

        // Keep the gate aligned with EffectiveConfigResolver: the latest
        // persisted state is checked across all statuses before any tenant
        // connection is initialized. A newer suspended/cancelled/expired row
        // must not be bypassed by an older active or trial row.
        $latest = DB::connection('central')->table('subscriptions')
            ->where('tenant_id', $tenantId)
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->first(['id', 'status', 'expires_at', 'created_at']);

        if (
            $latest === null ||
            ! in_array($latest->status, ['trial', 'active'], true) ||
            ($latest->expires_at !== null && now()->greaterThanOrEqualTo($latest->expires_at))
        ) {
            return response()->json(['message' => 'Tenant subscription is inactive.'], 402);
        }

        return $next($request);
    }
}
