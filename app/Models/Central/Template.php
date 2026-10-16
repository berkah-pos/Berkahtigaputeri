<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;

class Template extends Model
{
    protected $connection = 'central';

    protected $primaryKey = 'id';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = ['id', 'config', 'version', 'max_users'];

    protected $casts = [
        'config' => 'array',
        'version' => 'integer',
        'max_users' => 'integer',
    ];
}
