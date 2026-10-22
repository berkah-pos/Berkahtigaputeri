<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;

class Domain extends Model
{
    protected $connection = 'central';
    protected $table = 'domains';
    protected $primaryKey = 'domain';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['domain', 'tenant_id'];
}
