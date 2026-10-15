<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureCentralHost
{
    public function handle(Request $request, Closure $next): Response
    {
        abort_unless($request->attributes->get('host_domain_type') === 'central', 404);

        return $next($request);
    }
}
