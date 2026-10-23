#!/usr/bin/env python3
"""Verify Compose separates provisioning secrets without printing secret values.

The report contains environment-variable NAMES only. Never log Compose's rendered
configuration because it contains interpolated secret values.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
INFRASTRUCTURE_SERVICES = {"postgres", "redis", "openbao"}
ELEVATED_NAME_MARKERS = (
    "PROVISIONER_",
    "OPENBAO_PROVISIONER_",
    "MIGRATOR",
    "VAULT_ROOT",
    "OPENBAO_ROOT",
    "ROOT_DB_",
    "DB_ROOT_",
    "DB_SUPERUSER_",
    "DB_ADMIN_",
    "ROOT_TOKEN",
)


def has_elevated_name(name: str) -> bool:
    normalized = name.upper()
    return any(marker in normalized for marker in ELEVATED_NAME_MARKERS)


def fail(message: str) -> int:
    print(f"FAIL: {message}", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()

    command = [
        "docker", "compose",
        "-f", "docker-compose.yml",
        "-f", "docker-compose.provisioner.yml",
        "--profile", "provisioning",
        "config", "--format", "json",
    ]
    try:
        rendered = subprocess.run(
            command,
            cwd=ROOT,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError:
        return fail("Docker Compose could not be invoked; no credential-boundary evidence produced.")

    if rendered.returncode != 0:
        # Do not echo captured output: Compose errors may contain interpolated values.
        return fail("Compose configuration is invalid; captured output withheld to avoid secret disclosure.")

    try:
        config: dict[str, Any] = json.loads(rendered.stdout)
    except json.JSONDecodeError:
        return fail("Compose did not return valid JSON; rendered output withheld.")

    services = config.get("services")
    if not isinstance(services, dict):
        return fail("Resolved Compose configuration has no services mapping.")

    app = services.get("app")
    provisioner = services.get("provisioner")
    if not isinstance(app, dict) or not isinstance(provisioner, dict):
        return fail("Expected app and opt-in provisioner services are both required.")

    build = provisioner.get("build") or {}
    if not isinstance(build, dict) or build.get("target") != "production":
        return fail("Provisioner must use the reviewed production image target, not the development image.")

    entrypoint = provisioner.get("entrypoint")
    if entrypoint:
        return fail("Provisioner must preserve the production image entrypoint for safe Laravel path preparation.")

    def environment_names(service: dict[str, Any]) -> list[str]:
        environment = service.get("environment") or {}
        if isinstance(environment, dict):
            return sorted(str(name) for name in environment)
        if isinstance(environment, list):
            return sorted(str(item).split("=", 1)[0] for item in environment)
        return []

    def environment_map(service: dict[str, Any]) -> dict[str, str]:
        environment = service.get("environment") or {}
        if isinstance(environment, dict):
            return {str(name): "" if value is None else str(value) for name, value in environment.items()}
        if isinstance(environment, list):
            pairs = [str(item).split("=", 1) for item in environment]
            return {pair[0]: pair[1] if len(pair) > 1 else "" for pair in pairs}
        return {}

    # Require dedicated source variables instead of accidentally inheriting the
    # application's default CENTRAL_DB_USERNAME=postgres / CENTRAL_DB_PASSWORD.
    overlay = (ROOT / "docker-compose.provisioner.yml").read_text(encoding="utf-8")
    required_overlay_mappings = {
        "username": "CENTRAL_DB_USERNAME: ${WORKER_CENTRAL_DB_USERNAME:-}",
        "password": "CENTRAL_DB_PASSWORD: ${WORKER_CENTRAL_DB_PASSWORD:-}",
    }
    overlay_lines = {line.strip() for line in overlay.splitlines()}
    for setting, mapping in required_overlay_mappings.items():
        if mapping not in overlay_lines:
            return fail(
                "Provisioner central DB " + setting
                + " must map to its dedicated WORKER_CENTRAL_DB_" + setting.upper() + " input."
            )

    app_environment = environment_map(app)
    worker_environment = environment_map(provisioner)
    app_central_username = app_environment.get("CENTRAL_DB_USERNAME", "")
    app_central_password = app_environment.get("CENTRAL_DB_PASSWORD", "")
    worker_central_username = worker_environment.get("CENTRAL_DB_USERNAME", "")
    worker_central_password = worker_environment.get("CENTRAL_DB_PASSWORD", "")
    broker_username = worker_environment.get("PROVISIONER_DB_USERNAME", "")
    broker_password = worker_environment.get("PROVISIONER_DB_PASSWORD", "")
    if (
        not worker_central_username.strip()
        or not worker_central_password
        or worker_central_username == app_central_username
        or worker_central_password == app_central_password
        or worker_central_username == broker_username
        or worker_central_password == broker_password
    ):
        return fail(
            "Provisioner central DB identity must be non-empty and distinct from both the app "
            "central identity and the PostgreSQL broker identity; credential values are withheld."
        )

    privileged_services: list[str] = []
    service_report: dict[str, Any] = {}

    for service_name, definition in services.items():
        if not isinstance(definition, dict):
            return fail(f"Service definition '{service_name}' is invalid.")

        names = environment_names(definition)
        privileged_names = sorted(name for name in names if has_elevated_name(name))
        is_provisioner = service_name == "provisioner"

        if privileged_names:
            privileged_services.append(service_name)
        if privileged_names and not is_provisioner:
            return fail(
                "Privileged environment-variable names appear outside the isolated provisioner service: "
                + ", ".join(privileged_names)
            )

        service_report[service_name] = {
            "classification": (
                "isolated-provisioner" if is_provisioner
                else "infrastructure" if service_name in INFRASTRUCTURE_SERVICES
                else "application-runtime"
            ),
            "environment_names": names,
            "elevated_environment_names": privileged_names,
            "has_published_ports": bool(definition.get("ports")),
            "profiles": sorted(definition.get("profiles") or []),
            "network_mode": definition.get("network_mode") or "compose-private-network",
            "privileged_container": bool(definition.get("privileged", False)),
        }

    provisioner_names = set(environment_names(provisioner))
    required = {
        "OPENBAO_PROVISIONER_MODE",
        "OPENBAO_PROVISIONER_TOKEN",
        "PROVISIONER_DB_USERNAME",
        "PROVISIONER_DB_PASSWORD",
    }
    missing = sorted(required - provisioner_names)
    if missing:
        return fail("Isolated provisioner service is missing required environment-variable names: " + ", ".join(missing))

    profiles = set(provisioner.get("profiles") or [])
    if "provisioning" not in profiles:
        return fail("Provisioner must be gated behind the explicit 'provisioning' Compose profile.")
    if provisioner.get("ports"):
        return fail("Provisioner publishes ports; privileged worker ingress must remain private.")
    if (provisioner.get("network_mode") or "").lower() == "host":
        return fail("Provisioner must not use host networking.")
    if bool(provisioner.get("privileged", False)):
        return fail("Provisioner container must not run in privileged mode.")
    raw_command = provisioner.get("command") or []
    if not isinstance(raw_command, list) or raw_command[:3] != ["php", "artisan", "tenants:provision-database"]:
        return fail("Provisioner must directly invoke the tenant provisioning Artisan command without a shell wrapper.")
    if len(raw_command) != 4 or not str(raw_command[3]).strip():
        return fail("Provisioner must receive exactly one non-empty tenant ULID argument.")

    if privileged_services != ["provisioner"]:
        return fail("Only the isolated provisioner service may receive elevated environment-variable names.")

    report = {
        "schema_version": 1,
        "scope": (
            "resolved Compose environment-variable names and worker exposure only; "
            "never credential values or PostgreSQL role attributes/privileges"
        ),
        "checks": {
            "app_has_no_elevated_environment_names": not any(
                has_elevated_name(name) for name in environment_names(app)
            ),
            "only_provisioner_has_elevated_environment_names": privileged_services == ["provisioner"],
            "provisioner_is_profile_gated": True,
            "provisioner_has_no_published_ports": True,
            "provisioner_does_not_use_host_networking": True,
            "provisioner_is_not_privileged": True,
            "provisioner_uses_production_image": True,
            "provisioner_invokes_artisan_without_shell_wrapper": True,
            "worker_central_identity_uses_dedicated_inputs": True,
            "worker_central_identity_differs_from_app_identity": True,
            "worker_central_identity_differs_from_broker_identity": True,
            "secret_values_included": False,
        },
        "services": service_report,
        "note": (
            "This verifies repository Compose configuration only. It does not establish "
            "that the live Coolify deployment has the same service environment or networking, "
            "and it does not prove the PostgreSQL privileges of configured DB identities."
        ),
    }

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("PASS: provisioning-only variables are isolated to the profile-gated, non-public worker.")
    print("PASS: redacted environment-name report written; no secret values were printed or stored.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
