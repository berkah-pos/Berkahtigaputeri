#!/usr/bin/env python3
"""Static preflight for the Phase 5 Flutter migration and config contract.

The historical filename is retained for workflow compatibility. This script is
not a runtime tenant-isolation certification; PostgreSQL integration tests own
that security gate.
"""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "pos-app"
CONFIG_SERVICE = APP / "lib/core/config/config_service.dart"
CONFIG_TEST = APP / "test/config/config_service_test.dart"
MAIN = APP / "lib/main.dart"
PUBSPEC = APP / "pubspec.yaml"
CANONICAL = ROOT / "docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md"
ROUTES = ROOT / "routes/api.php"
IDENTITY = ROOT / "app/Http/Controllers/Api/V1/IdentityController.php"
IDENTITY_CONTEXT = ROOT / "app/Http/Middleware/EnsureIdentityContext.php"

def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

def require(text: str, fragment: str, source: str) -> None:
    if fragment.casefold() not in text.casefold():
        fail(f"{source} is missing required contract fragment: {fragment}")

def main() -> int:
    canonical = CANONICAL.read_text(encoding="utf-8")
    config_service = CONFIG_SERVICE.read_text(encoding="utf-8")
    config_test = CONFIG_TEST.read_text(encoding="utf-8")
    main_source = MAIN.read_text(encoding="utf-8")
    pubspec = PUBSPEC.read_text(encoding="utf-8")
    routes = ROUTES.read_text(encoding="utf-8")
    identity = IDENTITY.read_text(encoding="utf-8")
    identity_context = IDENTITY_CONTEXT.read_text(encoding="utf-8")

    for layer in ("GLOBAL", "TEMPLATE", "TENANT", "SERVICE", "DEVICE"):
        require(canonical, layer, str(CANONICAL.relative_to(ROOT)))
    require(canonical, "352", str(CANONICAL.relative_to(ROOT)))
    require(config_test, "GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE", str(CONFIG_TEST.relative_to(ROOT)))
    require(config_service, "class EffectiveConfigResolver", str(CONFIG_SERVICE.relative_to(ROOT)))
    require(config_service, "mergeLayers", str(CONFIG_SERVICE.relative_to(ROOT)))
    require(config_service, "TenantFeatures", str(CONFIG_SERVICE.relative_to(ROOT)))
    require(config_service, "fromEffectiveConfig", str(CONFIG_SERVICE.relative_to(ROOT)))
    require(main_source, "LaravelAuthService", str(MAIN.relative_to(ROOT)))
    require(main_source, "BERKAH_API_BASE_URL", str(MAIN.relative_to(ROOT)))
    require(routes, "api.v1.auth.login", str(ROUTES.relative_to(ROOT)))
    require(routes, "identity.context", str(ROUTES.relative_to(ROOT)))
    require(identity, "device_secret", str(IDENTITY.relative_to(ROOT)))
    require(identity, "tenant_membership_denied", str(IDENTITY.relative_to(ROOT)))
    require(identity_context, "X-Tenant-ID", str(IDENTITY_CONTEXT.relative_to(ROOT)))
    require(identity_context, "X-Device-ID", str(IDENTITY_CONTEXT.relative_to(ROOT)))

    if "supabase_flutter" in pubspec.casefold():
        fail("Flutter package manifest must not depend on supabase_flutter")
    if "supabase" in main_source.casefold() or "supabase" in config_service.casefold():
        fail("Flutter runtime must not import or reference Supabase")
    if "_client.rpc(" in config_service or "get_effective_config" in config_service:
        fail("Flutter config helper must not call a legacy remote RPC")
    if "package:http/" in config_service or "SupabaseClient" in config_service:
        fail("EffectiveConfigResolver must remain a pure local helper until its Laravel client contract is implemented")

    # Guard all currently shipped Flutter Dart sources/tests, including test-only
    # code that might otherwise reintroduce an SDK dependency unnoticed.
    for subtree in (APP / "lib", APP / "test"):
        for source in subtree.rglob("*.dart"):
            body = source.read_text(encoding="utf-8")
            if "supabase" in body.casefold() or "get_effective_config" in body:
                fail(f"{source.relative_to(ROOT)} contains legacy Supabase runtime/RPC references")

    print("PASS: five-layer/352-entry config contract preserved; Flutter uses Laravel identity and no Supabase runtime/RPC")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
