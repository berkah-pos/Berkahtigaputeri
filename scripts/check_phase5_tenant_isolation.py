#!/usr/bin/env python3
"""Fail-closed static guards for the active Laravel mobile/API architecture.

This check validates source wiring only; PostgreSQL grant isolation and full
runtime acceptance are covered by the disposable PostgreSQL 17 CI suite.
"""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    print("FAIL: " + message, file=sys.stderr)
    raise SystemExit(1)


def require(text: str, fragment: str, source: str) -> None:
    if fragment.casefold() not in text.casefold():
        fail(source + " is missing required contract fragment: " + fragment)


def main() -> int:
    pubspec = (ROOT / "pos-app/pubspec.yaml").read_text(encoding="utf-8")
    main_dart = (ROOT / "pos-app/lib/main.dart").read_text(encoding="utf-8")
    api_client_path = ROOT / "pos-app/lib/core/api/laravel_api_client.dart"
    config_path = ROOT / "pos-app/lib/core/config/config_service.dart"
    api_client = api_client_path.read_text(encoding="utf-8")
    config_service = config_path.read_text(encoding="utf-8")
    routes = (ROOT / "routes/api.php").read_text(encoding="utf-8")
    config_controller = (ROOT / "app/Http/Controllers/Api/V1/EffectiveConfigController.php").read_text(encoding="utf-8")
    device_controller = (ROOT / "app/Http/Controllers/Api/V1/DeviceController.php").read_text(encoding="utf-8")
    auth_controller = (ROOT / "app/Http/Controllers/Api/V1/AuthController.php").read_text(encoding="utf-8")
    database_config = (ROOT / "config/database.php").read_text(encoding="utf-8")
    workbook_workflow = (ROOT / ".github/workflows/canonical-workbook-validate.yml").read_text(encoding="utf-8")

    if "supabase_flutter" in pubspec.casefold():
        fail("Flutter package manifest still depends on the prohibited Supabase SDK.")
    for path in (ROOT / "pos-app/lib").rglob("*.dart"):
        source = path.read_text(encoding="utf-8")
        for forbidden in ("supabase_flutter", "Supabase.initialize", "SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "Supabase.instance"):
            if forbidden.casefold() in source.casefold():
                fail(str(path.relative_to(ROOT)) + " contains a prohibited active Supabase runtime reference: " + forbidden)

    require(main_dart, "BERKAH_API_BASE_URL", "pos-app/lib/main.dart")
    require(api_client, "FlutterSecureStorage", str(api_client_path.relative_to(ROOT)))
    require(api_client, "Authorization", str(api_client_path.relative_to(ROOT)))
    require(api_client, "Bearer", str(api_client_path.relative_to(ROOT)))
    require(api_client, "enrollDevice", str(api_client_path.relative_to(ROOT)))
    require(api_client, "getEffectiveConfig", str(api_client_path.relative_to(ROOT)))
    require(config_service, "on ApiTransportException", str(config_path.relative_to(ROOT)))
    require(config_service, "config_scope_mismatch", str(config_path.relative_to(ROOT)))
    require(routes, "/v1/auth/login", "routes/api.php")
    require(routes, "/v1/auth/logout", "routes/api.php")
    require(routes, "/v1/devices/enroll", "routes/api.php")
    require(routes, "/v1/config/effective", "routes/api.php")
    require(routes, "/v1/sync", "routes/api.php")
    require(routes, "auth:sanctum", "routes/api.php")
    require(config_controller, "sha256", "EffectiveConfigController.php")
    require(auth_controller, "createToken", "AuthController.php")
    require(auth_controller, "hasActiveSubscription", "AuthController.php")
    require(device_controller, "device_already_bound", "DeviceController.php")
    require(config_controller, "device_not_authorized", "EffectiveConfigController.php")
    require(config_controller, "sha256", "EffectiveConfigController.php")
    require(database_config, "'username' => env('TENANT_DB_USERNAME') ?: '__tenant_runtime_role_required__'", "config/database.php")
    tenant = database_config.split("'tenant' => [", 1)[1].split("        ],", 1)[0]
    if "CENTRAL_DB_USERNAME" in tenant or "CENTRAL_DB_PASSWORD" in tenant or "TENANT_DB_URL" in tenant:
        fail("Tenant connection must not inherit central credentials or accept an overriding DSN.")
    if "scripts/sync_excel_to_supabase.py" in workbook_workflow:
        fail("Active workbook CI must never invoke the prohibited legacy sync script.")

    print("PASS: Laravel API route/auth/device/config source contract and no-Supabase Flutter runtime guard")
    print("NOTE: This static check is not proof of production tenant isolation; the disposable PostgreSQL 17 tests are a separate gate.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
