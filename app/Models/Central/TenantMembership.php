<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class TenantMembership extends Model
{
    protected $connection = 'central';

    protected $table = 'tenant_memberships';

    protected $fillable = [
        'user_id',
        'tenant_id',
        'role',
        'status',
        'activated_at',
        'revoked_at',
    ];

    protected function casts(): array
    {
        return [
            'activated_at' => 'datetime',
            'revoked_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
