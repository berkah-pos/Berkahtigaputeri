<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

class InventoryLot extends TenantModel
{
    protected $fillable = ['id','product_id','batch_code','expires_at','quantity_received','quantity_remaining','unit_cost','received_at'];
    protected $casts = ['expires_at' => 'immutable_date','quantity_received' => 'decimal:3','quantity_remaining' => 'decimal:3','unit_cost' => 'integer','received_at' => 'immutable_datetime'];
    public function product(): BelongsTo { return $this->belongsTo(Product::class, 'product_id', 'id'); }
}
