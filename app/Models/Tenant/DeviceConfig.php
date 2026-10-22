<?php

namespace App\Models\Tenant;

class DeviceConfig extends TenantModel
{
    protected $table = 'device_configs';
    protected $primaryKey = 'device_id';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['device_id','config','version'];
    protected $casts = ['config' => 'array','version' => 'integer'];
}
