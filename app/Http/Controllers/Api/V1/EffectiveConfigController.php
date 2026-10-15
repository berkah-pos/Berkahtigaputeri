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

        $resolved = $resolver->resolve(
            $user,
            $input['tenant_id'],
            $input['device_id'],
            $input['service'],
        );
        $meta = $resolved['meta'];

        // Keep version/hash fields at the top level for simple client cache keys.
        // Retain meta for clients that consume the existing response envelope.
        return response()->json([
            'effective_config' => $resolved['config'],
            'effective_version' => $meta['effective_version'],
            'config_hash' => $meta['config_hash'],
            'scoped_hash' => $meta['scoped_hash'],
            'layer_versions' => $meta['layer_versions'],
            'tenant_id' => $input['tenant_id'],
            'device_id' => $input['device_id'],
            'service' => $input['service'],
            'meta' => [
                'config_hash' => $meta['config_hash'],
                'scoped_hash' => $meta['scoped_hash'],
                'effective_version' => $meta['effective_version'],
                'effective_revision' => $meta['effective_revision'],
                'version_vector' => $meta['version_vector'],
                'layer_versions' => $meta['layer_versions'],
                'device_config_missing' => $meta['device_config_missing'],
                'subscription' => $meta['subscription'],
            ],
        ]);
    }
}
