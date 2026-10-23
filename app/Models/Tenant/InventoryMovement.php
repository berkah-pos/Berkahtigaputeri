<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Model;

class InventoryMovement extends Model
{
    protected $connection = 'tenant';
    protected $table = 'inventory_movements';
    protected $fillable = ['source_event_id', 'product_id', 'movement_type', 'quantity', 'reference_id', 'occurred_at'];

    protected function casts(): array
    {
        return [
            'quantity' => 'decimal:3',
            'occurred_at' => 'immutable_datetime',
        ];
    }
}
