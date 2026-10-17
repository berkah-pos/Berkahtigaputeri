<?php

namespace App\Services;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Throwable;

final class TenantHostResolver
{
    /**
     * Resolve host routing from the effective Host value only. No result is cached:
     * domain changes and tenant suspension must affect the very next request.
     *
     * @return array{type: 'central', host: string}|array{type: 'tenant', host: string, tenant_id: string}|null
     */
    public function resolve(Request $request): ?array
    {
        try {
            $host = $this->effectiveHost($request);

            if ($host === null) {
                return null;
            }

            if (in_array($host, $this->centralHosts(), true)) {
                return ['type' => 'central', 'host' => $host];
            }

            // IP literals and single-label names are never tenant domains.
            if (filter_var($host, FILTER_VALIDATE_IP) !== false || ! str_contains($host, '.')) {
                return null;
            }

            $domain = DB::connection('central')
                ->table('domains')
                ->whereRaw('LOWER(domain) = ?', [$host])
                ->first();

            if ($domain === null || ! $this->domainIsActive($domain)) {
                return null;
            }

            $tenant = DB::connection('central')
                ->table('tenants')
                ->where('id', $domain->tenant_id)
                ->first();

            if ($tenant === null || ! $this->tenantIsActive($tenant)) {
                return null;
            }

            // Never return database names or provisioning identifiers to callers.
            return [
                'type' => 'tenant',
                'host' => $host,
                'tenant_id' => (string) $tenant->id,
            ];
        } catch (Throwable) {
            // Includes malformed hosts, unavailable central DB and schema drift.
            // Do not reflect exception text or tenant metadata to an untrusted caller.
            return null;
        }
    }

    public function normalizeHostValue(mixed $value): ?string
    {
        if (! is_string($value) || $value === '' || $value !== trim($value)) {
            return null;
        }

        if (str_contains($value, ',') || str_contains($value, '/') || str_contains($value, '@')) {
            return null;
        }

        $host = strtolower($value);

        // A single final dot is a valid absolute DNS spelling; multiple dots are not.
        if (str_ends_with($host, '.')) {
            $host = substr($host, 0, -1);
        }

        if ($host === '' || str_ends_with($host, '.') || strlen($host) > 253) {
            return null;
        }

        if (filter_var($host, FILTER_VALIDATE_IP) !== false) {
            return $host;
        }

        $label = '(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)';

        return preg_match('/^'.$label.'(?:\.'.$label.')*$/D', $host) === 1
            ? $host
            : null;
    }

    private function effectiveHost(Request $request): ?string
    {
        $hasXForwardedHost = $request->headers->has('X-Forwarded-Host');
        $hasForwarded = $request->headers->has('Forwarded');

        // Forwarding metadata is never trusted merely because it is present.
        if (($hasXForwardedHost || $hasForwarded) && ! $request->isFromTrustedProxy()) {
            return null;
        }

        $forwardedHost = null;

        if ($hasXForwardedHost) {
            $raw = $request->headers->get('X-Forwarded-Host');

            // A comma-separated host chain is ambiguous for an authorization boundary.
            if (! is_string($raw) || $raw === '' || str_contains($raw, ',')) {
                return null;
            }

            $forwardedHost = $this->normalizeHostValue($raw);

            if ($forwardedHost === null) {
                return null;
            }
        }

        try {
            // Symfony only uses X-Forwarded-Host when the peer and header are trusted.
            $host = $this->normalizeHostValue($request->getHost());
        } catch (Throwable) {
            return null;
        }

        if ($host === null || ($forwardedHost !== null && $forwardedHost !== $host)) {
            return null;
        }

        if ($hasForwarded) {
            $rawForwarded = $request->headers->get('Forwarded');

            // This application does not let Forwarded override the effective Host.
            // Accept it only as a single, consistent value from a configured proxy.
            if (! is_string($rawForwarded) || str_contains($rawForwarded, ',')) {
                return null;
            }

            if (preg_match_all('/(?:^|;)\\s*host\\s*=/', $rawForwarded) !== 1) {
                return null;
            }

            if (! preg_match('/(?:^|;)\s*host=(?:"([^"]+)"|([^;\s]+))/i', $rawForwarded, $matches)) {
                return null;
            }

            $forwardedAuthority = $this->normalizeHostValue(($matches[1] ?? '') !== '' ? $matches[1] : ($matches[2] ?? ''));

            if ($forwardedAuthority === null || $forwardedAuthority !== $host) {
                return null;
            }
        }

        return $host;
    }

    /**
     * APP_URL is the existing single-host deployment contract. An optional
     * app.central_hosts array can supply additional central host aliases when the
     * deployment configuration owner enables it. Local aliases are test/dev-only.
     *
     * @return list<string>
     */
    private function centralHosts(): array
    {
        $hosts = [];
        $appUrl = (string) config('app.url', '');
        $urlHost = parse_url($appUrl, PHP_URL_HOST);

        if (is_string($urlHost)) {
            $normalized = $this->normalizeHostValue($urlHost);

            if ($normalized !== null) {
                $hosts[] = $normalized;
            }
        }

        foreach ((array) config('app.central_hosts', []) as $configuredHost) {
            $normalized = $this->normalizeHostValue($configuredHost);

            if ($normalized !== null) {
                $hosts[] = $normalized;
            }
        }

        if (app()->environment(['local', 'testing'])) {
            $hosts = array_merge($hosts, ['localhost', '127.0.0.1', '::1']);
        }

        return array_values(array_unique($hosts));
    }

    private function domainIsActive(object $domain): bool
    {
        $schema = Schema::connection('central');

        if ($schema->hasColumn('domains', 'is_active')) {
            return (bool) ($domain->is_active ?? false);
        }

        if ($schema->hasColumn('domains', 'status')) {
            return in_array(strtolower((string) ($domain->status ?? '')), ['active', 'ready'], true);
        }

        // On the current baseline, a domain row itself is the registration grant.
        // Removing/retargeting the row takes effect immediately because no cache is used.
        return true;
    }

    private function tenantIsActive(object $tenant): bool
    {
        $data = $tenant->data ?? null;

        if (is_string($data)) {
            $data = json_decode($data, true);
        } elseif (is_object($data)) {
            $data = get_object_vars($data);
        }

        if (! is_array($data)) {
            return false;
        }

        return in_array(strtolower((string) ($data['status'] ?? '')), ['active', 'ready'], true);
    }
}
