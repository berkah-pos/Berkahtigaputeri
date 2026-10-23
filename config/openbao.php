<?php

return [
    // API address must be HTTPS and reachable only from private Coolify networks.
    'address' => env('OPENBAO_ADDR'),
    'kv_mount' => env('OPENBAO_KV_MOUNT', 'secret'),

    // Give the shared Laravel runtime only a read-only runtime-secret token.
    // The isolated provisioning worker receives a different token.
    'runtime_token' => env('OPENBAO_RUNTIME_TOKEN'),
    'provisioner_token' => env('OPENBAO_PROVISIONER_TOKEN'),

    // Optional PEM CA bundle for a private certificate authority. TLS verification
    // cannot be disabled; without this value, the OS trust store is used.
    'ca_bundle' => env('OPENBAO_CA_BUNDLE'),

    'connect_timeout_seconds' => (int) env('OPENBAO_CONNECT_TIMEOUT_SECONDS', 3),
    'timeout_seconds' => (int) env('OPENBAO_TIMEOUT_SECONDS', 5),

    // Must be true only in the dedicated, non-public provisioning worker.
    // It does not replace the requirement to omit PROVISIONER_* secrets from web.
    'provisioner_mode' => (bool) env('OPENBAO_PROVISIONER_MODE', false),
];
