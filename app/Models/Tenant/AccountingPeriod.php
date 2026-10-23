<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Model;

class AccountingPeriod extends Model
{
    protected $connection = 'tenant';
    protected $table = 'accounting_periods';
    protected $fillable = ['starts_on', 'ends_on', 'status', 'closed_at', 'closed_by'];

    protected function casts(): array
    {
        return [
            'starts_on' => 'date',
            'ends_on' => 'date',
            'closed_at' => 'immutable_datetime',
        ];
    }
}
