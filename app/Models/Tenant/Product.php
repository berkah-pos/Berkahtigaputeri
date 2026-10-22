<?php

namespace App\Models\Tenant;

use Illuminate\Database\Eloquent\Model;

class Product extends Model
{
    protected $connection = 'tenant';
    protected $table = 'products';
    protected $primaryKey = 'id';
    public $incrementing = false;
    protected $keyType = 'string';
    protected $fillable = ['id', 'sku', 'barcode', 'name', 'category_id', 'price', 'requires_review', 'is_active'];

    protected function casts(): array
    {
        return [
            'price' => 'decimal:2',
            'requires_review' => 'boolean',
            'is_active' => 'boolean',
        ];
    }
}
