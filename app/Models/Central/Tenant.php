<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Tenant extends Model
{
    protected $connection = 'central';
    protected $table = 'tenants';
    protected $keyType = 'string';
    public $incrementing = false;

    protected $fillable = ['id', 'data', 'template_id', 'status'];

    protected function casts(): array
    {
        return ['data' => 'array'];
    }

    public function memberships(): HasMany
    {
        return $this->hasMany(TenantMembership::class, 'tenant_id', 'id');
    }
}
