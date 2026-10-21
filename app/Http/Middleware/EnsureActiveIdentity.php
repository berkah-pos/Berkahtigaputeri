<?php

namespace App\Http\Middleware;

use App\Models\Central\PersonalAccessToken;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureActiveIdentity
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();
        $token = $user?->currentAccessToken();

        if (! $user || ! $token instanceof PersonalAccessToken) {
            return $this->deny('identity_session_invalid', 401);
        }

        if (! $user->is_active) {
            // Disable all existing bearer sessions as soon as a disabled account
            // attempts any protected identity/API operation.
            $user->tokens()->delete();

            return $this->deny('identity_disabled', 403);
        }

        if (! in_array($token->token_kind, ['device', 'platform_admin'], true)) {
            return $this->deny('identity_session_unbound', 403);
        }

        if ($token->token_kind === 'platform_admin' && ! $user->is_super_admin) {
            $token->delete();

            return $this->deny('identity_session_invalid', 403);
        }

        return $next($request);
    }

    private function deny(string $code, int $status): JsonResponse
    {
        return response()->json([
            'error' => $code,
            'message' => 'This identity session is not authorized for the requested operation.',
        ], $status);
    }
}
