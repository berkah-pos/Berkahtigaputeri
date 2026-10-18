<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;

class TenantConfig extends Model
{
    protected $connection = 'central';

    protected $table = 'tenant_configs';

    protected $fillable = ['tenant_id', 'service', 'service_scope', 'template_id', 'config', 'version'];

    protected $casts = [
        'config' => 'array',
        'version' => 'integer',
    ];
}
