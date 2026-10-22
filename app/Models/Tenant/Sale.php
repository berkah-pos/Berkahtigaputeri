<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Model;

class Sale extends Model
{
    protected $connection = 'tenant';
    protected $table = 'sales';
    protected $primaryKey = 'id';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['id', 'device_id', 'source_event_id', 'status', 'payment_method', 'subtotal', 'tax_amount', 'total_amount', 'occurred_at'];

    protected function casts(): array
    {
        return [
            'subtotal' => 'decimal:2',
            'tax_amount' => 'decimal:2',
            'total_amount' => 'decimal:2',
            'occurred_at' => 'immutable_datetime',
        ];
    }
}
