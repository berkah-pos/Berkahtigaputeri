<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Stancl\Tenancy\Contracts\TenantWithDatabase;
use Stancl\Tenancy\Contracts\TenantWithDomains;
use Stancl\Tenancy\Database\Models\Tenant as BaseTenant;
use Stancl\Tenancy\Database\Concerns\HasDatabase;
use Stancl\Tenancy\Database\Concerns\HasDomains;

class Tenant extends BaseTenant implements TenantWithDatabase, TenantWithDomains
{
    use HasDatabase, HasDomains;

    protected $connection = 'central';

    // Preserve stancl/tenancy's tenant data cast while applying the shared
    // configuration cast required by central configuration models.
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
}
