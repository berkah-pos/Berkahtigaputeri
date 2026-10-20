<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Central\User;
use App\Services\TenantAccess;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class AuthController extends Controller
{
    public function login(Request $request, TenantAccess $tenantAccess): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'string', 'email', 'max:254'],
            'password' => ['required', 'string', 'max:1024'],
            'device_name' => ['sometimes', 'string', 'max:120'],
        ]);

        $email = mb_strtolower(trim($validated['email']));
        $user = User::query()->where('email', $email)->first();

        if ($user === null || ! $user->is_active || ! Hash::check($validated['password'], $user->password)) {
            return response()->json([
                'error' => [
                    'code' => 'invalid_credentials',
                    'message' => 'Email or password is incorrect.',
                ],
            ], 401);
        }

        if (! $tenantAccess->hasActiveSubscription($user->tenant_id === null ? null : (string) $user->tenant_id)) {
            return response()->json([
                'error' => [
                    'code' => 'tenant_not_entitled',
                    'message' => 'The account has no active tenant entitlement.',
                ],
            ], 403);
        }

        $expiresAt = now()->addDays(30);
        $token = $user->createToken(
            trim((string) ($validated['device_name'] ?? 'android-client')) ?: 'android-client',
            ['*'],
            $expiresAt
        );

        return response()->json([
            'token_type' => 'Bearer',
            'access_token' => $token->plainTextToken,
            'expires_at' => $expiresAt->toIso8601String(),
            'user' => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'tenant_id' => $user->tenant_id,
            ],
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $token = $request->user()?->currentAccessToken();
        if ($token !== null && method_exists($token, 'delete')) {
            $token->delete();
        }

        return response()->json(['status' => 'ok']);
    }
}
