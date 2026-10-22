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
    protected $fillable = ['id', 'config', 'version'];

    protected function casts(): array
    {
        return [
            'config' => 'array',
            'version' => 'integer',
        ];
    }
}
