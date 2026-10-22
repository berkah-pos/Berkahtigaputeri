<?php

namespace App\Console\Commands;

use App\Models\Central\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class BootstrapPlatformAdmin extends Command
{
    protected $signature = 'platform:bootstrap-admin';

    protected $description = 'Create the first platform administrator interactively (one-time bootstrap).';

    public function handle(): int
    {
        if (User::query()->where('is_super_admin', true)->exists()) {
            $this->error('A platform administrator already exists; refusing to bootstrap another.');

            return self::FAILURE;
        }

        $name = trim((string) $this->ask('Platform administrator name'));
        $email = mb_strtolower(trim((string) $this->ask('Platform administrator email')));
        $password = (string) $this->secret('Password (minimum 16 characters)');
        $passwordConfirmation = (string) $this->secret('Confirm password');

        if ($name === '' || mb_strlen($name) > 120) {
            $this->error('Name must contain between 1 and 120 characters.');

            return self::INVALID;
        }

        if (mb_strlen($email) > 254 || filter_var($email, FILTER_VALIDATE_EMAIL) === false) {
            $this->error('A valid email address is required.');

            return self::INVALID;
        }

        if (mb_strlen($password) < 16) {
            $this->error('The password must contain at least 16 characters.');

            return self::INVALID;
        }

        if (! hash_equals($password, $passwordConfirmation)) {
            $this->error('The password confirmation does not match.');

            return self::INVALID;
        }

        $result = DB::connection('central')->transaction(function () use ($name, $email, $password): array {
            // PostgreSQL advisory transaction lock serializes two simultaneous
            // first-admin bootstraps even while the users table is empty.
            DB::connection('central')->select(
                'SELECT pg_advisory_xact_lock(hashtext(?))',
                ['berkah-pos-platform-admin-bootstrap'],
            );

            if (DB::connection('central')->table('users')->where('is_super_admin', true)->exists()) {
                return ['state' => 'admin_exists'];
            }

            if (DB::connection('central')->table('users')->whereRaw('LOWER(email) = ?', [$email])->exists()) {
                return ['state' => 'email_exists'];
            }

            $user = new User();
            $user->name = $name;
            $user->email = $email;
            // User's hashed cast performs password hashing before persistence.
            $user->password = $password;
            $user->tenant_id = null;
            $user->is_super_admin = true;
            $user->is_active = true;
            $user->save();

            DB::connection('central')->table('audit_events')->insert([
                'actor_user_id' => $user->getKey(),
                'tenant_id' => null,
                'scope_type' => 'identity',
                'scope_id' => (string) $user->getKey(),
                'action' => 'identity.platform_admin_bootstrapped',
                'previous_version' => null,
                'new_version' => null,
                'previous_sha256' => null,
                'new_sha256' => null,
                'metadata' => json_encode([
                    'email' => $email,
                    'method' => 'interactive_cli',
                ], JSON_THROW_ON_ERROR),
                'created_at' => now(),
            ]);

            return ['state' => 'created', 'user_id' => (int) $user->getKey()];
        }, 3);

        if ($result['state'] === 'admin_exists') {
            $this->error('A platform administrator already exists; refusing to bootstrap another.');

            return self::FAILURE;
        }

        if ($result['state'] === 'email_exists') {
            $this->error('That email already belongs to an account. No account was created.');

            return self::FAILURE;
        }

        $this->info('The first platform administrator was created successfully.');
        $this->line('User ID: ' . $result['user_id']);
        $this->line('No password or token was written to output.');

        return self::SUCCESS;
    }
}
