<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Model;

class SyncReceipt extends Model
{
    protected $connection = 'tenant';
    protected $table = 'sync_receipts';
    protected $primaryKey = 'event_id';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['event_id', 'device_id', 'payload_sha256', 'response', 'accepted_at'];

    protected function casts(): array
    {
        return [
            'response' => 'array',
            'accepted_at' => 'immutable_datetime',
        ];
    }
}
