#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# This harness creates and drops ONLY uniquely named, preflight-absent CI resources.
# It is deliberately opt-in and refuses network hosts, non-postgres admin DBs,
# non-superuser setup identities, or any non-PostgreSQL-17 target.
: "${ALLOW_DISPOSABLE_PG17_TENANT_ISOLATION:=}"
if [[ "$ALLOW_DISPOSABLE_PG17_TENANT_ISOLATION" != "YES" ]]; then
  echo "BLOCKED: set ALLOW_DISPOSABLE_PG17_TENANT_ISOLATION=YES only for a disposable PostgreSQL 17 service." >&2
  exit 64
fi

# Do not run this destructive fixture harness on a developer machine, a forwarded
# database port, staging, or production. The workflow must explicitly attest the
# disposable GitHub Actions service and bind output to this workflow run/checkout.
if [[ "${CI:-}" != "true" || "${GITHUB_ACTIONS:-}" != "true" ||
      "${PG17_ISOLATION_APPROVED_SERVICE:-}" != "github-actions-postgres-17-disposable" ||
      ! "${GITHUB_RUN_ID:-}" =~ ^[0-9]+$ || ! "${PG17_ISOLATION_CHECKOUT_SHA:-}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "BLOCKED: harness only runs in the declared GitHub Actions disposable PostgreSQL 17 service." >&2
  exit 64
fi

PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-postgres}"
export PGHOST PGPORT PGUSER PGDATABASE

case "$PGHOST" in
  127.0.0.1|localhost) ;;
  *) echo "BLOCKED: PGHOST must be loopback; remote hosts are refused." >&2; exit 64 ;;
esac
if [[ "$PGDATABASE" != "postgres" ]]; then
  echo "BLOCKED: setup connection must target the disposable service's postgres maintenance database." >&2
  exit 64
fi
if [[ -z "${PGPASSWORD:-}" ]]; then
  echo "BLOCKED: PGPASSWORD must be provided by the isolated test service environment." >&2
  exit 64
fi

ARTIFACT="${PG17_ISOLATION_ARTIFACT:-/tmp/pg17-tenant-isolation.log}"
mkdir -p "$(dirname "$ARTIFACT")"
: > "$ARTIFACT"
chmod 600 "$ARTIFACT"
TMP_DIR="$(mktemp -d)"
CREATED_RESOURCES=0
CLEANUP_FAILED=0

CENTRAL_DB="btp_iso_central_ci"
DB_A="btp_iso_tenant_a_ci"
DB_B="btp_iso_tenant_b_ci"
CENTRAL_OWNER="btp_iso_central_owner_ci"
OWNER_A="btp_iso_tenant_a_owner_ci"
OWNER_B="btp_iso_tenant_b_owner_ci"
MIGRATOR_A="btp_iso_tenant_a_migrator_ci"
MIGRATOR_B="btp_iso_tenant_b_migrator_ci"
RUNTIME_A="btp_iso_tenant_a_runtime_ci"
RUNTIME_B="btp_iso_tenant_b_runtime_ci"
ROLES=("$CENTRAL_OWNER" "$OWNER_A" "$OWNER_B" "$MIGRATOR_A" "$MIGRATOR_B" "$RUNTIME_A" "$RUNTIME_B")
DATABASES=("$CENTRAL_DB" "$DB_A" "$DB_B")
PASS_A="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
PASS_B="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
MIGRATOR_PASS_A="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
MIGRATOR_PASS_B="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"

log() {
  printf '%s\n' "$*" | tee -a "$ARTIFACT"
}
fail() {
  log "FAIL: $*"
  exit 1
}
admin_sql() {
  psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "$1"
}
query() {
  local database="$1"; shift
  psql -X -q -t -A -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$database" -c "$1"
}
runtime_query() {
  local user="$1" password="$2" database="$3" sql="$4"
  PGUSER="$user" PGPASSWORD="$password" psql -X -q -t -A -v ON_ERROR_STOP=1 \
    -h "$PGHOST" -p "$PGPORT" -U "$user" -d "$database" -c "$sql"
}
expect_denied() {
  local label="$1" expected="$2"; shift 2
  local output="$TMP_DIR/denied.out"
  if "$@" >"$output" 2>&1; then
    fail "$label unexpectedly succeeded"
  fi
  if ! grep -Fqi "$expected" "$output"; then
    sed -E 's/(password|token|secret)[^[:space:]]*/[redacted]/Ig' "$output" >> "$ARTIFACT"
    fail "$label failed for an unexpected reason (expected sanitized marker: $expected)"
  fi
  log "PASS: $label (expected denial matched: $expected)"
}
assert_true() {
  local label="$1" database="$2" sql="$3"
  local result
  result="$(query "$database" "$sql" | tr -d '[:space:]')"
  [[ "$result" == "t" ]] || fail "$label (expected true, actual result was not true)"
  log "PASS: $label"
}
assert_value() {
  local label="$1" database="$2" sql="$3" expected="$4"
  local result
  result="$(query "$database" "$sql" | tr -d '\r')"
  [[ "$result" == "$expected" ]] || fail "$label (expected '$expected', got '$result')"
  log "PASS: $label"
}
cleanup() {
  local status=$?
  if [[ "$CREATED_RESOURCES" == "1" ]]; then
    log "CLEANUP: drop only this run's preflight-absent disposable databases/roles"
    for database in "${DATABASES[@]}"; do
      if ! admin_sql "DROP DATABASE IF EXISTS \"$database\" WITH (FORCE)" >/dev/null 2>&1; then
        CLEANUP_FAILED=1
        log "CLEANUP_FAIL: disposable database $database could not be removed"
      fi
    done
    for role in "${ROLES[@]}"; do
      if ! admin_sql "DROP ROLE IF EXISTS \"$role\"" >/dev/null 2>&1; then
        CLEANUP_FAILED=1
        log "CLEANUP_FAIL: disposable role $role could not be removed"
      fi
    done
  fi
  rm -rf "$TMP_DIR"
  if [[ "$CLEANUP_FAILED" == "1" ]]; then
    log "FAIL: test-resource cleanup incomplete; destroy the disposable PostgreSQL service after preserving this artifact"
    status=1
  fi
  if [[ "$status" == "0" ]]; then
    log "RESULT: PASS — disposable PostgreSQL 17 role/grant contract probes all passed."
  else
    log "RESULT: FAIL — see preceding assertions and sanitized diagnostics."
  fi
  exit "$status"
}
trap cleanup EXIT

log "RUN: PostgreSQL 17 disposable tenant-isolation role/grant harness"
log "CI_RUN_ID: $GITHUB_RUN_ID"
log "CHECKOUT_SHA: $PG17_ISOLATION_CHECKOUT_SHA"
log "TARGET: host=loopback port=$PGPORT admin_database=$PGDATABASE"

server_version="$(query "$PGDATABASE" "SELECT current_setting('server_version')")"
server_version_num="$(query "$PGDATABASE" "SHOW server_version_num" | tr -d '[:space:]')"
[[ "$server_version_num" == 17* ]] || fail "target engine is not PostgreSQL 17 (observed server_version=$server_version)"
admin_is_superuser="$(query "$PGDATABASE" "SELECT rolsuper FROM pg_roles WHERE rolname = current_user" | tr -d '[:space:]')"
[[ "$admin_is_superuser" == "t" ]] || fail "test setup identity must be superuser on the disposable service"
log "SERVER_VERSION: $server_version"
log "SETUP_IDENTITY: current user is superuser; used only to create isolated synthetic fixtures"

# Refuse to reuse resources. No cleanup path is enabled until absence is proven.
for database in "${DATABASES[@]}"; do
  present="$(query "$PGDATABASE" "SELECT count(*) FROM pg_database WHERE datname = '$database'")"
  [[ "$present" == "0" ]] || fail "pre-existing database $database found; refusing to drop or reuse it"
done
for role in "${ROLES[@]}"; do
  present="$(query "$PGDATABASE" "SELECT count(*) FROM pg_roles WHERE rolname = '$role'")"
  [[ "$present" == "0" ]] || fail "pre-existing role $role found; refusing to drop or reuse it"
done
CREATED_RESOURCES=1

# Passwords are random per run and supplied over SQL stdin (not process arguments or logs).
psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" <<SQL
CREATE ROLE "$CENTRAL_OWNER" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE "$OWNER_A" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE "$OWNER_B" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE "$MIGRATOR_A" LOGIN PASSWORD '$MIGRATOR_PASS_A' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE "$MIGRATOR_B" LOGIN PASSWORD '$MIGRATOR_PASS_B' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE "$RUNTIME_A" LOGIN PASSWORD '$PASS_A' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE ROLE "$RUNTIME_B" LOGIN PASSWORD '$PASS_B' NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
CREATE DATABASE "$CENTRAL_DB" OWNER "$CENTRAL_OWNER";
CREATE DATABASE "$DB_A" OWNER "$OWNER_A";
CREATE DATABASE "$DB_B" OWNER "$OWNER_B";
REVOKE ALL ON DATABASE "$CENTRAL_DB" FROM PUBLIC;
REVOKE ALL ON DATABASE "$DB_A" FROM PUBLIC;
REVOKE ALL ON DATABASE "$DB_B" FROM PUBLIC;
GRANT CONNECT ON DATABASE "$DB_A" TO "$RUNTIME_A", "$MIGRATOR_A";
GRANT CONNECT ON DATABASE "$DB_B" TO "$RUNTIME_B", "$MIGRATOR_B";
ALTER ROLE "$RUNTIME_A" IN DATABASE "$DB_A" SET search_path TO tenant_a, pg_catalog;
ALTER ROLE "$RUNTIME_B" IN DATABASE "$DB_B" SET search_path TO tenant_b, pg_catalog;
SQL

# Create central and tenant-owned objects with default privileges configured before DDL.
psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$CENTRAL_DB" <<SQL
REVOKE ALL ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA central_data AUTHORIZATION "$CENTRAL_OWNER";
SET ROLE "$CENTRAL_OWNER";
CREATE TABLE central_data.central_marker (marker text PRIMARY KEY);
INSERT INTO central_data.central_marker VALUES ('central-only-synthetic');
RESET ROLE;
SQL

for item in "A:$DB_A:$OWNER_A:$MIGRATOR_A:$RUNTIME_A" "B:$DB_B:$OWNER_B:$MIGRATOR_B:$RUNTIME_B"; do
  IFS=: read -r label database owner migrator runtime <<< "$item"
  schema="tenant_${label,,}"
  psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$database" <<SQL
REVOKE ALL ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA "$schema" AUTHORIZATION "$migrator";
ALTER DEFAULT PRIVILEGES FOR ROLE "$migrator" IN SCHEMA "$schema"
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "$runtime";
ALTER DEFAULT PRIVILEGES FOR ROLE "$migrator" IN SCHEMA "$schema"
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO "$runtime";
-- PostgreSQL per-schema REVOKE cannot cancel globally granted default privileges.
ALTER DEFAULT PRIVILEGES FOR ROLE "$migrator"
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
SET ROLE "$migrator";
CREATE TABLE "$schema".isolation_probe (
  id BIGSERIAL PRIMARY KEY,
  tenant_label text NOT NULL UNIQUE,
  note text NOT NULL
);
INSERT INTO "$schema".isolation_probe (tenant_label, note)
VALUES ('tenant-$label-synthetic', 'initial');
CREATE FUNCTION "$schema".private_marker() RETURNS text
LANGUAGE sql AS \$fn\$ SELECT 'private-$label-synthetic'::text \$fn\$;
RESET ROLE;
GRANT USAGE ON SCHEMA "$schema" TO "$runtime";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA "$schema" TO "$runtime";
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA "$schema" TO "$runtime";
SQL
  # This object is created after the explicit ON ALL grant; only default privileges can
  # grant its runtime access, so it is a direct regression oracle for future migrations.
  psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$database" <<SQL
SET ROLE "$migrator";
CREATE TABLE "$schema".future_probe (id BIGSERIAL PRIMARY KEY, note text NOT NULL);
RESET ROLE;
SQL
done

# Safe catalog evidence: role flags and database owners, not password or customer data.
log "ROLE_FLAGS (rolcanlogin/superuser/createdb/createrole/replication/bypassrls/inherit):"
query "$PGDATABASE" "SELECT rolname || '|' || rolcanlogin || '|' || rolsuper || '|' || rolcreatedb || '|' || rolcreaterole || '|' || rolreplication || '|' || rolbypassrls || '|' || rolinherit FROM pg_roles WHERE rolname LIKE 'btp_iso_%_ci' ORDER BY rolname" | tee -a "$ARTIFACT"
log "DATABASE_OWNERS (database|owner):"
query "$PGDATABASE" "SELECT d.datname || '|' || r.rolname FROM pg_database d JOIN pg_roles r ON r.oid=d.datdba WHERE d.datname IN ('$CENTRAL_DB','$DB_A','$DB_B') ORDER BY d.datname" | tee -a "$ARTIFACT"

# Runtime positive path: CRUD, identity sequence use, future-object defaults, scoped search_path.
search_path_a="$(runtime_query "$RUNTIME_A" "$PASS_A" "$DB_A" "SELECT current_setting('search_path')")"
[[ "$search_path_a" == "tenant_a, pg_catalog" ]] || fail "Tenant A runtime search_path did not match the database-specific setting"
log "PASS: Tenant A runtime default search_path is tenant_a, pg_catalog"
search_path_b="$(runtime_query "$RUNTIME_B" "$PASS_B" "$DB_B" "SELECT current_setting('search_path')")"
[[ "$search_path_b" == "tenant_b, pg_catalog" ]] || fail "Tenant B runtime search_path did not match the database-specific setting"
log "PASS: Tenant B runtime default search_path is tenant_b, pg_catalog"
own_select="$(runtime_query "$RUNTIME_A" "$PASS_A" "$DB_A" "SELECT count(*) FROM tenant_a.isolation_probe WHERE tenant_label='tenant-A-synthetic'")"
[[ "$own_select" == "1" ]] || fail "Tenant A runtime SELECT of its own row failed"
log "PASS: Tenant A runtime SELECT own row"
inserted="$(runtime_query "$RUNTIME_A" "$PASS_A" "$DB_A" "INSERT INTO tenant_a.isolation_probe (tenant_label,note) VALUES ('tenant-A-inserted','before') RETURNING id")"
[[ "$inserted" =~ ^[0-9]+$ ]] || fail "Tenant A INSERT/sequence use did not return a generated ID"
log "PASS: Tenant A INSERT and sequence USAGE (generated ID returned)"
assert_value "Tenant A can UPDATE own row" "$DB_A" "SELECT count(*) FROM tenant_a.isolation_probe WHERE tenant_label='tenant-A-inserted' AND note='before'" "1"
runtime_query "$RUNTIME_A" "$PASS_A" "$DB_A" "UPDATE tenant_a.isolation_probe SET note='updated' WHERE tenant_label='tenant-A-inserted' RETURNING note" >/dev/null
assert_value "Tenant A UPDATE persisted" "$DB_A" "SELECT count(*) FROM tenant_a.isolation_probe WHERE tenant_label='tenant-A-inserted' AND note='updated'" "1"
runtime_query "$RUNTIME_A" "$PASS_A" "$DB_A" "DELETE FROM tenant_a.isolation_probe WHERE tenant_label='tenant-A-inserted' RETURNING id" >/dev/null
assert_value "Tenant A DELETE persisted" "$DB_A" "SELECT count(*) FROM tenant_a.isolation_probe WHERE tenant_label='tenant-A-inserted'" "0"
own_select_b="$(runtime_query "$RUNTIME_B" "$PASS_B" "$DB_B" "SELECT count(*) FROM tenant_b.isolation_probe WHERE tenant_label='tenant-B-synthetic'")"
[[ "$own_select_b" == "1" ]] || fail "Tenant B runtime SELECT of its own row failed"
log "PASS: Tenant B runtime SELECT own row"
inserted_b="$(runtime_query "$RUNTIME_B" "$PASS_B" "$DB_B" "INSERT INTO tenant_b.isolation_probe (tenant_label,note) VALUES ('tenant-B-inserted','before') RETURNING id")"
[[ "$inserted_b" =~ ^[0-9]+$ ]] || fail "Tenant B INSERT/sequence use did not return a generated ID"
log "PASS: Tenant B INSERT and sequence USAGE (generated ID returned)"
runtime_query "$RUNTIME_B" "$PASS_B" "$DB_B" "UPDATE tenant_b.isolation_probe SET note='updated' WHERE tenant_label='tenant-B-inserted' RETURNING note" >/dev/null
assert_value "Tenant B UPDATE persisted" "$DB_B" "SELECT count(*) FROM tenant_b.isolation_probe WHERE tenant_label='tenant-B-inserted' AND note='updated'" "1"
runtime_query "$RUNTIME_B" "$PASS_B" "$DB_B" "DELETE FROM tenant_b.isolation_probe WHERE tenant_label='tenant-B-inserted' RETURNING id" >/dev/null
assert_value "Tenant B DELETE persisted" "$DB_B" "SELECT count(*) FROM tenant_b.isolation_probe WHERE tenant_label='tenant-B-inserted'" "0"
assert_value "Tenant A receives default DML on future tables" "$DB_A" "SELECT has_table_privilege('$RUNTIME_A','tenant_a.future_probe','SELECT') AND has_table_privilege('$RUNTIME_A','tenant_a.future_probe','INSERT') AND has_table_privilege('$RUNTIME_A','tenant_a.future_probe','UPDATE') AND has_table_privilege('$RUNTIME_A','tenant_a.future_probe','DELETE')" "t"
assert_value "Tenant A receives sequence privilege on future tables" "$DB_A" "SELECT has_sequence_privilege('$RUNTIME_A','tenant_a.future_probe_id_seq','USAGE') AND has_sequence_privilege('$RUNTIME_A','tenant_a.future_probe_id_seq','SELECT')" "t"
assert_value "Tenant A cannot CREATE in its schema" "$DB_A" "SELECT NOT has_schema_privilege('$RUNTIME_A','tenant_a','CREATE')" "t"
assert_value "Tenant A lacks global database/role DDL flags" "$PGDATABASE" "SELECT NOT rolcreatedb AND NOT rolcreaterole AND NOT rolsuper AND NOT rolreplication AND NOT rolbypassrls AND NOT rolinherit FROM pg_roles WHERE rolname='$RUNTIME_A' AND rolcanlogin" "t"
assert_value "Tenant B lacks global database/role DDL flags" "$PGDATABASE" "SELECT NOT rolcreatedb AND NOT rolcreaterole AND NOT rolsuper AND NOT rolreplication AND NOT rolbypassrls AND NOT rolinherit FROM pg_roles WHERE rolname='$RUNTIME_B' AND rolcanlogin" "t"
assert_value "Tenant A has neither DATABASE CREATE nor TEMP privilege" "$DB_A" "SELECT NOT has_database_privilege('$RUNTIME_A','$DB_A','CREATE') AND NOT has_database_privilege('$RUNTIME_A','$DB_A','TEMP')" "t"
assert_value "Tenant A cannot execute its private function by default" "$DB_A" "SELECT NOT has_function_privilege('$RUNTIME_A','tenant_a.private_marker()','EXECUTE')" "t"
expect_denied "Tenant A cannot EXECUTE private function created under default ACL" "permission denied for function" env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_A" -c "SELECT tenant_a.private_marker()"
assert_value "Tenant B cannot execute its private function by default" "$DB_B" "SELECT NOT has_function_privilege('$RUNTIME_B','tenant_b.private_marker()','EXECUTE')" "t"
assert_value "Tenant A is not a member of owner/migrator/tenant B roles" "$PGDATABASE" "SELECT NOT pg_has_role('$RUNTIME_A','$OWNER_A','MEMBER') AND NOT pg_has_role('$RUNTIME_A','$MIGRATOR_A','MEMBER') AND NOT pg_has_role('$RUNTIME_A','$RUNTIME_B','MEMBER')" "t"
assert_value "Tenant B is not a member of owner/migrator/tenant A roles" "$PGDATABASE" "SELECT NOT pg_has_role('$RUNTIME_B','$OWNER_B','MEMBER') AND NOT pg_has_role('$RUNTIME_B','$MIGRATOR_B','MEMBER') AND NOT pg_has_role('$RUNTIME_B','$RUNTIME_A','MEMBER')" "t"

# Runtime must be unable to create/alter roles, databases, schema objects, or assume migrator.
expect_denied "Tenant A CREATE TABLE" "permission denied for schema" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_A" -c "CREATE TABLE tenant_a.forbidden (id integer)"
expect_denied "Tenant A CREATE ROLE" "permission denied to create role" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_A" -c "CREATE ROLE btp_iso_runtime_tamper_ci"
expect_denied "Tenant A CREATE DATABASE" "permission denied to create database" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_A" -c "CREATE DATABASE btp_iso_tamper_ci"
expect_denied "Tenant A ALTER ROLE to SUPERUSER" "permission denied to alter role" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_A" -c "ALTER ROLE $RUNTIME_A SUPERUSER"
expect_denied "Tenant A SET ROLE to migrator" "permission denied to set role" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_A" -c "SET ROLE $MIGRATOR_A"

# At baseline, CONNECT must fail. Then deliberately grant CONNECT in this disposable test
# to prove schema/table/sequence/function grants still deny cross-tenant data operations.
expect_denied "Tenant A CONNECT to tenant B database" "permission denied for database" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_B" -c "SELECT 1"
expect_denied "Tenant A CONNECT to central database" "permission denied for database" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$CENTRAL_DB" -c "SELECT 1"

expect_denied "Tenant B CONNECT to tenant A database" "permission denied for database" env PGUSER="$RUNTIME_B" PGPASSWORD="$PASS_B" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_A" -c "SELECT 1"
expect_denied "Tenant B CONNECT to central database" "permission denied for database" env PGUSER="$RUNTIME_B" PGPASSWORD="$PASS_B" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$CENTRAL_DB" -c "SELECT 1"

admin_sql "GRANT CONNECT ON DATABASE \"$DB_B\" TO \"$RUNTIME_A\""
admin_sql "GRANT CONNECT ON DATABASE \"$CENTRAL_DB\" TO \"$RUNTIME_A\""
admin_sql "GRANT CONNECT ON DATABASE \"$DB_A\" TO \"$RUNTIME_B\""
admin_sql "GRANT CONNECT ON DATABASE \"$CENTRAL_DB\" TO \"$RUNTIME_B\""
assert_value "Tenant A has no B schema USAGE" "$DB_B" "SELECT NOT has_schema_privilege('$RUNTIME_A','tenant_b','USAGE')" "t"
assert_value "Tenant A has no B SELECT/INSERT/UPDATE/DELETE" "$DB_B" "SELECT NOT has_table_privilege('$RUNTIME_A','tenant_b.isolation_probe','SELECT') AND NOT has_table_privilege('$RUNTIME_A','tenant_b.isolation_probe','INSERT') AND NOT has_table_privilege('$RUNTIME_A','tenant_b.isolation_probe','UPDATE') AND NOT has_table_privilege('$RUNTIME_A','tenant_b.isolation_probe','DELETE')" "t"
assert_value "Tenant A has no B sequence access" "$DB_B" "SELECT NOT has_sequence_privilege('$RUNTIME_A','tenant_b.isolation_probe_id_seq','USAGE') AND NOT has_sequence_privilege('$RUNTIME_A','tenant_b.isolation_probe_id_seq','SELECT') AND NOT has_sequence_privilege('$RUNTIME_A','tenant_b.isolation_probe_id_seq','UPDATE')" "t"
assert_value "Tenant A cannot execute B private function" "$DB_B" "SELECT NOT has_function_privilege('$RUNTIME_A','tenant_b.private_marker()','EXECUTE')" "t"
expect_denied "Tenant A SELECT from B after accidental CONNECT grant" "permission denied for schema" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_B" -c "SELECT * FROM tenant_b.isolation_probe"
expect_denied "Tenant A INSERT into B after accidental CONNECT grant" "permission denied for schema" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_B" -c "INSERT INTO tenant_b.isolation_probe (tenant_label,note) VALUES ('cross-tenant','forbidden')"
expect_denied "Tenant A UPDATE B after accidental CONNECT grant" "permission denied for schema" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_B" -c "UPDATE tenant_b.isolation_probe SET note='forbidden'"
expect_denied "Tenant A DELETE B after accidental CONNECT grant" "permission denied for schema" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_B" -c "DELETE FROM tenant_b.isolation_probe"
expect_denied "Tenant A sequence use in B after accidental CONNECT grant" "permission denied for schema" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_B" -c "SELECT nextval('tenant_b.isolation_probe_id_seq')"
expect_denied "Tenant A execute B function after accidental CONNECT grant" "permission denied for schema" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_B" -c "SELECT tenant_b.private_marker()"
assert_value "Tenant A has no central schema/table rights after accidental CONNECT" "$CENTRAL_DB" "SELECT NOT has_schema_privilege('$RUNTIME_A','central_data','USAGE') AND NOT has_table_privilege('$RUNTIME_A','central_data.central_marker','SELECT') AND NOT has_table_privilege('$RUNTIME_A','central_data.central_marker','INSERT') AND NOT has_table_privilege('$RUNTIME_A','central_data.central_marker','UPDATE') AND NOT has_table_privilege('$RUNTIME_A','central_data.central_marker','DELETE')" "t"
expect_denied "Tenant A SELECT central data after accidental CONNECT" "permission denied for schema" \
  env PGUSER="$RUNTIME_A" PGPASSWORD="$PASS_A" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$CENTRAL_DB" -c "SELECT * FROM central_data.central_marker"
assert_value "Tenant B has no A schema USAGE" "$DB_A" "SELECT NOT has_schema_privilege('$RUNTIME_B','tenant_a','USAGE')" "t"
assert_value "Tenant B has no A SELECT/INSERT/UPDATE/DELETE" "$DB_A" "SELECT NOT has_table_privilege('$RUNTIME_B','tenant_a.isolation_probe','SELECT') AND NOT has_table_privilege('$RUNTIME_B','tenant_a.isolation_probe','INSERT') AND NOT has_table_privilege('$RUNTIME_B','tenant_a.isolation_probe','UPDATE') AND NOT has_table_privilege('$RUNTIME_B','tenant_a.isolation_probe','DELETE')" "t"
assert_value "Tenant B has no A sequence access" "$DB_A" "SELECT NOT has_sequence_privilege('$RUNTIME_B','tenant_a.isolation_probe_id_seq','USAGE') AND NOT has_sequence_privilege('$RUNTIME_B','tenant_a.isolation_probe_id_seq','SELECT') AND NOT has_sequence_privilege('$RUNTIME_B','tenant_a.isolation_probe_id_seq','UPDATE')" "t"
expect_denied "Tenant B SELECT from A after accidental CONNECT grant" "permission denied for schema" env PGUSER="$RUNTIME_B" PGPASSWORD="$PASS_B" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_A" -c "SELECT * FROM tenant_a.isolation_probe"
expect_denied "Tenant B INSERT into A after accidental CONNECT grant" "permission denied for schema" env PGUSER="$RUNTIME_B" PGPASSWORD="$PASS_B" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_A" -c "INSERT INTO tenant_a.isolation_probe (tenant_label,note) VALUES ('cross-tenant-b','forbidden')"
expect_denied "Tenant B UPDATE A after accidental CONNECT grant" "permission denied for schema" env PGUSER="$RUNTIME_B" PGPASSWORD="$PASS_B" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_A" -c "UPDATE tenant_a.isolation_probe SET note='forbidden'"
expect_denied "Tenant B DELETE A after accidental CONNECT grant" "permission denied for schema" env PGUSER="$RUNTIME_B" PGPASSWORD="$PASS_B" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_A" -c "DELETE FROM tenant_a.isolation_probe"
expect_denied "Tenant B sequence use in A after accidental CONNECT grant" "permission denied for schema" env PGUSER="$RUNTIME_B" PGPASSWORD="$PASS_B" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$DB_A" -c "SELECT nextval('tenant_a.isolation_probe_id_seq')"
expect_denied "Tenant B SELECT central data after accidental CONNECT" "permission denied for schema" env PGUSER="$RUNTIME_B" PGPASSWORD="$PASS_B" psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -d "$CENTRAL_DB" -c "SELECT * FROM central_data.central_marker"

admin_sql "REVOKE CONNECT ON DATABASE \"$DB_B\" FROM \"$RUNTIME_A\""
admin_sql "REVOKE CONNECT ON DATABASE \"$CENTRAL_DB\" FROM \"$RUNTIME_A\""
admin_sql "REVOKE CONNECT ON DATABASE \"$DB_A\" FROM \"$RUNTIME_B\""
admin_sql "REVOKE CONNECT ON DATABASE \"$CENTRAL_DB\" FROM \"$RUNTIME_B\""

# PUBLIC grants and database ownership are asserted from catalog ACLs, not documentation.
for database in "${DATABASES[@]}"; do
  assert_value "PUBLIC has no CONNECT on $database" "$PGDATABASE" "SELECT NOT EXISTS (SELECT 1 FROM pg_database d CROSS JOIN LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a WHERE d.datname='$database' AND a.grantee=0 AND a.privilege_type='CONNECT')" "t"
done
assert_value "Central DB owner is the central NOLOGIN owner role" "$PGDATABASE" "SELECT r.rolname='$CENTRAL_OWNER' AND NOT r.rolcanlogin FROM pg_database d JOIN pg_roles r ON r.oid=d.datdba WHERE d.datname='$CENTRAL_DB'" "t"
assert_value "Tenant A DB owner is its NOLOGIN owner role" "$PGDATABASE" "SELECT r.rolname='$OWNER_A' AND NOT r.rolcanlogin FROM pg_database d JOIN pg_roles r ON r.oid=d.datdba WHERE d.datname='$DB_A'" "t"
assert_value "Tenant B DB owner is its NOLOGIN owner role" "$PGDATABASE" "SELECT r.rolname='$OWNER_B' AND NOT r.rolcanlogin FROM pg_database d JOIN pg_roles r ON r.oid=d.datdba WHERE d.datname='$DB_B'" "t"
assert_value "PUBLIC has no CREATE/USAGE on tenant A public schema" "$DB_A" "SELECT NOT EXISTS (SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) a WHERE n.nspname='public' AND a.grantee=0 AND a.privilege_type IN ('CREATE','USAGE'))" "t"
assert_value "PUBLIC has no USAGE/CREATE on tenant A application schema" "$DB_A" "SELECT NOT EXISTS (SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) a WHERE n.nspname='tenant_a' AND a.grantee=0 AND a.privilege_type IN ('USAGE','CREATE'))" "t"
assert_value "PUBLIC has no table privileges in tenant A schema" "$DB_A" "SELECT NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a WHERE n.nspname='tenant_a' AND c.relkind IN ('r','p','v','m','f') AND a.grantee=0 AND a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'))" "t"
assert_value "PUBLIC has no sequence privileges in tenant A schema" "$DB_A" "SELECT NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('S', c.relowner))) a WHERE n.nspname='tenant_a' AND c.relkind='S' AND a.grantee=0 AND a.privilege_type IN ('USAGE','SELECT','UPDATE'))" "t"
assert_value "Tenant A migrator default ACLs have no PUBLIC grants" "$DB_A" "SELECT NOT EXISTS (SELECT 1 FROM pg_default_acl d JOIN pg_roles creator ON creator.oid=d.defaclrole CROSS JOIN LATERAL aclexplode(d.defaclacl) a WHERE creator.rolname='$MIGRATOR_A' AND d.defaclobjtype IN ('r','S','f') AND a.grantee=0)" "t"
assert_value "Default function ACL does not give PUBLIC EXECUTE in tenant A" "$DB_A" "SELECT NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE n.nspname='tenant_a' AND p.proname='private_marker' AND a.grantee=0 AND a.privilege_type='EXECUTE')" "t"
assert_value "PUBLIC has no CREATE/USAGE on tenant B public schema" "$DB_B" "SELECT NOT EXISTS (SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) a WHERE n.nspname='public' AND a.grantee=0 AND a.privilege_type IN ('CREATE','USAGE'))" "t"
assert_value "PUBLIC has no USAGE/CREATE on tenant B application schema" "$DB_B" "SELECT NOT EXISTS (SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) a WHERE n.nspname='tenant_b' AND a.grantee=0 AND a.privilege_type IN ('USAGE','CREATE'))" "t"
assert_value "PUBLIC has no table privileges in tenant B schema" "$DB_B" "SELECT NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a WHERE n.nspname='tenant_b' AND c.relkind IN ('r','p','v','m','f') AND a.grantee=0 AND a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'))" "t"
assert_value "PUBLIC has no sequence privileges in tenant B schema" "$DB_B" "SELECT NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('S', c.relowner))) a WHERE n.nspname='tenant_b' AND c.relkind='S' AND a.grantee=0 AND a.privilege_type IN ('USAGE','SELECT','UPDATE'))" "t"
assert_value "Tenant B migrator default ACLs have no PUBLIC grants" "$DB_B" "SELECT NOT EXISTS (SELECT 1 FROM pg_default_acl d JOIN pg_roles creator ON creator.oid=d.defaclrole CROSS JOIN LATERAL aclexplode(d.defaclacl) a WHERE creator.rolname='$MIGRATOR_B' AND d.defaclobjtype IN ('r','S','f') AND a.grantee=0)" "t"
assert_value "Default function ACL does not give PUBLIC EXECUTE in tenant B" "$DB_B" "SELECT NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a WHERE n.nspname='tenant_b' AND p.proname='private_marker' AND a.grantee=0 AND a.privilege_type='EXECUTE')" "t"

log "DATABASE_PRIVILEGE_MATRIX (database|role|CONNECT|CREATE|TEMP):"
for item in "$CENTRAL_DB:$RUNTIME_A" "$CENTRAL_DB:$RUNTIME_B" "$DB_A:$RUNTIME_A" "$DB_A:$RUNTIME_B" "$DB_B:$RUNTIME_A" "$DB_B:$RUNTIME_B"; do
  database="${item%%:*}"
  role="${item#*:}"
  query "$PGDATABASE" "SELECT '$database' || '|' || '$role' || '|' || has_database_privilege('$role','$database','CONNECT') || '|' || has_database_privilege('$role','$database','CREATE') || '|' || has_database_privilege('$role','$database','TEMP')" | tee -a "$ARTIFACT"
done
log "TENANT_A_OBJECT_PRIVILEGE_MATRIX (role|schema|USAGE|CREATE|table CRUD/TRUNCATE/REFERENCES/TRIGGER|sequence USAGE/SELECT/UPDATE|function EXECUTE):"
query "$DB_A" "SELECT '$RUNTIME_A' || '|tenant_a|' || has_schema_privilege('$RUNTIME_A','tenant_a','USAGE') || '|' || has_schema_privilege('$RUNTIME_A','tenant_a','CREATE') || '|' || has_table_privilege('$RUNTIME_A','tenant_a.future_probe','SELECT') || '|' || has_table_privilege('$RUNTIME_A','tenant_a.future_probe','INSERT') || '|' || has_table_privilege('$RUNTIME_A','tenant_a.future_probe','UPDATE') || '|' || has_table_privilege('$RUNTIME_A','tenant_a.future_probe','DELETE') || '|' || has_table_privilege('$RUNTIME_A','tenant_a.future_probe','TRUNCATE') || '|' || has_table_privilege('$RUNTIME_A','tenant_a.future_probe','REFERENCES') || '|' || has_table_privilege('$RUNTIME_A','tenant_a.future_probe','TRIGGER') || '|' || has_sequence_privilege('$RUNTIME_A','tenant_a.future_probe_id_seq','USAGE') || '|' || has_sequence_privilege('$RUNTIME_A','tenant_a.future_probe_id_seq','SELECT') || '|' || has_sequence_privilege('$RUNTIME_A','tenant_a.future_probe_id_seq','UPDATE') || '|' || has_function_privilege('$RUNTIME_A','tenant_a.private_marker()','EXECUTE')" | tee -a "$ARTIFACT"
log "TENANT_B_OBJECT_PRIVILEGE_MATRIX (role|schema|USAGE|CREATE|table CRUD/TRUNCATE/REFERENCES/TRIGGER|sequence USAGE/SELECT/UPDATE|function EXECUTE):"
query "$DB_B" "SELECT '$RUNTIME_B' || '|tenant_b|' || has_schema_privilege('$RUNTIME_B','tenant_b','USAGE') || '|' || has_schema_privilege('$RUNTIME_B','tenant_b','CREATE') || '|' || has_table_privilege('$RUNTIME_B','tenant_b.future_probe','SELECT') || '|' || has_table_privilege('$RUNTIME_B','tenant_b.future_probe','INSERT') || '|' || has_table_privilege('$RUNTIME_B','tenant_b.future_probe','UPDATE') || '|' || has_table_privilege('$RUNTIME_B','tenant_b.future_probe','DELETE') || '|' || has_table_privilege('$RUNTIME_B','tenant_b.future_probe','TRUNCATE') || '|' || has_table_privilege('$RUNTIME_B','tenant_b.future_probe','REFERENCES') || '|' || has_table_privilege('$RUNTIME_B','tenant_b.future_probe','TRIGGER') || '|' || has_sequence_privilege('$RUNTIME_B','tenant_b.future_probe_id_seq','USAGE') || '|' || has_sequence_privilege('$RUNTIME_B','tenant_b.future_probe_id_seq','SELECT') || '|' || has_sequence_privilege('$RUNTIME_B','tenant_b.future_probe_id_seq','UPDATE') || '|' || has_function_privilege('$RUNTIME_B','tenant_b.private_marker()','EXECUTE')" | tee -a "$ARTIFACT"
log "DEFAULT_PRIVILEGE_ACL_MATRIX (database|creator_role|schema|object_type|grantee:privilege:grantable):"
for item in "$DB_A:$MIGRATOR_A" "$DB_B:$MIGRATOR_B"; do
  database="${item%%:*}"
  role="${item#*:}"
  query "$database" "SELECT '$database' || '|' || creator.rolname || '|' || COALESCE(n.nspname,'<global>') || '|' || d.defaclobjtype::text || '|' || COALESCE(string_agg(COALESCE(grantee.rolname,'PUBLIC') || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' ORDER BY COALESCE(grantee.rolname,'PUBLIC'),a.privilege_type),'') FROM pg_default_acl d JOIN pg_roles creator ON creator.oid=d.defaclrole LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace CROSS JOIN LATERAL aclexplode(d.defaclacl) a LEFT JOIN pg_roles grantee ON grantee.oid=a.grantee WHERE creator.rolname='$role' GROUP BY creator.rolname,n.nspname,d.defaclobjtype" | tee -a "$ARTIFACT"
done

log "MATRIX: Tenant A/B direct database boundary; central DB; CRUD; sequence; future-object defaults; schema CREATE; role/database tampering; role membership; search_path; PUBLIC ACL; function EXECUTE."
log "LIMITATION: This fixture validates PostgreSQL grant behavior using synthetic roles. It does not certify an application provisioner/broker, Laravel tenant resolver, Host/X-Forwarded-Host validation, forged API IDs, inactive state, replay, or long-lived worker reset."
