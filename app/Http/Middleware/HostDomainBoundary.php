<?php

namespace App\Http\Middleware;

use App\Services\TenantHostResolver;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class HostDomainBoundary
{
    public function __construct(private readonly TenantHostResolver $resolver)
    {
    }

    public function handle(Request $request, Closure $next): Response
    {
        // Host is the boundary selector. Forwarded headers never select a tenant.
        $host = $this->resolver->normalizeHost((string) $request->headers->get('host', ''));
        abort_if($host === null, 404);

        $forwardedHost = $request->headers->get('x-forwarded-host');
        if ($forwardedHost !== null) {
            $normalizedForwardedHost = $this->resolver->normalizeHost((string) $forwardedHost);
            abort_if($normalizedForwardedHost === null || $normalizedForwardedHost !== $host, 404);
        }

        $centralDomains = array_values(array_filter(array_map(
            fn (string $configuredHost): ?string => $this->resolver->normalizeHost($configuredHost),
            (array) config('tenancy.central_domains', [])
        )));

        $request->attributes->set('host_domain', $host);
        if (in_array($host, $centralDomains, true)) {
            $request->attributes->set('host_domain_type', 'central');
            $request->attributes->set('host_tenant_id', null);
            $request->attributes->set('host_tenant', null);

            return $next($request);
        }

        $tenant = $this->resolver->resolveActiveTenant($host);
        abort_if($tenant === null, 404);

        $request->attributes->set('host_domain_type', 'tenant');
        $request->attributes->set('host_tenant_id', (string) $tenant->getTenantKey());
        $request->attributes->set('host_tenant', $tenant);

        return $next($request);
    }
}
