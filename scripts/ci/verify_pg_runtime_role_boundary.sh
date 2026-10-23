#!/usr/bin/env bash
set -euo pipefail

: "${CENTRAL_DB_USERNAME:?CENTRAL_DB_USERNAME must name the ordinary central runtime role}"
: "${CENTRAL_DB_PASSWORD:?CENTRAL_DB_PASSWORD must be set}"
: "${CENTRAL_DB_DATABASE:?CENTRAL_DB_DATABASE must be set}"
: "${TENANT_DB_USERNAME:?TENANT_DB_USERNAME must name the ordinary tenant runtime role}"
: "${TENANT_DB_PASSWORD:?TENANT_DB_PASSWORD must be set}"
: "${TENANT_DB_DATABASE:?TENANT_DB_DATABASE must be set}"

PG_CLIENT_IMAGE="${PG_CLIENT_IMAGE:-postgres:17}"

die() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

admin_psql() {
  local database="$1"
  shift
  PGPASSWORD=postgres docker run --rm --network host --env PGPASSWORD \
    "$PG_CLIENT_IMAGE" psql -X -h 127.0.0.1 -U postgres -d "$database" \
    -v ON_ERROR_STOP=1 "$@"
}

runtime_psql() {
  local username="$1"
  local password="$2"
  local database="$3"
  shift 3
  PGPASSWORD="$password" docker run --rm --network host --env PGPASSWORD \
    "$PG_CLIENT_IMAGE" psql -X -h 127.0.0.1 -U "$username" -d "$database" \
    -v ON_ERROR_STOP=1 "$@"
}

assert_runtime_role_flags() {
  local role="$1"
  local flags
  if [[ ! "$role" =~ ^[a-z_][a-z0-9_]{0,62}$ ]]; then
    die "Runtime database role has an unsafe identifier: $role"
  fi
  # The identifier was strictly allowlisted above, so embedding this role name
  # as a SQL string is safe. psql variable expansion is not applied to -c input.
  flags="$(admin_psql postgres -At -c \
    "SELECT rolcanlogin::int || '|' || rolsuper::int || '|' || rolcreatedb::int || '|' || rolcreaterole::int || '|' || rolreplication::int || '|' || rolbypassrls::int FROM pg_roles WHERE rolname = '$role'")"
  [[ "$flags" == "1|0|0|0|0|0" ]] || die "$role must be LOGIN, NOSUPERUSER, NOCREATEDB, NOCREATEROLE, NOREPLICATION and NOBYPASSRLS; observed flags=$flags"
  printf 'PASS: role attributes least-privilege verified for %s\n' "$role"
}

assert_no_schema_create() {
  local username="$1"
  local password="$2"
  local database="$3"
  local schema_flags
  schema_flags="$(runtime_psql "$username" "$password" "$database" -At -c \
    "SELECT has_schema_privilege(current_user, 'public', 'USAGE')::int || '|' || has_schema_privilege(current_user, 'public', 'CREATE')::int")"
  [[ "$schema_flags" == "1|0" ]] || die "$username must have public-schema USAGE but not CREATE; observed flags=$schema_flags"

  local database_create
  database_create="$(runtime_psql "$username" "$password" "$database" -At -c \
    "SELECT has_database_privilege(current_user, current_database(), 'CREATE')::int")"
  [[ "$database_create" == "0" ]] || die "$username must not have database CREATE privilege on $database"

  if runtime_psql "$username" "$password" "$database" -c \
    'CREATE SCHEMA prompt05_runtime_schema_probe' >/dev/null 2>&1; then
    admin_psql "$database" -c 'DROP SCHEMA IF EXISTS prompt05_runtime_schema_probe CASCADE' >/dev/null
    die "$username unexpectedly created a schema in $database"
  fi

  if runtime_psql "$username" "$password" "$database" -c \
    'CREATE TABLE public.prompt05_runtime_ddl_probe (id integer)' >/dev/null 2>&1; then
    admin_psql "$database" -c 'DROP TABLE IF EXISTS public.prompt05_runtime_ddl_probe' >/dev/null
    die "$username unexpectedly created a table in $database"
  fi
  printf 'PASS: runtime database/schema/table DDL denied for %s on %s\n' "$username" "$database"
}

assert_table_dml() {
  local username="$1"
  local password="$2"
  local database="$3"
  local table="$4"
  local privileges
  privileges="$(runtime_psql "$username" "$password" "$database" -At -c \
    "SELECT CASE WHEN has_table_privilege(current_user, '$table', 'SELECT') AND has_table_privilege(current_user, '$table', 'INSERT') AND has_table_privilege(current_user, '$table', 'UPDATE') AND has_table_privilege(current_user, '$table', 'DELETE') THEN 'PASS' ELSE 'FAIL' END")"
  [[ "$privileges" == "PASS" ]] || die "$username lacks expected DML privileges on $table in $database"

  local sequences
  sequences="$(runtime_psql "$username" "$password" "$database" -At -c \
    "SELECT CASE WHEN COUNT(*) = 0 OR BOOL_AND(has_sequence_privilege(current_user, c.oid, 'USAGE')) THEN 'PASS' ELSE 'FAIL' END FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'S' AND n.nspname = 'public'")"
  [[ "$sequences" == "PASS" ]] || die "$username lacks USAGE on one or more public-schema sequences in $database"
  printf 'PASS: table DML and sequence usage verified for %s on %s\n' "$username" "$database"
}

assert_connection_denied() {
  local username="$1"
  local password="$2"
  local database="$3"
  if runtime_psql "$username" "$password" "$database" -At -c 'SELECT 1' >/dev/null 2>&1; then
    die "$username unexpectedly connected to unauthorized database $database"
  fi
  printf 'PASS: cross-database CONNECT denied for %s to %s\n' "$username" "$database"
}

assert_runtime_role_flags "$CENTRAL_DB_USERNAME"
assert_runtime_role_flags "$TENANT_DB_USERNAME"

central_login="$(runtime_psql "$CENTRAL_DB_USERNAME" "$CENTRAL_DB_PASSWORD" "$CENTRAL_DB_DATABASE" -At -c 'SELECT current_user')"
tenant_login="$(runtime_psql "$TENANT_DB_USERNAME" "$TENANT_DB_PASSWORD" "$TENANT_DB_DATABASE" -At -c 'SELECT current_user')"
[[ "$central_login" == "$CENTRAL_DB_USERNAME" ]] || die 'Central connection did not authenticate as the configured restricted runtime role'
[[ "$tenant_login" == "$TENANT_DB_USERNAME" ]] || die 'Tenant connection did not authenticate as the configured restricted runtime role'

assert_table_dml "$CENTRAL_DB_USERNAME" "$CENTRAL_DB_PASSWORD" "$CENTRAL_DB_DATABASE" 'public.tenants'
assert_table_dml "$TENANT_DB_USERNAME" "$TENANT_DB_PASSWORD" "$TENANT_DB_DATABASE" 'public.products'
assert_no_schema_create "$CENTRAL_DB_USERNAME" "$CENTRAL_DB_PASSWORD" "$CENTRAL_DB_DATABASE"
assert_no_schema_create "$TENANT_DB_USERNAME" "$TENANT_DB_PASSWORD" "$TENANT_DB_DATABASE"

assert_connection_denied "$CENTRAL_DB_USERNAME" "$CENTRAL_DB_PASSWORD" "$TENANT_DB_DATABASE"
assert_connection_denied "$TENANT_DB_USERNAME" "$TENANT_DB_PASSWORD" "$CENTRAL_DB_DATABASE"

printf '%s\n' 'PASS: ordinary Laravel DB roles are restricted; central/tenant database boundaries verified.'
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '%s\n' '### PostgreSQL runtime role boundary'
    printf '%s\n' '- CI role attributes verified from PostgreSQL catalogs: no superuser, CREATEDB, CREATEROLE, replication, or BYPASSRLS.'
    printf '%s\n' '- Central and tenant runtime logins authenticated using their configured least-privilege accounts.'
    printf '%s\n' '- CRUD/sequence grants are usable; schema CREATE and cross-database CONNECT are denied.'
    printf '%s\n' '- Credential values are not emitted in the summary.'
  } >> "$GITHUB_STEP_SUMMARY"
fi
