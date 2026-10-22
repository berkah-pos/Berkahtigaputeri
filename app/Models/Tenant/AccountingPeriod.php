<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Relations\HasMany;

class AccountingPeriod extends TenantModel
{
    protected $fillable = ['period_key','starts_on','ends_on','status','closed_at','closed_by_user_id'];
    protected $casts = ['starts_on' => 'immutable_date','ends_on' => 'immutable_date','closed_at' => 'immutable_datetime','closed_by_user_id' => 'integer'];
    public function journalEntries(): HasMany { return $this->hasMany(JournalEntry::class, 'accounting_period_id'); }
}
