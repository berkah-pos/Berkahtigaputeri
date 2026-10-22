<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Relations\HasMany;
use Stancl\Tenancy\Database\Models\Tenant as StanclTenant;

class Tenant extends StanclTenant
{
    protected $connection = 'central';
    protected $fillable = ['id', 'data', 'template_id'];

    protected function casts(): array
    {
        return ['data' => 'array'];
    }

    public function getConnectionName(): string
    {
        return 'central';
    }

    public function domains(): HasMany
    {
        return $this->hasMany(Domain::class, 'tenant_id', 'id');
    }

    public function configurations(): HasMany
    {
        return $this->hasMany(TenantConfig::class, 'tenant_id', 'id');
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(Subscription::class, 'tenant_id', 'id');
    }

    public function devices(): HasMany
    {
        return $this->hasMany(DeviceRegistry::class, 'tenant_id', 'id');
    }
}
