#!/usr/bin/env python3
"""Fail-closed checks for the KVM2/Laravel migration and canonical config contract."""

from pathlib import Path
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
]
FORBIDDEN = (
    "supabase_flutter",
    "SupabaseClient",
    "SUPABASE_URL",
    "SUPABASE_PUBLISHABLE_KEY",
    "SUPABASE_SERVICE_ROLE_KEY",
    "get_effective_config",
)
REQUIRED = [
    ("composer.json", '"laravel/framework": "^11.0"'),
    ("composer.json", '"filament/filament": "^3.2"'),
    ("composer.json", '"stancl/tenancy": "^3.8"'),
    ("Dockerfile", "HEALTHCHECK"),
    ("docker-compose.yml", "mariadb:11"),
    ("config/tenancy.php", "'template_tenant_connection' => 'tenant'"),
    ("routes/api.php", "'/effective-config'"),
    ("app/Services/EffectiveConfigResolver.php", "array_merge($global, $template, $tenantLayer, $serviceLayer, $deviceLayer)"),
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
            if token in source:
                errors.append(f"{relative} contains forbidden runtime reference {token!r}")

    for relative, token in REQUIRED:
        path = ROOT / relative
        if not path.is_file() or token not in path.read_text(encoding="utf-8"):
            errors.append(f"missing contract: {relative} -> {token}")

    if (ROOT / "supabase").exists():
        errors.append("active supabase/ directory remains in the repository")

    if errors:
        print("\n".join(f"FAIL: {item}" for item in errors), file=sys.stderr)
        return 1

    print("PASS: active mobile, API, tenancy, deployment and documentation contracts are Supabase-free.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
