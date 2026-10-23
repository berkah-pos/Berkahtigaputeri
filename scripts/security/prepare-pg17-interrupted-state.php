<?php

declare(strict_types=1);

// Test-only crash-window fixture: commit the durable role/intent step, then exit
// before CREATE DATABASE. The shell suite creates the closed database separately
// to simulate a process interruption immediately after non-transactional CREATE DATABASE.
$tenantId = $argv[1] ?? '';
if (!preg_match('/^[0-9A-HJKMNP-TV-Z]{26}$/', $tenantId)) {
    fwrite(STDERR, "invalid synthetic tenant ID\n");
    exit(2);
}
$runtimePassword = getenv('TEST_C_RUNTIME_PASSWORD');
$migratorPassword = getenv('TEST_C_MIGRATOR_PASSWORD');
$brokerPassword = getenv('BROKER_DATABASE_PASSWORD');
if (!is_string($runtimePassword) || !is_string($migratorPassword) || !is_string($brokerPassword)) {
    fwrite(STDERR, "required test-only process environment is missing\n");
    exit(2);
}
$pdo = new PDO(
    'pgsql:host=127.0.0.1;port=5432;dbname=postgres;connect_timeout=5',
    'berkah_provisioner',
    $brokerPassword,
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_EMULATE_PREPARES => false],
);
$scramVerifier = static function (string $password): string {
    if (!preg_match('/^[a-fA-F0-9]{64,128}$/', $password)) {
        throw new InvalidArgumentException('Test password must be high-entropy hexadecimal.');
    }
    $salt = random_bytes(16);
    $iterations = 4096;
    $saltedPassword = hash_pbkdf2('sha256', $password, $salt, $iterations, 32, true);
    $clientKey = hash_hmac('sha256', 'Client Key', $saltedPassword, true);
    $storedKey = hash('sha256', $clientKey, true);
    $serverKey = hash_hmac('sha256', 'Server Key', $saltedPassword, true);

    return 'SCRAM-SHA-256$' . $iterations . ':' . base64_encode($salt)
        . '$' . base64_encode($storedKey) . ':' . base64_encode($serverKey);
};
$stmt = $pdo->prepare('SELECT provisioning.ensure_tenant_roles(:tenant_id, :runtime_password, :migrator_password) AS state');
$stmt->execute([
    'tenant_id' => $tenantId,
    'runtime_password' => $scramVerifier($runtimePassword),
    'migrator_password' => $scramVerifier($migratorPassword),
]);
if ($stmt->fetchColumn() !== 'provisioning') {
    fwrite(STDERR, "unexpected non-provisioning state\n");
    exit(3);
}
echo "PASS: durable role/intent transaction committed; synthetic interruption point reached\n";
