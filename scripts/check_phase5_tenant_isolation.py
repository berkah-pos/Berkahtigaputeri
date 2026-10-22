#!/usr/bin/env python3
"""Fail-closed static checks for the active Laravel Central API identity boundary.

The former Supabase/RLS check is intentionally replaced: the accepted runtime is
Laravel Central API + PostgreSQL, and the Flutter client must not depend on the
prohibited Supabase runtime or treat local tenant/device strings as authority.
"""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
POS = ROOT / "pos-app"
MAIN = POS / "lib/main.dart"
LOGIN = POS / "lib/features/auth/login_screen.dart"
IDENTITY = POS / "lib/core/auth/identity_service.dart"
CONFIG = POS / "lib/core/config/config_service.dart"
PUBSPEC = POS / "pubspec.yaml"
API_ROUTES = ROOT / "routes/api.php"
ACTIVE_DEVICE_MIDDLEWARE = ROOT / "app/Http/Middleware/EnsureVerifiedDevice.php"
ACTIVE_IDENTITY_MIDDLEWARE = ROOT / "app/Http/Middleware/EnsureActiveIdentity.php"


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def require(text: str, fragment: str, source: str) -> None:
    if fragment.casefold() not in text.casefold():
        fail(f"{source} is missing required contract fragment: {fragment}")


def forbid(text: str, fragment: str, source: str) -> None:
    if fragment.casefold() in text.casefold():
        fail(f"{source} contains prohibited active-runtime fragment: {fragment}")


def read(path: Path) -> str:
    if not path.is_file():
        fail(f"Required active-runtime file is missing: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def main() -> int:
    main_dart = read(MAIN)
    login = read(LOGIN)
    identity = read(IDENTITY)
    config = read(CONFIG)
    pubspec = read(PUBSPEC)
    routes = read(API_ROUTES)
    device_middleware = read(ACTIVE_DEVICE_MIDDLEWARE)
    active_identity_middleware = read(ACTIVE_IDENTITY_MIDDLEWARE)

    for fragment in (
        "BERKAH_API_BASE_URL",
        "IdentityService(",
        "await identityService.restoreSession()",
        "identityService?.hasAuthenticatedSession",
    ):
        require(main_dart, fragment, str(MAIN.relative_to(ROOT)))

    for fragment in (
        "IdentityService?",
        "identityService.signIn(",
        "SignInStatus.devicePendingApproval",
        "SignInStatus.tenantSelectionRequired",
        "requestEmailVerification",
        "requestPasswordReset",
        "Lanjutkan lokal tanpa akun",
    ):
        require(login, fragment, str(LOGIN.relative_to(ROOT)))

    for fragment in (
        "flutter_secure_storage",
        "api/v1/auth/login",
        "api/v1/auth/session",
        "api/v1/auth/logout",
        "Authorization': 'Bearer $token",
        "_validateTenantSession(session)",
        "tenantId != session.tenantId",
        "deviceId != session.deviceId",
        "service != 'pos' && service != 'akuntansi'",
        "statusCode == 401 || statusCode == 403",
    ):
        require(identity, fragment, str(IDENTITY.relative_to(ROOT)))

    for fragment in (
        "IdentityService",
        "_identityService.getEffectiveConfig(",
        "session.tenantId",
        "session.deviceId",
    ):
        require(config, fragment, str(CONFIG.relative_to(ROOT)))

    for fragment in (
        "api/v1/auth/login",
        "api.v1.auth.login",
        "api/v1/auth/session",
        "api.v1.auth/logout",
        "verified.device",
    ):
        require(routes, fragment, str(API_ROUTES.relative_to(ROOT)))

    for fragment in (
        "'device_registry as d'",
        "'tenant_memberships as tm'",
        "'t.status', 'active'",
        "'d.status', 'active'",
        "'tm.status', 'active'",
        "$token->tenant_id",
        "$token->device_id",
        "verified_identity_context",
    ):
        require(device_middleware, fragment, str(ACTIVE_DEVICE_MIDDLEWARE.relative_to(ROOT)))

    for fragment in (
        "$user->is_active",
        "$token->token_kind",
        "identity_disabled",
    ):
        require(active_identity_middleware, fragment, str(ACTIVE_IDENTITY_MIDDLEWARE.relative_to(ROOT)))

    # No active client source, tests, or package manifest may depend on Supabase.
    forbid(pubspec, "supabase_flutter", str(PUBSPEC.relative_to(ROOT)))
    forbid(pubspec, "SUPABASE_URL", str(PUBSPEC.relative_to(ROOT)))
    forbid(pubspec, "SUPABASE_PUBLISHABLE_KEY", str(PUBSPEC.relative_to(ROOT)))

    for tree in (POS / "lib", POS / "test"):
        for dart_file in tree.rglob("*.dart"):
            source = dart_file.read_text(encoding="utf-8")
            forbid(source, "package:supabase_flutter/", str(dart_file.relative_to(ROOT)))
            forbid(source, "SupabaseClient", str(dart_file.relative_to(ROOT)))
            forbid(source, "Supabase.initialize", str(dart_file.relative_to(ROOT)))

    # The mobile process cannot SELECT raw configuration layers or invent a
    # second merge/authentication path when the Central API is unavailable.
    forbid(config, "_client.rpc(", str(CONFIG.relative_to(ROOT)))
    forbid(config, ".from('app_config')", str(CONFIG.relative_to(ROOT)))
    forbid(config, "_fallbackSelectAndMerge", str(CONFIG.relative_to(ROOT)))

    print("PASS: Laravel Central API identity/device boundary; Supabase-free Flutter runtime; fail-closed config access")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
