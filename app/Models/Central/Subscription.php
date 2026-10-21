<?php

declare(strict_types=1);

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;

class Subscription extends Model
{
    protected $connection = 'central';

    protected $table = 'subscriptions';

    protected $fillable = [
        'tenant_id',
        'plan',
        'status',
        'expires_at',
        'provider_reference',
    ];

    protected $casts = [
        'expires_at' => 'datetime',
    ];
}
