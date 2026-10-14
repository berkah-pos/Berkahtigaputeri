<?php

namespace App\Http\Middleware;

use App\Models\Central\Tenant;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureTenantSubscriptionIsActive
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        if (! $user) {
            return response()->json(['message' => 'Authentication required.'], 401);
        }

        $requestedTenant = (string) $request->query('tenant_id', $user->tenant_id ?? '');
        if ($requestedTenant === '') {
            return response()->json(['message' => 'Tenant membership is required.'], 403);
        }
        if (! $user->is_super_admin && $user->tenant_id !== $requestedTenant) {
            return response()->json(['message' => 'User is not assigned to this tenant.'], 403);
        }

        $tenant = Tenant::query()->find($requestedTenant);
        $subscription = $tenant?->latestSubscription;
        if (! $subscription ||
            ! in_array($subscription->status, ['trial', 'active'], true) ||
            ($subscription->expires_at && $subscription->expires_at->isPast())) {
            return response()->json(['message' => 'Tenant subscription is inactive.'], 402);
        }

        return $next($request);
    }
}
