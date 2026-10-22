<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AuditEvent extends CentralModel
{
    protected $table = 'audit_events';
    public $timestamps = false;
    protected $fillable = ['actor_user_id','tenant_id','scope_type','scope_id','action','previous_version','new_version','previous_sha256','new_sha256','metadata','created_at'];
    protected $casts = ['metadata' => 'array','created_at' => 'immutable_datetime'];
    public function actor(): BelongsTo { return $this->belongsTo(User::class, 'actor_user_id'); }
}
