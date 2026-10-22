<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;

class Subscription extends Model
{
    protected $connection = 'central';
    protected $table = 'subscriptions';
    protected $fillable = ['tenant_id', 'plan', 'status', 'expires_at', 'provider_reference'];

    protected function casts(): array
    {
        return [
            'expires_at' => 'immutable_datetime',
        ];
    }
}
