<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

final class ApiRequestContext
{
    private const REQUEST_ID_ATTRIBUTE = 'api_request_id';

    private const REQUEST_ID_HEADER = 'X-Request-ID';

    private const UUID_PATTERN = '/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/iD';

    public function handle(Request $request, Closure $next): Response
    {
        if (! $request->is('api', 'api/*')) {
            return $next($request);
        }

        $requestId = self::ensureRequestId($request);
        $response = $next($request);

        $response->headers->set(self::REQUEST_ID_HEADER, $requestId);
        $response->headers->set('Cache-Control', 'no-store, private');
        $response->headers->set('X-Content-Type-Options', 'nosniff');

        return $response;
    }

    /**
     * Return one safe request identifier for both successful and exception responses.
     *
     * Only canonical UUID-shaped caller values are retained. Arbitrary values are
     * replaced so request IDs cannot inject response headers or unbounded log data.
     */
    public static function ensureRequestId(Request $request): string
    {
        $existing = $request->attributes->get(self::REQUEST_ID_ATTRIBUTE);

        if (is_string($existing) && self::isUuid($existing)) {
            return strtolower($existing);
        }

        $candidate = $request->headers->get(self::REQUEST_ID_HEADER);

        $requestId = is_string($candidate) && self::isUuid($candidate)
            ? strtolower($candidate)
            : (string) Str::uuid();

        $request->attributes->set(self::REQUEST_ID_ATTRIBUTE, $requestId);

        return $requestId;
    }

    private static function isUuid(string $value): bool
    {
        return preg_match(self::UUID_PATTERN, $value) === 1;
    }
}
