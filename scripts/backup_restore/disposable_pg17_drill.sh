#!/usr/bin/env bash
set -Eeuo pipefail

ARTIFACT_DIR=$BACKUP_DRILL_ARTIFACT_DIR
if [ -z "$ARTIFACT_DIR" ]; then
  echo "BLOCKED: BACKUP_DRILL_ARTIFACT_DIR must be set to a temporary artifact directory" >&2
  exit 2
fi
mkdir -p "$ARTIFACT_DIR"
for tool in docker openssl sha256sum tar python3 date; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf '{"status":"BLOCKED","reason":"missing required executable: %s"}\n' "$tool" > "$ARTIFACT_DIR/result.json"
    echo "BLOCKED: missing required executable: $tool" >&2
    exit 2
  fi
done
if ! docker info >/dev/null 2>&1; then
  printf '{"status":"BLOCKED","reason":"Docker daemon unavailable"}\n' > "$ARTIFACT_DIR/result.json"
  echo "BLOCKED: Docker daemon unavailable" >&2
  exit 2
fi

# Synthetic-only harness. No production URL/config input is accepted and no database port is published.
unset DATABASE_URL CENTRAL_DB_URL TENANT_DB_URL PGPASSWORD || true
umask 077
started=$(date +%s)
work=$(mktemp -d)
suffix="$(date -u +%Y%m%d%H%M%S)-$$"
network="backup-drill-net-$suffix"
source_db="backup-drill-src-$suffix"
target_db="backup-drill-dst-$suffix"
app_image="berkah-pos-backup-drill-$suffix"
db_password="DisposableOnly-Synthetic-Database-Password"
export BACKUP_DRILL_SYNTHETIC_PASSPHRASE="synthetic-only-passphrase-not-a-production-secret"

cleanup() {
  rc=$?
  set +e
  if [ "$rc" -ne 0 ] && [ ! -f "$ARTIFACT_DIR/result.json" ]; then
    printf '{"status":"FAILED","exit_code":%s,"sha":"%s","scope":"synthetic disposable PostgreSQL 17 drill only"}\n' "$rc" "$GITHUB_SHA" > "$ARTIFACT_DIR/result.json"
  fi
  docker rm -f "$target_db" "$source_db" >/dev/null 2>&1
  docker network rm "$network" >/dev/null 2>&1
  docker image rm "$app_image" >/dev/null 2>&1
  rm -rf "$work"
  exit "$rc"
}
trap cleanup EXIT

docker network create --internal "$network" >/dev/null
docker run -d --name "$source_db" --network "$network" \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD="$db_password" \
  -e POSTGRES_DB=berkahpos_central postgres:17 >/dev/null
docker run -d --name "$target_db" --network "$network" \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD="$db_password" \
  -e POSTGRES_DB=postgres postgres:17 >/dev/null
ready=false
for attempt in $(seq 1 60); do
  if docker exec "$source_db" pg_isready -U postgres -d berkahpos_central >/dev/null 2>&1 &&
     docker exec "$target_db" pg_isready -U postgres -d postgres >/dev/null 2>&1; then ready=true; break; fi
  sleep 2
done
if [ "$ready" != true ]; then echo "FAIL: disposable PostgreSQL containers did not become ready" >&2; exit 1; fi

docker build --pull --target development --tag "$app_image" .
docker exec "$source_db" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c 'CREATE DATABASE berkahpos_tenant_a'
docker exec "$source_db" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c 'CREATE DATABASE berkahpos_tenant_b'

docker run --rm --network "$network" \
  -e APP_ENV=testing -e APP_KEY=base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
  -e DB_CONNECTION=central -e CENTRAL_DB_HOST="$source_db" -e CENTRAL_DB_PORT=5432 \
  -e CENTRAL_DB_DATABASE=berkahpos_central -e CENTRAL_DB_USERNAME=postgres \
  -e CENTRAL_DB_PASSWORD="$db_password" -e CENTRAL_DB_SSLMODE=disable \
  -e TENANT_DB_HOST="$source_db" -e TENANT_DB_PORT=5432 \
  -e TENANT_DB_DATABASE=berkahpos_tenant_a -e TENANT_DB_USERNAME=postgres \
  -e TENANT_DB_PASSWORD="$db_password" -e TENANT_DB_SSLMODE=disable \
  "$app_image" php artisan migrate --database=central --path=database/migrations/central --force
for tenant_db in berkahpos_tenant_a berkahpos_tenant_b; do
  docker run --rm --network "$network" \
    -e APP_ENV=testing -e APP_KEY=base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
    -e DB_CONNECTION=central -e CENTRAL_DB_HOST="$source_db" -e CENTRAL_DB_PORT=5432 \
    -e CENTRAL_DB_DATABASE=berkahpos_central -e CENTRAL_DB_USERNAME=postgres \
    -e CENTRAL_DB_PASSWORD="$db_password" -e CENTRAL_DB_SSLMODE=disable \
    -e TENANT_DB_HOST="$source_db" -e TENANT_DB_PORT=5432 \
    -e TENANT_DB_DATABASE="$tenant_db" -e TENANT_DB_USERNAME=postgres \
    -e TENANT_DB_PASSWORD="$db_password" -e TENANT_DB_SSLMODE=disable \
    "$app_image" php artisan migrate --database=tenant --path=database/migrations/tenant --force
done

docker exec "$source_db" psql -U postgres -d berkahpos_central -v ON_ERROR_STOP=1 \
  -c "INSERT INTO tenants (id, template_id, created_at, updated_at) VALUES ('tenant_a_synthetic','BASIC',now(),now()),('tenant_b_synthetic','BASIC',now(),now())"
docker exec "$source_db" psql -U postgres -d berkahpos_tenant_a -v ON_ERROR_STOP=1 \
  -c "INSERT INTO products (id,name,price,requires_review,is_active,created_at,updated_at) VALUES ('DRILL-A','Synthetic marker A',1.00,false,true,now(),now())"
docker exec "$source_db" psql -U postgres -d berkahpos_tenant_b -v ON_ERROR_STOP=1 \
  -c "INSERT INTO products (id,name,price,requires_review,is_active,created_at,updated_at) VALUES ('DRILL-B','Synthetic marker B',2.00,false,true,now(),now())"

mkdir -p "$work/files"
printf 'SYNTHETIC FILE A ONLY - NO CUSTOMER DATA\n' > "$work/files/tenant-a.txt"
printf 'SYNTHETIC FILE B ONLY - NO CUSTOMER DATA\n' > "$work/files/tenant-b.txt"
sha256sum "$work/files/tenant-a.txt" "$work/files/tenant-b.txt" > "$work/file-checksums.txt"
printf 'synthetic-key-material-only\n' > "$work/synthetic-key.txt"
sha256sum "$work/synthetic-key.txt" > "$work/key-checksum.txt"
openssl enc -aes-256-cbc -pbkdf2 -salt -in "$work/synthetic-key.txt" -out "$work/synthetic-key.enc" -pass env:BACKUP_DRILL_SYNTHETIC_PASSPHRASE
openssl enc -d -aes-256-cbc -pbkdf2 -in "$work/synthetic-key.enc" -out "$work/synthetic-key.restored" -pass env:BACKUP_DRILL_SYNTHETIC_PASSPHRASE
sha256sum -c "$work/key-checksum.txt" >/dev/null
cmp "$work/synthetic-key.txt" "$work/synthetic-key.restored"

for db in berkahpos_central berkahpos_tenant_a berkahpos_tenant_b; do
  # Stream the custom-format archive directly from the disposable source container.
  docker exec -e PGPASSWORD="$db_password" "$source_db" \
    pg_dump -h 127.0.0.1 -U postgres -d "$db" -Fc > "$work/$db.dump"
  if [ ! -s "$work/$db.dump" ]; then echo "FAIL: generated backup archive is empty" >&2; exit 1; fi
  docker run -i --rm --network "$network" postgres:17 pg_restore --list < "$work/$db.dump" >/dev/null
  sha256sum "$work/$db.dump" > "$work/$db.sha256"
  openssl enc -aes-256-cbc -pbkdf2 -salt -in "$work/$db.dump" -out "$work/$db.dump.enc" -pass env:BACKUP_DRILL_SYNTHETIC_PASSPHRASE
  openssl enc -d -aes-256-cbc -pbkdf2 -in "$work/$db.dump.enc" -out "$work/$db.restore.dump" -pass env:BACKUP_DRILL_SYNTHETIC_PASSPHRASE
  sha256sum -c "$work/$db.sha256" >/dev/null
  docker run -i --rm --network "$network" postgres:17 pg_restore --list < "$work/$db.restore.dump" >/dev/null
  docker exec "$target_db" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE $db"
  docker run --rm --network "$network" -e PGPASSWORD="$db_password" postgres:17 \
    pg_restore --exit-on-error --no-owner -h "$target_db" -U postgres -d "$db" < "$work/$db.restore.dump"
done

central_count=$(docker exec "$target_db" psql -U postgres -d berkahpos_central -Atc "SELECT count(*) FROM tenants WHERE id IN ('tenant_a_synthetic','tenant_b_synthetic')")
a_count=$(docker exec "$target_db" psql -U postgres -d berkahpos_tenant_a -Atc "SELECT count(*) FROM products WHERE id='DRILL-A'")
b_cross_count=$(docker exec "$target_db" psql -U postgres -d berkahpos_tenant_a -Atc "SELECT count(*) FROM products WHERE id='DRILL-B'")
b_count=$(docker exec "$target_db" psql -U postgres -d berkahpos_tenant_b -Atc "SELECT count(*) FROM products WHERE id='DRILL-B'")
a_cross_count=$(docker exec "$target_db" psql -U postgres -d berkahpos_tenant_b -Atc "SELECT count(*) FROM products WHERE id='DRILL-A'")
[ "$central_count" = "2" ] && [ "$a_count" = "1" ] && [ "$b_count" = "1" ] && [ "$b_cross_count" = "0" ] && [ "$a_cross_count" = "0" ] || {
  echo "FAIL: synthetic central/tenant row-count or tenant marker validation failed" >&2; exit 1;
}
for spec in "central:berkahpos_central" "tenant:berkahpos_tenant_a" "tenant:berkahpos_tenant_b"; do
  connection=$(printf '%s' "$spec" | cut -d: -f1)
  db=$(printf '%s' "$spec" | cut -d: -f2-)
  status_file="$work/migration-$db.txt"
  if [ "$connection" = "central" ]; then
    docker run --rm --network "$network" -e APP_ENV=testing -e APP_KEY=base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
      -e DB_CONNECTION=central -e CENTRAL_DB_HOST="$target_db" -e CENTRAL_DB_PORT=5432 \
      -e CENTRAL_DB_DATABASE=berkahpos_central -e CENTRAL_DB_USERNAME=postgres -e CENTRAL_DB_PASSWORD="$db_password" \
      -e CENTRAL_DB_SSLMODE=disable "$app_image" php artisan migrate:status --database=central --path=database/migrations/central > "$status_file"
  else
    docker run --rm --network "$network" -e APP_ENV=testing -e APP_KEY=base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
      -e DB_CONNECTION=central -e CENTRAL_DB_HOST="$target_db" -e CENTRAL_DB_PORT=5432 \
      -e CENTRAL_DB_DATABASE=berkahpos_central -e CENTRAL_DB_USERNAME=postgres -e CENTRAL_DB_PASSWORD="$db_password" \
      -e CENTRAL_DB_SSLMODE=disable -e TENANT_DB_HOST="$target_db" -e TENANT_DB_PORT=5432 \
      -e TENANT_DB_DATABASE="$db" -e TENANT_DB_USERNAME=postgres -e TENANT_DB_PASSWORD="$db_password" \
      -e TENANT_DB_SSLMODE=disable "$app_image" php artisan migrate:status --database=tenant --path=database/migrations/tenant > "$status_file"
  fi
  if grep -Eq '\| No[[:space:]]+\|' "$status_file"; then
    echo "FAIL: pending migration detected after restore for a synthetic DB" >&2; exit 1
  fi
done

mkdir -p "$work/restore-files"
cp "$work/files/tenant-a.txt" "$work/restore-files/tenant-a.txt"
cp "$work/files/tenant-b.txt" "$work/restore-files/tenant-b.txt"
cp "$work/synthetic-key.restored" "$work/restore-files/synthetic-key.txt"
cmp "$work/files/tenant-a.txt" "$work/restore-files/tenant-a.txt"
cmp "$work/files/tenant-b.txt" "$work/restore-files/tenant-b.txt"
cmp "$work/synthetic-key.txt" "$work/restore-files/synthetic-key.txt"

finish=$(date +%s)
duration=$((finish-started))
pg_version=$(docker exec "$target_db" psql -U postgres -d postgres -Atc 'SHOW server_version')
pg_image_id=$(docker image inspect --format '{{.Id}}' postgres:17)
file_a_sha=$(sha256sum "$work/restore-files/tenant-a.txt" | awk '{print $1}')
file_b_sha=$(sha256sum "$work/restore-files/tenant-b.txt" | awk '{print $1}')
key_sha=$(sha256sum "$work/restore-files/synthetic-key.txt" | awk '{print $1}')
printf '{"status":"PASS","scope":"synthetic disposable data only","sha":"%s","postgres_version":"%s","postgres_image_id":"%s","duration_seconds":%s,"central_synthetic_tenants":%s,"tenant_a_marker_rows":%s,"tenant_b_marker_rows":%s,"cross_tenant_a_to_b_marker_rows":%s,"cross_tenant_b_to_a_marker_rows":%s,"file_a_sha256":"%s","file_b_sha256":"%s","synthetic_key_sha256":"%s","production_backup_used":false,"off_host_provider_tested":false,"pitr_tested":false,"real_vault_tested":false}\n' \
  "$GITHUB_SHA" "$pg_version" "$pg_image_id" "$duration" "$central_count" "$a_count" "$b_count" "$b_cross_count" "$a_cross_count" "$file_a_sha" "$file_b_sha" "$key_sha" > "$ARTIFACT_DIR/result.json"
cp "$work/file-checksums.txt" "$ARTIFACT_DIR/synthetic-file-checksums.txt"
sha256sum "$ARTIFACT_DIR/result.json" "$ARTIFACT_DIR/synthetic-file-checksums.txt" > "$ARTIFACT_DIR/artifact-checksums.txt"
echo "PASS: synthetic PostgreSQL 17 central + two-tenant dump/encrypt/restore and synthetic file/key integrity checks completed; no production or off-host provider was used."
