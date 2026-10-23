<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Model;

class AuditEvent extends Model
{
    protected $connection = 'central';
    protected $table = 'audit_events';
    public $timestamps = false;
    protected $fillable = ['actor_user_id', 'tenant_id', 'scope_type', 'scope_id', 'action', 'previous_version', 'new_version', 'previous_sha256', 'new_sha256', 'metadata'];

    protected function casts(): array
    {
        return [
            'previous_version' => 'integer',
            'new_version' => 'integer',
            'metadata' => 'array',
            'created_at' => 'immutable_datetime',
        ];
    }
}
