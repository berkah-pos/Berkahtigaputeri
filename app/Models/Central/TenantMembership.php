<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class TenantMembership extends Model
{
    protected $connection = 'central';

    protected $fillable = [
        'user_id', 'tenant_id', 'role', 'status', 'invited_by', 'joined_at',
    ];

    protected function casts(): array
    {
        return ['joined_at' => 'datetime'];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class, 'tenant_id', 'id');
    }
}
