<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureTenantHost
{
    public function handle(Request $request, Closure $next): Response
    {
        abort_unless(
            $request->attributes->get('host_domain_type') === 'tenant' &&
            $request->attributes->get('host_tenant') !== null &&
            is_string($request->attributes->get('host_tenant_id')),
            404
        );

        return $next($request);
    }
}
