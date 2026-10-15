<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Stancl\Tenancy\Facades\Tenancy;

class TenantContextController extends Controller
{
    public function __invoke(): JsonResponse
    {
        $tenant = Tenancy::tenant();
        abort_if($tenant === null, 404);

        return response()->json([
            'tenant_id' => (string) $tenant->getTenantKey(),
            'context_initialized' => true,
        ]);
    }
}
