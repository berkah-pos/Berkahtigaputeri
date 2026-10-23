<?php

declare(strict_types=1);

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;

class DeviceConfig extends Model
{
    protected $connection = 'central';

    protected $table = 'device_configs';

    protected $primaryKey = 'device_id';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'device_id',
        'tenant_id',
        'config',
        'version',
    ];

    protected $casts = [
        'config' => 'array',
        'version' => 'integer',
    ];
}
