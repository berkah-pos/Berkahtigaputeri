<?php

declare(strict_types=1);

namespace App\Services\Configuration;

use InvalidArgumentException;

/**
 * Validates the offline JSON manifest before the importer opens any database
 * connection or performs a write.
 */
final class CanonicalWorkbookManifestValidator
{
    public const CANONICAL_KEYSET_MD5 = '1fd3d64219ecc7c333453c20da80e295';

    private const EXPECTED_COUNTS = [
        'global' => 1,
        'template' => 3,
        'tenant' => 100,
        'service' => 140,
        'device' => 108,
    ];

    private const TEMPLATE_IDS = ['BASIC', 'ENTERPRISE', 'PRO'];

    private const SERVICES = ['akuntansi', 'pos'];

    public function __construct(
        private readonly string $expectedKeysetMd5 = self::CANONICAL_KEYSET_MD5,
    ) {
    }

    /**
     * @param mixed $manifest A decoded JSON value.
     */
    public function validate(mixed $manifest): void
    {
        if (! is_array($manifest) || array_is_list($manifest)) {
            throw new InvalidArgumentException('Manifest root must be a JSON object.');
        }

        if (($manifest['schema_version'] ?? null) !== 1) {
            throw new InvalidArgumentException('Unsupported manifest schema version.');
        }

        if (($manifest['keyset_md5'] ?? null) !== $this->expectedKeysetMd5) {
            throw new InvalidArgumentException('Manifest does not match the expected canonical keyset hash.');
        }

        $this->validateCounts($manifest);
        $this->validateObject($manifest['global_config'] ?? null, 'global_config');

        $templates = $this->validateTemplates($manifest['templates']);
        $tenants = $this->validateTenants($manifest['tenants'], $templates);
        $services = $this->validateServices($manifest['services'], $tenants);
        $devices = $this->validateDevices($manifest['devices'], $tenants);

        $keys = ['global'];
        foreach (array_keys($templates) as $templateId) {
            $keys[] = 'template:' . $templateId;
        }
        foreach ($tenants as $tenantId => $_templateId) {
            $keys[] = 'tenant:' . $tenantId;
        }
        foreach ($services as $tenantId => $serviceNames) {
            foreach ($serviceNames as $service) {
                $keys[] = 'tenant:' . $tenantId . ':service:' . $service;
            }
        }
        foreach ($devices as $deviceId => $_tenantId) {
            $keys[] = 'device:' . $deviceId;
        }

        if (count($keys) !== 352) {
            throw new InvalidArgumentException(sprintf(
                'Manifest projects to %d canonical keys; exactly 352 are required.',
                count($keys),
            ));
        }

        sort($keys, SORT_STRING);
        $computedKeysetMd5 = md5(implode("\n", $keys));
        if (! hash_equals($this->expectedKeysetMd5, $computedKeysetMd5)) {
            throw new InvalidArgumentException('Manifest rows do not reproduce the canonical 352-key inventory.');
        }
    }

    private function validateCounts(array $manifest): void
    {
        $counts = $manifest['counts'] ?? null;
        if (! is_array($counts) || count($counts) !== count(self::EXPECTED_COUNTS)) {
            throw new InvalidArgumentException('Manifest counts must contain exactly the five canonical scopes.');
        }

        foreach (self::EXPECTED_COUNTS as $scope => $expected) {
            if (($counts[$scope] ?? null) !== $expected) {
                throw new InvalidArgumentException(sprintf(
                    'Manifest count for %s must be %d.',
                    $scope,
                    $expected,
                ));
            }
        }

        foreach ([
            'templates' => self::EXPECTED_COUNTS['template'],
            'tenants' => self::EXPECTED_COUNTS['tenant'],
            'services' => self::EXPECTED_COUNTS['service'],
            'devices' => self::EXPECTED_COUNTS['device'],
        ] as $field => $expected) {
            if (! isset($manifest[$field]) || ! is_array($manifest[$field]) ||
                ! array_is_list($manifest[$field]) || count($manifest[$field]) !== $expected) {
                throw new InvalidArgumentException(sprintf(
                    'Manifest field %s must be a list of exactly %d rows.',
                    $field,
                    $expected,
                ));
            }
        }
    }

    /**
     * @return array<string, true> The validated template identifiers.
     */
    private function validateTemplates(array $rows): array
    {
        $templates = [];
        foreach ($rows as $index => $row) {
            if (! is_array($row) || ! is_string($row['id'] ?? null)) {
                throw new InvalidArgumentException(sprintf('Template row %d is invalid.', $index));
            }

            $id = $row['id'];
            if (! in_array($id, self::TEMPLATE_IDS, true) || isset($templates[$id])) {
                throw new InvalidArgumentException(sprintf('Template id %s is unknown or duplicated.', $id));
            }

            $this->validateObject($row['config'] ?? null, sprintf('templates[%d].config', $index));
            $templates[$id] = true;
        }

        $actualIds = array_keys($templates);
        sort($actualIds, SORT_STRING);
        if ($actualIds !== self::TEMPLATE_IDS) {
            throw new InvalidArgumentException('Manifest must contain BASIC, PRO and ENTERPRISE templates exactly once.');
        }

        return $templates;
    }

    /**
     * @param array<string, true> $templates
     * @return array<string, string> tenant id => template id
     */
    private function validateTenants(array $rows, array $templates): array
    {
        $tenants = [];
        foreach ($rows as $index => $row) {
            if (! is_array($row)) {
                throw new InvalidArgumentException(sprintf('Tenant row %d is invalid.', $index));
            }

            $tenantId = $this->validatedIdentifier($row['tenant_id'] ?? null, sprintf('tenants[%d].tenant_id', $index));
            $templateId = $row['template_id'] ?? null;

            if (isset($tenants[$tenantId])) {
                throw new InvalidArgumentException(sprintf('Duplicate tenant id %s.', $tenantId));
            }
            if (! is_string($templateId) || ! isset($templates[$templateId])) {
                throw new InvalidArgumentException(sprintf('Tenant %s references an unknown template.', $tenantId));
            }

            $this->validateObject($row['config'] ?? null, sprintf('tenants[%d].config', $index));
            $tenants[$tenantId] = $templateId;
        }

        return $tenants;
    }

    /**
     * @param array<string, string> $tenants
     * @return array<string, list<string>> tenant id => service names
     */
    private function validateServices(array $rows, array $tenants): array
    {
        $servicesByTenant = [];
        foreach ($rows as $index => $row) {
            if (! is_array($row)) {
                throw new InvalidArgumentException(sprintf('Service row %d is invalid.', $index));
            }

            $tenantId = $this->validatedIdentifier($row['tenant_id'] ?? null, sprintf('services[%d].tenant_id', $index));
            $service = $row['service'] ?? null;

            if (! isset($tenants[$tenantId])) {
                throw new InvalidArgumentException(sprintf('Service row references unknown tenant %s.', $tenantId));
            }
            if (! is_string($service) || ! in_array($service, self::SERVICES, true)) {
                throw new InvalidArgumentException(sprintf('Service row for tenant %s has an invalid service.', $tenantId));
            }
            if (isset($servicesByTenant[$tenantId]) && in_array($service, $servicesByTenant[$tenantId], true)) {
                throw new InvalidArgumentException(sprintf('Duplicate service mapping %s/%s.', $tenantId, $service));
            }
            if (! is_bool($row['enabled'] ?? null)) {
                throw new InvalidArgumentException(sprintf('Service enabled flag for %s/%s must be boolean.', $tenantId, $service));
            }

            $this->validateObject($row['config'] ?? null, sprintf('services[%d].config', $index));
            $servicesByTenant[$tenantId] ??= [];
            $servicesByTenant[$tenantId][] = $service;
        }

        return $servicesByTenant;
    }

    /**
     * @param array<string, string> $tenants
     * @return array<string, string> device id => tenant id
     */
    private function validateDevices(array $rows, array $tenants): array
    {
        $devices = [];
        foreach ($rows as $index => $row) {
            if (! is_array($row)) {
                throw new InvalidArgumentException(sprintf('Device row %d is invalid.', $index));
            }

            $deviceId = $this->validatedIdentifier($row['device_id'] ?? null, sprintf('devices[%d].device_id', $index));
            $tenantId = $this->validatedIdentifier($row['tenant_id'] ?? null, sprintf('devices[%d].tenant_id', $index));

            if (isset($devices[$deviceId])) {
                throw new InvalidArgumentException(sprintf('Duplicate device id %s.', $deviceId));
            }
            if (! isset($tenants[$tenantId])) {
                throw new InvalidArgumentException(sprintf('Device %s references unknown tenant %s.', $deviceId, $tenantId));
            }
            if (! is_bool($row['active'] ?? null)) {
                throw new InvalidArgumentException(sprintf('Device active flag for %s must be boolean.', $deviceId));
            }

            $this->validateObject($row['config'] ?? null, sprintf('devices[%d].config', $index));
            $devices[$deviceId] = $tenantId;
        }

        return $devices;
    }

    private function validatedIdentifier(mixed $value, string $field): string
    {
        if (! is_string($value) || $value === '' || trim($value) !== $value ||
            strlen($value) > 150 || str_contains($value, ':') ||
            preg_match('/[\x00-\x1F\x7F]/', $value) === 1) {
            throw new InvalidArgumentException(sprintf('%s must be a non-empty canonical identifier.', $field));
        }

        return $value;
    }

    private function validateObject(mixed $value, string $field): void
    {
        if (! is_array($value) || array_is_list($value) || $value === []) {
            throw new InvalidArgumentException(sprintf('%s must be a non-empty JSON object.', $field));
        }
    }
}
