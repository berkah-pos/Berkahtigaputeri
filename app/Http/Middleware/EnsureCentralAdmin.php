<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureCentralAdmin
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (! $user || ! $user->is_active || ! $user->is_super_admin) {
            return response()->json([
                'message' => 'Akses administrator pusat diperlukan.',
                'code' => 'central_admin_required',
            ], 403);
        }

        return $next($request);
    }
}
