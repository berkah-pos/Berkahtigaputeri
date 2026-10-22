<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Model;

class InventoryLot extends Model
{
    protected $connection = 'tenant';
    protected $table = 'inventory_lots';
    protected $primaryKey = 'id';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['id', 'product_id', 'batch_code', 'expires_at', 'quantity_received', 'quantity_remaining', 'unit_cost', 'received_at'];

    protected function casts(): array
    {
        return [
            'expires_at' => 'date',
            'received_at' => 'immutable_datetime',
            'quantity_received' => 'decimal:3',
            'quantity_remaining' => 'decimal:3',
            'unit_cost' => 'decimal:2',
        ];
    }
}
