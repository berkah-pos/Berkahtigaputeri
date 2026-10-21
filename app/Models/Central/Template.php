<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;

class Template extends Model
{
    protected $connection = 'central';

    protected $table = 'templates';

    protected $primaryKey = 'id';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'config' => 'array',
            'version' => 'integer',
        ];
    }
}
