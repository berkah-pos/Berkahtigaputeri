<?php

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
    protected function casts(): array
    {
        return ['config' => 'array', 'version' => 'integer'];
    }
}
