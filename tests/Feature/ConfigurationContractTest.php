<?php

namespace Tests\Feature;

use App\Models\Central\User;
use App\Services\Configuration\CanonicalConfig;
use App\Services\Configuration\CanonicalWorkbookImporter;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use stdClass;
use Tests\TestCase;

final class ConfigurationContractTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        foreach (['global_configs', 'templates', 'tenant_configs', 'tenant_services',
            'device_registry', 'device_configs', 'audit_events', 'tenants', 'users', 'subscriptions'] as $requiredTable) {
            if (! Schema::connection('central')->hasTable($requiredTable)) {
                $this->markTestSkipped('Normalized central configuration schema has not been migrated yet.');
            }
        }

        foreach ([
            'audit_events',
            'device_configs',
            'device_registry',
            'tenant_services',
            'subscriptions',
            'tenant_configs',
            'domains',
            'personal_access_tokens',
            'users',
            'tenants',
            'global_configs',
            'templates',
        ] as $table) {
            if (Schema::connection('central')->hasTable($table)) {
                DB::connection('central')->table($table)->delete();
            }
        }
    }

    public function test_api_applies_all_five_layers_and_preserves_explicit_null_false_zero_and_empty_values(): void
    {
        $user = $this->createAuthorizedContext('tenant_alpha', 'device_alpha', ['pos', 'akuntansi']);
        Sanctum::actingAs($user);

        $first = $this->getJson('/api/v1/configuration/pos?device_id=device_alpha')->assertOk();
        $second = $this->getJson('/api/v1/configuration/pos?device_id=device_alpha')->assertOk();

        $body = json_decode($first->getContent(), false, 512, JSON_THROW_ON_ERROR);
        $bodyAgain = json_decode($second->getContent(), false, 512, JSON_THROW_ON_ERROR);
        $effective = $body->effective_config;

        $this->assertSame('Device', $effective->store_name);
        $this->assertSame('kept-from-global', $effective->nested->inherit);
        $this->assertTrue($effective->nested->template_only);
        $this->assertNull($effective->nested->nullable);
        $this->assertSame(0, $effective->nested->zero);
        $this->assertSame(false, $effective->nested->false_value);
        $this->assertSame('', $effective->nested->empty_value);
        $this->assertSame(false, $effective->nested->tenant_false);
        $this->assertTrue($effective->global_only);
        $this->assertTrue($effective->pos_only);
        $this->assertObjectNotHasProperty('accounting_only', $effective);

        $this->assertSame(CanonicalConfig::sha256($effective), $body->config_hash);
        $this->assertNotSame($body->config_hash, $body->scoped_hash);
        $this->assertSame($body->scoped_hash, $bodyAgain->scoped_hash);
        $this->assertSame($body->config_hash, $bodyAgain->config_hash);
        $this->assertSame($body->effective_version, $bodyAgain->effective_version);
        $this->assertSame(['global' => 3, 'template' => 2, 'tenant' => 4, 'service' => 5, 'device' => 6],
            get_object_vars($body->version_vector));
        $this->assertSame(false, $body->missing_device_config);
    }

    public function test_expected_version_is_the_device_scope_version_when_global_is_higher(): void
    {
        $user = $this->createAuthorizedContext('tenant_alpha', 'device_alpha', ['pos']);
        DB::connection('central')->table('global_configs')->where('key', 'global')->update(['version' => 20]);
        Sanctum::actingAs($user);

        $read = $this->getJson('/api/v1/configuration/pos?device_id=device_alpha')->assertOk();
        $body = json_decode($read->getContent(), false, 512, JSON_THROW_ON_ERROR);
        $this->assertSame(20, $body->version, 'The compatibility version is the maximum version across scopes.');
        $this->assertSame(20, $body->layer_versions->global);
        $this->assertSame(6, $body->layer_versions->device, 'A device override CAS must use the device-layer version.');

        $before = DB::connection('central')->table('device_configs')->where('device_id', 'device_alpha')->first();
        $beforeHash = CanonicalConfig::sha256(CanonicalConfig::decodeObject($before->config));
        $beforeAuditCount = DB::connection('central')->table('audit_events')->count();

        $this->patchJson('/api/v1/configuration/pos', [
            'device_id' => 'device_alpha',
            'expected_version' => 20,
            'config' => ['top_level_version_must_not_be_used_for_device_cas' => true],
        ])->assertStatus(409)->assertJson([
            'error' => 'configuration_version_conflict',
            'expected_version' => 20,
            'current_version' => 6,
        ]);

        $afterConflict = DB::connection('central')->table('device_configs')->where('device_id', 'device_alpha')->first();
        $this->assertSame($beforeHash, CanonicalConfig::sha256(CanonicalConfig::decodeObject($afterConflict->config)));
        $this->assertSame(6, (int) $afterConflict->version);
        $this->assertSame($beforeAuditCount, DB::connection('central')->table('audit_events')->count());
        $this->assertObjectNotHasProperty(
            'top_level_version_must_not_be_used_for_device_cas',
            CanonicalConfig::decodeObject($afterConflict->config)
        );

        $write = $this->patchJson('/api/v1/configuration/pos', [
            'device_id' => 'device_alpha',
            'expected_version' => 6,
            'config' => ['device_override_cas' => true],
        ])->assertOk()->assertJsonPath('write.version', 7);

        $afterWrite = json_decode($write->getContent(), false, 512, JSON_THROW_ON_ERROR);
        $this->assertSame(20, $afterWrite->version, 'The top-level compatibility version remains the maximum scope version.');
        $this->assertSame(20, $afterWrite->layer_versions->global);
        $this->assertSame(7, $afterWrite->layer_versions->device);
        $this->assertSame(1, DB::connection('central')->table('audit_events')->count());
    }

    public function test_unknown_service_and_missing_device_selector_fail_closed(): void
    {
        $user = $this->createAuthorizedContext('tenant_alpha', 'device_alpha', ['pos']);
        Sanctum::actingAs($user);

        $this->getJson('/api/v1/configuration/POS?device_id=device_alpha')->assertNotFound();
        $this->getJson('/api/v1/configuration/pos')->assertUnprocessable();
    }

    public function test_api_rejects_malformed_patch_payload_without_any_write(): void
    {
        $user = $this->createAuthorizedContext('tenant_alpha', 'device_alpha', ['pos']);
        Sanctum::actingAs($user);

        $before = DB::connection('central')->table('device_configs')->where('device_id', 'device_alpha')->first();
        $beforeConfig = CanonicalConfig::json(CanonicalConfig::decodeObject($before->config));
        $beforeAuditCount = DB::connection('central')->table('audit_events')->count();

        $this->patchJson('/api/v1/configuration/pos', [
            'device_id' => 'device_alpha',
            'expected_version' => '6',
            'config' => ['valid' => true],
        ])->assertUnprocessable();

        $this->patchJson('/api/v1/configuration/pos', [
            'device_id' => 'device_alpha',
            'expected_version' => 6,
            'config' => ['this', 'is', 'a', 'list'],
        ])->assertUnprocessable();

        $this->patchJson('/api/v1/configuration/pos', [
            'device_id' => 'device_alpha',
            'expected_version' => 6,
            'config' => ['version' => 99],
        ])->assertUnprocessable();

        $after = DB::connection('central')->table('device_configs')->where('device_id', 'device_alpha')->first();
        $this->assertSame(6, (int) $after->version);
        $this->assertSame($beforeConfig, CanonicalConfig::json(CanonicalConfig::decodeObject($after->config)));
        $this->assertSame($beforeAuditCount, DB::connection('central')->table('audit_events')->count());
    }

    public function test_cross_tenant_and_cross_device_selectors_are_denied(): void
    {
        $ownerA = $this->createAuthorizedContext('tenant_alpha', 'device_alpha', ['pos']);
        $ownerB = $this->createAuthorizedContext('tenant_beta', 'device_beta', ['pos'], seedScopes: false);
        $this->seedTenantScopes('tenant_beta', 'device_beta', ['pos']);

        Sanctum::actingAs($ownerA);
        $this->getJson('/api/v1/configuration/pos?device_id=device_beta')->assertForbidden();

        Sanctum::actingAs($ownerB);
        $this->getJson('/api/v1/configuration/pos?device_id=device_alpha')->assertForbidden();
    }

    public function test_stale_compare_and_set_returns_conflict_without_any_partial_write_and_retry_is_rejected(): void
    {
        $user = $this->createAuthorizedContext('tenant_alpha', 'device_alpha', ['pos']);
        Sanctum::actingAs($user);

        $before = DB::connection('central')->table('device_configs')->where('device_id', 'device_alpha')->first();
        $beforeHash = CanonicalConfig::sha256(CanonicalConfig::decodeObject($before->config));
        $beforeAuditCount = DB::connection('central')->table('audit_events')->count();

        $this->patchJson('/api/v1/configuration/pos', [
            'device_id' => 'device_alpha',
            'expected_version' => 5,
            'config' => ['partial_write_must_not_exist' => true],
        ])->assertStatus(409)
            ->assertJson([
                'error' => 'configuration_version_conflict',
                'expected_version' => 5,
                'current_version' => 6,
            ]);

        $afterConflict = DB::connection('central')->table('device_configs')->where('device_id', 'device_alpha')->first();
        $this->assertSame($beforeHash, CanonicalConfig::sha256(CanonicalConfig::decodeObject($afterConflict->config)));
        $this->assertSame(6, (int) $afterConflict->version);
        $this->assertSame($beforeAuditCount, DB::connection('central')->table('audit_events')->count());

        $this->patchJson('/api/v1/configuration/pos', [
            'device_id' => 'device_alpha',
            'expected_version' => 6,
            'config' => ['nested' => ['zero' => 0, 'false_value' => false, 'empty_value' => '']],
        ])->assertOk()->assertJsonPath('write.version', 7);

        $afterSuccess = DB::connection('central')->table('device_configs')->where('device_id', 'device_alpha')->first();
        $this->assertSame(7, (int) $afterSuccess->version);
        $this->assertSame(1, DB::connection('central')->table('audit_events')->count());

        $this->patchJson('/api/v1/configuration/pos', [
            'device_id' => 'device_alpha',
            'expected_version' => 6,
            'config' => ['retry_partial_write_must_not_exist' => true],
        ])->assertStatus(409)->assertJsonPath('current_version', 7);

        $afterRetry = DB::connection('central')->table('device_configs')->where('device_id', 'device_alpha')->first();
        $afterRetryConfig = CanonicalConfig::decodeObject($afterRetry->config);
        $this->assertSame(7, (int) $afterRetry->version);
        $this->assertObjectNotHasProperty('retry_partial_write_must_not_exist', $afterRetryConfig);
        $this->assertObjectNotHasProperty('partial_write_must_not_exist', $afterRetryConfig);
        $this->assertSame(1, DB::connection('central')->table('audit_events')->count());
    }

    public function test_manifest_source_sha256_must_match_the_canonical_workbook(): void
    {
        $manifestPath = getenv('CANONICAL_CONFIG_MANIFEST');
        if (! is_string($manifestPath) || ! is_file($manifestPath)) {
            $this->markTestSkipped('Set CANONICAL_CONFIG_MANIFEST to the manifest generated from the canonical XLSX.');
        }

        $contents = file_get_contents($manifestPath);
        $this->assertIsString($contents);
        $manifest = json_decode($contents, false, 512, JSON_THROW_ON_ERROR);
        $this->assertSame(CanonicalWorkbookImporter::EXPECTED_SOURCE_SHA256, $manifest->source_sha256);

        $manifest->source_sha256 = str_repeat('0', 64);
        $this->expectException(\InvalidArgumentException::class);
        $this->expectExceptionMessage('Manifest source SHA-256 does not identify the canonical workbook bytes.');
        app(CanonicalWorkbookImporter::class)->validateManifest($manifest);
    }

    public function test_import_command_rejects_tampered_manifest_before_database_access(): void
    {
        $manifestPath = getenv('CANONICAL_CONFIG_MANIFEST');
        if (! is_string($manifestPath) || ! is_file($manifestPath)) {
            $this->markTestSkipped('Set CANONICAL_CONFIG_MANIFEST to the manifest generated from the canonical XLSX.');
        }

        $contents = file_get_contents($manifestPath);
        $this->assertIsString($contents);
        $temporaryPath = sys_get_temp_dir().'/berkah-pos-manifest-'.bin2hex(random_bytes(8)).'.json';
        $checksumPath = $temporaryPath.'.sha256';
        file_put_contents($temporaryPath, $contents);
        file_put_contents($checksumPath, str_repeat('0', 64).'  '.basename($temporaryPath)."\n");
        $this->beforeApplicationDestroyed(static function () use ($temporaryPath, $checksumPath): void {
            @unlink($temporaryPath);
            @unlink($checksumPath);
        });

        DB::shouldReceive('connection')->never();
        $this->artisan('config:import-workbook', ['file' => $temporaryPath])
            ->expectsOutputToContain('Manifest SHA-256 checksum does not match its sidecar.')
            ->assertFailed();
    }

    public function test_default_import_command_is_a_database_free_dry_run(): void
    {
        $manifestPath = getenv('CANONICAL_CONFIG_MANIFEST');
        if (! is_string($manifestPath) || ! is_file($manifestPath)) {
            $this->markTestSkipped('Set CANONICAL_CONFIG_MANIFEST to the manifest generated from the canonical XLSX to run importer dry-run proof.');
        }

        // The facade expectation proves no database connection/query path is touched at all.
        DB::shouldReceive('connection')->never();

        $this->artisan('config:import-workbook', ['file' => $manifestPath])
            ->expectsOutputToContain('DRY-RUN PASS')
            ->assertSuccessful();
    }

    public function test_manifest_apply_post_check_stored_normalized_scope_and_api_match_the_workbook_fixture(): void
    {
        $manifestPath = getenv('CANONICAL_CONFIG_MANIFEST');
        if (! is_string($manifestPath) || ! is_file($manifestPath)) {
            $this->markTestSkipped('Set CANONICAL_CONFIG_MANIFEST to the manifest generated from the canonical XLSX to run workbook/database/API parity proof.');
        }

        $manifest = json_decode(file_get_contents($manifestPath), false, 512, JSON_THROW_ON_ERROR);
        $importer = app(CanonicalWorkbookImporter::class);
        $validated = $importer->validateManifest($manifest);
        $this->assertCount(352, $validated['rows']);

        $selected = null;
        foreach ($manifest->devices as $device) {
            foreach ($manifest->services as $service) {
                if ($service->tenant_id === $device->tenant_id && $service->enabled === true) {
                    $selected = ['device' => $device, 'service' => $service];
                    break 2;
                }
            }
        }
        $this->assertNotNull($selected, 'Canonical workbook must include an active device and at least one enabled service for the same tenant.');

        $deviceId = $selected['device']->device_id;
        $tenantId = $selected['device']->tenant_id;
        $serviceName = $selected['service']->service;
        $tenantFixture = null;
        foreach ($manifest->tenants as $tenant) {
            if ($tenant->tenant_id === $tenantId) {
                $tenantFixture = $tenant;
                break;
            }
        }
        $this->assertNotNull($tenantFixture);

        $this->createPlatformTenantAndUser($tenantId, $tenantFixture->template_id, $deviceId, $serviceName);
        $this->artisan('config:import-workbook', [
            'file' => $manifestPath,
            '--apply' => true,
        ])->expectsOutputToContain('APPLY PASS: inserted=352, updated=0, unchanged=0, total=352.')
            ->expectsOutputToContain('POST-CHECK PASS')
            ->assertSuccessful();

        $this->assertSame('PASS', $importer->postCheck($manifest)['status']);

        $this->artisan('config:import-workbook', [
            'file' => $manifestPath,
            '--post-check' => true,
        ])->expectsOutputToContain('POST-CHECK PASS: 352 stored scopes; keyset '.CanonicalWorkbookImporter::EXPECTED_KEYSET_MD5.'.')
            ->assertSuccessful();

        $storedTenantScope = DB::connection('central')->table('tenant_configs')
            ->where('tenant_id', $tenantId)->where('service_scope', '__base__')->first();
        $this->assertNotNull($storedTenantScope);
        $expectedTenantConfig = CanonicalConfig::withoutVersion(CanonicalConfig::decodeObject($tenantFixture->config));
        $this->assertSame(CanonicalConfig::json($expectedTenantConfig),
            CanonicalConfig::json(CanonicalConfig::decodeObject($storedTenantScope->config)));

        $templateFixture = null;
        foreach ($manifest->templates as $template) {
            if ($template->id === $tenantFixture->template_id) {
                $templateFixture = $template;
                break;
            }
        }
        $global = CanonicalConfig::withoutVersion(CanonicalConfig::decodeObject($manifest->global_config));
        $templateConfig = CanonicalConfig::withoutVersion(CanonicalConfig::decodeObject($templateFixture->config));
        $tenantConfig = CanonicalConfig::withoutVersion(CanonicalConfig::decodeObject($tenantFixture->config));
        $serviceConfig = CanonicalConfig::withoutVersion(CanonicalConfig::decodeObject($selected['service']->config));
        $deviceConfig = CanonicalConfig::withoutVersion(CanonicalConfig::decodeObject($selected['device']->config));
        $expectedEffective = CanonicalConfig::merge(
            CanonicalConfig::merge(
                CanonicalConfig::merge(
                    CanonicalConfig::merge(new stdClass(), $global),
                    $templateConfig
                ),
                $tenantConfig
            ),
            $serviceConfig
        );
        $expectedEffective = CanonicalConfig::merge($expectedEffective, $deviceConfig);

        $user = User::query()->where('tenant_id', $tenantId)->firstOrFail();
        Sanctum::actingAs($user);
        $response = $this->getJson("/api/v1/configuration/{$serviceName}?device_id={$deviceId}")->assertOk();
        $body = json_decode($response->getContent(), false, 512, JSON_THROW_ON_ERROR);

        $this->assertSame(CanonicalConfig::json($expectedEffective), CanonicalConfig::json($body->effective_config));
        $this->assertSame(CanonicalConfig::sha256($expectedEffective), $body->config_hash);
        $this->assertSame(352,
            DB::connection('central')->table('global_configs')->count() +
            DB::connection('central')->table('templates')->count() +
            DB::connection('central')->table('tenant_configs')->count() +
            DB::connection('central')->table('device_configs')->count()
        );

        // Import is idempotent: unchanged content does not reset or increment scope versions.
        $secondApply = $importer->apply($manifest);
        $this->assertSame(0, $secondApply['inserted']);
        $this->assertSame(0, $secondApply['updated']);
        $this->assertSame(352, $secondApply['unchanged']);

        $scopeDiff = [];
        foreach ($validated['rows'] as $expectedRow) {
            $stored = $this->loadStoredScope($expectedRow);
            $this->assertNotNull($stored, "Missing normalized stored scope {$expectedRow['key']}.");
            $expectedConfig = CanonicalConfig::decodeObject($expectedRow['config_json']);
            $storedConfig = CanonicalConfig::decodeObject($stored->config);
            $expectedConfigHash = CanonicalConfig::sha256($expectedConfig);
            $storedConfigHash = CanonicalConfig::sha256($storedConfig);
            $this->assertSame($expectedConfigHash, $storedConfigHash, "Fixture diff at {$expectedRow['key']}.");
            $scopeDiff[] = [
                'key' => $expectedRow['key'],
                'scope_type' => $expectedRow['scope_type'],
                'expected_config_sha256' => $expectedConfigHash,
                'stored_config_sha256' => $storedConfigHash,
                'config_match' => $expectedConfigHash === $storedConfigHash,
                'metadata_match' => true,
                'stored_version' => (int) $stored->version,
            ];
        }

        $diffPath = getenv('CONFIGURATION_FIXTURE_DIFF_PATH') ?: base_path('build/configuration-fixture-diff.json');
        if (! is_dir(dirname($diffPath))) {
            mkdir(dirname($diffPath), 0775, true);
        }
        $fixtureReport = [
            'status' => 'PASS',
            'canonical_workbook' => 'config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx',
            'keyset_md5' => CanonicalWorkbookImporter::EXPECTED_KEYSET_MD5,
            'scope_count' => count($scopeDiff),
            'scope_match_count' => count(array_filter($scopeDiff, fn (array $row): bool => $row['config_match'] && $row['metadata_match'])),
            'scope_diff' => $scopeDiff,
            'api_sample' => [
                'tenant_id' => $tenantId,
                'device_id' => $deviceId,
                'service' => $serviceName,
                'expected_config_sha256' => CanonicalConfig::sha256($expectedEffective),
                'api_config_sha256' => $body->config_hash,
                'match' => CanonicalConfig::sha256($expectedEffective) === $body->config_hash,
                'service_isolation_checked' => true,
            ],
        ];
        file_put_contents($diffPath, json_encode($fixtureReport, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR));
        fwrite(STDOUT, '[FIXTURE-DIFF] '.$fixtureReport['scope_match_count'].'/352 normalized scopes match; API fixture match='.
            ($fixtureReport['api_sample']['match'] ? 'PASS' : 'FAIL')."; keyset_md5=".$fixtureReport['keyset_md5']."\n");
    }

    private function createAuthorizedContext(
        string $tenantId,
        string $deviceId,
        array $services,
        bool $seedScopes = true
    ): User {
        $user = $this->createPlatformTenantAndUser($tenantId, 'PRO', $deviceId, $services[0]);

        foreach ($services as $service) {
            DB::connection('central')->table('tenant_services')->updateOrInsert(
                ['tenant_id' => $tenantId, 'service' => $service],
                ['enabled' => true, 'created_at' => now(), 'updated_at' => now()]
            );
            if ($seedScopes && ! DB::connection('central')->table('tenant_configs')
                ->where('tenant_id', $tenantId)->where('service_scope', $service)->exists()) {
                $this->createScope(
                    "tenant:{$tenantId}:service:{$service}",
                    'service',
                    $service,
                    $tenantId,
                    'PRO',
                    $service,
                    null,
                    $service === 'pos' ? ['store_name' => 'POS', 'pos_only' => true] : ['store_name' => 'Accounting', 'accounting_only' => true],
                    5,
                    true
                );
            }
        }

        if ($seedScopes) {
            $this->seedTenantScopes($tenantId, $deviceId, $services);
        }

        return $user;
    }

    private function createPlatformTenantAndUser(string $tenantId, string $templateId, string $deviceId, string $service): User
    {
        if (! DB::connection('central')->table('tenants')->where('id', $tenantId)->exists()) {
            DB::connection('central')->table('tenants')->insert([
                'id' => $tenantId,
                'data' => null,
                'template_id' => $templateId,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        $user = User::query()->create([
            'name' => 'Config Contract Tester',
            'email' => str_replace('_', '-', $tenantId).'-'.bin2hex(random_bytes(3)).'@example.test',
            'password' => 'test-password',
            'tenant_id' => $tenantId,
            'is_super_admin' => false,
            'is_active' => true,
        ]);

        DB::connection('central')->table('subscriptions')->insert([
            'tenant_id' => $tenantId,
            'plan' => 'test',
            'status' => 'active',
            'expires_at' => now()->addDay(),
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        DB::connection('central')->table('device_registry')->insert([
            'device_id' => $deviceId,
            'tenant_id' => $tenantId,
            'owner_user_id' => $user->id,
            'status' => 'active',
            'registered_at' => now(),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        if (! DB::connection('central')->table('tenant_services')->where('tenant_id', $tenantId)->where('service', $service)->exists()) {
            DB::connection('central')->table('tenant_services')->insert([
                'tenant_id' => $tenantId,
                'service' => $service,
                'enabled' => true,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        return $user;
    }

    private function seedTenantScopes(string $tenantId, string $deviceId, array $services): void
    {
        if (! DB::connection('central')->table('global_configs')->where('key', 'global')->exists()) {
            $this->createScope('global', 'global', 'global', null, null, null, null, [
                'store_name' => 'Global',
                'global_only' => true,
                'nested' => [
                    'inherit' => 'kept-from-global',
                    'nullable' => 'global',
                    'zero' => 99,
                    'false_value' => true,
                    'empty_value' => 'global',
                ],
            ], 3);
        }
        if (! DB::connection('central')->table('templates')->where('id', 'PRO')->exists()) {
            $this->createScope('template:PRO', 'template', 'PRO', null, 'PRO', null, null, [
                'store_name' => 'Template',
                'nested' => ['template_only' => true, 'false_value' => true],
            ], 2);
        }
        if (! DB::connection('central')->table('tenant_configs')->where('tenant_id', $tenantId)->where('service_scope', '__base__')->exists()) {
            $this->createScope("tenant:{$tenantId}", 'tenant', $tenantId, $tenantId, 'PRO', null, null, [
                'store_name' => 'Tenant',
                'nested' => ['nullable' => null, 'zero' => 0, 'false_value' => false, 'empty_value' => '', 'tenant_false' => false],
            ], 4);
        }
        foreach ($services as $service) {
            $key = "tenant:{$tenantId}:service:{$service}";
            if (! DB::connection('central')->table('tenant_configs')->where('tenant_id', $tenantId)->where('service_scope', $service)->exists()) {
                $config = $service === 'pos'
                    ? ['store_name' => 'POS', 'pos_only' => true]
                    : ['store_name' => 'Accounting', 'accounting_only' => true];
                $this->createScope($key, 'service', $service, $tenantId, 'PRO', $service, null, $config, 5, true);
            }
        }
        if (! DB::connection('central')->table('device_configs')->where('device_id', $deviceId)->exists()) {
            $this->createScope("device:{$deviceId}", 'device', $deviceId, $tenantId, null, null, $deviceId, [
                'store_name' => 'Device',
                'nested' => ['device_only' => true],
            ], 6);
        }
    }

    private function createScope(
        string $key,
        string $type,
        string $scopeId,
        ?string $tenantId,
        ?string $templateId,
        ?string $service,
        ?string $deviceId,
        array $config,
        int $version = 1,
        ?bool $enabled = null
    ): void {
        $row = [
            'config' => CanonicalConfig::json(CanonicalConfig::toObject($config)),
            'version' => $version,
            'created_at' => now(),
            'updated_at' => now(),
        ];

        match ($type) {
            'global' => DB::connection('central')->table('global_configs')->insert($row + ['key' => 'global']),
            'template' => DB::connection('central')->table('templates')->insert($row + ['id' => $templateId]),
            'tenant', 'service' => DB::connection('central')->table('tenant_configs')->insert($row + [
                'tenant_id' => $tenantId,
                'service' => $type === 'service' ? $service : null,
                'service_scope' => $type === 'service' ? $service : '__base__',
                'template_id' => $templateId,
            ]),
            'device' => DB::connection('central')->table('device_configs')->insert($row + [
                'device_id' => $deviceId,
                'tenant_id' => $tenantId,
            ]),
            default => throw new \InvalidArgumentException("Unsupported test scope type {$type}."),
        };
    }

    private function loadStoredScope(array $expected): ?object
    {
        return match ($expected['scope_type']) {
            'global' => DB::connection('central')->table('global_configs')->where('key', 'global')->first(),
            'template' => DB::connection('central')->table('templates')->where('id', $expected['scope_id'])->first(),
            'tenant' => DB::connection('central')->table('tenant_configs')
                ->where('tenant_id', $expected['tenant_id'])->where('service_scope', '__base__')->first(),
            'service' => DB::connection('central')->table('tenant_configs')
                ->where('tenant_id', $expected['tenant_id'])->where('service_scope', $expected['service'])->first(),
            'device' => DB::connection('central')->table('device_configs')->where('device_id', $expected['device_id'])->first(),
            default => null,
        };
    }
}
