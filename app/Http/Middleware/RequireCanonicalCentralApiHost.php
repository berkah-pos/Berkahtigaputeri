<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

final class RequireCanonicalCentralApiHost
{
    public function handle(Request $request, Closure $next): Response
    {
        $configured = parse_url((string) config('app.url'), PHP_URL_HOST);

        if (! is_string($configured) || $configured === '') {
            return response()->json(['error' => 'not_found'], 404);
        }

        $expectedHost = strtolower(rtrim($configured, '.'));
        $requestHost = strtolower(rtrim($request->getHost(), '.'));
        if (app()->environment('production') && in_array($expectedHost, ['localhost', '127.0.0.1', '::1'], true)) {
            return response()->json(['error' => 'not_found'], 404);
        }

        if ($expectedHost === '' || $requestHost !== $expectedHost) {
            return response()->json(['error' => 'not_found'], 404);
        }

        return $next($request);
    }
}
