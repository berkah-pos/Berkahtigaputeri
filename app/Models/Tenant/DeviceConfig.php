<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Model;

class DeviceConfig extends Model
{
    protected $connection = 'tenant';
    protected $table = 'device_configs';
    protected $primaryKey = 'device_id';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['device_id', 'config', 'version'];

    protected function casts(): array
    {
        return [
            'config' => 'array',
            'version' => 'integer',
        ];
    }
}
