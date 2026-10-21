<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Central\PersonalAccessToken;
use App\Models\Central\User;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class IdentityController extends Controller
{
    public function login(Request $request): JsonResponse
    {
        $payload = $request->validate([
            'email' => ['required', 'string', 'email', 'max:254'],
            'password' => ['required', 'string', 'max:4096'],
            'tenant_id' => ['nullable', 'string', 'max:150'],
            'device_id' => ['nullable', 'string', 'min:16', 'max:150', 'regex:/\A[A-Za-z0-9][A-Za-z0-9._:-]*\z/'],
            'device_name' => ['nullable', 'string', 'max:100'],
        ]);

        $email = mb_strtolower(trim($payload['email']));
        $user = User::query()->whereRaw('LOWER(email) = ?', [$email])->first();

        if (! $user || ! Hash::check($payload['password'], (string) $user->password)) {
            return $this->error(
                'invalid_credentials',
                'The email or password is invalid.',
                401,
            );
        }

        if (! $user->is_active) {
            $user->tokens()->delete();

            return $this->error(
                'identity_disabled',
                'This account is disabled. Contact the platform administrator.',
                403,
            );
        }

        $requestedTenantId = isset($payload['tenant_id']) && trim($payload['tenant_id']) !== ''
            ? trim($payload['tenant_id'])
            : null;

        // Platform-administrator access is short-lived and separately scoped.
        // It cannot be used as a tenant/device token.
        if ($user->is_super_admin && $requestedTenantId === null) {
            return $this->issuePlatformAdminToken($user);
        }

        $membership = $this->resolveMembership((int) $user->getKey(), $requestedTenantId);
        if ($membership instanceof JsonResponse) {
            return $membership;
        }

        $deviceId = trim((string) ($payload['device_id'] ?? ''));
        if ($deviceId === '') {
            return $this->error(
                'device_id_required',
                'A stable installation device_id is required before tenant access can be granted.',
                422,
            );
        }

        try {
            $result = DB::connection('central')->transaction(function () use (
                $user,
                $membership,
                $deviceId,
                $payload,
            ): array {
                $now = now();
                $device = DB::connection('central')
                    ->table('device_registry')
                    ->where('device_id', $deviceId)
                    ->lockForUpdate()
                    ->first();

                if (! $device) {
                    DB::connection('central')->table('device_registry')->insert([
                        'device_id' => $deviceId,
                        'tenant_id' => $membership->tenant_id,
                        'owner_user_id' => $user->getKey(),
                        'status' => 'pending',
                        'device_name' => $payload['device_name'] ?? null,
                        'registered_at' => null,
                        'enrollment_requested_at' => $now,
                        'revoked_at' => null,
                        'created_at' => $now,
                        'updated_at' => $now,
                    ]);

                    $this->recordAudit(
                        (int) $user->getKey(),
                        (string) $membership->tenant_id,
                        $deviceId,
                        'device.enrollment_requested',
                        ['status' => 'pending', 'device_name' => $payload['device_name'] ?? null],
                    );

                    return ['state' => 'pending'];
                }

                // Device identifiers are globally unique. Never reassign a
                // device identifier supplied by a different user/tenant.
                if ((int) ($device->owner_user_id ?? 0) !== (int) $user->getKey() ||
                    (string) $device->tenant_id !== (string) $membership->tenant_id) {
                    return ['state' => 'conflict'];
                }

                if ($device->status === 'revoked') {
                    return ['state' => 'revoked'];
                }

                if ($device->status !== 'active') {
                    return ['state' => 'pending'];
                }

                if (! $this->hasActiveMembership((int) $user->getKey(), (string) $membership->tenant_id)) {
                    return ['state' => 'membership_inactive'];
                }

                $expiresAt = now()->addHours(12);
                $created = $user->createToken(
                    'berkah-pos-device',
                    ['identity:read', 'tenant:access', 'device:revoke'],
                    $expiresAt,
                );
                $created->accessToken->forceFill([
                    'tenant_id' => $membership->tenant_id,
                    'device_id' => $deviceId,
                    'token_kind' => 'device',
                ])->save();

                $this->recordAudit(
                    (int) $user->getKey(),
                    (string) $membership->tenant_id,
                    $deviceId,
                    'identity.device_token_issued',
                    ['token_id' => $created->accessToken->getKey(), 'expires_at' => $expiresAt->toIso8601String()],
                );

                return [
                    'state' => 'authenticated',
                    'plain_text_token' => $created->plainTextToken,
                    'expires_at' => $expiresAt->toIso8601String(),
                    'tenant_id' => (string) $membership->tenant_id,
                    'device_id' => $deviceId,
                    'role' => (string) $membership->role,
                ];
            }, 3);
        } catch (QueryException) {
            // A concurrent first-login can race on the globally unique device
            // key. Return a generic conflict; never disclose the existing owner.
            return $this->error(
                'device_id_conflict',
                'This device identifier could not be enrolled. Restart enrollment with a new installation identifier or contact an administrator.',
                409,
            );
        }

        if ($result['state'] === 'conflict') {
            return $this->error(
                'device_id_conflict',
                'This device identifier is already registered to another identity.',
                409,
            );
        }

        if ($result['state'] === 'revoked') {
            return $this->error(
                'device_revoked',
                'This device has been revoked. Use a new installation identifier and request enrollment.',
                403,
            );
        }

        if ($result['state'] === 'membership_inactive') {
            return $this->error(
                'membership_inactive',
                'This user no longer has active membership in the selected tenant.',
                403,
            );
        }

        if ($result['state'] === 'pending') {
            return response()->json([
                'status' => 'device_pending_approval',
                'device' => [
                    'device_id' => $deviceId,
                    'tenant_id' => (string) $membership->tenant_id,
                    'status' => 'pending',
                ],
                'message' => 'The device has been submitted for approval. No tenant access token has been issued.',
            ], 202);
        }

        return response()->json([
            'status' => 'authenticated',
            'token_type' => 'Bearer',
            'access_token' => $result['plain_text_token'],
            'expires_at' => $result['expires_at'],
            'user' => [
                'id' => (int) $user->getKey(),
                'name' => $user->name,
                'email' => $user->email,
                'is_super_admin' => false,
            ],
            'tenant' => [
                'id' => $result['tenant_id'],
                'membership_role' => $result['role'],
            ],
            'device' => [
                'device_id' => $result['device_id'],
                'status' => 'active',
            ],
        ]);
    }

    public function session(Request $request): JsonResponse
    {
        $user = $request->user();
        $token = $user->currentAccessToken();

        return response()->json([
            'status' => 'authenticated',
            'user' => [
                'id' => (int) $user->getKey(),
                'name' => $user->name,
                'email' => $user->email,
                'is_super_admin' => (bool) $user->is_super_admin,
            ],
            'token_kind' => $token->token_kind,
            'token_expires_at' => $token->expires_at?->toIso8601String(),
            'memberships' => $this->activeMemberships((int) $user->getKey())
                ->map(fn ($membership): array => [
                    'tenant_id' => (string) $membership->tenant_id,
                    'template_id' => (string) $membership->template_id,
                    'role' => (string) $membership->role,
                ])
                ->values()
                ->all(),
            'device' => $token->token_kind === 'device'
                ? ['device_id' => $token->device_id, 'tenant_id' => $token->tenant_id]
                : null,
        ]);
    }

    public function context(Request $request): JsonResponse
    {
        return response()->json([
            'context' => $request->attributes->get('verified_identity_context'),
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $token = $request->user()?->currentAccessToken();
        if ($token && method_exists($token, 'delete')) {
            $token->delete();
        }

        return response()->json(null, 204);
    }

    public function logoutAll(Request $request): JsonResponse
    {
        $request->user()->tokens()->delete();

        return response()->json(null, 204);
    }

    public function approveDevice(Request $request, string $deviceId): JsonResponse
    {
        $user = $request->user();

        if (! $user->is_super_admin) {
            return $this->error('platform_admin_required', 'Only a platform administrator may approve devices.', 403);
        }

        $result = DB::connection('central')->transaction(function () use ($user, $deviceId): array {
            $device = DB::connection('central')
                ->table('device_registry')
                ->where('device_id', $deviceId)
                ->lockForUpdate()
                ->first();

            if (! $device) {
                return ['state' => 'not_found'];
            }

            if ($device->status === 'active') {
                return ['state' => 'active', 'changed' => false];
            }

            if ($device->status !== 'pending') {
                return ['state' => 'not_pending'];
            }

            $eligibleOwner = $device->owner_user_id !== null &&
                DB::connection('central')->table('users')
                    ->where('id', $device->owner_user_id)
                    ->where('is_active', true)
                    ->exists() &&
                $this->hasActiveMembership((int) $device->owner_user_id, (string) $device->tenant_id);

            if (! $eligibleOwner) {
                return ['state' => 'membership_inactive'];
            }

            $now = now();
            DB::connection('central')->table('device_registry')
                ->where('device_id', $deviceId)
                ->update([
                    'status' => 'active',
                    'registered_at' => $now,
                    'revoked_at' => null,
                    'updated_at' => $now,
                ]);

            $this->recordAudit(
                (int) $user->getKey(),
                (string) $device->tenant_id,
                $deviceId,
                'device.approved',
                ['status' => 'active'],
            );

            return ['state' => 'active', 'changed' => true];
        }, 3);

        return match ($result['state']) {
            'not_found' => $this->error('device_not_found', 'The requested device was not found.', 404),
            'not_pending' => $this->error('device_not_pending', 'A revoked or invalid device cannot be approved.', 409),
            'membership_inactive' => $this->error('membership_inactive', 'The device owner no longer has active membership in an active tenant.', 409),
            default => response()->json([
                'status' => 'active',
                'device_id' => $deviceId,
                'changed' => $result['changed'],
            ]),
        };
    }

    public function revokeDevice(Request $request, string $deviceId): JsonResponse
    {
        $user = $request->user();
        $token = $user->currentAccessToken();

        if (! $token instanceof PersonalAccessToken) {
            return $this->error('identity_session_invalid', 'A supported identity session is required.', 403);
        }

        $device = DB::connection('central')
            ->table('device_registry')
            ->where('device_id', $deviceId)
            ->first();

        if (! $device) {
            return $this->error('device_not_found', 'The requested device was not found.', 404);
        }

        $isPlatformAdmin = $user->is_super_admin &&
            $token->token_kind === 'platform_admin' &&
            $token->can('devices:revoke');

        $isOwner = $token->token_kind === 'device' &&
            (int) ($device->owner_user_id ?? 0) === (int) $user->getKey() &&
            (string) $token->tenant_id === (string) $device->tenant_id &&
            $this->hasActiveMembership((int) $user->getKey(), (string) $device->tenant_id) &&
            $this->hasActiveDeviceToken($token, (int) $user->getKey());

        if (! $isPlatformAdmin && ! $isOwner) {
            return $this->error('device_revoke_forbidden', 'You cannot revoke this device.', 403);
        }

        $changed = DB::connection('central')->transaction(function () use ($user, $deviceId): bool {
            $locked = DB::connection('central')
                ->table('device_registry')
                ->where('device_id', $deviceId)
                ->lockForUpdate()
                ->first();

            if (! $locked) {
                return false;
            }

            if ($locked->status !== 'revoked') {
                $now = now();
                DB::connection('central')->table('device_registry')
                    ->where('device_id', $deviceId)
                    ->update([
                        'status' => 'revoked',
                        'registered_at' => null,
                        'revoked_at' => $now,
                        'updated_at' => $now,
                    ]);

                $this->recordAudit(
                    (int) $user->getKey(),
                    (string) $locked->tenant_id,
                    $deviceId,
                    'device.revoked',
                    ['status' => 'revoked'],
                );
            }

            DB::connection('central')
                ->table('personal_access_tokens')
                ->where('device_id', $deviceId)
                ->delete();

            return true;
        }, 3);

        if (! $changed) {
            return $this->error('device_not_found', 'The requested device was not found.', 404);
        }

        return response()->json([
            'status' => 'revoked',
            'device_id' => $deviceId,
        ]);
    }

    private function issuePlatformAdminToken(User $user): JsonResponse
    {
        $expiresAt = now()->addMinutes(15);

        $issued = DB::connection('central')->transaction(function () use ($user, $expiresAt) {
            $created = $user->createToken(
                'berkah-pos-platform-admin',
                ['identity:read', 'devices:approve', 'devices:revoke'],
                $expiresAt,
            );

            $created->accessToken->forceFill([
                'tenant_id' => null,
                'device_id' => null,
                'token_kind' => 'platform_admin',
            ])->save();

            $this->recordAudit(
                (int) $user->getKey(),
                null,
                (string) $user->getKey(),
                'identity.platform_admin_token_issued',
                ['token_id' => $created->accessToken->getKey(), 'expires_at' => $expiresAt->toIso8601String()],
            );

            return $created;
        }, 3);

        return response()->json([
            'status' => 'authenticated',
            'token_type' => 'Bearer',
            'token_kind' => 'platform_admin',
            'access_token' => $issued->plainTextToken,
            'expires_at' => $expiresAt->toIso8601String(),
            'user' => [
                'id' => (int) $user->getKey(),
                'name' => $user->name,
                'email' => $user->email,
                'is_super_admin' => true,
            ],
        ]);
    }

    private function resolveMembership(int $userId, ?string $requestedTenantId): object|JsonResponse
    {
        $memberships = $this->activeMemberships($userId);

        if ($memberships->isEmpty()) {
            return $this->error(
                'active_membership_required',
                'This account has no active tenant membership.',
                403,
            );
        }

        if ($requestedTenantId !== null) {
            $membership = $memberships->firstWhere('tenant_id', $requestedTenantId);

            if (! $membership) {
                return $this->error(
                    'tenant_membership_forbidden',
                    'The requested tenant is not an active membership of this account.',
                    403,
                );
            }

            return $membership;
        }

        if ($memberships->count() > 1) {
            return $this->error(
                'tenant_selection_required',
                'Select one of the active tenant memberships for this session.',
                422,
                [
                    'memberships' => $memberships->map(fn ($membership): array => [
                        'tenant_id' => (string) $membership->tenant_id,
                        'template_id' => (string) $membership->template_id,
                        'role' => (string) $membership->role,
                    ])->values()->all(),
                ],
            );
        }

        return $memberships->first();
    }

    private function activeMemberships(int $userId)
    {
        return DB::connection('central')
            ->table('tenant_memberships as tm')
            ->join('tenants as t', 't.id', '=', 'tm.tenant_id')
            ->where('tm.user_id', $userId)
            ->where('tm.status', 'active')
            ->where('t.status', 'active')
            ->select(['tm.tenant_id', 'tm.role', 't.template_id'])
            ->orderBy('tm.tenant_id')
            ->get();
    }

    private function hasActiveMembership(int $userId, string $tenantId): bool
    {
        return DB::connection('central')
            ->table('tenant_memberships as tm')
            ->join('tenants as t', 't.id', '=', 'tm.tenant_id')
            ->where('tm.user_id', $userId)
            ->where('tm.tenant_id', $tenantId)
            ->where('tm.status', 'active')
            ->where('t.status', 'active')
            ->exists();
    }

    private function hasActiveDeviceToken(PersonalAccessToken $token, int $userId): bool
    {
        if ($token->token_kind !== 'device' || ! $token->device_id || ! $token->tenant_id) {
            return false;
        }

        return DB::connection('central')
            ->table('device_registry')
            ->where('device_id', $token->device_id)
            ->where('tenant_id', $token->tenant_id)
            ->where('owner_user_id', $userId)
            ->where('status', 'active')
            ->exists();
    }

    private function recordAudit(
        int $actorUserId,
        ?string $tenantId,
        string $scopeId,
        string $action,
        array $metadata,
    ): void {
        DB::connection('central')->table('audit_events')->insert([
            'actor_user_id' => $actorUserId,
            'tenant_id' => $tenantId,
            'scope_type' => 'identity_device',
            'scope_id' => $scopeId,
            'action' => $action,
            'previous_version' => null,
            'new_version' => null,
            'previous_sha256' => null,
            'new_sha256' => null,
            'metadata' => json_encode($metadata, JSON_THROW_ON_ERROR),
            'created_at' => now(),
        ]);
    }

    private function error(string $code, string $message, int $status, array $extra = []): JsonResponse
    {
        return response()->json(array_merge([
            'error' => $code,
            'message' => $message,
        ], $extra), $status);
    }
}
