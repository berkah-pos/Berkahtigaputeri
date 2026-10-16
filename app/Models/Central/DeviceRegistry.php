<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;

class DeviceRegistry extends Model
{
    protected $connection = 'central';

    protected $table = 'device_registry';

    protected $primaryKey = 'device_id';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'device_id', 'tenant_id', 'owner_user_id', 'status', 'registered_at',
        'platform', 'hardware_mode', 'device_model',
    ];

    protected $casts = [
        'config' => 'array',
        'registered_at' => 'datetime',
        'owner_user_id' => 'integer',
    ];
}
