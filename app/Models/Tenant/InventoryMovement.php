<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

class InventoryMovement extends TenantModel
{
    protected $fillable = ['source_event_id','product_id','movement_type','quantity','reference_id','occurred_at'];
    protected $casts = ['quantity' => 'decimal:3','occurred_at' => 'immutable_datetime'];
    public function product(): BelongsTo { return $this->belongsTo(Product::class, 'product_id', 'id'); }
}
