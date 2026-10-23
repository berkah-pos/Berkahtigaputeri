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
    protected $hidden = ['device_secret_hash'];

    protected $fillable = [
        'device_id', 'tenant_id', 'owner_user_id', 'status', 'registered_at',
        'device_name', 'platform', 'device_secret_hash', 'revoked_at', 'last_seen_at',
    ];

    protected function casts(): array
    {
        return [
            'registered_at' => 'datetime',
            'revoked_at' => 'datetime',
            'last_seen_at' => 'datetime',
        ];
    }
}
