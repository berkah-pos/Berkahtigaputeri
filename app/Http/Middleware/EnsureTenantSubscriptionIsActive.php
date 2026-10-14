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
        if (! $user || ! $user->tenant_id) {
            return response()->json(['message' => 'Tenant membership is required.'], 403);
        }

        $tenant = Tenant::query()->find($user->tenant_id);
        $subscription = $tenant?->latestSubscription;
        if (! $subscription ||
            ! in_array($subscription->status, ['trial', 'active'], true) ||
            ($subscription->expires_at && $subscription->expires_at->isPast())) {
            return response()->json(['message' => 'Tenant subscription is inactive.'], 402);
        }

        return $next($request);
    }
}
