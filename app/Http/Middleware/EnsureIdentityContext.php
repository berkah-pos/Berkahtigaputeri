<?php

namespace App\Http\Middleware;

use App\Models\Central\DeviceRegistry;
use App\Models\Central\PersonalAccessToken;
use App\Models\Central\TenantMembership;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureIdentityContext
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        $token = $user?->currentAccessToken();

        if (! $user || ! $user->is_active || ! $token instanceof PersonalAccessToken || ! $token->can('*')) {
            return $this->denied();
        }

        $tenantId = $token->tenant_id;
        $deviceId = $token->device_id;

        // Request values may constrain the already-authenticated identity, never set it.
        if (! $tenantId || ! $deviceId ||
            ($request->header('X-Tenant-ID') !== null && $request->header('X-Tenant-ID') !== $tenantId) ||
            ($request->header('X-Device-ID') !== null && $request->header('X-Device-ID') !== $deviceId)) {
            return $this->denied();
        }

        $membershipIsActive = TenantMembership::query()
            ->where('user_id', $user->getAuthIdentifier())
            ->where('tenant_id', $tenantId)
            ->where('status', 'active')
            ->whereHas('tenant', fn ($query) => $query->where('status', 'active'))
            ->exists();

        $device = DeviceRegistry::query()
            ->where('device_id', $deviceId)
            ->where('tenant_id', $tenantId)
            ->where('owner_user_id', $user->getAuthIdentifier())
            ->where('status', 'active')
            ->whereNull('revoked_at')
            ->first();

        if (! $membershipIsActive || ! $device || ! $device->device_secret_hash) {
            return $this->denied();
        }

        $device->forceFill(['last_seen_at' => now()])->save();
        $request->attributes->set('identity.user_id', $user->getAuthIdentifier());
        $request->attributes->set('identity.tenant_id', $tenantId);
        $request->attributes->set('identity.device_id', $deviceId);

        return $next($request);
    }

    private function denied(): JsonResponse
    {
        return response()->json([
            'message' => 'Identitas tenant atau perangkat tidak memiliki akses aktif.',
            'code' => 'identity_context_denied',
        ], 403);
    }
}
