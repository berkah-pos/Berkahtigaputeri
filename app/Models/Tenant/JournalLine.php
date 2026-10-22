<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

class JournalLine extends TenantModel
{
    protected $fillable = ['journal_entry_id','account_code','debit','credit'];
    protected $casts = ['debit' => 'integer','credit' => 'integer'];
    public function journalEntry(): BelongsTo { return $this->belongsTo(JournalEntry::class, 'journal_entry_id', 'id'); }
    public function account(): BelongsTo { return $this->belongsTo(ChartOfAccount::class, 'account_code', 'code'); }
}
