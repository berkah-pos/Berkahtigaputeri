<?php

namespace App\Models\Central;

use Filament\Models\Contracts\FilamentUser;
use Filament\Panel;
use Illuminate\Auth\MustVerifyEmail as MustVerifyEmailTrait;
use Illuminate\Contracts\Auth\MustVerifyEmail as MustVerifyEmailContract;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable implements FilamentUser, MustVerifyEmailContract
{
    use HasApiTokens, HasFactory, Notifiable, MustVerifyEmailTrait;

    protected $connection = 'central';

    protected $fillable = [
        'name', 'email', 'password', 'tenant_id', 'is_super_admin', 'is_active',
    ];

    protected $hidden = ['password', 'remember_token'];

    public function canAccessPanel(Panel $panel): bool
    {
        return $this->is_active && $this->is_super_admin;
    }

    public function tenantMemberships(): HasMany
    {
        return $this->hasMany(TenantMembership::class, 'user_id');
    }

    public function devices(): HasMany
    {
        return $this->hasMany(DeviceRegistry::class, 'owner_user_id');
    }

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'is_super_admin' => 'boolean',
            'is_active' => 'boolean',
            'email_verification_required' => 'boolean',
        ];
    }
}
