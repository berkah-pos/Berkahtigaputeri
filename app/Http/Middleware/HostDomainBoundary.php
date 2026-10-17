<?php

namespace App\Http\Middleware;

use App\Services\TenantHostResolver;
use Closure;
use Illuminate\Http\Request;

final class HostDomainBoundary
{
    public function __construct(private readonly TenantHostResolver $resolver)
    {
    }

    public function handle(Request $request, Closure $next): mixed
    {
        $context = $this->resolver->resolve($request);

        if ($context === null) {
            abort(404);
        }

        // Host identity is request-scoped. Do not mutate process-global tenant,
        // DB, cache, filesystem, or auth state here: concurrent requests can overlap.
        $request->attributes->set('host_boundary', $context);

        try {
            return $next($request);
        } finally {
            $request->attributes->remove('host_boundary');
        }
    }
}
