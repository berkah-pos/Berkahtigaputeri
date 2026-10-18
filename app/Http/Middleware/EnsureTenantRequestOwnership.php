<?php

namespace App\Http\Middleware;

use App\Services\TenantHostResolver;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Throwable;

final class EnsureTenantRequestOwnership
{
    private const SERVICES = [
        'pos' => 'POS',
        'akuntansi' => 'AKUNTANSI',
    ];

    public function __construct(private readonly TenantHostResolver $resolver)
    {
    }

    public function handle(Request $request, Closure $next): mixed
    {
        try {
            $hostContext = $request->attributes->get('host_boundary');

            if (
                ! is_array($hostContext)
                || ($hostContext['type'] ?? null) !== 'tenant'
                || ! is_string($hostContext['tenant_id'] ?? null)
                || $hostContext['tenant_id'] === ''
                || ! is_string($hostContext['host'] ?? null)
                || $hostContext['host'] === ''
            ) {
                abort(404);
            }

            $tenantId = (string) $hostContext['tenant_id'];
            $host = (string) $hostContext['host'];

            // Re-resolve immediately before authorizing tenant access. This narrows the
            // host/domain and suspension race between routing and auth middleware.
            $currentHostContext = $this->resolver->resolve($request);

            if (
                ! is_array($currentHostContext)
                || ($currentHostContext['type'] ?? null) !== 'tenant'
                || ! is_string($currentHostContext['tenant_id'] ?? null)
                || ! hash_equals($tenantId, $currentHostContext['tenant_id'])
                || ! is_string($currentHostContext['host'] ?? null)
                || ! hash_equals($host, $currentHostContext['host'])
            ) {
                abort(404);
            }

            // Resolve bearer authentication only after host classification. Keeping
            // auth:sanctum out of route middleware prevents framework priority from
            // returning 401 before an invalid host has been rejected.
            $user = Auth::guard('sanctum')->user();

            if ($user === null) {
                return response()->json(['message' => 'Unauthenticated.'], 401);
            }

            if (
                ! (bool) $user->is_active
                || ! is_scalar($user->tenant_id)
                || ! hash_equals($tenantId, (string) $user->tenant_id)
            ) {
                abort(404);
            }

            // Re-read the membership grant so a token authenticated just before a
            // suspension/tenant reassignment cannot rely on a stale model snapshot.
            $membership = DB::connection('central')
                ->table('users')
                ->where('id', $user->getAuthIdentifier())
                ->first(['tenant_id', 'is_active']);

            if (
                $membership === null
                || ! in_array($membership->is_active, [true, 1, '1', 't', 'true'], true)
                || ! is_scalar($membership->tenant_id)
                || ! hash_equals($tenantId, (string) $membership->tenant_id)
            ) {
                abort(404);
            }

            $tenantIdHeader = $request->header('X-Tenant-ID');
            $tenantIdHeaderValues = $tenantIdHeader === null ? [] : [$tenantIdHeader];

            $this->assertSelectorsMatch($request, 'tenant_id', $tenantIdHeaderValues, $tenantId);
            $this->assertDomainSelectorsMatch($request, $host);

            $deviceId = $request->header('X-Device-ID');

            if (
                ! is_string($deviceId)
                || preg_match('/^[A-Za-z0-9][A-Za-z0-9._:-]{0,149}$/D', $deviceId) !== 1
            ) {
                abort(404);
            }

            $this->assertSelectorsMatch($request, 'device_id', [$deviceId], $deviceId);

            $serviceValues = $this->selectorValues($request, 'service');

            if ($serviceValues === []) {
                $serviceValues[] = $request->input('service');
            }

            $service = null;

            foreach ($serviceValues as $value) {
                if (! is_string($value) || $value !== trim($value)) {
                    abort(404);
                }

                $canonical = self::SERVICES[strtolower($value)] ?? null;

                if ($canonical === null || ($service !== null && $service !== $canonical)) {
                    abort(404);
                }

                $service = $canonical;
            }

            if ($service === null) {
                abort(404);
            }

            $device = DB::connection('central')
                ->table('device_registry')
                ->where('device_id', $deviceId)
                ->where('tenant_id', $tenantId)
                ->where('owner_user_id', $user->getAuthIdentifier())
                ->first();

            if (
                $device === null
                || ! in_array(strtolower((string) ($device->status ?? '')), ['active', 'enrolled'], true)
                || empty($device->registered_at)
            ) {
                abort(404);
            }

            // The latest subscription record controls access; an older active record
            // cannot override a newer suspended/cancelled/expired state.
            $subscription = DB::connection('central')
                ->table('subscriptions')
                ->where('tenant_id', $tenantId)
                ->orderByDesc('id')
                ->first();

            if (
                $subscription === null
                || ! in_array(strtolower((string) ($subscription->status ?? '')), ['active', 'trial'], true)
            ) {
                abort(404);
            }

            $expiresAt = $subscription->expires_at
                ? Carbon::parse($subscription->expires_at)
                : null;

            if (($expiresAt !== null && ! $expiresAt->isFuture()) || (strtolower($subscription->status) === 'trial' && $expiresAt === null)) {
                abort(404);
            }

            $entitled = DB::connection('central')
                ->table('tenant_services')
                ->where('tenant_id', $tenantId)
                ->whereRaw('LOWER(service) = ?', [strtolower($service)])
                ->where('enabled', true)
                ->exists();

            if (! $entitled) {
                abort(404);
            }

            $authorizedContext = [
                'tenant_id' => $tenantId,
                'device_id' => $deviceId,
                'service' => $service,
            ];

        } catch (Throwable) {
            // A single indistinguishable denial covers unknown, inactive and mismatched
            // resources. Do not include IDs, database names, or exception messages.
            abort(404);
        }

        if (! is_array($authorizedContext ?? null)) {
            abort(404);
        }

        $request->attributes->set('authorized_tenant', $authorizedContext);

        return $next($request);
    }

    private function assertDomainSelectorsMatch(Request $request, string $effectiveHost): void
    {
        $values = $this->selectorValues($request, 'domain');
        $values[] = $request->header('X-Tenant-Domain');

        foreach ($values as $value) {
            if ($value === null) {
                continue;
            }

            $normalized = $this->resolver->normalizeHostValue($value);

            if ($normalized === null || ! hash_equals($effectiveHost, $normalized)) {
                abort(404);
            }
        }
    }

    /**
     * Gather every independently supplied selector instead of relying on Laravel's
     * merged input precedence, which could hide query/body disagreement.
     *
     * @return list<mixed>
     */
    private function selectorValues(Request $request, string $key): array
    {
        $values = [];

        foreach ([$request->query->all(), $request->request->all()] as $source) {
            if (array_key_exists($key, $source)) {
                $values[] = $source[$key];
            }
        }

        if ($request->isJson()) {
            $json = $request->json()->all();

            if (array_key_exists($key, $json)) {
                $values[] = $json[$key];
            }
        }

        $routeValue = $request->route($key);

        if ($routeValue !== null) {
            $values[] = $routeValue;
        }

        return $values;
    }

    /**
     * @param list<mixed> $headerValues
     */
    private function assertSelectorsMatch(Request $request, string $key, array $headerValues, string $expected): void
    {
        $values = array_merge($this->selectorValues($request, $key), $headerValues);

        foreach ($values as $value) {
            if (! is_string($value) || ! hash_equals($expected, $value)) {
                abort(404);
            }
        }
    }
}
