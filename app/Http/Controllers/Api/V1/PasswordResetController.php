<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Central\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Str;

class PasswordResetController extends Controller
{
    public function requestResetLink(Request $request): JsonResponse
    {
        $payload = $request->validate([
            'email' => ['required', 'string', 'email', 'max:254'],
        ]);

        $email = mb_strtolower(trim($payload['email']));
        $user = User::query()->whereRaw('LOWER(email) = ?', [$email])->first();

        // Avoid leaking whether an identity exists or is disabled. In production,
        // never create a reset token when the configured mailer would log the
        // message body (and therefore the reset secret) to application logs.
        if (! $user || ! $user->is_active ||
            (app()->isProduction() && config('mail.default') === 'log')) {
            return $this->accepted();
        }

        Password::broker('users')->sendResetLink(['email' => $user->email]);

        // Broker outcomes (sent, throttled, or unavailable identity) are not
        // exposed to the caller to avoid account enumeration.
        return $this->accepted();
    }

    public function resetPassword(Request $request): JsonResponse
    {
        $payload = $request->validate([
            'email' => ['required', 'string', 'email', 'max:254'],
            'token' => ['required', 'string', 'min:20', 'max:512'],
            'password' => ['required', 'string', 'min:16', 'max:4096', 'confirmed'],
        ]);

        $email = mb_strtolower(trim($payload['email']));
        $user = User::query()->whereRaw('LOWER(email) = ?', [$email])->first();

        if (! $user || ! $user->is_active) {
            return $this->invalidReset();
        }

        $status = Password::broker('users')->reset([
            'email' => $user->email,
            'token' => $payload['token'],
            'password' => $payload['password'],
            'password_confirmation' => $payload['password_confirmation'],
        ], function (User $resetUser, string $password): void {
            $resetUser->forceFill([
                'password' => $password,
                'remember_token' => Str::random(60),
            ])->save();

            // Password reset invalidates every previously issued API session.
            $revokedCount = (int) $resetUser->tokens()->count();
            $resetUser->tokens()->delete();

            $auditEvent = [
                'actor_user_id' => $resetUser->getKey(),
                'tenant_id' => null,
                'scope_type' => 'identity',
                'scope_id' => (string) $resetUser->getKey(),
                'action' => 'identity.password_reset',
                'previous_version' => null,
                'new_version' => null,
                'previous_sha256' => null,
                'new_sha256' => null,
                'metadata' => json_encode(['revoked_token_count' => $revokedCount], JSON_THROW_ON_ERROR),
                'created_at' => now(),
            ];

            DB::connection('central')->table('audit_events')->insert($auditEvent);
        });

        if ($status !== Password::PASSWORD_RESET) {
            return $this->invalidReset();
        }

        return response()->json([
            'status' => 'password_reset',
            'message' => 'Password updated. Sign in again on each device.',
        ]);
    }

    private function accepted(): JsonResponse
    {
        return response()->json([
            'status' => 'accepted',
            'message' => 'If the account is eligible, a password reset link will be sent to its email address.',
        ], 202);
    }

    private function invalidReset(): JsonResponse
    {
        return response()->json([
            'error' => 'password_reset_invalid',
            'message' => 'The reset request is invalid or expired. Request a new reset link and try again.',
        ], 422);
    }
}
