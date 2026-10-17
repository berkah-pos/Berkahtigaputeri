<?php

namespace App\Services\Configuration;

use App\Models\Central\User;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;
use stdClass;

final class ConfigurationWriter
{
    public function __construct(private readonly EffectiveConfigResolver $resolver)
    {
    }

    /**
     * Update only an enrolled device's central config using PostgreSQL compare-and-set.
     * The config update and audit event share one transaction.
     *
     * @return array{key: string, version: int, config_hash: string, config: stdClass}
     */
    public function compareAndSetDeviceOverride(
        User $user,
        string $deviceId,
        string $service,
        int $expectedVersion,
        stdClass $patch
    ): array {
        if ($expectedVersion < 1) {
            throw new InvalidArgumentException('expected_version must be a positive integer.');
        }
        if (count(get_object_vars($patch)) === 0) {
            throw new InvalidArgumentException('config patch must contain at least one field.');
        }
        if (property_exists($patch, 'version')) {
            throw new InvalidArgumentException('config patch cannot set the reserved version field.');
        }

        $key = "device:{$deviceId}";

        return DB::connection('central')->transaction(function () use ($user, $deviceId, $service, $key, $expectedVersion, $patch): array {
            // Re-check server-owned authorization in the transaction before acquiring/writing the scope.
            $context = $this->resolver->authorizeUser($user, $deviceId, $service);
            $scope = DB::connection('central')->table('device_configs')
                ->where('device_id', $deviceId)
                ->lockForUpdate()
                ->first();

            if ($scope === null || $scope->device_id !== $deviceId || $scope->tenant_id !== $context['tenant_id']) {
                throw new AuthorizationException('A canonical device configuration is not registered for this device.');
            }

            $currentVersion = (int) $scope->version;
            if ($currentVersion !== $expectedVersion) {
                throw new ConfigurationVersionConflict($expectedVersion, $currentVersion);
            }

            try {
                $existing = CanonicalConfig::decodeObject($scope->config, 'stored device config');
            } catch (InvalidArgumentException $exception) {
                throw new ConfigurationUnavailableException('Stored device configuration is malformed.', previous: $exception);
            }
            $updated = CanonicalConfig::merge($existing, $patch);
            $nextVersion = $currentVersion + 1;
            $oldHash = CanonicalConfig::sha256($existing);
            $newHash = CanonicalConfig::sha256($updated);
            $now = now();

            $changed = DB::connection('central')->table('device_configs')
                ->where('device_id', $deviceId)
                ->where('tenant_id', $context['tenant_id'])
                ->where('version', $expectedVersion)
                ->update([
                    'config' => CanonicalConfig::json($updated),
                    'version' => $nextVersion,
                    'updated_at' => $now,
                ]);

            if ($changed !== 1) {
                $freshVersion = (int) (DB::connection('central')->table('device_configs')
                    ->where('device_id', $deviceId)->value('version') ?? $currentVersion);
                throw new ConfigurationVersionConflict($expectedVersion, $freshVersion);
            }

            DB::connection('central')->table('audit_events')->insert([
                'actor_user_id' => $user->getAuthIdentifier(),
                'tenant_id' => $context['tenant_id'],
                'scope_type' => 'device',
                'scope_id' => $deviceId,
                'action' => 'configuration.device.updated',
                'previous_version' => $currentVersion,
                'new_version' => $nextVersion,
                'previous_sha256' => $oldHash,
                'new_sha256' => $newHash,
                'metadata' => CanonicalConfig::json((object) ['service' => $service]),
                'created_at' => $now,
            ]);

            return [
                'key' => $key,
                'version' => $nextVersion,
                'config_hash' => $newHash,
                'config' => $updated,
            ];
        }, 3);
    }
}
