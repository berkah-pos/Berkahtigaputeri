<?php

namespace App\Models\Tenant;

class SyncReceipt extends TenantModel
{
    protected $primaryKey = 'event_id';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['event_id','device_id','payload_sha256','response','accepted_at'];
    protected $casts = ['response' => 'array','accepted_at' => 'immutable_datetime'];
}
