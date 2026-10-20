<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Central\User;
use App\Services\TenantAccess;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class DeviceController extends Controller
{
    public function enroll(Request $request, TenantAccess $tenantAccess): JsonResponse
    {
        $validated = $request->validate([
            'device_id' => ['required', 'string', 'min:3', 'max:150', 'regex:/^[A-Za-z0-9_.:-]+$/'],
        ]);

        $user = $request->user();
        if (! $user instanceof User || ! $user->is_active) {
            return response()->json(['error' => ['code' => 'inactive_user']], 401);
        }

        $tenantId = $user->tenant_id === null ? '' : (string) $user->tenant_id;
        if (! $tenantAccess->hasActiveSubscription($tenantId)) {
            return response()->json(['error' => ['code' => 'tenant_not_entitled']], 403);
        }

        $deviceId = $validated['device_id'];
        $central = DB::connection('central');

        $result = $central->transaction(function () use ($central, $deviceId, $tenantId, $user): array {
            $device = $central->table('device_registry')
                ->where('device_id', $deviceId)
                ->lockForUpdate()
                ->first();

            if ($device !== null) {
                $foreignTenant = (string) $device->tenant_id !== $tenantId;
                $foreignOwner = $device->owner_user_id !== null
                    && (int) $device->owner_user_id !== (int) $user->id;
                $revokedOrSuspended = in_array($device->status, ['revoked', 'suspended', 'disabled'], true);

                if ($foreignTenant || $foreignOwner || $revokedOrSuspended) {
                    return ['conflict' => true, 'created' => false];
                }

                $central->table('device_registry')
                    ->where('device_id', $deviceId)
                    ->update([
                        'tenant_id' => $tenantId,
                        'owner_user_id' => $user->id,
                        'status' => 'active',
                        'registered_at' => $device->registered_at ?? now(),
                        'updated_at' => now(),
                    ]);

                return ['conflict' => false, 'created' => false];
            }

            $central->table('device_registry')->insert([
                'device_id' => $deviceId,
                'tenant_id' => $tenantId,
                'owner_user_id' => $user->id,
                'status' => 'active',
                'registered_at' => now(),
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            return ['conflict' => false, 'created' => true];
        }, 3);

        if ($result['conflict']) {
            return response()->json([
                'error' => [
                    'code' => 'device_already_bound',
                    'message' => 'The device is owned by another tenant/user or has been disabled.',
                ],
            ], 409);
        }

        return response()->json([
            'status' => 'active',
            'device_id' => $deviceId,
            'tenant_id' => $tenantId,
        ], $result['created'] ? 201 : 200);
    }
}
