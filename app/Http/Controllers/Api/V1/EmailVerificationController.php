<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Central\User;
use Illuminate\Auth\Events\Verified;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class EmailVerificationController extends Controller
{
    public function requestVerification(Request $request): JsonResponse
    {
        $payload = $request->validate([
            'email' => ['required', 'string', 'email', 'max:254'],
        ]);

        $email = mb_strtolower(trim($payload['email']));
        $user = User::query()->whereRaw('LOWER(email) = ?', [$email])->first();

        // Do not disclose whether an account is present, disabled, already
        // verified, or exempt from the verification requirement.
        if (! $user || ! $user->is_active ||
            ! $user->email_verification_required ||
            $user->hasVerifiedEmail() ||
            (app()->isProduction() && config('mail.default') === 'log')) {
            return $this->accepted();
        }

        $user->sendEmailVerificationNotification();

        return $this->accepted();
    }

    public function verify(Request $request, string $id, string $hash): JsonResponse
    {
        $user = User::query()->find($id);

        if (! $user || ! $user->is_active ||
            ! hash_equals(sha1($user->getEmailForVerification()), $hash)) {
            return response()->json([
                'error' => 'email_verification_invalid',
                'message' => 'The verification link is invalid or the account is no longer active.',
            ], 403);
        }

        if ($user->hasVerifiedEmail()) {
            return response()->json([
                'status' => 'already_verified',
                'message' => 'The email address is already verified. You may sign in.',
            ]);
        }

        if (! $user->markEmailAsVerified()) {
            return response()->json([
                'error' => 'email_verification_failed',
                'message' => 'The email address could not be verified. Request a new link.',
            ], 500);
        }

        DB::connection('central')->table('audit_events')->insert([
            'actor_user_id' => $user->getKey(),
            'tenant_id' => null,
            'scope_type' => 'identity',
            'scope_id' => (string) $user->getKey(),
            'action' => 'identity.email_verified',
            'previous_version' => null,
            'new_version' => null,
            'previous_sha256' => null,
            'new_sha256' => null,
            'metadata' => json_encode([
                'verification_method' => 'signed_email_link',
            ], JSON_THROW_ON_ERROR),
            'created_at' => now(),
        ]);

        event(new Verified($user));

        return response()->json([
            'status' => 'verified',
            'message' => 'Email verified. You may sign in and continue device enrollment.',
        ]);
    }

    private function accepted(): JsonResponse
    {
        return response()->json([
            'status' => 'accepted',
            'message' => 'If the account requires verification, a verification link will be sent to its email address.',
        ], 202);
    }
}
