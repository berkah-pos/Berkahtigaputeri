<?php

namespace Database\Seeders;

use App\Models\Central\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        // No default credentials are shipped. Set all three variables explicitly
        // during the first controlled bootstrap if a central administrator is needed.
        $email = trim((string) env('CENTRAL_ADMIN_EMAIL'));
        $password = (string) env('CENTRAL_ADMIN_PASSWORD');
        $name = trim((string) env('CENTRAL_ADMIN_NAME', 'Central Administrator'));
        if ($email === '' || $password === '') {
            return;
        }
        if (strlen($password) < 16) {
            throw new \RuntimeException('CENTRAL_ADMIN_PASSWORD must be at least 16 characters.');
        }

        User::query()->updateOrCreate(
            ['email' => strtolower($email)],
            [
                'name' => $name ?: 'Central Administrator',
                'password' => Hash::make($password),
                'is_super_admin' => true,
                'is_active' => true,
            ]
        );
    }
}
