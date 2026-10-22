<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Relations\HasMany;

class ChartOfAccount extends TenantModel
{
    protected $table = 'chart_of_accounts';
    protected $primaryKey = 'code';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['code','name','account_type','normal_balance','is_locked'];
    protected $casts = ['is_locked' => 'boolean'];
    public function journalLines(): HasMany { return $this->hasMany(JournalLine::class, 'account_code', 'code'); }
}
