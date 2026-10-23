<?php

declare(strict_types=1);

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;

class GlobalConfig extends Model
{
    protected $connection = 'central';

    protected $table = 'global_configs';

    protected $primaryKey = 'key';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = ['key', 'config', 'version'];

    protected $casts = [
        'config' => 'array',
        'version' => 'integer',
    ];
}
