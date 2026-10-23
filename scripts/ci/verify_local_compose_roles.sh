#!/usr/bin/env bash
set -euo pipefail

bash -n "$0"

readonly smoke_database="berkahpos_local_compose_ci"
readonly smoke_role="berkahpos_local_compose_runtime_ci"
readonly smoke_password="local-compose-runtime-ci-only-password"
readonly compose_json="$(mktemp)"
database_created=0

admin_psql() {
  local database="$1"
  shift
  PGPASSWORD=postgres docker run --rm --network host --env PGPASSWORD postgres:17 \
    psql -X --no-psqlrc -h 127.0.0.1 -U postgres -d "$database" \
    -v ON_ERROR_STOP=1 "$@"
}

runtime_psql() {
  local username="$1"
  local password="$2"
  local database="$3"
  shift 3
  PGPASSWORD="$password" docker run --rm --network host --env PGPASSWORD postgres:17 \
    psql -X --no-psqlrc -h 127.0.0.1 -U "$username" -d "$database" \
    -v ON_ERROR_STOP=1 "$@"
}

cleanup() {
  if [[ "$database_created" == "1" ]]; then
    admin_psql postgres -c "DROP DATABASE IF EXISTS $smoke_database" >/dev/null 2>&1 || true
  fi

  # The smoke role name was checked absent before this run. Only remove it if
  # the local helper's marker shows this run created/managed it.
  local managed="f"
  managed="$(admin_psql postgres -At -c \
    "SELECT COALESCE(shobj_description(oid, 'pg_authid') = 'berkahpos-local-compose-runtime-v1', false) FROM pg_roles WHERE rolname = '$smoke_role'" 2>/dev/null || true)"
  if [[ "$managed" == "t" ]]; then
    admin_psql postgres -c "DROP ROLE IF EXISTS $smoke_role" >/dev/null 2>&1 || true
  fi
  rm -f "$compose_json"
}
trap cleanup EXIT

# Parse the actual Compose model, not raw YAML, so invalid interpolation and
# unsupported Compose fields fail the check before the SQL integration test.
docker compose config --format json > "$compose_json"
python3 - "$compose_json" <<'PY'
import json
import sys
from pathlib import Path

model = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
services = model["services"]
postgres = services["postgres"]
bootstrap = services["db-bootstrap"]
app = services["app"]
migrate = services["dev-migrate"]

pg_env = postgres["environment"]
bootstrap_env = bootstrap["environment"]
app_env = app["environment"]
migrate_env = migrate["environment"]

assert pg_env["POSTGRES_USER"], "PostgreSQL bootstrap username is missing"
assert pg_env["POSTGRES_PASSWORD"], "PostgreSQL bootstrap password is missing"
assert app_env["CENTRAL_DB_USERNAME"] != pg_env["POSTGRES_USER"], (
    "web app must use a different role from the PostgreSQL bootstrap account"
)
assert app_env["CENTRAL_DB_PASSWORD"] != pg_env["POSTGRES_PASSWORD"], (
    "web app runtime password must differ from the bootstrap password"
)
for key in app_env:
    assert not key.startswith(("POSTGRES_BOOTSTRAP_", "PROVISIONER_", "MIGRATOR_")), (
        f"privileged credential family leaked into app environment: {key}"
    )
assert app_env["CENTRAL_DB_USERNAME"] != "postgres", (
    "web app must not default to the PostgreSQL superuser"
)
assert "CENTRAL_DB_PASSWORD" in app_env
assert "db-bootstrap" in app["depends_on"]
assert app["depends_on"]["db-bootstrap"]["condition"] == "service_completed_successfully"
assert "postgres" in app["depends_on"]
assert app["depends_on"]["postgres"]["condition"] == "service_healthy"

assert bootstrap_env["PGUSER"] == pg_env["POSTGRES_USER"]
assert bootstrap_env["PGPASSWORD"] == pg_env["POSTGRES_PASSWORD"]
assert bootstrap_env["PGDATABASE"] == pg_env["POSTGRES_DB"]
assert bootstrap.get("entrypoint") == ["/bin/sh", "/bootstrap-local.sh"], (
    "db-bootstrap must run the isolated, file-based bootstrap script"
)
assert "ports" not in bootstrap, "db-bootstrap must not expose a public/listening port"
assert bootstrap.get("restart") == "no"
for required_target in ("/bootstrap-local.sql", "/bootstrap-local.sh"):
    assert any(
        volume.get("target") == required_target and volume.get("read_only") is True
        for volume in bootstrap.get("volumes", [])
    ), f"{required_target} must be mounted read-only"

assert "tools" in migrate.get("profiles", []), "elevated migration helper must be opt-in"
assert migrate_env["CENTRAL_DB_USERNAME"] == pg_env["POSTGRES_USER"]
assert migrate_env["CENTRAL_DB_PASSWORD"] == pg_env["POSTGRES_PASSWORD"]
assert migrate.get("restart") == "no"

for service_name, expected_port in (("postgres", "5432"), ("app", "8000")):
    ports = services[service_name].get("ports", [])
    assert ports, f"{service_name} must declare its intended local port binding"
    assert all(p.get("host_ip") == "127.0.0.1" for p in ports), (
        f"{service_name} port must bind loopback only"
    )
print("PASS: rendered Compose model isolates bootstrap/migration credentials from the web app.")
PY

# Refuse to delete or adopt an existing database/role: the test may create only
# its own uniquely named disposable objects.
existing_database="$(admin_psql postgres -At -c \
  "SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = '$smoke_database')")"
[[ "$existing_database" == "f" ]] || {
  echo "Refusing to use existing smoke database $smoke_database" >&2
  exit 1
}
existing_role="$(admin_psql postgres -At -c \
  "SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$smoke_role')")"
[[ "$existing_role" == "f" ]] || {
  echo "Refusing to use existing smoke role $smoke_role" >&2
  exit 1
}

admin_psql postgres -c "CREATE DATABASE $smoke_database" >/dev/null
database_created=1

sh -n docker/postgres/bootstrap-local.sh
docker run --rm --network host \
  --env PGHOST=127.0.0.1 \
  --env PGPORT=5432 \
  --env PGDATABASE="$smoke_database" \
  --env PGUSER=postgres \
  --env PGPASSWORD=postgres \
  --env LOCAL_CENTRAL_RUNTIME_ROLE="$smoke_role" \
  --env LOCAL_CENTRAL_RUNTIME_PASSWORD="$smoke_password" \
  -v "$PWD/docker/postgres/bootstrap-local.sql:/bootstrap-local.sql:ro" \
  -v "$PWD/docker/postgres/bootstrap-local.sh:/bootstrap-local.sh:ro" \
  postgres:17 /bin/sh /bootstrap-local.sh >/dev/null

role_flags="$(admin_psql postgres -At -c \
  "SELECT rolcanlogin::int || '|' || rolsuper::int || '|' || rolcreatedb::int || '|' || rolcreaterole::int || '|' || rolreplication::int || '|' || rolbypassrls::int FROM pg_roles WHERE rolname = '$smoke_role'")"
[[ "$role_flags" == "1|0|0|0|0|0" ]] || {
  echo "Runtime role attributes did not meet least-privilege contract: $role_flags" >&2
  exit 1
}

# Run the real central schema migrations as the explicitly elevated local
# migration identity. Runtime privileges are supplied through default ACLs.
docker run --rm --network host \
  --env APP_ENV=testing \
  --env APP_KEY=base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
  --env DB_CONNECTION=central \
  --env CENTRAL_DB_HOST=127.0.0.1 \
  --env CENTRAL_DB_PORT=5432 \
  --env CENTRAL_DB_DATABASE="$smoke_database" \
  --env CENTRAL_DB_USERNAME=postgres \
  --env CENTRAL_DB_PASSWORD=postgres \
  "$CI_IMAGE" php artisan migrate --database=central --path=database/migrations/central --force >/dev/null

admin_psql "$smoke_database" -c \
  "CREATE TABLE public.prompt05_compose_dml_probe (id BIGSERIAL PRIMARY KEY, value TEXT NOT NULL)" >/dev/null

schema_flags="$(runtime_psql "$smoke_role" "$smoke_password" "$smoke_database" -At -c \
  "SELECT has_schema_privilege(current_user, 'public', 'USAGE')::int || '|' || has_schema_privilege(current_user, 'public', 'CREATE')::int")"
[[ "$schema_flags" == "1|0" ]] || {
  echo "Unexpected schema privileges for local runtime role: $schema_flags" >&2
  exit 1
}

database_create="$(runtime_psql "$smoke_role" "$smoke_password" "$smoke_database" -At -c \
  "SELECT has_database_privilege(current_user, current_database(), 'CREATE')::int")"
[[ "$database_create" == "0" ]] || {
  echo "Local runtime role unexpectedly has database CREATE privilege" >&2
  exit 1
}

table_privileges="$(runtime_psql "$smoke_role" "$smoke_password" "$smoke_database" -At -c \
  "SELECT CASE WHEN has_table_privilege(current_user, 'public.prompt05_compose_dml_probe', 'SELECT') AND has_table_privilege(current_user, 'public.prompt05_compose_dml_probe', 'INSERT') AND has_table_privilege(current_user, 'public.prompt05_compose_dml_probe', 'UPDATE') AND has_table_privilege(current_user, 'public.prompt05_compose_dml_probe', 'DELETE') THEN 'PASS' ELSE 'FAIL' END")"
[[ "$table_privileges" == "PASS" ]] || {
  echo "Local runtime role lacks the required table DML privileges" >&2
  exit 1
}

sequence_privileges="$(runtime_psql "$smoke_role" "$smoke_password" "$smoke_database" -At -c \
  "SELECT CASE WHEN has_sequence_privilege(current_user, 'public.prompt05_compose_dml_probe_id_seq', 'USAGE') AND has_sequence_privilege(current_user, 'public.prompt05_compose_dml_probe_id_seq', 'SELECT') AND NOT has_sequence_privilege(current_user, 'public.prompt05_compose_dml_probe_id_seq', 'UPDATE') THEN 'PASS' ELSE 'FAIL' END")"
[[ "$sequence_privileges" == "PASS" ]] || {
  echo "Local runtime sequence grants do not meet least-privilege contract" >&2
  exit 1
}

runtime_psql "$smoke_role" "$smoke_password" "$smoke_database" -c \
  "BEGIN; INSERT INTO public.prompt05_compose_dml_probe (value) VALUES ('before') RETURNING id; UPDATE public.prompt05_compose_dml_probe SET value = 'after' WHERE value = 'before'; SELECT count(*) FROM public.prompt05_compose_dml_probe WHERE value = 'after'; DELETE FROM public.prompt05_compose_dml_probe WHERE value = 'after'; ROLLBACK" >/dev/null

for ddl_sql in \
  "CREATE SCHEMA prompt05_runtime_schema_probe" \
  "CREATE TABLE public.prompt05_runtime_ddl_probe (id integer)"
do
  if runtime_psql "$smoke_role" "$smoke_password" "$smoke_database" -c "$ddl_sql" >/dev/null 2>&1; then
    admin_psql "$smoke_database" -c "DROP TABLE IF EXISTS public.prompt05_runtime_ddl_probe; DROP SCHEMA IF EXISTS prompt05_runtime_schema_probe CASCADE" >/dev/null 2>&1 || true
    echo "Local runtime role unexpectedly executed DDL: $ddl_sql" >&2
    exit 1
  fi
done

if runtime_psql "$smoke_role" "$smoke_password" berkahpos_tenant_ci -c "SELECT 1" >/dev/null 2>&1; then
  echo "Local central runtime role unexpectedly connected to a tenant database" >&2
  exit 1
fi

echo "PASS: local Compose bootstrap creates a restricted runtime login; migrations succeed under the elevated tool account; runtime DML works and DDL/cross-database CONNECT are denied."
