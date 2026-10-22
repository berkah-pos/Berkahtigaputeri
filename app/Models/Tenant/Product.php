<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Relations\HasMany;

class Product extends TenantModel
{
    protected $fillable = ['id','sku','barcode','name','category_id','price','requires_review','is_active'];
    protected $casts = ['price' => 'integer','requires_review' => 'boolean','is_active' => 'boolean'];
    public function inventoryLots(): HasMany { return $this->hasMany(InventoryLot::class, 'product_id', 'id'); }
    public function saleItems(): HasMany { return $this->hasMany(SaleItem::class, 'product_id', 'id'); }
}
