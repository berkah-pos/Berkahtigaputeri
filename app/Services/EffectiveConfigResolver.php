<?php

namespace App\Services;

use InvalidArgumentException;
use JsonException;

final class EffectiveConfigResolver
{
    private const SUPPORTED_SERVICES = ['pos', 'akuntansi'];

    /**
     * Resolve one requested service. The serviceConfigs argument is keyed by
     * service name so the caller cannot accidentally merge POS and Akuntansi.
     *
     * Later layers override only the top-level fields they explicitly provide.
     * The canonical order is GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE.
     *
     * @param array<string, mixed> $global
     * @param array<string, mixed> $template
     * @param array<string, mixed> $tenant
     * @param array<string, array<string, mixed>> $serviceConfigs
     * @param array<string, mixed> $device
     * @return array<string, mixed>
     */
    public function resolve(
        string $requestedService,
        array $global,
        array $template,
        array $tenant,
        array $serviceConfigs,
        array $device,
    ): array {
        $service = strtolower(trim($requestedService));
        if (! in_array($service, self::SUPPORTED_SERVICES, true)) {
            throw new InvalidArgumentException('Unsupported configuration service.');
        }

        if (! array_key_exists($service, $serviceConfigs) || ! is_array($serviceConfigs[$service])) {
            throw new InvalidArgumentException('Configuration for the requested service is missing.');
        }

        $effective = [];
        foreach ([$global, $template, $tenant, $serviceConfigs[$service], $device] as $layer) {
            foreach ($layer as $key => $value) {
                $effective[$key] = $value;
            }
        }

        return $effective;
    }

    /**
     * Hash semantically identical JSON configuration deterministically,
     * independent of associative key ordering.
     *
     * @param array<string, mixed> $effectiveConfig
     * @throws JsonException
     */
    public function sha256(array $effectiveConfig): string
    {
        $canonical = $this->canonicalize($effectiveConfig);
        $json = json_encode(
            $canonical,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION | JSON_THROW_ON_ERROR,
        );

        return hash('sha256', $json);
    }

    private function canonicalize(array $value): array
    {
        if (array_is_list($value)) {
            return array_map(
                fn (mixed $item): mixed => is_array($item) ? $this->canonicalize($item) : $item,
                $value,
            );
        }

        ksort($value, SORT_STRING);
        foreach ($value as $key => $item) {
            if (is_array($item)) {
                $value[$key] = $this->canonicalize($item);
            }
        }

        return $value;
    }
}
