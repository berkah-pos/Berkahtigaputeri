<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Model;

class SaleItem extends Model
{
    protected $connection = 'tenant';
    protected $table = 'sale_items';
    protected $fillable = ['sale_id', 'product_id', 'product_name', 'quantity', 'unit_price', 'line_total', 'unit_cost'];

    protected function casts(): array
    {
        return [
            'quantity' => 'decimal:3',
            'unit_price' => 'decimal:2',
            'line_total' => 'decimal:2',
            'unit_cost' => 'decimal:2',
        ];
    }
}
