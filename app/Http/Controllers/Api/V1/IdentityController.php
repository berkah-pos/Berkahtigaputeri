<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Central\DeviceRegistry;
use App\Models\Central\PersonalAccessToken;
use App\Models\Central\Tenant;
use App\Models\Central\TenantMembership;
use App\Models\Central\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpFoundation\Response;

class IdentityController extends Controller
{
    public function login(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'string', 'email', 'max:255'],
            'password' => ['required', 'string', 'max:1024'],
            'device_id' => ['required', 'string', 'regex:/^[a-f0-9]{64}$/'],
            'device_secret' => ['required', 'string', 'regex:/^[a-f0-9]{64}$/'],
            'tenant_id' => ['nullable', 'string', 'max:255'],
        ]);

        $email = mb_strtolower(trim($validated['email']));
        $user = User::query()->whereRaw('LOWER(email) = ?', [$email])->first();

        if (! $user || ! $user->is_active || ! Hash::check($validated['password'], $user->password)) {
            return response()->json([
                'message' => 'Email atau kata sandi tidak valid.',
                'code' => 'invalid_credentials',
            ], 401);
        }

        $memberships = TenantMembership::query()
            ->with('tenant')
            ->where('user_id', $user->getAuthIdentifier())
            ->where('status', 'active')
            ->whereHas('tenant', fn ($query) => $query->where('status', 'active'))
            ->get();

        if ($memberships->isEmpty()) {
            return response()->json([
                'message' => 'Akun belum memiliki membership tenant yang aktif.',
                'code' => 'account_has_no_active_membership',
            ], 403);
        }

        $requestedTenantId = $validated['tenant_id'] ?? null;
        if ($requestedTenantId === null || trim($requestedTenantId) === '') {
            if ($memberships->count() > 1) {
                return response()->json([
                    'message' => 'Pilih tenant aktif untuk melanjutkan.',
                    'code' => 'tenant_selection_required',
                    'memberships' => $memberships->map(fn ($membership) => [
                        'tenant_id' => $membership->tenant_id,
                        'label' => $membership->tenant?->data['name'] ?? $membership->tenant_id,
                    ])->values(),
                ], 422);
            }
            $membership = $memberships->first();
        } else {
            $membership = $memberships->firstWhere('tenant_id', $requestedTenantId);
            if (! $membership) {
                return response()->json([
                    'message' => 'Akun tidak memiliki akses ke tenant yang diminta.',
                    'code' => 'tenant_membership_denied',
                ], 403);
            }
        }

        $deviceId = $validated['device_id'];
        $deviceSecretHash = hash('sha256', $validated['device_secret']);
        $tenantId = $membership->tenant_id;
        $device = DeviceRegistry::query()->whereKey($deviceId)->first();
        $deviceStatus = 'unregistered';

        if ($device) {
            if ($device->tenant_id !== $tenantId ||
                ($device->owner_user_id !== null && (int) $device->owner_user_id !== (int) $user->getAuthIdentifier())) {
                return response()->json([
                    'message' => 'Perangkat sudah terikat pada tenant atau identitas lain.',
                    'code' => 'device_identity_conflict',
                ], 409);
            }
            if ($device->status === 'revoked' || $device->revoked_at !== null) {
                return response()->json([
                    'message' => 'Perangkat ini telah dicabut. Hubungi administrator.',
                    'code' => 'device_revoked',
                ], 403);
            }
            if (! $device->device_secret_hash || ! hash_equals($device->device_secret_hash, $deviceSecretHash)) {
                return response()->json([
                    'message' => 'Bukti kepemilikan perangkat tidak valid.',
                    'code' => 'device_proof_invalid',
                ], 403);
            }
            if ($device->owner_user_id === null || $device->status === 'pending') {
                $deviceStatus = 'pending';
            } elseif ($device->status === 'active') {
                $deviceStatus = 'active';
            } else {
                return response()->json([
                    'message' => 'Status perangkat tidak mengizinkan login.',
                    'code' => 'device_not_usable',
                ], 403);
            }
        }

        $now = now();
        $abilities = $deviceStatus === 'active' ? ['*'] : ['device:enroll'];
        $createdToken = DB::connection('central')->transaction(function () use (
            $user, $deviceId, $tenantId, $abilities, $now, $deviceStatus
        ) {
            $created = $user->createToken('mobile:'.$deviceId, $abilities);
            $token = $created->accessToken;
            $token->forceFill([
                'device_id' => $deviceId,
                'tenant_id' => $tenantId,
                'expires_at' => $now->copy()->addMinutes((int) config('sanctum.expiration', 10080)),
            ])->save();

            DB::connection('central')->table('audit_events')->insert([
                'actor_user_id' => $user->getAuthIdentifier(),
                'tenant_id' => $tenantId,
                'scope_type' => 'device',
                'scope_id' => $deviceId,
                'action' => 'identity.login_succeeded',
                'metadata' => json_encode(['device_status' => $deviceStatus], JSON_THROW_ON_ERROR),
                'created_at' => $now,
            ]);

            return [
                'token' => $created->plainTextToken,
                'expires_at' => $token->expires_at?->toISOString(),
            ];
        });

        return response()->json([
            'token_type' => 'Bearer',
            'access_token' => $createdToken['token'],
            'expires_at' => $createdToken['expires_at'],
            'user' => [
                'id' => $user->getAuthIdentifier(),
                'name' => $user->name,
                'email' => $user->email,
            ],
            'tenant_id' => $tenantId,
            'device_id' => $deviceId,
            'device_status' => $deviceStatus,
        ]);
    }

    public function me(Request $request): JsonResponse
    {
        $user = $request->user();
        $token = $user?->currentAccessToken();

        if (! $user || ! $token instanceof PersonalAccessToken) {
            return response()->json(['message' => 'Sesi tidak aktif.', 'code' => 'session_inactive'], 403);
        }

        if (! $user->is_active) {
            $token->delete();

            return response()->json(['message' => 'Akun tidak aktif.', 'code' => 'user_inactive'], 403);
        }

        $tenantId = $token->tenant_id;
        $deviceId = $token->device_id;
        $membershipActive = $tenantId && TenantMembership::query()
            ->where('user_id', $user->getAuthIdentifier())
            ->where('tenant_id', $tenantId)
            ->where('status', 'active')
            ->whereHas('tenant', fn ($query) => $query->where('status', 'active'))
            ->exists();

        if (! $membershipActive) {
            $token->delete();
            return response()->json(['message' => 'Membership tenant tidak lagi aktif.', 'code' => 'tenant_membership_denied'], 403);
        }

        $device = $deviceId ? DeviceRegistry::query()->find($deviceId) : null;
        $deviceMatches = $device
            && $device->tenant_id === $tenantId
            && (int) $device->owner_user_id === (int) $user->getAuthIdentifier()
            && $device->revoked_at === null;
        $status = 'unregistered';

        if ($deviceMatches && $device->status === 'active' && $device->device_secret_hash && $token->can('*')) {
            $status = 'active';
        } elseif ($deviceMatches && $device->status === 'pending' && $device->device_secret_hash && $token->can('device:enroll')) {
            $status = 'pending';
        } elseif (! $device && $token->can('device:enroll')) {
            $status = 'unregistered';
        } else {
            $token->delete();
            return response()->json(['message' => 'Sesi perangkat tidak lagi valid.', 'code' => 'device_session_denied'], 403);
        }

        return response()->json([
            'user' => ['id' => $user->getAuthIdentifier(), 'name' => $user->name, 'email' => $user->email],
            'tenant_id' => $tenantId,
            'device_id' => $deviceId,
            'device_status' => $status,
            'expires_at' => $token->expires_at?->toISOString(),
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $user = $request->user();
        $token = $user?->currentAccessToken();

        if (! $user || ! $token instanceof PersonalAccessToken) {
            return response()->json(['message' => 'Sesi Bearer diperlukan.', 'code' => 'bearer_session_required'], 401);
        }

        $tenantId = $token->tenant_id;
        $deviceId = $token->device_id;
        $token->delete();
        $this->audit((int) $user->getAuthIdentifier(), $tenantId, 'device', $deviceId ?? (string) $user->getAuthIdentifier(), 'identity.logout');

        return response()->json(['status' => 'signed_out']);
    }

    public function logoutAll(Request $request): JsonResponse
    {
        $user = $request->user();
        $currentToken = $user?->currentAccessToken();

        if (! $user || ! $user->is_active || ! $currentToken instanceof PersonalAccessToken) {
            return response()->json(['message' => 'Sesi Bearer diperlukan.', 'code' => 'bearer_session_required'], 401);
        }

        $tenantId = $currentToken->tenant_id;
        $userId = (int) $user->getAuthIdentifier();
        $user->tokens()->delete();
        $this->audit($userId, $tenantId, 'user', (string) $userId, 'identity.logout_all');

        return response()->json(['status' => 'all_sessions_revoked']);
    }

    public function enrollDevice(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'device_secret' => ['required', 'string', 'regex:/^[a-f0-9]{64}$/'],
            'device_name' => ['nullable', 'string', 'max:120'],
            'platform' => ['nullable', Rule::in(['android', 'ios', 'macos', 'windows', 'linux', 'fuchsia', 'other'])],
        ]);

        $user = $request->user();
        $token = $user?->currentAccessToken();

        if (! $user || ! $user->is_active || ! $token instanceof PersonalAccessToken ||
            ! $token->tenant_id || ! $token->device_id || ! $token->can('device:enroll')) {
            return response()->json(['message' => 'Sesi enrollment perangkat tidak valid.', 'code' => 'device_enrollment_session_invalid'], 403);
        }

        $tenantId = $token->tenant_id;
        $deviceId = $token->device_id;
        $membershipActive = TenantMembership::query()
            ->where('user_id', $user->getAuthIdentifier())
            ->where('tenant_id', $tenantId)
            ->where('status', 'active')
            ->whereHas('tenant', fn ($query) => $query->where('status', 'active'))
            ->exists();

        if (! $membershipActive) {
            return response()->json(['message' => 'Membership tenant tidak lagi aktif.', 'code' => 'tenant_membership_denied'], 403);
        }

        $secretHash = hash('sha256', $validated['device_secret']);
        $now = now();

        DB::connection('central')->table('device_registry')->insertOrIgnore([
            'device_id' => $deviceId,
            'tenant_id' => $tenantId,
            'owner_user_id' => $user->getAuthIdentifier(),
            'status' => 'pending',
            'registered_at' => null,
            'device_name' => $validated['device_name'] ?? null,
            'platform' => $validated['platform'] ?? null,
            'device_secret_hash' => $secretHash,
            'revoked_at' => null,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $device = DeviceRegistry::query()->find($deviceId);
        if (! $device || $device->tenant_id !== $tenantId ||
            (int) $device->owner_user_id !== (int) $user->getAuthIdentifier() ||
            ! $device->device_secret_hash || ! hash_equals($device->device_secret_hash, $secretHash)) {
            return response()->json(['message' => 'Perangkat sudah terikat pada identitas lain.', 'code' => 'device_identity_conflict'], 409);
        }
        if ($device->status === 'revoked' || $device->revoked_at !== null) {
            return response()->json(['message' => 'Perangkat yang dicabut tidak dapat didaftarkan ulang dengan ID yang sama.', 'code' => 'device_revoked'], 409);
        }
        if ($device->status === 'active') {
            return response()->json(['message' => 'Perangkat sudah disetujui. Login ulang untuk mendapatkan sesi aktif.', 'code' => 'device_approval_requires_signin'], 409);
        }

        $this->audit((int) $user->getAuthIdentifier(), $tenantId, 'device', $deviceId, 'device.enrollment_requested', [
            'platform' => $validated['platform'] ?? null,
        ]);

        return response()->json([
            'status' => 'pending',
            'device_id' => $deviceId,
            'message' => 'Menunggu persetujuan administrator sebelum akses cloud diberikan.',
        ], Response::HTTP_ACCEPTED);
    }

    public function approveDevice(Request $request, string $deviceId): JsonResponse
    {
        $device = DeviceRegistry::query()->whereKey($deviceId)->firstOrFail();

        if ($device->status === 'revoked' || $device->revoked_at !== null || ! $device->device_secret_hash) {
            return response()->json(['message' => 'Perangkat yang dicabut atau belum memiliki bukti kepemilikan tidak dapat diaktifkan.', 'code' => 'device_not_approvable'], 409);
        }
        if ($device->status === 'active') {
            return response()->json(['status' => 'active', 'device_id' => $deviceId]);
        }

        $validOwner = $device->owner_user_id !== null && TenantMembership::query()
            ->where('user_id', $device->owner_user_id)
            ->where('tenant_id', $device->tenant_id)
            ->where('status', 'active')
            ->whereHas('tenant', fn ($query) => $query->where('status', 'active'))
            ->exists();

        if (! $validOwner) {
            return response()->json(['message' => 'Pemilik perangkat tidak memiliki membership tenant aktif.', 'code' => 'device_owner_not_active'], 409);
        }

        $device->forceFill(['status' => 'active', 'registered_at' => now(), 'revoked_at' => null])->save();
        // Re-login after approval creates a token with active-device abilities.
        PersonalAccessToken::query()->where('device_id', $deviceId)->delete();
        $this->audit((int) $request->user()->getAuthIdentifier(), $device->tenant_id, 'device', $deviceId, 'device.approved');

        return response()->json(['status' => 'active', 'device_id' => $deviceId]);
    }

    public function revokeDevice(Request $request, string $deviceId): JsonResponse
    {
        $device = DeviceRegistry::query()->whereKey($deviceId)->firstOrFail();
        if ($device->status !== 'revoked' || $device->revoked_at === null) {
            $device->forceFill(['status' => 'revoked', 'revoked_at' => now()])->save();
            PersonalAccessToken::query()->where('device_id', $deviceId)->delete();
            $this->audit((int) $request->user()->getAuthIdentifier(), $device->tenant_id, 'device', $deviceId, 'device.revoked');
        }

        return response()->json(['status' => 'revoked', 'device_id' => $deviceId]);
    }

    public function setMembership(Request $request, string $tenantId): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'string', 'email', 'max:255'],
            'role' => ['required', Rule::in(['owner', 'manager', 'cashier', 'accountant', 'member'])],
            'status' => ['required', Rule::in(['active', 'suspended'])],
        ]);

        $tenant = Tenant::query()->findOrFail($tenantId);
        if ($validated['status'] === 'active' && $tenant->status !== 'active') {
            return response()->json(['message' => 'Tenant belum aktif.', 'code' => 'tenant_not_active'], 409);
        }

        $email = mb_strtolower(trim($validated['email']));
        $member = User::query()->whereRaw('LOWER(email) = ?', [$email])->first();
        if (! $member) {
            return response()->json(['message' => 'Akun pengguna tidak ditemukan.', 'code' => 'user_not_found'], 404);
        }

        $now = now();
        $membership = DB::connection('central')->transaction(function () use ($member, $tenantId, $validated, $request, $now) {
            $membership = TenantMembership::query()->updateOrCreate(
                ['user_id' => $member->getAuthIdentifier(), 'tenant_id' => $tenantId],
                [
                    'role' => $validated['role'],
                    'status' => $validated['status'],
                    'invited_by' => $request->user()->getAuthIdentifier(),
                    'joined_at' => $validated['status'] === 'active' ? $now : null,
                ],
            );
            DB::connection('central')->table('audit_events')->insert([
                'actor_user_id' => $request->user()->getAuthIdentifier(),
                'tenant_id' => $tenantId,
                'scope_type' => 'membership',
                'scope_id' => (string) $member->getAuthIdentifier(),
                'action' => 'membership.'.$validated['status'],
                'metadata' => json_encode(['role' => $validated['role']], JSON_THROW_ON_ERROR),
                'created_at' => $now,
            ]);

            return $membership;
        });

        return response()->json([
            'user_id' => $membership->user_id,
            'tenant_id' => $membership->tenant_id,
            'role' => $membership->role,
            'status' => $membership->status,
        ], Response::HTTP_OK);
    }

    private function audit(int $actorId, ?string $tenantId, string $scopeType, string $scopeId, string $action, array $metadata = []): void
    {
        DB::connection('central')->table('audit_events')->insert([
            'actor_user_id' => $actorId,
            'tenant_id' => $tenantId,
            'scope_type' => $scopeType,
            'scope_id' => $scopeId,
            'action' => $action,
            'metadata' => json_encode($metadata, JSON_THROW_ON_ERROR),
            'created_at' => now(),
        ]);
    }
}
