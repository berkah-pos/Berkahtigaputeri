#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# Inspect the rendered Compose model without printing the resolved environment
# (which can include locally configured credentials).
docker compose --profile tools -f docker-compose.yml config --format json | python3 -c '
import json
import sys

config = json.load(sys.stdin)
services = config["services"]
postgres = services["postgres"]
bootstrap = services["db-bootstrap"]
app = services["app"]
migrate = services["dev-migrate"]

postgres_env = postgres.get("environment", {})
bootstrap_env = bootstrap.get("environment", {})
app_env = app.get("environment", {})
migrate_env = migrate.get("environment", {})

assert app_env.get("CENTRAL_DB_USERNAME"), "app lacks a central runtime username"
assert app_env["CENTRAL_DB_USERNAME"] != postgres_env.get("POSTGRES_USER"), "app uses the PostgreSQL bootstrap account"
assert app_env["CENTRAL_DB_USERNAME"] == bootstrap_env.get("LOCAL_CENTRAL_RUNTIME_ROLE"), "bootstrap role and app runtime role do not match"
assert app_env.get("CENTRAL_DB_PASSWORD") == bootstrap_env.get("LOCAL_CENTRAL_RUNTIME_PASSWORD"), "bootstrap role and app runtime password do not match"
assert app_env.get("CENTRAL_DB_PASSWORD") != postgres_env.get("POSTGRES_PASSWORD"), "app runtime password must differ from PostgreSQL bootstrap password"

forbidden_prefixes = ("POSTGRES_BOOTSTRAP_", "PROVISIONER_DB_", "LOCAL_CENTRAL_RUNTIME_")
forbidden_names = {"PGUSER", "PGPASSWORD"}
leaked = sorted(
    key for key in app_env
    if key in forbidden_names or key.startswith(forbidden_prefixes)
)
assert not leaked, "privileged/bootstrap environment leaked to app: " + ", ".join(leaked)

assert bootstrap_env.get("PGUSER") == postgres_env.get("POSTGRES_USER"), "bootstrap job does not use the DB bootstrap identity"
assert bootstrap_env.get("PGPASSWORD") == postgres_env.get("POSTGRES_PASSWORD"), "bootstrap job does not match the DB bootstrap credential"
assert not bootstrap.get("ports") and not bootstrap.get("expose"), "bootstrap service must not have ingress"
assert not migrate.get("ports") and not migrate.get("expose"), "migration tool must not have ingress"
assert migrate.get("profiles") == ["tools"], "elevated local migration service must be explicitly opt-in"
assert migrate_env.get("CENTRAL_DB_USERNAME") == postgres_env.get("POSTGRES_USER"), "migration tool should use the one-shot local bootstrap account"
assert migrate_env.get("CENTRAL_DB_PASSWORD") == postgres_env.get("POSTGRES_PASSWORD"), "migration tool must use the local bootstrap password"
app_deps = app.get("depends_on", {})
assert app_deps.get("db-bootstrap", {}).get("condition") == "service_completed_successfully", "app must wait for successful runtime-role setup"
assert all(port.get("host_ip") == "127.0.0.1" for port in postgres.get("ports", [])), "local PostgreSQL port must bind to loopback only"
assert all(port.get("host_ip") == "127.0.0.1" for port in app.get("ports", [])), "local app port must bind to loopback only"
print("PASS: Compose keeps bootstrap credentials out of the app service and confines elevated migration access to an opt-in one-shot tool.")
'

TEST_DB="berkahpos_compose_role_ci"
TEST_ROLE="berkahpos_compose_runtime_ci"
TEST_PASSWORD="compose-runtime-ci-only-password"
CENTRAL_CI_DB="${CENTRAL_DB_DATABASE:-berkahpos_central_ci}"
TEST_DB_CREATED=0
ROLE_WAS_ABSENT=0

admin_psql() {
  local database="$1"
  shift
  PGPASSWORD=postgres docker run --rm --network host --env PGPASSWORD postgres:17 \
    psql -X -h 127.0.0.1 -U postgres -d "$database" -v ON_ERROR_STOP=1 "$@"
}

runtime_psql() {
  local user="$1"
  local password="$2"
  local database="$3"
  shift 3
  PGPASSWORD="$password" docker run --rm --network host --env PGPASSWORD postgres:17 \
    psql -X -h 127.0.0.1 -U "$user" -d "$database" -v ON_ERROR_STOP=1 "$@"
}

cleanup() {
  set +e
  if [[ "$TEST_DB_CREATED" == "1" ]]; then
    admin_psql postgres -c "DROP DATABASE IF EXISTS \"$TEST_DB\" WITH (FORCE)" >/dev/null
  fi
  if [[ "$ROLE_WAS_ABSENT" == "1" ]]; then
    admin_psql postgres -c "DROP ROLE IF EXISTS \"$TEST_ROLE\"" >/dev/null
  fi
}
trap cleanup EXIT

database_exists="$(admin_psql postgres -At -c "SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = '$TEST_DB')")"
[[ "$database_exists" == "f" ]] || die "unexpected pre-existing disposable database: $TEST_DB"
role_exists="$(admin_psql postgres -At -c "SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$TEST_ROLE')")"
[[ "$role_exists" == "f" ]] || die "unexpected pre-existing disposable role: $TEST_ROLE"
ROLE_WAS_ABSENT=1

admin_psql postgres -c "CREATE DATABASE \"$TEST_DB\"" >/dev/null
TEST_DB_CREATED=1

# Exercise the exact SQL used by Compose and repeat it to prove that bootstrap
# is idempotent on a disposable PostgreSQL 17 database.
for attempt in 1 2; do
  PGPASSWORD=postgres docker run --rm --network host --env PGPASSWORD postgres:17 \
    psql -X --no-psqlrc -h 127.0.0.1 -U postgres -d "$TEST_DB" -v ON_ERROR_STOP=1 \
    --set=bootstrap_role=postgres --set=central_database="$TEST_DB" \
    --set=runtime_role="$TEST_ROLE" --set=runtime_password="$TEST_PASSWORD" \
    --file=docker/postgres/bootstrap-local.sql >/dev/null
done
printf '%s\n' 'PASS: local PostgreSQL bootstrap SQL applies twice without widening privileges.'

# Simulate a migration-runner-created table so default DML/sequence privileges
# are checked as actual PostgreSQL permissions rather than YAML assertions.
admin_psql "$TEST_DB" -c "CREATE TABLE public.bootstrap_probe (id BIGSERIAL PRIMARY KEY, value TEXT NOT NULL)" >/dev/null
runtime_psql "$TEST_ROLE" "$TEST_PASSWORD" "$TEST_DB" -c "INSERT INTO public.bootstrap_probe (value) VALUES ('runtime-dml-pass')" >/dev/null
value="$(runtime_psql "$TEST_ROLE" "$TEST_PASSWORD" "$TEST_DB" -At -c "SELECT value FROM public.bootstrap_probe WHERE id = 1")"
[[ "$value" == "runtime-dml-pass" ]] || die "runtime role could not use its intended DML grant"

flags="$(admin_psql postgres -At -c "SELECT rolcanlogin::int || '|' || rolsuper::int || '|' || rolcreatedb::int || '|' || rolcreaterole::int || '|' || rolreplication::int || '|' || rolbypassrls::int || '|' || rolinherit::int FROM pg_roles WHERE rolname = '$TEST_ROLE'")"
[[ "$flags" == "1|0|0|0|0|0|0" ]] || die "local runtime role has unexpected attributes: $flags"

create_db_privilege="$(runtime_psql "$TEST_ROLE" "$TEST_PASSWORD" "$TEST_DB" -At -c "SELECT has_database_privilege(current_user, current_database(), 'CREATE')::int")"
[[ "$create_db_privilege" == "0" ]] || die "local runtime role has database CREATE privilege"
schema_create="$(runtime_psql "$TEST_ROLE" "$TEST_PASSWORD" "$TEST_DB" -At -c "SELECT has_schema_privilege(current_user, 'public', 'CREATE')::int")"
[[ "$schema_create" == "0" ]] || die "local runtime role has schema CREATE privilege"
sequence_usage="$(runtime_psql "$TEST_ROLE" "$TEST_PASSWORD" "$TEST_DB" -At -c "SELECT has_sequence_privilege(current_user, 'public.bootstrap_probe_id_seq', 'USAGE')::int")"
[[ "$sequence_usage" == "1" ]] || die "local runtime role lacks required sequence USAGE"

if runtime_psql "$TEST_ROLE" "$TEST_PASSWORD" "$TEST_DB" -c "CREATE SCHEMA prompt05_must_deny" >/dev/null 2>&1; then
  die "local runtime role unexpectedly created a schema"
fi
if runtime_psql "$TEST_ROLE" "$TEST_PASSWORD" "$TEST_DB" -c "CREATE TABLE public.prompt05_must_deny (id integer)" >/dev/null 2>&1; then
  die "local runtime role unexpectedly created a table"
fi
if runtime_psql "$TEST_ROLE" "$TEST_PASSWORD" "$CENTRAL_CI_DB" -c "SELECT 1" >/dev/null 2>&1; then
  die "local runtime role unexpectedly connected to the unrelated central CI database"
fi

printf '%s\n' 'PASS: local runtime role can use granted DML/sequences, cannot create database objects, and cannot connect to the separate central CI database.'
