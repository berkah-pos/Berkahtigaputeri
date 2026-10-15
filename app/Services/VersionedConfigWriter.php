<?php

namespace App\Services;

use App\Exceptions\StaleConfigurationVersionException;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;
use RuntimeException;

class VersionedConfigWriter
{
    private const CONTRACT = [
        'central' => [
            'global_configs' => ['identity' => ['key'], 'extra' => []],
            'templates' => ['identity' => ['id'], 'extra' => ['max_users']],
            'tenant_configs' => ['identity' => ['tenant_id', 'service_scope'], 'extra' => ['service', 'template_id']],
        ],
        'tenant' => ['device_configs' => ['identity' => ['device_id'], 'extra' => []]],
    ];

    public function compareAndSwap(
        string $connection,
        string $table,
        array $identity,
        int $expectedVersion,
        array $config,
        array $extra = [],
    ): int {
        $contract = self::CONTRACT[$connection][$table] ?? null;
        if ($contract === null) {
            throw new InvalidArgumentException('Configuration writer refused an unapproved connection/table.');
        }
        $identityKeys = array_keys($identity);
        $expectedKeys = $contract['identity'];
        sort($identityKeys);
        sort($expectedKeys);
        if ($identityKeys !== $expectedKeys || in_array(null, $identity, true)) {
            throw new InvalidArgumentException('Configuration identity does not match allowlisted columns.');
        }
        if (array_diff(array_keys($extra), $contract['extra']) !== []) {
            throw new InvalidArgumentException('Configuration writer refused an unapproved metadata column.');
        }
        if ($expectedVersion < 0) {
            throw new InvalidArgumentException('Expected version cannot be negative.');
        }
        $newVersion = $config['version'] ?? null;
        if (! is_int($newVersion) || $newVersion < 1) {
            throw new InvalidArgumentException('New configuration version must be a positive integer.');
        }

        $db = DB::connection($connection);
        $existing = $db->table($table)->where($identity)->first();
        if ($expectedVersion === 0) {
            if ($newVersion !== 1) {
                throw new InvalidArgumentException('A new configuration row must start at version one.');
            }
            if ($existing !== null) {
                throw new StaleConfigurationVersionException('Configuration create conflicted with an existing row.');
            }
            $values = array_merge($identity, $extra, [
                'config' => json_encode($config, JSON_THROW_ON_ERROR),
                'version' => 1, 'created_at' => now(), 'updated_at' => now(),
            ]);
            try {
                $db->table($table)->insert($values);
            } catch (QueryException $exception) {
                if ($db->table($table)->where($identity)->exists()) {
                    throw new StaleConfigurationVersionException(
                        'Configuration was concurrently created by another writer.',
                        previous: $exception,
                    );
                }
                throw $exception;
            }
            return 1;
        }
        if ($existing === null || (int) $existing->version !== $expectedVersion) {
            throw new StaleConfigurationVersionException(sprintf(
                'Stale configuration version: expected %d, found %s.',
                $expectedVersion, $existing->version ?? 'missing',
            ));
        }

        $current = $this->decodeConfig($existing->config ?? null);
        unset($current['version']);
        $next = $config;
        unset($next['version']);
        $unchanged = $this->canonicalJson($current) === $this->canonicalJson($next);
        if ($unchanged && $newVersion !== $expectedVersion) {
            throw new InvalidArgumentException('Unchanged configuration must preserve its current version.');
        }
        if (! $unchanged && $newVersion !== $expectedVersion + 1) {
            throw new InvalidArgumentException('Changed configuration must increment the version by exactly one.');
        }
        if ($unchanged && $extra === []) {
            return $expectedVersion;
        }
        $affected = $db->table($table)->where($identity)->where('version', $expectedVersion)->update(array_merge(
            $extra,
            ['config' => json_encode($config, JSON_THROW_ON_ERROR), 'version' => $newVersion, 'updated_at' => now()],
        ));
        if ($affected !== 1) {
            $latest = $db->table($table)->where($identity)->first();
            if ($latest === null || (int) $latest->version !== $expectedVersion) {
                throw new StaleConfigurationVersionException(sprintf(
                    'Concurrent configuration update rejected: expected version %d, found %s.',
                    $expectedVersion, $latest->version ?? 'missing',
                ));
            }
        }
        return $newVersion;
    }

    private function decodeConfig(mixed $raw): array
    {
        if (is_array($raw)) return $raw;
        if (! is_string($raw)) throw new RuntimeException('Stored configuration is missing or malformed.');
        $decoded = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
        if (! is_array($decoded)) throw new RuntimeException('Stored configuration must decode to an object.');
        return $decoded;
    }

    private function canonicalJson(array $value): string
    {
        $normalize = function (&$item) use (&$normalize): void {
            if (! is_array($item)) return;
            if (! array_is_list($item)) ksort($item, SORT_STRING);
            foreach ($item as &$child) $normalize($child);
            unset($child);
        };
        $normalize($value);
        return json_encode($value, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    }
}
