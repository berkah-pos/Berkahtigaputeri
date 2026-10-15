<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\SyncOutboxRequest;
use App\Models\Central\Tenant;
use App\Services\TenantSyncService;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

class SyncOutboxController extends Controller
{
    public function __invoke(SyncOutboxRequest $request, TenantSyncService $sync): JsonResponse
    {
        $user = $request->user();
        abort_unless($user !== null && (bool) $user->is_active, 403, 'An active account is required.');

        $token = $user->currentAccessToken();
        abort_unless($token !== null && $token->can('sync:write'), 403, 'Token does not have sync:write permission.');

        $input = $request->validated();
        $tenantId = (string) $input['tenant_id'];
        $deviceId = (string) $input['device_id'];

        // A body/header selector never grants access; it must not contradict the canonical selector.
        if ($request->headers->has('x-tenant-id')) {
            abort_unless(hash_equals($tenantId, (string) $request->header('x-tenant-id')), 404);
        }
        if ($request->headers->has('x-device-id')) {
            abort_unless(hash_equals($deviceId, (string) $request->header('x-device-id')), 404);
        }
        foreach ($input['events'] as $event) {
            $payload = $event['payload'] ?? [];
            if (isset($payload['tenant_id']) && ! hash_equals($tenantId, (string) $payload['tenant_id'])) {
                abort(404, 'Payload tenant selector conflicts with the authorized tenant.');
            }
            if (isset($payload['device_id']) && ! hash_equals($deviceId, (string) $payload['device_id'])) {
                abort(404, 'Payload device selector conflicts with the authorized device.');
            }
        }

        $tenant = Tenant::on('central')->where('id', $tenantId)->first();
        abort_if($tenant === null, 404, 'Tenant was not found.');
        abort_unless((bool) $tenant->is_active, 403, 'Tenant is inactive.');

        $membership = DB::connection('central')->table('tenant_memberships')
            ->where('tenant_id', $tenantId)
            ->where('user_id', $user->getAuthIdentifier())
            ->where('is_active', true)
            ->exists();
        abort_unless($membership, 403, 'Active tenant membership is required.');

        $serviceEnabled = DB::connection('central')->table('tenant_services')
            ->where('tenant_id', $tenantId)
            ->where('service', 'pos')
            ->where('enabled', true)
            ->exists();
        abort_unless($serviceEnabled, 403, 'POS sync is not enabled for this tenant.');

        $device = DB::connection('central')->table('device_registry')
            ->where('device_id', $deviceId)
            ->where('tenant_id', $tenantId)
            ->where('status', 'active')
            ->first();
        abort_if($device === null, 404, 'The device is not registered to this tenant.');
        abort_unless(
            $device->owner_user_id !== null
                && (int) $device->owner_user_id === (int) $user->getAuthIdentifier(),
            403,
            'The device is not owned by the authenticated user.'
        );

        $result = $sync->sync($tenant, $deviceId, (string) $input['batch_id'], $input['events']);

        return response()->json($result, 200);
    }
}
