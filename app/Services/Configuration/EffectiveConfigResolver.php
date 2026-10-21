<?php

declare(strict_types=1);

namespace App\Services\Configuration;

use InvalidArgumentException;
use JsonException;

/**
 * Deterministic implementation of the canonical configuration inheritance
 * contract. Authorization and loading of each layer remain the API's job.
 */
final class EffectiveConfigResolver
{
    private const LAYER_ORDER = ['global', 'template', 'tenant', 'service', 'device'];

    private const ALLOWED_SERVICES = ['pos', 'akuntansi'];

    /**
     * @param array{global: array, template: array, tenant: array, service: array, device: array} $layers
     * @param array{global: int, template: int, tenant: int, service: int, device: int} $versions
     * @return array{tenant_id: string, device_id: string, service: string, version: int, versions: array, hash: string, config: array}
     *
     * @throws InvalidArgumentException when a tuple, layer set, or version vector violates the contract.
     * @throws JsonException when a configuration cannot be canonically encoded.
     */
    public function resolve(
        string $tenantId,
        string $deviceId,
        string $service,
        array $layers,
        array $versions,
    ): array {
        $tenantId = $this->validateIdentifier($tenantId, 'tenant_id');
        $deviceId = $this->validateIdentifier($deviceId, 'device_id');

        if (! in_array($service, self::ALLOWED_SERVICES, true)) {
            throw new InvalidArgumentException('Service must be exactly one allowlisted value: pos or akuntansi.');
        }

        if (array_keys($layers) !== self::LAYER_ORDER) {
            throw new InvalidArgumentException('Configuration layers must be supplied in canonical order: global, template, tenant, service, device.');
        }

        if (array_keys($versions) !== self::LAYER_ORDER) {
            throw new InvalidArgumentException('Configuration versions must match the five canonical layers in order.');
        }

        $effective = [];
        foreach (self::LAYER_ORDER as $layerName) {
            $layer = $layers[$layerName];
            if (! is_array($layer) || ($layer !== [] && array_is_list($layer))) {
                throw new InvalidArgumentException(sprintf('Configuration layer %s must be a JSON object or an empty object.', $layerName));
            }

            $version = $versions[$layerName];
            if (! is_int($version) || $version < 1) {
                throw new InvalidArgumentException(sprintf('Configuration version for %s must be a positive integer.', $layerName));
            }

            $effective = $this->mergeObject($effective, $layer);
        }

        $version = max($versions);
        $canonicalConfig = $this->sortObjectKeysRecursively($effective);
        $canonicalPayload = [
            'tenant_id' => $tenantId,
            'device_id' => $deviceId,
            'service' => $service,
            'versions' => $versions,
            'config' => $canonicalConfig,
        ];
        $encodedPayload = json_encode(
            $canonicalPayload,
            JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE,
        );

        return [
            'tenant_id' => $tenantId,
            'device_id' => $deviceId,
            'service' => $service,
            'version' => $version,
            'versions' => $versions,
            'hash' => hash('sha256', $encodedPayload),
            'config' => $canonicalConfig,
        ];
    }

    /**
     * Later layers override explicit leaves only. Associative objects merge
     * recursively; scalar values and lists replace their prior value as a unit.
     */
    private function mergeObject(array $base, array $override): array
    {
        foreach ($override as $key => $value) {
            if (
                array_key_exists($key, $base) &&
                is_array($base[$key]) &&
                is_array($value) &&
                $this->isObjectMap($base[$key]) &&
                $this->isObjectMap($value)
            ) {
                $base[$key] = $this->mergeObject($base[$key], $value);
            } else {
                $base[$key] = $value;
            }
        }

        return $base;
    }

    private function isObjectMap(array $value): bool
    {
        return $value !== [] && ! array_is_list($value);
    }

    private function sortObjectKeysRecursively(array $value): array
    {
        if (array_is_list($value)) {
            return array_map(
                fn (mixed $item): mixed => is_array($item) ? $this->sortObjectKeysRecursively($item) : $item,
                $value,
            );
        }

        ksort($value, SORT_STRING);
        foreach ($value as $key => $item) {
            if (is_array($item)) {
                $value[$key] = $this->sortObjectKeysRecursively($item);
            }
        }

        return $value;
    }

    private function validateIdentifier(string $value, string $field): string
    {
        if (
            $value === '' ||
            trim($value) !== $value ||
            strlen($value) > 150 ||
            str_contains($value, ':') ||
            preg_match('/[\x00-\x1F\x7F]/', $value) === 1
        ) {
            throw new InvalidArgumentException(sprintf('%s is not a valid canonical identifier.', $field));
        }

        return $value;
    }
}
