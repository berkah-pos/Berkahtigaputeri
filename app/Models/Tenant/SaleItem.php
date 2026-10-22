<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SaleItem extends TenantModel
{
    protected $fillable = ['sale_id','product_id','product_name','quantity','unit_price','line_total','unit_cost'];
    protected $casts = ['quantity' => 'decimal:3','unit_price' => 'integer','line_total' => 'integer','unit_cost' => 'integer'];
    public function sale(): BelongsTo { return $this->belongsTo(Sale::class, 'sale_id', 'id'); }
    public function product(): BelongsTo { return $this->belongsTo(Product::class, 'product_id', 'id'); }
}
