<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Stancl\Tenancy\Facades\Tenancy;
use Symfony\Component\HttpFoundation\Response;

/**
 * Post-initialization consistency check only. Identity/membership/device
 * authorization is performed by EnsureTenantRequestPrincipal before the
 * tenant database bootstrapper is entered.
 */
class EnsureTenantRequestOwnership
{
    public function handle(Request $request, Closure $next): Response
    {
        $tenantId = (string) $request->attributes->get('host_tenant_id', '');
        $activeTenant = Tenancy::tenant();

        abort_unless(
            $tenantId !== '' &&
            $activeTenant !== null &&
            (string) $activeTenant->getTenantKey() === $tenantId,
            404
        );

        abort_unless(
            $request->attributes->get('tenant_principal_authorized') === true &&
            is_string($request->attributes->get('tenant_device_id')),
            403,
            'Tenant request authorization is required.'
        );

        return $next($request);
    }
}
