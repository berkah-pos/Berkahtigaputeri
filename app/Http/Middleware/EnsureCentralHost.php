<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

final class EnsureCentralHost
{
    public function handle(Request $request, Closure $next): mixed
    {
        $context = $request->attributes->get('host_boundary');

        if (! is_array($context) || ($context['type'] ?? null) !== 'central') {
            abort(404);
        }

        return $next($request);
    }
}
