<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Subscription extends CentralModel
{
    protected $fillable = ['tenant_id','plan','status','expires_at','provider_reference'];
    protected $casts = ['expires_at' => 'immutable_datetime'];
    public function tenant(): BelongsTo { return $this->belongsTo(Tenant::class, 'tenant_id', 'id'); }
}
