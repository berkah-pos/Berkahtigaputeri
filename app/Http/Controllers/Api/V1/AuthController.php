<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1;

use App\Models\Central\Tenant;
use App\Models\Central\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\PersonalAccessToken;

final class AuthController
{
    private const TOKEN_TTL_DAYS = 30;

    public function login(Request $request): JsonResponse
    {
        $credentials = $request->validate([
            'email' => ['required', 'string', 'email', 'max:255'],
            'password' => ['required', 'string', 'max:4096'],
        ]);

        $email = mb_strtolower(trim($credentials['email']));
        $user = User::query()
            ->whereRaw('LOWER(email) = ?', [$email])
            ->first();

        // Use one response for absent users, inactive users, wrong passwords and
        // unavailable tenant membership to avoid revealing account state.
        if (
            $user === null ||
            ! Hash::check($credentials['password'], (string) $user->getAuthPassword()) ||
            ! $user->is_active ||
            ! is_string($user->tenant_id) ||
            $user->tenant_id === '' ||
            ! Tenant::query()->where('id', $user->tenant_id)->where('status', 'active')->exists()
        ) {
            return response()->json([
                'error' => [
                    'code' => 'invalid_credentials',
                    'message' => 'The supplied credentials are invalid or unavailable.',
                ],
            ], 401)->header('Cache-Control', 'private, no-store');
        }

        $newToken = $user->createToken('berkah-pos-mobile', ['config:read']);
        $newToken->accessToken->forceFill([
            'expires_at' => now()->addDays(self::TOKEN_TTL_DAYS),
        ])->save();

        return response()->json([
            'data' => [
                'token' => $newToken->plainTextToken,
                'token_type' => 'Bearer',
                'expires_at' => $newToken->accessToken->expires_at?->toISOString(),
                'user' => [
                    'id' => $user->getKey(),
                    'name' => $user->name,
                    'email' => $user->email,
                    'tenant_id' => $user->tenant_id,
                ],
            ],
        ])->header('Cache-Control', 'private, no-store');
    }

    public function logout(Request $request): JsonResponse
    {
        $token = $request->user()?->currentAccessToken();
        if ($token instanceof PersonalAccessToken) {
            $token->delete();
        }

        return response()->json([
            'data' => ['logged_out' => true],
        ])->header('Cache-Control', 'private, no-store');
    }
}
