<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Relations\HasMany;

class Sale extends TenantModel
{
    protected $fillable = ['id','device_id','source_event_id','status','payment_method','subtotal','tax_amount','total_amount','occurred_at'];
    protected $casts = ['subtotal' => 'integer','tax_amount' => 'integer','total_amount' => 'integer','occurred_at' => 'immutable_datetime'];
    public function items(): HasMany { return $this->hasMany(SaleItem::class, 'sale_id', 'id'); }
}
