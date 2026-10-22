<?php

namespace App\Models\Central;

class Template extends CentralModel
{
    protected $table = 'templates';
    protected $primaryKey = 'id';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['id','config','version'];
    protected $casts = ['config' => 'array','version' => 'integer'];
}
