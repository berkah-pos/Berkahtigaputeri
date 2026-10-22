<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AccountingEvent extends TenantModel
{
    protected $fillable = ['journal_entry_id','event_type','actor_user_id','device_id','app_version','occurred_at','metadata'];
    protected $casts = ['actor_user_id' => 'integer','occurred_at' => 'immutable_datetime','metadata' => 'array'];
    public function journalEntry(): BelongsTo { return $this->belongsTo(JournalEntry::class, 'journal_entry_id', 'id'); }
}
