<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Model;

class JournalLine extends Model
{
    protected $connection = 'tenant';
    protected $table = 'journal_lines';
    protected $fillable = ['journal_entry_id', 'account_code', 'debit', 'credit'];

    protected function casts(): array
    {
        return [
            'debit' => 'decimal:2',
            'credit' => 'decimal:2',
        ];
    }
}
