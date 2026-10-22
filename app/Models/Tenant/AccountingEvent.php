<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Model;

class AccountingEvent extends Model
{
    protected $connection = 'tenant';
    protected $table = 'accounting_events';
    public $timestamps = false;
    protected $fillable = ['journal_entry_id', 'actor_id', 'device_id', 'app_version', 'action', 'occurred_at', 'metadata'];

    protected function casts(): array
    {
        return [
            'occurred_at' => 'immutable_datetime',
            'metadata' => 'array',
        ];
    }
}
