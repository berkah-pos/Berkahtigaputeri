<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\DB;
use Tests\Support\ProvisionedTenantPair;
use Tests\TestCase;

class TenantABIsolationMariaDbTest extends TestCase
{
    use ProvisionedTenantPair;

    public function test_tenant_a_real_database_user_is_denied_all_crud_operations_on_tenant_b_and_central(): void
    {
        $pair = $this->createProvisionedTenantPair('phase4-grants');
        $runtimeA = DB::connection($this->runtimeConnectionFor($pair, 'A'));
        $runtimeB = DB::connection($this->runtimeConnectionFor($pair, 'B'));

        $productB = 'phase4-b-' . $pair['suffix'];
        $runtimeB->table('products')->insert([
            'id' => $productB,
            'name' => 'Tenant B protected row',
            'price' => '27.50',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->assertSame($pair['databaseA'], (string) $runtimeA->selectOne('SELECT DATABASE() AS db')->db);
        $this->assertSame($pair['databaseB'], (string) $runtimeB->selectOne('SELECT DATABASE() AS db')->db);

        $tenantB = $this->quoteDatabaseIdentifier($pair['databaseB']);
        $central = $this->quoteDatabaseIdentifier('berkahpos_central');
        $products = $this->quoteDatabaseIdentifier('products');
        $tenants = $this->quoteDatabaseIdentifier('tenants');

        $this->assertMariaDbPrivilegeDenied(fn () => $runtimeA->selectOne(
            'SELECT id FROM ' . $tenantB . '.' . $products . ' WHERE id = ?',
            [$productB]
        ));
        $this->assertMariaDbPrivilegeDenied(fn () => $runtimeA->statement(
            'INSERT INTO ' . $tenantB . '.' . $products . ' (id, name, price, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
            ['cross-insert-' . $pair['suffix'], 'Denied insert', '1.00', now(), now()]
        ));
        $this->assertMariaDbPrivilegeDenied(fn () => $runtimeA->statement(
            'UPDATE ' . $tenantB . '.' . $products . ' SET price = ? WHERE id = ?',
            ['99.00', $productB]
        ));
        $this->assertMariaDbPrivilegeDenied(fn () => $runtimeA->statement(
            'DELETE FROM ' . $tenantB . '.' . $products . ' WHERE id = ?',
            [$productB]
        ));

        $this->assertMariaDbPrivilegeDenied(fn () => $runtimeA->selectOne(
            'SELECT id FROM ' . $central . '.' . $tenants . ' WHERE id = ?',
            [$pair['tenantAId']]
        ));
        $this->assertMariaDbPrivilegeDenied(fn () => $runtimeA->statement(
            'INSERT INTO ' . $central . '.' . $tenants . ' (id, template_id, created_at, updated_at) VALUES (?, ?, ?, ?)',
            ['cross-central-' . $pair['suffix'], 'BASIC', now(), now()]
        ));
        $this->assertMariaDbPrivilegeDenied(fn () => $runtimeA->statement(
            'UPDATE ' . $central . '.' . $tenants . ' SET template_id = ? WHERE id = ?',
            ['PRO', $pair['tenantAId']]
        ));
        $this->assertMariaDbPrivilegeDenied(fn () => $runtimeA->statement(
            'DELETE FROM ' . $central . '.' . $tenants . ' WHERE id = ?',
            [$pair['tenantAId']]
        ));

        $this->assertSame(
            '27.50',
            (string) $runtimeB->table('products')->where('id', $productB)->value('price'),
            'Denied mutations must not change Tenant B data.'
        );
    }
}
