<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Stancl\Tenancy\Facades\Tenancy;
use Symfony\Component\HttpFoundation\Response;

class InitializeTenantContext
{
    public function handle(Request $request, Closure $next): Response
    {
        $tenant = $request->attributes->get('host_tenant');
        abort_unless($tenant !== null, 404);

        try {
            Tenancy::initialize($tenant);

            return $next($request);
        } finally {
            if (Tenancy::initialized()) {
                Tenancy::end();
            }
        }
    }
}
