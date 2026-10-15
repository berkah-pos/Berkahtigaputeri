#!/usr/bin/env python3
"""Fail closed if public app/queue services receive privileged DB credentials."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ROOT / "docker-compose.yml"
DB_CONFIG = ROOT / "config/database.php"
TENANCY_CONFIG = ROOT / "config/tenancy.php"
GRANTS_SQL = ROOT / "docker/mysql-init/10-tenant-db-privileges.sql"

SENSITIVE_PREFIXES = (
    "PROVISIONER_", "MIGRATOR_", "TENANT_PROVISIONER_", "TENANT_MIGRATOR_",
    "MARIADB_ROOT_", "MYSQL_ROOT_", "ROOT_DB_", "TEST_DB_ADMIN_",
)


def parse_services(text):
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines)
                  if line.strip() == "services:" and not line.startswith(" ")), None)
    if start is None:
        raise ValueError("missing top-level services mapping")
    services = {}
    active = None
    for line in lines[start + 1:]:
        if line and not line.startswith(" "):
            break
        match = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if match:
            active = match.group(1)
            services[active] = []
        elif active is not None:
            services[active].append(line)
    return {name: "\n".join(lines) for name, lines in services.items()}


def environment_keys(block):
    lines = block.splitlines()
    start = next((i for i, line in enumerate(lines)
                  if re.match(r"^    environment:\s*$", line)), None)
    if start is None:
        return set()
    result = set()
    for line in lines[start + 1:]:
        if line.strip() and len(line) - len(line.lstrip(" ")) <= 4:
            break
        match = re.match(r"^      ([A-Z][A-Z0-9_]*):", line)
        if match:
            result.add(match.group(1))
    return result


def main():
    errors = []
    try:
        services = parse_services(COMPOSE.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print("FAIL: unable to parse Compose service structure (" + type(exc).__name__ + ")")
        return 1

    for name in ("app", "queue"):
        block = services.get(name)
        if block is None:
            errors.append("missing public service: " + name)
            continue
        if re.search(r"^    env_file:", block, re.MULTILINE):
            errors.append(name + " uses env_file instead of an explicit environment allowlist")
        forbidden = sorted(k for k in environment_keys(block) if k.startswith(SENSITIVE_PREFIXES))
        if forbidden:
            errors.append(name + " receives privileged variable names: " + ", ".join(forbidden))

    worker = services.get("tenant-provisioner", "")
    if not worker:
        errors.append("missing tenant-provisioner service")
    else:
        keys = environment_keys(worker)
        for key in ("PROVISIONER_DB_USERNAME", "PROVISIONER_DB_PASSWORD",
                    "MIGRATOR_DB_USERNAME", "MIGRATOR_DB_PASSWORD"):
            if key not in keys:
                errors.append("tenant-provisioner missing credential variable: " + key)
        if not re.search(r"^    profiles:\s*\[.*provisioner.*\]", worker, re.MULTILINE):
            errors.append("tenant-provisioner is not opt-in under the provisioner profile")
        if re.search(r"^    ports:", worker, re.MULTILINE):
            errors.append("tenant-provisioner must not publish ports")
        if "tenant-provisioning" not in worker:
            errors.append("tenant-provisioner must consume only the tenant-provisioning queue")
        if any(k.startswith(("MARIADB_ROOT_", "MYSQL_ROOT_", "ROOT_DB_", "TEST_DB_ADMIN_")) for k in keys):
            errors.append("tenant-provisioner receives a root credential variable")

    db_config = DB_CONFIG.read_text(encoding="utf-8")
    if re.search(r"env\('(?:CENTRAL|TENANT)_DB_USERNAME',\s*'root'\)", db_config):
        errors.append("central/tenant connection falls back to root")
    if re.search(r"'tenant'\s*=>\s*\[", db_config):
        errors.append("tenant is statically configured instead of package-managed")
    if "'username' => null" not in db_config or "'password' => null" not in db_config:
        errors.append("tenant_template has a shared static credential")

    tenancy = TENANCY_CONFIG.read_text(encoding="utf-8")
    if "TenantDatabaseManager::class" not in tenancy or "tenant_template" not in tenancy:
        errors.append("stancl tenancy is not wired to the guarded manager/template")
    if "JobPipeline::make" in tenancy or "CreateDatabase::class" in tenancy:
        errors.append("default unrestricted tenant creation pipeline remains enabled")

    grants = GRANTS_SQL.read_text(encoding="utf-8")
    normalized_grants = " ".join(
        grants.replace(chr(96), "").replace("\\_", "_").replace("\\%", "%").split()
    )
    central_grant = "GRANT SELECT, INSERT, UPDATE, DELETE ON berkahpos_central.* TO 'berkahpos_app'@'%'"
    app_grants = re.findall(r"GRANT [^;]+? TO 'berkahpos_app'@'%'", normalized_grants, re.IGNORECASE)
    if normalized_grants.count(central_grant) != 1 or len(app_grants) != 1:
        errors.append("central app user must have exactly one central-only CRUD grant")
    if re.search(r"GRANT\s+.+?\s+ON\s+\*\.\*\s+TO 'berkahpos_app'@'%'", normalized_grants, re.IGNORECASE):
        errors.append("central app user has a global grant")
    if errors:
        for item in errors:
            print("FAIL: " + item)
        return 1
    print("PASS: public app/queue allowlists exclude root/provisioner/migrator credentials; tenant credentials are tenant-bound; central app grants are central-only.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
