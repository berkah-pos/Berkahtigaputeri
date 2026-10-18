#!/usr/bin/env bash
set -euo pipefail

# Disposable permission-boundary test. It uses synthetic credentials/data,
# no published ports, and Docker's network=none so the database cannot reach
# production, staging, Supabase, or any other network service.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
container_name="berkah-pg-role-boundary-${GITHUB_RUN_ID:-local}-${RANDOM}"

cleanup() {
  docker rm -f "$container_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --name "$container_name" --network none \
  --env POSTGRES_DB=postgres \
  --env POSTGRES_USER=postgres \
  --env POSTGRES_PASSWORD=bootstrap-ci-only \
  --env CENTRAL_DB_DATABASE=berkahpos_central_role_ci \
  --env CENTRAL_DB_USERNAME=berkah_central_runtime \
  --env CENTRAL_DB_PASSWORD=central-runtime-test-only \
  --env CENTRAL_DB_MIGRATOR_USERNAME=berkah_central_migrator \
  --env CENTRAL_DB_MIGRATOR_PASSWORD=central-migrator-test-only \
  --env TENANT_DB_DATABASE=berkahpos_tenant_role_ci \
  --env TENANT_DB_USERNAME=berkah_tenant_runtime \
  --env TENANT_DB_PASSWORD=tenant-runtime-test-only \
  --env TENANT_DB_MIGRATOR_USERNAME=berkah_tenant_migrator \
  --env TENANT_DB_MIGRATOR_PASSWORD=tenant-migrator-test-only \
  --volume "$repo_root/docker/postgres-init/10-runtime-roles.sql:/docker-entrypoint-initdb.d/10-runtime-roles.sql:ro" \
  postgres:17 >/dev/null

ready=false
for attempt in $(seq 1 60); do
  if docker exec "$container_name" pg_isready -U postgres -d postgres >/dev/null 2>&1; then
    if docker exec "$container_name" psql -U postgres -d postgres -X -Atqc \
      "SELECT count(*) FROM pg_roles WHERE rolname IN ('berkah_central_runtime','berkah_central_migrator','berkah_tenant_runtime','berkah_tenant_migrator')" \
      2>/dev/null | grep -qx "4"; then
      ready=true
      break
    fi
  fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null || true)" != "true" ]; then
    echo "Disposable PostgreSQL exited during initialization." >&2
    docker logs "$container_name" >&2 || true
    exit 1
  fi
  sleep 2
done

if [ "$ready" != "true" ]; then
  echo "Timed out waiting for disposable PostgreSQL role initialization." >&2
  docker logs "$container_name" >&2 || true
  exit 1
fi

assert_unprivileged_role() {
  local role="$1"
  local flags
  flags="$(docker exec "$container_name" psql -U postgres -d postgres -X -Atqc \
    "SELECT (NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls) FROM pg_roles WHERE rolname = '$role'")"
  if [ "$flags" != "t" ]; then
    echo "Role privilege boundary failed for $role." >&2
    exit 1
  fi
}

assert_unprivileged_role berkah_central_runtime
assert_unprivileged_role berkah_central_migrator
assert_unprivileged_role berkah_tenant_runtime
assert_unprivileged_role berkah_tenant_migrator

# The central and tenant runtime identities may connect only to their own
# local fixture database; they must not cross the central/tenant boundary.
central_db="berkahpos_central_role_ci"
tenant_db="berkahpos_tenant_role_ci"

central_db_name="$(docker exec -e PGPASSWORD=central-runtime-test-only "$container_name" \
  psql -h 127.0.0.1 -U berkah_central_runtime -d "$central_db" -X -Atqc "SELECT current_database()")"
tenant_db_name="$(docker exec -e PGPASSWORD=tenant-runtime-test-only "$container_name" \
  psql -h 127.0.0.1 -U berkah_tenant_runtime -d "$tenant_db" -X -Atqc "SELECT current_database()")"
test "$central_db_name" = "$central_db"
test "$tenant_db_name" = "$tenant_db"

if docker exec -e PGPASSWORD=central-runtime-test-only "$container_name" \
  psql -h 127.0.0.1 -U berkah_central_runtime -d "$tenant_db" -X -Atqc "SELECT 1" >/dev/null 2>&1; then
  echo "Central runtime unexpectedly connected to the tenant database." >&2
  exit 1
fi
if docker exec -e PGPASSWORD=tenant-runtime-test-only "$container_name" \
  psql -h 127.0.0.1 -U berkah_tenant_runtime -d "$central_db" -X -Atqc "SELECT 1" >/dev/null 2>&1; then
  echo "Tenant runtime unexpectedly connected to the central database." >&2
  exit 1
fi

# Database-scoped migrators can create their own schema objects, but runtime
# identities have only DML/sequence grants and cannot take ownership/drop them.
docker exec -e PGPASSWORD=central-migrator-test-only "$container_name" \
  psql -h 127.0.0.1 -U berkah_central_migrator -d "$central_db" -X -v ON_ERROR_STOP=1 \
  -c "CREATE TABLE ops_role_probe (id bigserial PRIMARY KEY, payload text NOT NULL)" >/dev/null

insert_result="$(docker exec -e PGPASSWORD=central-runtime-test-only "$container_name" \
  psql -h 127.0.0.1 -U berkah_central_runtime -d "$central_db" -X -v ON_ERROR_STOP=1 -Atqc \
  "INSERT INTO ops_role_probe(payload) VALUES ('dml-ok') RETURNING payload")"
test "$insert_result" = "dml-ok"

if docker exec -e PGPASSWORD=central-runtime-test-only "$container_name" \
  psql -h 127.0.0.1 -U berkah_central_runtime -d "$central_db" -X -v ON_ERROR_STOP=1 \
  -c "DROP TABLE ops_role_probe" >/dev/null 2>&1; then
  echo "Central runtime unexpectedly dropped a migration-owned table." >&2
  exit 1
fi

central_can_create_schema="$(docker exec -e PGPASSWORD=central-runtime-test-only "$container_name" \
  psql -h 127.0.0.1 -U berkah_central_runtime -d "$central_db" -X -Atqc \
  "SELECT has_schema_privilege(current_user, 'public', 'CREATE')")"
test "$central_can_create_schema" = "f"

echo "PASS: local PostgreSQL runtime roles are non-superuser, cannot create roles/databases, cannot cross central/tenant DB CONNECT boundaries, and cannot perform DDL."
echo "Scope: one disposable local tenant fixture only; this is not proof of production per-tenant grants, backup/restore, PITR, or capacity."
