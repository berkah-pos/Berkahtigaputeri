<?php

namespace App\Http\Middleware;

use App\Models\Central\PersonalAccessToken;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

class EnsureVerifiedDevice
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        $token = $user?->currentAccessToken();

        if (! $user || ! $token instanceof PersonalAccessToken ||
            $token->token_kind !== 'device' ||
            ! $token->tenant_id ||
            ! $token->device_id ||
            ! $token->can('tenant:access')) {
            return $this->deny();
        }

        $verified = DB::connection('central')
            ->table('device_registry as d')
            ->join('tenant_memberships as tm', function ($join): void {
                $join->on('tm.user_id', '=', 'd.owner_user_id')
                    ->on('tm.tenant_id', '=', 'd.tenant_id');
            })
            ->join('tenants as t', 't.id', '=', 'd.tenant_id')
            ->where('d.device_id', $token->device_id)
            ->where('d.tenant_id', $token->tenant_id)
            ->where('d.owner_user_id', $user->getKey())
            ->where('d.status', 'active')
            ->where('tm.status', 'active')
            ->where('t.status', 'active')
            ->select([
                'd.device_id',
                'd.tenant_id',
                'tm.role as membership_role',
            ])
            ->first();

        if (! $verified) {
            return $this->deny();
        }

        // Downstream handlers must read this server-derived context rather than
        // promoting request tenant_id/device_id fields to authority.
        $context = [
            'user_id' => (int) $user->getKey(),
            'tenant_id' => (string) $verified->tenant_id,
            'device_id' => (string) $verified->device_id,
            'membership_role' => (string) $verified->membership_role,
            'token_id' => (int) $token->getKey(),
        ];

        $request->attributes->set('verified_identity_context', $context);
        $request->attributes->set('verified_tenant_id', $context['tenant_id']);
        $request->attributes->set('verified_device_id', $context['device_id']);

        return $next($request);
    }

    private function deny(): JsonResponse
    {
        return response()->json([
            'error' => 'active_device_required',
            'message' => 'An active device registered to this user and tenant is required.',
        ], 403);
    }
}
