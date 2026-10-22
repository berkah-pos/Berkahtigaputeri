<?php

namespace App\Http\Middleware;

use App\Models\Central\PersonalAccessToken;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsurePlatformAbility
{
    public function handle(Request $request, Closure $next, string $ability): Response
    {
        $user = $request->user();
        $token = $user?->currentAccessToken();

        if (! $user || ! $user->is_active || ! $user->is_super_admin ||
            ! $token instanceof PersonalAccessToken ||
            $token->token_kind !== 'platform_admin' ||
            ! $token->can($ability)) {
            return response()->json([
                'error' => 'platform_admin_required',
                'message' => 'A platform administrator session with the required ability is required.',
            ], 403);
        }

        return $next($request);
    }
}
