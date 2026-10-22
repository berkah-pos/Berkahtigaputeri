<?php

namespace App\Models\Central;

use Illuminate\Database\Eloquent\Relations\BelongsTo;

class TenantConfig extends CentralModel
{
    protected $fillable = ['tenant_id','service','service_scope','template_id','config','version'];
    protected $casts = ['config' => 'array','version' => 'integer'];
    public function tenant(): BelongsTo { return $this->belongsTo(Tenant::class, 'tenant_id', 'id'); }
    public function template(): BelongsTo { return $this->belongsTo(Template::class, 'template_id', 'id'); }
}
