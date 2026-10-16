<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class TenantProductController extends Controller
{
    public function index(): JsonResponse
    {
        $products = DB::connection('tenant')->table('products')
            ->where('is_active', true)
            ->orderBy('name')
            ->get(['id', 'sku', 'barcode', 'name', 'price', 'category_id', 'requires_review', 'is_active']);

        return response()->json(['data' => $products]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'id' => ['sometimes', 'string', 'max:100', 'regex:/^[A-Za-z0-9_-]+$/'],
            'sku' => ['nullable', 'string', 'max:100'],
            'barcode' => ['nullable', 'string', 'max:100'],
            'name' => ['required', 'string', 'max:255'],
            'price' => ['required', 'numeric', 'min:0', 'max:9999999999999999.99'],
            'category_id' => ['nullable', 'string', 'max:100'],
            'requires_review' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        $id = (string) ($data['id'] ?? Str::ulid());
        $now = now();
        DB::connection('tenant')->table('products')->insert([
            'id' => $id,
            'sku' => $data['sku'] ?? null,
            'barcode' => $data['barcode'] ?? null,
            'name' => $data['name'],
            'price' => (string) $data['price'],
            'category_id' => $data['category_id'] ?? null,
            'requires_review' => (bool) ($data['requires_review'] ?? false),
            'is_active' => (bool) ($data['is_active'] ?? true),
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        return response()->json([
            'data' => DB::connection('tenant')->table('products')->where('id', $id)->first(),
        ], 201);
    }

    public function show(string $productId): JsonResponse
    {
        $product = DB::connection('tenant')->table('products')
            ->where('id', $productId)
            ->first(['id', 'sku', 'barcode', 'name', 'price', 'category_id', 'requires_review', 'is_active']);

        abort_if($product === null, 404);

        return response()->json(['data' => $product]);
    }

    public function update(Request $request, string $productId): JsonResponse
    {
        $data = $request->validate([
            'sku' => ['sometimes', 'nullable', 'string', 'max:100'],
            'barcode' => ['sometimes', 'nullable', 'string', 'max:100'],
            'name' => ['sometimes', 'required', 'string', 'max:255'],
            'price' => ['sometimes', 'numeric', 'min:0', 'max:9999999999999999.99'],
            'category_id' => ['sometimes', 'nullable', 'string', 'max:100'],
            'requires_review' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        $query = DB::connection('tenant')->table('products')->where('id', $productId);
        abort_unless((clone $query)->exists(), 404);

        if ($data !== []) {
            $data['updated_at'] = now();
            $query->update($data);
        }

        return $this->show($productId);
    }

    public function destroy(string $productId): JsonResponse
    {
        $query = DB::connection('tenant')->table('products')->where('id', $productId);
        abort_unless($query->exists(), 404);
        $query->delete();

        return response()->json([], 204);
    }
}
