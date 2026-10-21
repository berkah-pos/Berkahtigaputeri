<?php

namespace App\Models\Central;

use Stancl\Tenancy\Database\Models\Tenant as BaseTenant;

class Tenant extends BaseTenant
{
    protected $connection = 'central';

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'data' => 'array',
        ];
    }
}
