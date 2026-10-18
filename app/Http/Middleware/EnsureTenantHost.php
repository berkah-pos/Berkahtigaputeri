<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

final class EnsureTenantHost
{
    public function handle(Request $request, Closure $next): mixed
    {
        $context = $request->attributes->get('host_boundary');

        if (
            ! is_array($context)
            || ($context['type'] ?? null) !== 'tenant'
            || ! is_string($context['tenant_id'] ?? null)
            || $context['tenant_id'] === ''
        ) {
            abort(404);
        }

        return $next($request);
    }
}
