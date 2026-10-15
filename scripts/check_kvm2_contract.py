#!/usr/bin/env python3
"""Fail-closed checks for active KVM2/Laravel runtime and canonical config contract."""

from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ACTIVE_FILES = [
    "pos-app/pubspec.yaml",
    "pos-app/lib/main.dart",
    "pos-app/lib/core/config/config_service.dart",
    "pos-app/lib/core/config/central_api_client.dart",
    "pos-app/lib/features/auth/login_screen.dart",
    "pos-app/test/auth/login_screen_test.dart",
    ".github/workflows/berkah-pos-aab.yml",
    ".github/workflows/kvm2-laravel-ci.yml",
    "app/Services/EffectiveConfigResolver.php",
    "app/Services/VersionedConfigWriter.php",
    "app/Models/Central/TenantMembership.php",
    "app/Services/TenantDatabaseProvisioner.php",
    "app/Database/TenantDatabaseManager.php",
    "app/Jobs/ProvisionTenantDatabase.php",
    "app/Console/Commands/ProvisionTenantDatabaseCommand.php",
    "scripts/check_provisioning_env_contract.py",
    "app/Http/Controllers/Api/V1/EffectiveConfigController.php",
    "routes/api.php",
    "composer.json",
    "Dockerfile",
    "docker-compose.yml",
]
FORBIDDEN = (
    "supabase_flutter",
    "SupabaseClient",
    "SUPABASE_URL",
    "SUPABASE_PUBLISHABLE_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
    "get_effective_config",
    "supabase-js",
)
REQUIRED = [
    ("composer.json", '"laravel/framework": "^11.0"'),
    ("composer.json", '"filament/filament": "^3.2"'),
    ("composer.json", '"stancl/tenancy": "^3.8"'),
    ("Dockerfile", "HEALTHCHECK"),
    ("docker-compose.yml", "mariadb:11"),
    ("config/tenancy.php", "'template_tenant_connection' => 'tenant_template'"),
    ("config/tenancy.php", "TenantDatabaseManager::class"),
    ("app/Console/Commands/ProvisionTenantDatabaseCommand.php", "database.connections.provisioner.username"),
    ("docker/mysql-init/10-tenant-db-privileges.sql", "GRANT SELECT, INSERT, UPDATE, DELETE"),
    ("routes/api.php", "'/effective-config'"),
    ("app/Services/EffectiveConfigResolver.php", "$this->deepMerge("),
    ("app/Services/EffectiveConfigResolver.php", "tenant_memberships"),
    ("app/Services/EffectiveConfigResolver.php", "$this->loadRequestedServiceRow($tenantId, $service)"),
    ("app/Services/VersionedConfigWriter.php", "->where('version', $expectedVersion)"),
    ("app/Console/Commands/ImportCanonicalWorkbook.php", "compareAndSwap("),
    ("app/Services/EffectiveConfigResolver.php", "hash('sha256', $this->canonicalJson($merged))"),
    ("app/Http/Controllers/Api/V1/EffectiveConfigController.php", "'effective_version' => $meta['effective_version']"),
    ("app/Console/Commands/ImportCanonicalWorkbook.php", '$calculatedHash = md5(implode("\\n", $keys));'),
    ("app/Console/Commands/ImportCanonicalWorkbook.php", "{--dry-run"),
    ("docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md", "**Status:** CANONICAL"),
]


def main() -> int:
    errors: list[str] = []
    for relative in ACTIVE_FILES:
        path = ROOT / relative
        if not path.is_file():
            errors.append(f"missing active file: {relative}")
            continue

        source = path.read_text(encoding="utf-8")
        for token in FORBIDDEN:
            if token.lower() in source.lower():
                errors.append(f"{relative} contains forbidden active-runtime reference {token!r}")

    for relative, token in REQUIRED:
        path = ROOT / relative
        if not path.is_file() or token not in path.read_text(encoding="utf-8"):
            errors.append(f"missing contract: {relative} -> {token}")

    if errors:
        print("\n".join(f"FAIL: {item}" for item in errors), file=sys.stderr)
        return 1

    env_contract = subprocess.run(
        [sys.executable, str(ROOT / "scripts/check_provisioning_env_contract.py")],
        check=False,
    )
    if env_contract.returncode != 0:
        return env_contract.returncode

    print(
        "PASS: active Flutter/Laravel runtime is Supabase-free; deep merge, SHA-256 "
        "version hashes, CLI import validation, and provisioning credential contracts are present."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
