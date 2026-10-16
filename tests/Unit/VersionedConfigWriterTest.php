<?php

namespace Tests\Unit;

use App\Exceptions\StaleConfigurationVersionException;
use App\Services\VersionedConfigWriter;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use InvalidArgumentException;
use Tests\TestCase;

class VersionedConfigWriterTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config(['database.connections.central' => [
            'driver' => 'sqlite', 'database' => ':memory:', 'prefix' => '', 'foreign_key_constraints' => true,
        ]]);
        DB::purge('central');
        Schema::connection('central')->create('global_configs', function (Blueprint $table): void {
            $table->string('key')->primary();
            $table->text('config');
            $table->unsignedInteger('version')->default(1);
            $table->dateTime('created_at')->nullable();
            $table->dateTime('updated_at')->nullable();
        });
    }

    public function test_compare_and_swap_advances_version_once_and_rejects_stale_write(): void
    {
        DB::connection('central')->table('global_configs')->insert([
            'key' => 'global', 'config' => json_encode(['mode' => 'old', 'version' => 1], JSON_THROW_ON_ERROR),
            'version' => 1, 'created_at' => now(), 'updated_at' => now(),
        ]);
        $writer = new VersionedConfigWriter;
        $this->assertSame(2, $writer->compareAndSwap('central', 'global_configs', ['key' => 'global'], 1, ['mode' => 'new', 'version' => 2]));
        $this->expectException(StaleConfigurationVersionException::class);
        $this->expectExceptionMessage('expected 1, found 2');
        $writer->compareAndSwap('central', 'global_configs', ['key' => 'global'], 1, ['mode' => 'stale', 'version' => 2]);
    }

    public function test_version_must_be_integer_and_new_rows_start_at_one(): void
    {
        $writer = new VersionedConfigWriter;
        try {
            $writer->compareAndSwap('central', 'global_configs', ['key' => 'global'], 0, ['version' => 1.0]);
            $this->fail('A float version must be rejected.');
        } catch (InvalidArgumentException $exception) {
            $this->assertStringContainsString('positive integer', $exception->getMessage());
        }
        $this->expectException(InvalidArgumentException::class);
        $writer->compareAndSwap('central', 'global_configs', ['key' => 'global'], 0, ['version' => 2]);
    }
}
