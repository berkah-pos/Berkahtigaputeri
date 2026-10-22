<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DeviceRegistry extends Model
{
    protected $connection = 'central';

    protected $table = 'device_registry';

    protected $primaryKey = 'device_id';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'device_id',
        'tenant_id',
        'owner_user_id',
        'status',
        'device_name',
        'registered_at',
        'enrollment_requested_at',
        'revoked_at',
    ];

    protected function casts(): array
    {
        return [
            'registered_at' => 'datetime',
            'enrollment_requested_at' => 'datetime',
            'revoked_at' => 'datetime',
        ];
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_user_id');
    }
}
