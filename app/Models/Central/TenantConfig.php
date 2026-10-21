<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;

class TenantConfig extends Model
{
    protected $connection = 'central';

    protected $table = 'tenant_configs';

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'config' => 'array',
            'version' => 'integer',
        ];
    }
}
