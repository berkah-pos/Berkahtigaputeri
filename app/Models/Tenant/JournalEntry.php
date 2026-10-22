<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class JournalEntry extends TenantModel
{
    protected $primaryKey = 'id';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['id','source_event_id','description','journal_date','status','posted_at','posted_by_user_id','posted_by_device_id','app_version','accounting_period_id','reversal_of_entry_id','reversal_reason'];
    protected $casts = ['journal_date' => 'immutable_date','posted_at' => 'immutable_datetime','posted_by_user_id' => 'integer','accounting_period_id' => 'integer'];
    public function lines(): HasMany { return $this->hasMany(JournalLine::class, 'journal_entry_id', 'id'); }
    public function accountingPeriod(): BelongsTo { return $this->belongsTo(AccountingPeriod::class, 'accounting_period_id'); }
    public function reversalOf(): BelongsTo { return $this->belongsTo(self::class, 'reversal_of_entry_id', 'id'); }
    public function events(): HasMany { return $this->hasMany(AccountingEvent::class, 'journal_entry_id', 'id'); }
}
