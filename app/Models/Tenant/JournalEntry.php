<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Model;

class JournalEntry extends Model
{
    protected $connection = 'tenant';
    protected $table = 'journal_entries';
    protected $primaryKey = 'id';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['id', 'source_event_id', 'description', 'journal_date', 'status', 'posted_at', 'posted_by', 'device_id', 'app_version', 'period_id', 'reversal_of_id'];

    protected function casts(): array
    {
        return [
            'journal_date' => 'date',
            'posted_at' => 'immutable_datetime',
            'period_id' => 'integer',
        ];
    }
}
