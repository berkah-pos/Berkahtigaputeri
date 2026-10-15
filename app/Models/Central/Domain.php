<?php

namespace App\Models\Central;

use App\Services\TenantHostResolver;
use Stancl\Tenancy\Database\Models\Domain as BaseDomain;

class Domain extends BaseDomain
{
    protected $connection = 'central';

    protected $fillable = ['domain', 'tenant_id', 'is_active'];

    protected $casts = [
        'is_active' => 'boolean',
    ];

    protected static function booted(): void
    {
        static::saving(function (Domain $domain): void {
            $resolver = app(TenantHostResolver::class);
            $resolver->forgetHosts([
                (string) $domain->getOriginal('domain'),
                (string) $domain->domain,
            ]);
            $domain->domain = strtolower(rtrim(trim((string) $domain->domain), '.'));
            $resolver->forgetHosts([(string) $domain->domain]);
        });

        static::deleting(function (Domain $domain): void {
            app(TenantHostResolver::class)->forgetHosts([(string) $domain->domain]);
        });
    }
}
