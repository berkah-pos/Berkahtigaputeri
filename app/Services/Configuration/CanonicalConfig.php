<?php

namespace App\Services\Configuration;

use InvalidArgumentException;
use JsonException;
use stdClass;

final class CanonicalConfig
{
    public static function decodeObject(mixed $value, string $label = 'config'): stdClass
    {
        if (is_string($value)) {
            try {
                $value = json_decode($value, false, 512, JSON_THROW_ON_ERROR);
            } catch (JsonException $exception) {
                throw new InvalidArgumentException("{$label} is not valid JSON.", previous: $exception);
            }
        }

        if ($value instanceof stdClass) {
            return clone $value;
        }

        if (is_array($value) && ! array_is_list($value)) {
            return self::toObject($value);
        }

        throw new InvalidArgumentException("{$label} must be a JSON object.");
    }

    public static function toObject(array|stdClass $value): stdClass
    {
        if ($value instanceof stdClass) {
            $source = get_object_vars($value);
        } else {
            if (array_is_list($value) && $value !== []) {
                throw new InvalidArgumentException('Configuration payload must be an object, not a list.');
            }
            $source = $value;
        }

        $result = new stdClass();
        foreach ($source as $key => $item) {
            $result->{(string) $key} = self::convertNested($item);
        }

        return $result;
    }

    private static function convertNested(mixed $value): mixed
    {
        if ($value instanceof stdClass) {
            return self::toObject($value);
        }

        if (is_array($value)) {
            if ($value === []) {
                return [];
            }

            if (array_is_list($value)) {
                return array_map(self::convertNested(...), $value);
            }

            return self::toObject($value);
        }

        return $value;
    }

    public static function versionFrom(stdClass $config, string $label): int
    {
        $version = $config->version ?? 1;
        if (is_bool($version) || (! is_int($version) && ! (is_string($version) && ctype_digit($version))) ||
            (int) $version < 1) {
            throw new InvalidArgumentException("{$label}: version must be a positive integer.");
        }

        return (int) $version;
    }

    public static function withoutVersion(stdClass $config): stdClass
    {
        $values = get_object_vars($config);
        unset($values['version']);

        return self::toObject($values);
    }

    public static function merge(stdClass $base, stdClass $override): stdClass
    {
        $merged = clone $base;

        foreach (get_object_vars($override) as $key => $value) {
            if (property_exists($merged, $key) &&
                $merged->{$key} instanceof stdClass &&
                $value instanceof stdClass) {
                $merged->{$key} = self::merge($merged->{$key}, $value);
            } else {
                // Presence, not truthiness, controls overrides: null/false/0/"" are explicit values.
                $merged->{$key} = $value;
            }
        }

        return $merged;
    }

    public static function canonicalize(mixed $value): mixed
    {
        if ($value instanceof stdClass) {
            $members = get_object_vars($value);
            ksort($members, SORT_STRING);
            $canonical = new stdClass();
            foreach ($members as $key => $member) {
                $canonical->{$key} = self::canonicalize($member);
            }

            return $canonical;
        }

        if (is_array($value)) {
            return array_map(self::canonicalize(...), $value);
        }

        return $value;
    }

    public static function json(mixed $value): string
    {
        return json_encode(
            self::canonicalize($value),
            JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION | JSON_THROW_ON_ERROR
        );
    }

    public static function sha256(mixed $value): string
    {
        return hash('sha256', self::json($value));
    }

    public static function identifier(string $value, string $label): string
    {
        if ($value === '' || trim($value) !== $value ||
            ! preg_match('/^[a-z][a-z0-9]*(?:[_-][a-z0-9]+)*$/D', $value)) {
            throw new InvalidArgumentException("{$label} must be a normalized lowercase identifier.");
        }

        return $value;
    }
}
