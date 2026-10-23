<?php

declare(strict_types=1);

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;

class Template extends Model
{
    protected $connection = 'central';

    protected $table = 'templates';

    protected $primaryKey = 'id';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = ['id', 'config', 'version'];

    protected $casts = [
        'config' => 'array',
        'version' => 'integer',
    ];
}
