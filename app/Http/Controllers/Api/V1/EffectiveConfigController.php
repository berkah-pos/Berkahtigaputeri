<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\EffectiveConfigResolver;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class EffectiveConfigController extends Controller
{
    public function __invoke(Request $request, EffectiveConfigResolver $resolver): JsonResponse
    {
        $input = $request->validate([
            'tenant_id' => ['required', 'string', 'max:100', 'regex:/^[a-zA-Z0-9_-]+$/'],
            'device_id' => ['required', 'string', 'max:150', 'regex:/^[a-zA-Z0-9_.:-]+$/'],
            'service' => ['required', 'in:pos,akuntansi'],
        ]);
        $user = $request->user();
        abort_unless($user, 401, 'Authentication required.');

        $token = $user->currentAccessToken();
        if ($token && ! $token->can('config:read')) {
            abort(403, 'Token does not have config:read permission.');
        }

        $config = $resolver->resolve(
            $user,
            $input['tenant_id'],
            $input['device_id'],
            $input['service'],
        );

        return response()->json([
            'effective_config' => $config,
            'tenant_id' => $input['tenant_id'],
            'device_id' => $input['device_id'],
            'service' => $input['service'],
        ]);
    }
}
