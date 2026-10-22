<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Relations\HasMany;
use Stancl\Tenancy\Contracts\TenantWithDatabase;
use Stancl\Tenancy\Database\Concerns\HasDatabase;
use Stancl\Tenancy\Database\Models\Tenant as StanclTenant;

class Tenant extends StanclTenant implements TenantWithDatabase
{
    use HasDatabase;

    protected $connection = 'central';
    protected $table = 'tenants';
    protected $primaryKey = 'id';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['id','template_id','data'];
    protected $casts = ['data' => 'array'];

    public function getConnectionName() { return 'central'; }
    public function domains(): HasMany { return $this->hasMany(Domain::class, 'tenant_id', 'id'); }
    public function subscriptions(): HasMany { return $this->hasMany(Subscription::class, 'tenant_id', 'id'); }
    public function configuration(): HasMany { return $this->hasMany(TenantConfig::class, 'tenant_id', 'id'); }
    public function devices(): HasMany { return $this->hasMany(DeviceRegistry::class, 'tenant_id', 'id'); }
}
