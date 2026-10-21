<?php

namespace App\Http\Controllers\Api\V1;

use App\Models\Central\TenantMembership;
use App\Models\Central\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\PersonalAccessToken;

final class AuthController
{
    public function login(Request $request): JsonResponse
    {
        $input = $request->validate([
            'email' => ['required', 'string', 'email', 'max:254'],
            'password' => ['required', 'string', 'max:255'],
            'device_name' => ['nullable', 'string', 'max:100'],
        ]);

        $email = mb_strtolower(trim($input['email']));
        $candidate = User::query()
            ->whereRaw('LOWER(email) = ?', [$email])
            ->first();

        if (! $candidate || ! Hash::check($input['password'], $candidate->password)) {
            return response()->json(['message' => 'Invalid credentials.'], 401);
        }

        return DB::connection('central')->transaction(function () use ($candidate, $input): JsonResponse {
            $user = User::query()
                ->whereKey($candidate->getKey())
                ->lockForUpdate()
                ->first();

            if (! $user || ! Hash::check($input['password'], $user->password)) {
                return response()->json(['message' => 'Invalid credentials.'], 401);
            }

            if (! $user->is_active) {
                return response()->json(['message' => 'Account is inactive.'], 403);
            }

            $memberships = TenantMembership::query()
                ->where('user_id', $user->getKey())
                ->where('status', 'active')
                ->orderBy('tenant_id')
                ->get(['tenant_id', 'role']);

            if (! $user->is_super_admin && $memberships->isEmpty()) {
                return response()->json(['message' => 'No active tenant membership.'], 403);
            }

            $tokenLifetimeMinutes = max(1, (int) config('sanctum.expiration', 720));
            $expiresAt = now()->addMinutes($tokenLifetimeMinutes);
            $deviceName = trim((string) ($input['device_name'] ?? 'Berkah POS'));
            if ($deviceName === '') {
                $deviceName = 'Berkah POS';
            }

            $token = $user->createToken(
                mb_substr($deviceName, 0, 100),
                ['*'],
                $expiresAt,
            );

            $this->recordAudit(
                actorUserId: (int) $user->getKey(),
                tenantId: $memberships->count() === 1 ? (string) $memberships->first()->tenant_id : null,
                action: 'auth.token_issued',
                metadata: [
                    'token_id' => $token->accessToken->getKey(),
                    'expires_at' => $expiresAt->toIso8601String(),
                ],
            );

            return response()->json([
                'token_type' => 'Bearer',
                'token' => $token->plainTextToken,
                'expires_at' => $expiresAt->toIso8601String(),
                'user' => $this->publicUser($user),
                'memberships' => $memberships->map(static fn (TenantMembership $membership): array => [
                    'tenant_id' => $membership->tenant_id,
                    'role' => $membership->role,
                ])->values(),
            ], 201);
        });
    }

    public function me(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();

        $memberships = TenantMembership::query()
            ->where('user_id', $user->getKey())
            ->where('status', 'active')
            ->orderBy('tenant_id')
            ->get(['tenant_id', 'role']);

        return response()->json([
            'user' => $this->publicUser($user),
            'memberships' => $memberships->map(static fn (TenantMembership $membership): array => [
                'tenant_id' => $membership->tenant_id,
                'role' => $membership->role,
            ])->values(),
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        /** @var User $user */
        $user = $request->user();
        $token = $user->currentAccessToken();

        if (! $token instanceof PersonalAccessToken) {
            return response()->json(['message' => 'A revocable bearer token is required.'], 401);
        }

        DB::connection('central')->transaction(function () use ($token, $user): void {
            $this->recordAudit(
                actorUserId: (int) $user->getKey(),
                tenantId: null,
                action: 'auth.token_revoked',
                metadata: ['token_id' => $token->getKey()],
            );
            $token->delete();
        });

        return response()->json(['status' => 'revoked']);
    }

    /**
     * @return array{id: int, name: string, email: string, is_super_admin: bool}
     */
    private function publicUser(User $user): array
    {
        return [
            'id' => (int) $user->getKey(),
            'name' => (string) $user->name,
            'email' => (string) $user->email,
            'is_super_admin' => (bool) $user->is_super_admin,
        ];
    }

    /**
     * @param array<string, int|string> $metadata
     */
    private function recordAudit(
        int $actorUserId,
        ?string $tenantId,
        string $action,
        array $metadata,
    ): void {
        DB::connection('central')->table('audit_events')->insert([
            'actor_user_id' => $actorUserId,
            'tenant_id' => $tenantId,
            'scope_type' => 'user',
            'scope_id' => (string) $actorUserId,
            'action' => $action,
            'previous_version' => null,
            'new_version' => null,
            'previous_sha256' => null,
            'new_sha256' => null,
            'metadata' => json_encode($metadata, JSON_THROW_ON_ERROR),
            'created_at' => now(),
        ]);
    }
}
