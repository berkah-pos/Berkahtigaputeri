<?php

namespace App\Http\Middleware;

use App\Services\TenantHostResolver;
use App\Services\TenantWorkerContextResetter;
use Closure;
use Illuminate\Http\Request;

final class HostDomainBoundary
{
    public function __construct(
        private readonly TenantHostResolver $resolver,
        private readonly TenantWorkerContextResetter $resetter,
    ) {
    }

    public function handle(Request $request, Closure $next): mixed
    {
        return $this->resetter->runForRequest($request, function (Request $request) use ($next): mixed {
            $context = $this->resolver->resolve($request);

            if ($context === null) {
                abort(404);
            }

            // Request-scoped state only; do not mutate global connection/config state here.
            $request->attributes->set('host_boundary', $context);

            return $next($request);
        });
    }
}
