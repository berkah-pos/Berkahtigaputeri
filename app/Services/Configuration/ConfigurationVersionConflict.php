<?php

namespace App\Services\Configuration;

use RuntimeException;

final class ConfigurationVersionConflict extends RuntimeException
{
    public function __construct(
        public readonly int $expectedVersion,
        public readonly int $currentVersion,
        string $message = 'Configuration version conflict.'
    ) {
        parent::__construct($message);
    }
}
