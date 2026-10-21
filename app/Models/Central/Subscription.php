<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;

class Subscription extends Model
{
    protected $connection = 'central';

    protected $table = 'subscriptions';

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'expires_at' => 'datetime',
        ];
    }
}
