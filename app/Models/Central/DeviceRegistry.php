<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DeviceRegistry extends CentralModel
{
    protected $table = 'device_registry';
    protected $primaryKey = 'device_id';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['device_id','tenant_id','owner_user_id','status','registered_at'];
    protected $casts = ['registered_at' => 'immutable_datetime'];
    public function tenant(): BelongsTo { return $this->belongsTo(Tenant::class, 'tenant_id', 'id'); }
    public function owner(): BelongsTo { return $this->belongsTo(User::class, 'owner_user_id'); }
}
