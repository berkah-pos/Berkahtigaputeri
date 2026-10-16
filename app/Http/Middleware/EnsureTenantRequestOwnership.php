<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Stancl\Tenancy\Facades\Tenancy;
use Symfony\Component\HttpFoundation\Response;

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

        $selectors = [];
        if ($request->input('tenant_id') !== null) {
            $selectors[] = (string) $request->input('tenant_id');
        }
        if ($request->headers->has('x-tenant-id')) {
            $selectors[] = (string) $request->headers->get('x-tenant-id');
        }
        foreach ($selectors as $selector) {
            abort_unless(hash_equals($tenantId, $selector), 404);
        }

        $user = $request->user();
        abort_unless($user !== null && (bool) $user->is_active, 403, 'Active authentication is required.');

        if (! (bool) $user->is_super_admin) {
            $member = DB::connection('central')->table('tenant_memberships')
                ->where('tenant_id', $tenantId)
                ->where('user_id', $user->getAuthIdentifier())
                ->where('is_active', true)
                ->exists();
            abort_unless($member, 403, 'Active tenant membership is required.');
        }

        $deviceIds = [];
        if ($request->headers->has('x-device-id')) {
            $deviceIds[] = (string) $request->headers->get('x-device-id');
        }
        if ($request->input('device_id') !== null) {
            $deviceIds[] = (string) $request->input('device_id');
        }
        abort_if($deviceIds === [], 403, 'A registered device ID is required.');

        $deviceId = $deviceIds[0];
        foreach ($deviceIds as $providedId) {
            abort_unless(hash_equals($deviceId, $providedId), 404);
        }

        $device = DB::connection('central')->table('device_registry')
            ->where('device_id', $deviceId)
            ->where('tenant_id', $tenantId)
            ->where('status', 'active')
            ->first();
        abort_if($device === null, 404);

        if (! (bool) $user->is_super_admin) {
            abort_unless(
                $device->owner_user_id !== null &&
                (int) $device->owner_user_id === (int) $user->getAuthIdentifier(),
                404
            );
        }

        $request->attributes->set('tenant_device_id', $deviceId);

        return $next($request);
    }
}
