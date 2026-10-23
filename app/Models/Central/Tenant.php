<?php

declare(strict_types=1);

namespace App\Models\Central;

use Stancl\Tenancy\Contracts\TenantWithDatabase;
use Stancl\Tenancy\Database\Concerns\HasDatabase;
use Stancl\Tenancy\Database\Concerns\HasDomains;
use Stancl\Tenancy\Database\Models\Tenant as BaseTenant;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Tenant extends BaseTenant implements TenantWithDatabase
{
    use HasDatabase;
    use HasDomains;

    protected $connection = 'central';

    protected $table = 'tenants';

    protected $fillable = ['id', 'data', 'template_id', 'status'];

    protected $casts = [
        'data' => 'array',
    ];

    public function memberships(): HasMany
    {
        return $this->hasMany(TenantMembership::class, 'tenant_id', 'id');
    }

    /**
     * Tenant metadata must always be loaded from the central database.
     * The active tenant database is resolved separately by stancl/tenancy.
     */
    public function getConnectionName()
    {
        return 'central';
    }
}
