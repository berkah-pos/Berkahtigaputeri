<?php

namespace App\Models\Central;

class GlobalConfig extends CentralModel
{
    protected $table = 'global_configs';
    protected $primaryKey = 'key';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['key','config','version'];
    protected $casts = ['config' => 'array','version' => 'integer'];
}
