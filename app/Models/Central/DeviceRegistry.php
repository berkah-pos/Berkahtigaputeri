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

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'owner_user_id' => 'integer',
            'registered_at' => 'datetime',
        ];
    }
}
