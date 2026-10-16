<?php

namespace App\Models\Central;

use App\Services\TenantHostResolver;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Stancl\Tenancy\Contracts\TenantWithDatabase;
use Stancl\Tenancy\Database\Concerns\HasDatabase;
use Stancl\Tenancy\Database\Concerns\HasDomains;
use Stancl\Tenancy\Database\Models\Tenant as BaseTenant;

class Tenant extends BaseTenant implements TenantWithDatabase
{
    use HasDatabase, HasDomains;

    protected $connection = 'central';

    protected $casts = [
        'data' => 'array',
        'config' => 'array',
        'is_active' => 'boolean',
        'store_name' => 'string',
    ];

    public static function getCustomColumns(): array
    {
        return ['id', 'template_id', 'store_name', 'is_active'];
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(Subscription::class, 'tenant_id', 'id');
    }

    public function latestSubscription(): HasOne
    {
        return $this->hasOne(Subscription::class, 'tenant_id', 'id')->latestOfMany();
    }

    protected static function booted(): void
    {
        static::updating(function (Tenant $tenant): void {
            app(TenantHostResolver::class)->forgetTenantDomains((string) $tenant->getTenantKey());
        });

        static::deleting(function (Tenant $tenant): void {
            app(TenantHostResolver::class)->forgetTenantDomains((string) $tenant->getTenantKey());
        });
    }
}
