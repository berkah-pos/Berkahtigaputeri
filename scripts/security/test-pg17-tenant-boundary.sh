#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
: "${CI_IMAGE:?CI_IMAGE must identify the PHP 8.4/PDO_PGSQL development image}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
SECRETS="$TMP/secrets"
mkdir -m 700 "$SECRETS"
chmod 700 "$TMP"
trap 'unset BROKER_DATABASE_PASSWORD PGPASSWORD TEST_BROKER_PASSWORD TEST_CENTRAL_PASSWORD TEST_C_RUNTIME_PASSWORD TEST_C_MIGRATOR_PASSWORD A_MIGRATOR_PASS B_MIGRATOR_PASS C_MIGRATOR_PASS D_MIGRATOR_PASS A_RUNTIME_PASS B_RUNTIME_PASS CENTRAL_PASS; rm -rf "$TMP"' EXIT

A_ID="01ARZ3NDEKTSV4RRFFQ69G5FAV"
B_ID="01ARZ3NDEKTSV4RRFFQ69G5FAW"
C_ID="01ARZ3NDEKTSV4RRFFQ69G5FAX"
D_ID="01ARZ3NDEKTSV4RRFFQ69G5FAY"
E_ID="01ARZ3NDEKTSV4RRFFQ69G5FAZ"
A_DB="berkahpos_t_${A_ID,,}"
B_DB="berkahpos_t_${B_ID,,}"
C_DB="berkahpos_t_${C_ID,,}"
D_DB="berkahpos_t_${D_ID,,}"
E_DB="berkahpos_t_${E_ID,,}"
C_OWNER="berkah_owner_${C_ID,,}"
C_RUNTIME="berkah_runtime_${C_ID,,}"
C_MIGRATOR="berkah_migrator_${C_ID,,}"
A_OWNER="berkah_owner_${A_ID,,}"
A_RUNTIME="berkah_runtime_${A_ID,,}"
B_RUNTIME="berkah_runtime_${B_ID,,}"
A_MIGRATOR="berkah_migrator_${A_ID,,}"
B_MIGRATOR="berkah_migrator_${B_ID,,}"

make_secret() {
  local name="$1"
  openssl rand -hex 32 > "$SECRETS/$name"
  chmod 600 "$SECRETS/$name"
}
for name in broker central runtime-a migrator-a runtime-b migrator-b runtime-c migrator-c runtime-d migrator-d runtime-e migrator-e; do
  make_secret "$name"
done

psql_super() {
  local db="$1"; shift
  docker run --rm --network host -e PGPASSWORD=postgres -e TEST_BROKER_PASSWORD -e TEST_CENTRAL_PASSWORD \
    postgres:17 psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 5432 -U postgres -d "$db" "$@"
}
psql_as() {
  local user="$1" password="$2" db="$3"; shift 3
  PGPASSWORD="$password" docker run --rm --network host \
    -e PGPASSWORD -e PGHOST=127.0.0.1 -e PGPORT=5432 -e PGUSER="$user" -e PGDATABASE="$db" \
    postgres:17 psql -X -v ON_ERROR_STOP=1 "$@"
}
run_broker() {
  docker run --rm --network host -e BROKER_DATABASE_HOST=127.0.0.1 -e BROKER_DATABASE_PORT=5432 \
    -e BROKER_DATABASE_NAME -e BROKER_DATABASE_USERNAME=berkah_provisioner -e BROKER_DATABASE_PASSWORD \
    -v "$SECRETS:/run/secrets:ro" --entrypoint php "$CI_IMAGE" \
    /var/www/berkah-pos/bin/tenant-db-broker.php "$@"
}
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s (expected %s, observed %s)\n' "$label" "$expected" "$actual" >&2; exit 1
  fi
  printf 'PASS: %s = %s\n' "$label" "$actual"
}
expect_denied() {
  local label="$1" pattern="$2"; shift 2
  local output="$TMP/expected-denial.log"
  if "$@" >"$output" 2>&1; then
    printf 'FAIL: %s unexpectedly succeeded\n' "$label" >&2; exit 1
  fi
  if ! grep -Eiq "$pattern" "$output"; then
    printf 'FAIL: %s failed for an unexpected reason; sanitized excerpt follows\n' "$label" >&2
    grep -E '^(ERROR|FATAL|FAIL CLOSED|psql: error:)' "$output" | head -n 3 >&2 || true
    exit 1
  fi
  printf 'PASS: expected denial — %s\n' "$label"
}

printf '%s\n' '=== PostgreSQL 17 disposable tenant isolation integration tests ==='
printf 'PostgreSQL version: '
psql_super postgres -Atc 'SHOW server_version'
psql_super postgres <<'SQL' >/dev/null
ALTER SYSTEM SET log_parameter_max_length = 0;
ALTER SYSTEM SET log_parameter_max_length_on_error = 0;
SQL
psql_super postgres -Atc 'SELECT pg_reload_conf()' >/dev/null
assert_eq "log_parameter_max_length" "0" "$(psql_super postgres -Atc 'SHOW log_parameter_max_length')"
assert_eq "log_parameter_max_length_on_error" "0" "$(psql_super postgres -Atc 'SHOW log_parameter_max_length_on_error')"

export TEST_BROKER_PASSWORD
TEST_BROKER_PASSWORD="$(cat "$SECRETS/broker")"
export TEST_CENTRAL_PASSWORD
TEST_CENTRAL_PASSWORD="$(cat "$SECRETS/central")"
psql_super postgres <<'SQL'
\getenv broker_pass TEST_BROKER_PASSWORD
\getenv central_pass TEST_CENTRAL_PASSWORD
CREATE ROLE berkah_provisioner LOGIN NOINHERIT NOSUPERUSER CREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 3 PASSWORD :'broker_pass';
CREATE ROLE berkah_central_runtime LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 30 PASSWORD :'central_pass';
CREATE DATABASE berkahpos_central_boundary OWNER postgres;
REVOKE CONNECT, TEMPORARY ON DATABASE berkahpos_central_boundary FROM PUBLIC;
GRANT CONNECT ON DATABASE berkahpos_central_boundary TO berkah_central_runtime;
CREATE DATABASE berkahpos_t_01arz3ndektsv4rrffq69g5faz OWNER postgres;
REVOKE CONNECT, TEMPORARY ON DATABASE berkahpos_t_01arz3ndektsv4rrffq69g5faz FROM PUBLIC;
REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;
GRANT CONNECT ON DATABASE postgres TO berkah_provisioner;
\unset broker_pass
\unset central_pass
SQL
psql_super berkahpos_central_boundary <<'SQL'
CREATE TABLE central_private (id integer PRIMARY KEY, marker text NOT NULL);
INSERT INTO central_private VALUES (1, 'synthetic-central-boundary-fixture');
GRANT SELECT ON central_private TO berkah_central_runtime;
SQL
docker run --rm --network host -e PGPASSWORD=postgres \
  -v "$ROOT/scripts/security/install-pg17-provisioner-functions.sql:/tmp/provisioner.sql:ro" \
  postgres:17 psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p 5432 -U postgres -d postgres -f /tmp/provisioner.sql >/dev/null
printf '%s\n' 'PASS: narrow SECURITY DEFINER functions installed on disposable PostgreSQL 17'

export BROKER_DATABASE_PASSWORD
BROKER_DATABASE_PASSWORD="$(cat "$SECRETS/broker")"
unset TEST_BROKER_PASSWORD TEST_CENTRAL_PASSWORD

run_broker provision "$A_ID" --runtime-password-file=/run/secrets/runtime-a --migrator-password-file=/run/secrets/migrator-a
run_broker provision "$B_ID" --runtime-password-file=/run/secrets/runtime-b --migrator-password-file=/run/secrets/migrator-b

# Reproduce the non-transactional CREATE DATABASE interruption window with a
# durable intent written by the real broker function and a closed, unmarked DB.
export TEST_C_RUNTIME_PASSWORD="$(cat "$SECRETS/runtime-c")"
export TEST_C_MIGRATOR_PASSWORD="$(cat "$SECRETS/migrator-c")"
docker run --rm --network host \
  -e BROKER_DATABASE_HOST=127.0.0.1 -e BROKER_DATABASE_PORT=5432 \
  -e BROKER_DATABASE_NAME=postgres -e BROKER_DATABASE_USERNAME=berkah_provisioner \
  -e BROKER_DATABASE_PASSWORD -e TEST_C_RUNTIME_PASSWORD -e TEST_C_MIGRATOR_PASSWORD \
  --entrypoint php "$CI_IMAGE" /var/www/berkah-pos/scripts/security/prepare-pg17-interrupted-state.php "$C_ID"
unset TEST_C_RUNTIME_PASSWORD TEST_C_MIGRATOR_PASSWORD
psql_as berkah_provisioner "$BROKER_DATABASE_PASSWORD" postgres -c \
  "CREATE DATABASE \"$C_DB\" OWNER \"$C_OWNER\" ALLOW_CONNECTIONS FALSE;" >/dev/null
assert_eq "interrupted database remains closed before recovery" "t" \
  "$(psql_super postgres -Atc "SELECT shobj_description(oid,'pg_database') IS NULL AND NOT datallowconn FROM pg_database WHERE datname='$C_DB'")"
run_broker provision "$C_ID" --runtime-password-file=/run/secrets/runtime-c --migrator-password-file=/run/secrets/migrator-c
echo "PASS: unmarked database recovered only from matching durable intent"

C_MIGRATOR_PASS="$(cat "$SECRETS/migrator-c")"
psql_as "$C_MIGRATOR" "$C_MIGRATOR_PASS" "$C_DB" <<'SQL'
CREATE TABLE migrations (id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, migration text NOT NULL);
CREATE TABLE products (id bigserial PRIMARY KEY, sku text NOT NULL UNIQUE, quantity integer NOT NULL);
CREATE TABLE sales (id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, total_cents bigint NOT NULL);
CREATE TABLE sync_receipts (event_id text PRIMARY KEY, digest text NOT NULL);
SQL
run_broker finalize "$C_ID"

A_MIGRATOR_PASS="$(cat "$SECRETS/migrator-a")"
B_MIGRATOR_PASS="$(cat "$SECRETS/migrator-b")"
psql_as "$A_MIGRATOR" "$A_MIGRATOR_PASS" "$A_DB" <<'SQL'
CREATE TABLE migrations (id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, migration text NOT NULL);
CREATE TABLE products (id bigserial PRIMARY KEY, sku text NOT NULL UNIQUE, quantity integer NOT NULL);
CREATE TABLE sales (id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, total_cents bigint NOT NULL);
CREATE TABLE sync_receipts (event_id text PRIMARY KEY, digest text NOT NULL);
INSERT INTO products(sku, quantity) VALUES ('interrupted-before-retry', 17);
SQL
psql_as "$B_MIGRATOR" "$B_MIGRATOR_PASS" "$B_DB" <<'SQL'
CREATE TABLE migrations (id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, migration text NOT NULL);
CREATE TABLE products (id bigserial PRIMARY KEY, sku text NOT NULL UNIQUE, quantity integer NOT NULL);
CREATE TABLE sales (id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, total_cents bigint NOT NULL);
CREATE TABLE sync_receipts (event_id text PRIMARY KEY, digest text NOT NULL);
INSERT INTO products(sku, quantity) VALUES ('tenant-b-private', 99);
SQL

run_broker provision "$A_ID" --runtime-password-file=/run/secrets/runtime-a --migrator-password-file=/run/secrets/migrator-a
assert_eq "interrupted provisioning data preserved" "17" \
  "$(psql_as "$A_MIGRATOR" "$A_MIGRATOR_PASS" "$A_DB" -Atc "SELECT quantity FROM products WHERE sku='interrupted-before-retry'")"

(
  run_broker provision "$D_ID" --runtime-password-file=/run/secrets/runtime-d --migrator-password-file=/run/secrets/migrator-d >"$TMP/concurrent-1.out" 2>"$TMP/concurrent-1.err"
) &
PID1=$!
(
  run_broker provision "$D_ID" --runtime-password-file=/run/secrets/runtime-d --migrator-password-file=/run/secrets/migrator-d >"$TMP/concurrent-2.out" 2>"$TMP/concurrent-2.err"
) &
PID2=$!
wait "$PID1"; wait "$PID2"
grep -Eq '"result":"(provisioning|resumed)"' "$TMP/concurrent-1.out"
grep -Eq '"result":"(provisioning|resumed)"' "$TMP/concurrent-2.out"
assert_eq "concurrent provisioning has exactly one database" "1" "$(psql_super postgres -Atc "SELECT count(*) FROM pg_database WHERE datname='$D_DB'")"
assert_eq "concurrent provisioning has exactly one marked runtime role" "1" \
  "$(psql_super postgres -Atc "SELECT count(*) FROM pg_roles WHERE rolname='berkah_runtime_${D_ID,,}' AND shobj_description(oid,'pg_authid')='berkah-pos:tenant-role:v1;tenant=$D_ID;kind=runtime'")"
D_MIGRATOR="berkah_migrator_${D_ID,,}"
D_MIGRATOR_PASS="$(cat "$SECRETS/migrator-d")"
psql_as "$D_MIGRATOR" "$D_MIGRATOR_PASS" "$D_DB" <<'SQL'
CREATE TABLE migrations (id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, migration text NOT NULL);
CREATE TABLE products (id bigserial PRIMARY KEY, sku text NOT NULL UNIQUE, quantity integer NOT NULL);
CREATE TABLE sales (id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY, total_cents bigint NOT NULL);
CREATE TABLE sync_receipts (event_id text PRIMARY KEY, digest text NOT NULL);
SQL
run_broker finalize "$D_ID"
run_broker finalize "$D_ID"
assert_eq "retrying finalization does not duplicate database" "1" "$(psql_super postgres -Atc "SELECT count(*) FROM pg_database WHERE datname='$D_DB'")"
run_broker finalize "$A_ID"
run_broker finalize "$B_ID"

printf '%s\n' '--- Redacted pg_roles / database ownership transcript ---'
psql_super postgres <<SQL
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls, rolinherit, rolconnlimit,
       shobj_description(oid, 'pg_authid') AS role_marker
  FROM pg_roles
 WHERE rolname IN ('berkah_provisioner', 'berkah_role_admin', '$A_OWNER', '$A_RUNTIME', '$A_MIGRATOR',
   '$B_OWNER', '$B_RUNTIME', '$B_MIGRATOR', 'berkah_central_runtime')
 ORDER BY rolname;
SELECT datname, pg_get_userbyid(datdba) AS owner, datallowconn, shobj_description(oid, 'pg_database') AS db_marker
  FROM pg_database
 WHERE datname IN ('postgres', 'berkahpos_central_boundary', '$A_DB', '$B_DB', '$D_DB') ORDER BY datname;
SQL

assert_eq "PUBLIC CONNECT revoked on tenant A" "f" "$(psql_super postgres -Atc "SELECT COALESCE(bool_or(a.grantee=0 AND a.privilege_type='CONNECT'),FALSE) FROM pg_database d LEFT JOIN LATERAL aclexplode(COALESCE(d.datacl,acldefault('d',d.datdba))) a ON TRUE WHERE d.datname='$A_DB'")"
assert_eq "PUBLIC TEMPORARY revoked on tenant A" "f" "$(psql_super postgres -Atc "SELECT COALESCE(bool_or(a.grantee=0 AND a.privilege_type='TEMPORARY'),FALSE) FROM pg_database d LEFT JOIN LATERAL aclexplode(COALESCE(d.datacl,acldefault('d',d.datdba))) a ON TRUE WHERE d.datname='$A_DB'")"
assert_eq "broker cannot CONNECT to tenant A after provisioning" "f" "$(psql_super postgres -Atc "SELECT has_database_privilege('berkah_provisioner','$A_DB','CONNECT')")"
assert_eq "runtime can CONNECT to tenant A after finalization" "t" "$(psql_super postgres -Atc "SELECT has_database_privilege('$A_RUNTIME','$A_DB','CONNECT')")"
assert_eq "migrator cannot CONNECT after finalization" "f" "$(psql_super postgres -Atc "SELECT has_database_privilege('$A_MIGRATOR','$A_DB','CONNECT')")"
assert_eq "PUBLIC has no USAGE/CREATE on tenant A public schema" "f" "$(psql_super "$A_DB" -Atc "SELECT COALESCE(bool_or(a.grantee=0 AND a.privilege_type IN ('USAGE','CREATE')),FALSE) FROM pg_namespace n LEFT JOIN LATERAL aclexplode(COALESCE(n.nspacl,acldefault('n',n.nspowner))) a ON TRUE WHERE n.nspname='public'")"
assert_eq "PUBLIC has no DML/sequence privilege on products" "f" "$(psql_super "$A_DB" -Atc "SELECT COALESCE(bool_or(a.grantee=0 AND a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','USAGE')),FALSE) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a ON TRUE WHERE n.nspname='public' AND c.relname='products'")"
assert_eq "runtime has DML on products" "t" "$(psql_super "$A_DB" -Atc "SELECT has_table_privilege('$A_RUNTIME','public.products','SELECT,INSERT,UPDATE,DELETE')")"
assert_eq "runtime has sequence USAGE and SELECT" "t" "$(psql_super "$A_DB" -Atc "SELECT has_sequence_privilege('$A_RUNTIME','public.products_id_seq','USAGE,SELECT')")"
DEFAULT_PRIV_COUNT="$(psql_super "$A_DB" -Atc "SELECT count(*) FROM pg_default_acl d JOIN pg_roles r ON r.oid=d.defaclrole CROSS JOIN LATERAL aclexplode(d.defaclacl) a JOIN pg_roles g ON g.oid=a.grantee WHERE d.defaclnamespace='public'::regnamespace AND r.rolname='$A_MIGRATOR' AND g.rolname='$A_RUNTIME' AND ((d.defaclobjtype='r' AND a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE')) OR (d.defaclobjtype='S' AND a.privilege_type IN ('USAGE','SELECT')))")"
if [[ "$DEFAULT_PRIV_COUNT" -lt 6 ]]; then echo "FAIL: expected all six tenant default grants, found $DEFAULT_PRIV_COUNT" >&2; exit 1; fi
printf 'PASS: migration default privileges contain %s required table/sequence entries\n' "$DEFAULT_PRIV_COUNT"

printf '%s\n' '--- Tenant A actual database ACL / schema / table / sequence / default grants ---'
psql_super "$A_DB" <<SQL
SELECT COALESCE(bool_or(a.grantee = 0 AND a.privilege_type = 'CONNECT'), FALSE) AS public_connect,
       COALESCE(bool_or(a.grantee = 0 AND a.privilege_type = 'TEMPORARY'), FALSE) AS public_temp,
       has_database_privilege('berkah_provisioner', d.datname, 'CONNECT') AS broker_connect,
       has_database_privilege('$A_RUNTIME', d.datname, 'CONNECT') AS runtime_connect,
       has_database_privilege('$A_MIGRATOR', d.datname, 'CONNECT') AS migrator_connect
  FROM pg_database d
  LEFT JOIN LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) a ON TRUE
 WHERE d.datname = '$A_DB' GROUP BY d.oid, d.datname;
SELECT nspname, COALESCE(bool_or(a.grantee = 0 AND a.privilege_type IN ('USAGE','CREATE')), FALSE) AS public_schema_privilege,
       has_schema_privilege('$A_RUNTIME', n.nspname, 'USAGE') AS runtime_usage,
       has_schema_privilege('$A_RUNTIME', n.nspname, 'CREATE') AS runtime_create
  FROM pg_namespace n LEFT JOIN LATERAL aclexplode(COALESCE(n.nspacl, acldefault('n', n.nspowner))) a ON TRUE
 WHERE n.nspname='public' GROUP BY n.oid,n.nspname;
SELECT c.relname, c.relkind,
       COALESCE(bool_or(a.grantee = 0 AND a.privilege_type IN ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','USAGE')), FALSE) AS public_data_privilege,
       has_table_privilege('$A_RUNTIME', c.oid, 'SELECT,INSERT,UPDATE,DELETE') AS runtime_dml,
       CASE WHEN c.relkind='S' THEN has_sequence_privilege('$A_RUNTIME', c.oid, 'USAGE,SELECT') ELSE NULL END AS runtime_sequence
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  LEFT JOIN LATERAL aclexplode(COALESCE(c.relacl, CASE WHEN c.relkind='S' THEN acldefault('S',c.relowner) ELSE acldefault('r',c.relowner) END)) a ON TRUE
 WHERE n.nspname='public' AND c.relkind IN ('r','p','S') GROUP BY c.oid,c.relname,c.relkind ORDER BY c.relname;
SELECT r.rolname AS default_privilege_owner, g.rolname AS grantee, d.defaclobjtype, a.privilege_type
  FROM pg_default_acl d JOIN pg_roles r ON r.oid=d.defaclrole
  CROSS JOIN LATERAL aclexplode(d.defaclacl) a JOIN pg_roles g ON g.oid=a.grantee
 WHERE d.defaclnamespace='public'::regnamespace AND r.rolname='$A_MIGRATOR' AND g.rolname='$A_RUNTIME'
 ORDER BY d.defaclobjtype,a.privilege_type;
SQL

A_RUNTIME_PASS="$(cat "$SECRETS/runtime-a")"
A_PRODUCT_ID="$(psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$A_DB" -Atc "INSERT INTO products(sku,quantity) VALUES ('runtime-a-crud',3) RETURNING id")"
[[ "$A_PRODUCT_ID" =~ ^[0-9]+$ ]]
psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$A_DB" -c "UPDATE products SET quantity=8 WHERE id=$A_PRODUCT_ID" >/dev/null
assert_eq "tenant A own update" "8" "$(psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$A_DB" -Atc "SELECT quantity FROM products WHERE id=$A_PRODUCT_ID")"
assert_eq "tenant A sequence use" "t" "$(psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$A_DB" -Atc "SELECT has_sequence_privilege(current_user,'products_id_seq','USAGE')")"
psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$A_DB" -Atc "SELECT nextval('products_id_seq')" >/dev/null
psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$A_DB" -c "DELETE FROM products WHERE id=$A_PRODUCT_ID" >/dev/null
assert_eq "tenant A own delete" "0" "$(psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$A_DB" -Atc "SELECT count(*) FROM products WHERE id=$A_PRODUCT_ID")"
B_RUNTIME_PASS="$(cat "$SECRETS/runtime-b")"
assert_eq "tenant B data remains independent" "99" "$(psql_as "$B_RUNTIME" "$B_RUNTIME_PASS" "$B_DB" -Atc "SELECT quantity FROM products WHERE sku='tenant-b-private'")"
CENTRAL_PASS="$(cat "$SECRETS/central")"
assert_eq "central runtime can read central-only control data" "synthetic-central-boundary-fixture" \
  "$(psql_as berkah_central_runtime "$CENTRAL_PASS" berkahpos_central_boundary -Atc "SELECT marker FROM central_private WHERE id=1")"
expect_denied "central runtime cannot connect to tenant A" 'permission denied for database' \
  psql_as berkah_central_runtime "$CENTRAL_PASS" "$A_DB" -Atc 'SELECT 1'

expect_denied "tenant A cannot connect to tenant B" 'permission denied for database' psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$B_DB" -Atc 'SELECT 1'
expect_denied "tenant A cannot SELECT from tenant B" 'permission denied for database' psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$B_DB" -Atc 'SELECT * FROM products'
expect_denied "tenant A cannot INSERT into tenant B" 'permission denied for database' psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$B_DB" -c "INSERT INTO products(sku,quantity) VALUES ('attack',1)"
expect_denied "tenant A cannot UPDATE tenant B" 'permission denied for database' psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$B_DB" -c "UPDATE products SET quantity=0"
expect_denied "tenant A cannot DELETE from tenant B" 'permission denied for database' psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$B_DB" -c "DELETE FROM products"
expect_denied "tenant A cannot use tenant B sequence" 'permission denied for database' psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$B_DB" -c "SELECT nextval('products_id_seq')"
expect_denied "tenant A cannot connect to central DB" 'permission denied for database' psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" berkahpos_central_boundary -Atc 'SELECT * FROM central_private'
expect_denied "broker cannot connect to central DB" 'permission denied for database' psql_as berkah_provisioner "$BROKER_DATABASE_PASSWORD" berkahpos_central_boundary -Atc 'SELECT * FROM central_private'
expect_denied "runtime cannot create tables" 'permission denied for schema' psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$A_DB" -c 'CREATE TABLE forbidden_table(id integer)'
expect_denied "runtime cannot create roles" 'permission denied to create role' psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$A_DB" -c 'CREATE ROLE forbidden_role'
expect_denied "runtime cannot create databases" 'permission denied to create database' psql_as "$A_RUNTIME" "$A_RUNTIME_PASS" "$A_DB" -c 'CREATE DATABASE forbidden_database'
expect_denied "broker cannot create roles directly" 'permission denied to create role' psql_as berkah_provisioner "$BROKER_DATABASE_PASSWORD" postgres -c 'CREATE ROLE forbidden_role'

expect_denied "malformed tenant identifier rejected" 'FAIL CLOSED' run_broker provision '../postgres' \
  --runtime-password-file=/run/secrets/runtime-a --migrator-password-file=/run/secrets/migrator-a
expect_denied "caller cannot pass a database-name override" 'FAIL CLOSED' run_broker provision "$A_ID" --database=berkahpos_central_boundary \
  --runtime-password-file=/run/secrets/runtime-a --migrator-password-file=/run/secrets/migrator-a
if BROKER_DATABASE_NAME=berkahpos_central_boundary run_broker provision "$A_ID" \
  --runtime-password-file=/run/secrets/runtime-a --migrator-password-file=/run/secrets/migrator-a >"$TMP/broker-db-override.out" 2>&1; then
  echo 'FAIL: broker accepted a central database override' >&2; exit 1
else
  grep -q 'FAIL CLOSED' "$TMP/broker-db-override.out"
  echo 'PASS: broker refuses non-maintenance database configuration'
fi

expect_denied "unverified pre-existing database is rejected" 'FAIL CLOSED' run_broker provision "$E_ID" \
  --runtime-password-file=/run/secrets/runtime-e --migrator-password-file=/run/secrets/migrator-e
assert_eq "unverified collision still exists" "1" "$(psql_super postgres -Atc "SELECT count(*) FROM pg_database WHERE datname='$E_DB'")"
assert_eq "unverified collision retains original owner" "postgres" "$(psql_super postgres -Atc "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='$E_DB'")"
assert_eq "unverified collision remains unmarked" "t" "$(psql_super postgres -Atc "SELECT shobj_description(oid,'pg_database') IS NULL FROM pg_database WHERE datname='$E_DB'")"

printf '%s\n' '--- Redacted append-only broker audit transcript ---'
psql_super postgres -c "SELECT tenant_id, action, target, actor, happened_at FROM provisioning.audit_events WHERE tenant_id IN ('$A_ID','$B_ID','$C_ID','$D_ID') ORDER BY event_id"
printf '%s\n' 'PASS: disposable PostgreSQL 17 role/grant/provisioning checks completed'
printf '%s\n' 'NOT RUN: HTTP tenant/domain/subscription/device/Host/X-Forwarded-Host checks; audited source has no protected tenant API or host/domain authorization middleware'
