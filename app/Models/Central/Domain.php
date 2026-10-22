<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Stancl\Tenancy\Database\Models\Domain as StanclDomain;

class Domain extends StanclDomain
{
    protected $connection = 'central';
    protected $primaryKey = 'domain';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['domain','tenant_id'];

    public function getConnectionName() { return 'central'; }
    public function tenant(): BelongsTo { return $this->belongsTo(Tenant::class, 'tenant_id', 'id'); }
}
