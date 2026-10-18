#!/usr/bin/env python3
"""Fail-closed checks for the approved dependency baseline and active product contract."""

from pathlib import Path
import json
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
    "artisan",
    "composer.json",
    "composer.lock",
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
    ("Dockerfile", "FROM php:8.4.25-fpm-bookworm@sha256:"),
    ("Dockerfile", "composer validate --strict --no-check-publish"),
    ("Dockerfile", "composer install --no-dev"),
    ("Dockerfile", "composer audit --locked"),
    ("Dockerfile", "pdo_pgsql"),
    ("Dockerfile", "composer.json composer.lock"),
    ("config/tenancy.php", "'template_tenant_connection' => 'tenant_template'"),
    ("config/tenancy.php", "TenantDatabaseManager::class"),
    ("app/Console/Commands/ProvisionTenantDatabaseCommand.php", "database.connections.provisioner.username"),
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
]
ROOT_REQUIRE = {
    "php": "^8.4",
    "laravel/framework": "^13.0",
    "filament/filament": "^5.0",
    "stancl/tenancy": "^3.10.1",
    "laravel/sanctum": "^4.0",
}
LOCKED_PREFIXES = {
    "laravel/framework": "13.",
    "filament/filament": "5.",
    "laravel/sanctum": "4.",
}
EXACT_LOCKED_VERSIONS = {"stancl/tenancy": "3.10.1"}
POLICY_FILES = [
    "composer.json",
    "Dockerfile",
    ".github/workflows/kvm2-laravel-ci.yml",
    ".github/workflows/phase2-tenant-grants-ci.yml",
    ".github/workflows/pos-app-ci.yml",
]
FORBIDDEN_POLICY_TOKENS = (
    "--no-security-blocking",
    "--no-blocking",
    "--ignore-platform-reqs",
    "--no-audit",
    '"block": false',
    '"block":false',
)


def version_without_v(value: str) -> str:
    return value[1:] if value.startswith("v") else value


def check_dependency_baseline(errors: list[str]) -> None:
    try:
        manifest = json.loads((ROOT / "composer.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"cannot parse composer.json: {exc}")
        return

    requirements = manifest.get("require", {})
    for package, expected in ROOT_REQUIRE.items():
        if requirements.get(package) != expected:
            errors.append(
                f"dependency baseline drift: composer.json require.{package} "
                f"expected {expected!r}, got {requirements.get(package)!r}"
            )
    for extension in ("ext-pdo_mysql", "ext-pdo_pgsql"):
        if extension not in requirements:
            errors.append(f"dependency baseline drift: {extension} must remain an explicit platform requirement")

    composer_config = manifest.get("config", {})
    audit_config = composer_config.get("audit", {})
    if isinstance(audit_config, dict) and audit_config.get("ignore"):
        errors.append("Composer config.audit.ignore must remain empty; advisory suppression is prohibited")

    advisories = composer_config.get("policy", {}).get("advisories", {})
    if isinstance(advisories, dict) and (
        advisories.get("block") is False or "ignore" in advisories or "ignore-id" in advisories
    ):
        errors.append("Composer advisory blocking is disabled or advisory ignores are configured")

    lock_path = ROOT / "composer.lock"
    if not lock_path.is_file():
        errors.append("composer.lock is required and must be committed")
        return
    try:
        lock = json.loads(lock_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"cannot parse composer.lock: {exc}")
        return

    if not isinstance(lock.get("content-hash"), str) or not lock["content-hash"]:
        errors.append("composer.lock is missing its content-hash")

    packages = {
        item.get("name"): version_without_v(item.get("version", ""))
        for item in lock.get("packages", [])
        if isinstance(item, dict)
    }
    for package, expected_prefix in LOCKED_PREFIXES.items():
        actual = packages.get(package)
        if actual is None or not actual.startswith(expected_prefix):
            errors.append(f"locked dependency drift: {package} expected version prefix {expected_prefix!r}, got {actual!r}")
    for package, expected_version in EXACT_LOCKED_VERSIONS.items():
        actual = packages.get(package)
        if actual != expected_version:
            errors.append(f"locked dependency drift: {package} must stay at {expected_version!r}, got {actual!r}")

    platform = lock.get("platform", {})
    for requirement in ("ext-pdo", "ext-pdo_mysql", "ext-pdo_pgsql"):
        if requirement not in platform:
            errors.append(f"composer.lock platform requirements are missing {requirement}")

    if lock.get("platform-overrides", {}).get("php") != "8.4.0":
        errors.append("composer.lock platform-overrides.php must stay at 8.4.0")

    for relative in POLICY_FILES:
        path = ROOT / relative
        if not path.is_file():
            continue
        source = path.read_text(encoding="utf-8").lower()
        for token in FORBIDDEN_POLICY_TOKENS:
            if token.lower() in source:
                errors.append(f"{relative} contains prohibited Composer/platform-policy suppression {token!r}")


def main() -> int:
    errors: list[str] = []
    for relative in ACTIVE_FILES:
        path = ROOT / relative
        if not path.is_file():
            errors.append(f"missing active file: {relative}")
            continue
        text = path.read_text(encoding="utf-8")
        for token in FORBIDDEN:
            if token.lower() in text.lower():
                errors.append(f"{relative} contains forbidden active-runtime reference {token!r}")

    for relative, token in REQUIRED:
        path = ROOT / relative
        if not path.is_file() or token not in path.read_text(encoding="utf-8"):
            errors.append(f"missing contract: {relative} -> {token}")

    check_dependency_baseline(errors)
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
        "PASS: PHP 8.4 / Laravel 13 / Filament 5 / tenancy 3.10.1 baseline is locked; "
        "Composer advisory blocking remains active; active runtime is Supabase-free."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
