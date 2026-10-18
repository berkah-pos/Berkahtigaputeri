#!/usr/bin/env bash
set -euo pipefail

# Isolated, synthetic PostgreSQL 17 recovery exercise.
# No published ports; every database container uses --network none.
# This proves the scripted fixture path only, not off-host storage/vault or
# production recovery. Passwords and payloads below are disposable test data.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
source="berkah-pg-restore-source-${GITHUB_RUN_ID:-local}-${RANDOM}"
target="berkah-pg-restore-target-${GITHUB_RUN_ID:-local}-${RANDOM}"
pitr="berkah-pg-pitr-source-${GITHUB_RUN_ID:-local}-${RANDOM}"
pitr_target="berkah-pg-pitr-target-${GITHUB_RUN_ID:-local}-${RANDOM}"
started_epoch="$(date +%s)"

cleanup() {
  docker rm -f "$source" "$target" "$pitr" "$pitr_target" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
wait_pg() {
  local name="$1" attempts=0
  until docker exec "$name" pg_isready -U postgres -d postgres >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 60 ] || [ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)" != "true" ]; then
      docker logs "$name" >&2 || true
      fail "PostgreSQL did not become ready: $name"
    fi
    sleep 2
  done
}
exec_sql() {
  local name="$1" db="$2" sql="$3"
  docker exec -i "$name" psql -U postgres -d "$db" -X -v ON_ERROR_STOP=1 < "$sql"
}
exec_query() {
  local name="$1" db="$2" query="$3"
  docker exec "$name" psql -U postgres -d "$db" -X -Atqc "$query"
}
create_db() {
  local name="$1" db="$2"
  docker exec "$name" psql -U postgres -d postgres -X -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$db\"" >/dev/null
}
dump_db() {
  local name="$1" db="$2" dest="$3"
  docker exec "$name" pg_dump -U postgres --format=custom --no-owner --no-acl --dbname="$db" > "$dest"
  test -s "$dest" || fail "empty logical archive for $db"
  docker exec -i "$name" pg_restore --list < "$dest" >/dev/null
}
restore_db() {
  local name="$1" db="$2" archive="$3"
  create_db "$name" "$db"
  docker exec -i "$name" pg_restore -U postgres --dbname="$db" --no-owner --no-acl < "$archive"
}

mkdir -p "$work/backups" "$work/source-objects" "$work/recovered-objects" "$work/wal"
chmod 0777 "$work/wal"
printf 'SYNTHETIC RECEIPT A: sale-001; amount_cents=1250\n' > "$work/source-objects/receipt-a.txt"
printf 'SYNTHETIC RECEIPT B: sale-002; amount_cents=2750\n' > "$work/source-objects/receipt-b.txt"
printf 'SYNTHETIC RECOVERY KEY ONLY - NEVER FOR REAL ENCRYPTION\n' > "$work/synthetic-recovery-key.txt"
payload_a_sha="$(sha256sum "$work/source-objects/receipt-a.txt" | cut -d' ' -f1)"
payload_b_sha="$(sha256sum "$work/source-objects/receipt-b.txt" | cut -d' ' -f1)"
key_sha="$(sha256sum "$work/synthetic-recovery-key.txt" | cut -d' ' -f1)"

# Logical backup and restore test: central DB + two separate tenant DBs.
docker run -d --name "$source" --network none \
  -e POSTGRES_DB=postgres -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=synthetic-source-only \
  postgres:17 >/dev/null
wait_pg "$source"

central="berkahpos_central_recovery_ci"
tenant_a="berkahpos_tenant_a_recovery_ci"
tenant_b="berkahpos_tenant_b_recovery_ci"
create_db "$source" "$central"
create_db "$source" "$tenant_a"
create_db "$source" "$tenant_b"

cat > "$work/central.sql" <<SQL
CREATE TABLE tenant_registry (tenant_id text PRIMARY KEY, db_name text UNIQUE NOT NULL);
INSERT INTO tenant_registry VALUES
  ('SYNTH_TENANT_A', '$tenant_a'),
  ('SYNTH_TENANT_B', '$tenant_b');
CREATE TABLE object_refs (
  object_ref text PRIMARY KEY,
  sha256 text NOT NULL,
  key_version_ref text NOT NULL
);
INSERT INTO object_refs VALUES
  ('objects/receipt-a.txt', '$payload_a_sha', 'synthetic-recovery-key-v1'),
  ('objects/receipt-b.txt', '$payload_b_sha', 'synthetic-recovery-key-v1');
SQL
exec_sql "$source" "$central" "$work/central.sql"

for item in "A|$tenant_a|SYNTH_TENANT_A|1250" "B|$tenant_b|SYNTH_TENANT_B|2750"; do
  IFS='|' read -r suffix db tenant_id amount <<< "$item"
  cat > "$work/tenant-$suffix.sql" <<SQL
CREATE TABLE tenant_probe (id bigint PRIMARY KEY, tenant_id text NOT NULL, payload text NOT NULL);
INSERT INTO tenant_probe VALUES (1, '$tenant_id', 'sentinel-$suffix');
CREATE TABLE journal_entries (entry_id text PRIMARY KEY, posted boolean NOT NULL);
CREATE TABLE journal_lines (
  entry_id text NOT NULL REFERENCES journal_entries(entry_id),
  line_no integer NOT NULL,
  debit_cents bigint NOT NULL DEFAULT 0 CHECK (debit_cents >= 0),
  credit_cents bigint NOT NULL DEFAULT 0 CHECK (credit_cents >= 0),
  PRIMARY KEY (entry_id, line_no),
  CHECK (NOT (debit_cents > 0 AND credit_cents > 0))
);
INSERT INTO journal_entries VALUES ('SYNTH-JOURNAL-$suffix', true);
INSERT INTO journal_lines VALUES
  ('SYNTH-JOURNAL-$suffix', 1, $amount, 0),
  ('SYNTH-JOURNAL-$suffix', 2, 0, $amount);
SQL
  exec_sql "$source" "$db" "$work/tenant-$suffix.sql"
done

dump_db "$source" "$central" "$work/backups/central.dump"
dump_db "$source" "$tenant_a" "$work/backups/tenant-a.dump"
dump_db "$source" "$tenant_b" "$work/backups/tenant-b.dump"
(
  cd "$work"
  sha256sum backups/central.dump backups/tenant-a.dump backups/tenant-b.dump \
    source-objects/receipt-a.txt source-objects/receipt-b.txt synthetic-recovery-key.txt > backup-manifest.sha256
)
cp -a "$work/source-objects/." "$work/recovered-objects/"
cp "$work/synthetic-recovery-key.txt" "$work/recovered-recovery-key.txt"
for payload in receipt-a.txt receipt-b.txt; do
  cmp "$work/source-objects/$payload" "$work/recovered-objects/$payload" || fail "object payload mismatch: $payload"
done
cmp "$work/synthetic-recovery-key.txt" "$work/recovered-recovery-key.txt" || fail "synthetic recovery-key artifact mismatch"

docker run -d --name "$target" --network none \
  -e POSTGRES_DB=postgres -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=synthetic-target-only \
  postgres:17 >/dev/null
wait_pg "$target"
restore_started="$(date +%s)"
restore_db "$target" "$central" "$work/backups/central.dump"
restore_db "$target" "$tenant_a" "$work/backups/tenant-a.dump"
restore_db "$target" "$tenant_b" "$work/backups/tenant-b.dump"
restore_finished="$(date +%s)"
logical_restore_seconds=$((restore_finished - restore_started))

tenant_inventory="$(exec_query "$target" "$central" "SELECT string_agg(tenant_id, ',' ORDER BY tenant_id) FROM tenant_registry")"
test "$tenant_inventory" = "SYNTH_TENANT_A,SYNTH_TENANT_B" || fail "central registry mismatch after restore"

for pair in "$tenant_a|SYNTH_TENANT_A|SYNTH-JOURNAL-A" "$tenant_b|SYNTH_TENANT_B|SYNTH-JOURNAL-B"; do
  IFS='|' read -r db expected_tenant journal_id <<< "$pair"
  actual_tenant="$(exec_query "$target" "$db" "SELECT tenant_id FROM tenant_probe WHERE id=1")"
  test "$actual_tenant" = "$expected_tenant" || fail "tenant identity mismatch in $db"
  balance="$(exec_query "$target" "$db" "SELECT (sum(debit_cents) - sum(credit_cents))::text FROM journal_lines WHERE entry_id='$journal_id'")"
  test "$balance" = "0" || fail "journal does not balance in $db"
  posted="$(exec_query "$target" "$db" "SELECT posted::text FROM journal_entries WHERE entry_id='$journal_id'")"
  test "$posted" = "true" || fail "posted journal marker missing in $db"
done

ref_a="$(exec_query "$target" "$central" "SELECT sha256 FROM object_refs WHERE object_ref='objects/receipt-a.txt'")"
ref_b="$(exec_query "$target" "$central" "SELECT sha256 FROM object_refs WHERE object_ref='objects/receipt-b.txt'")"
test "$ref_a" = "$payload_a_sha" || fail "restored metadata checksum for object A differs"
test "$ref_b" = "$payload_b_sha" || fail "restored metadata checksum for object B differs"
test "$(sha256sum "$work/recovered-objects/receipt-a.txt" | cut -d' ' -f1)" = "$ref_a" || fail "recovered object A does not match DB reference"
test "$(sha256sum "$work/recovered-objects/receipt-b.txt" | cut -d' ' -f1)" = "$ref_b" || fail "recovered object B does not match DB reference"
key_ref="$(exec_query "$target" "$central" "SELECT key_version_ref FROM object_refs LIMIT 1")"
test "$key_ref" = "synthetic-recovery-key-v1" || fail "recovery key version reference missing"
test "$(sha256sum "$work/recovered-recovery-key.txt" | cut -d' ' -f1)" = "$key_sha" || fail "synthetic recovery key checksum differs"

# Single-tenant restore goes to a new database. A second tenant remains a
# sentinel; compare its pre/post fingerprint to prove this operation left it.
sentinel_before="$(exec_query "$target" "$tenant_b" "SELECT md5(string_agg(id::text || ':' || tenant_id || ':' || payload, '|' ORDER BY id)) FROM tenant_probe")"
restore_db "$target" "berkahpos_tenant_a_single_restore_ci" "$work/backups/tenant-a.dump"
sentinel_after="$(exec_query "$target" "$tenant_b" "SELECT md5(string_agg(id::text || ':' || tenant_id || ':' || payload, '|' ORDER BY id)) FROM tenant_probe")"
test "$sentinel_before" = "$sentinel_after" || fail "single-tenant restore changed the non-target tenant sentinel"
single_restored="$(exec_query "$target" "berkahpos_tenant_a_single_restore_ci" "SELECT tenant_id FROM tenant_probe WHERE id=1")"
test "$single_restored" = "SYNTH_TENANT_A" || fail "single-tenant restore target identity mismatch"

echo "LOGICAL_RESTORE=PASS"
echo "SOURCE_DATABASES=central+2_tenant"
echo "LOGICAL_RESTORE_SECONDS=$logical_restore_seconds"
echo "SINGLE_TENANT_RESTORE=PASS"
echo "SENTINEL_UNCHANGED=PASS"
echo "OBJECT_PAYLOAD_CHECKSUMS=PASS"
echo "SYNTHETIC_RECOVERY_KEY_ARTIFACT_CHECKSUM=PASS"
echo "RESTORE_MANIFEST_BEGIN"
cat "$work/backup-manifest.sha256"
echo "RESTORE_MANIFEST_END"

# Separate PITR test. Configure WAL archiving on a second disposable PG17
# instance, take a physical base backup, record a target point, commit a
# post-target marker, then replay archived WAL to the target timestamp.
pitr_wal="$work/wal"
docker run -d --name "$pitr" --network none \
  -e POSTGRES_DB=postgres -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=synthetic-pitr-only \
  -v "$pitr_wal:/wal" postgres:17 \
  -c wal_level=replica -c archive_mode=on -c archive_timeout=1s \
  -c "archive_command=test ! -f /wal/%f && cp %p /wal/%f" >/dev/null
wait_pg "$pitr"
archive_mode="$(exec_query "$pitr" postgres "SHOW archive_mode")"
test "$archive_mode" = "on" || fail "PITR source archive_mode did not enable"

pitr_db="pitr_synthetic_ci"
create_db "$pitr" "$pitr_db"
docker exec "$pitr" psql -U postgres -d "$pitr_db" -X -v ON_ERROR_STOP=1 \
  -c "CREATE TABLE pitr_markers (marker text PRIMARY KEY)" \
  -c "INSERT INTO pitr_markers VALUES ('before-base-backup')" >/dev/null
docker exec "$pitr" sh -lc 'rm -rf /tmp/pitr-base && mkdir /tmp/pitr-base'
docker exec -e PGPASSWORD=synthetic-pitr-only "$pitr" \
  pg_basebackup -h 127.0.0.1 -U postgres -D /tmp/pitr-base -Fp -X stream -c fast >/dev/null

docker exec "$pitr" psql -U postgres -d "$pitr_db" -X -v ON_ERROR_STOP=1 \
  -c "INSERT INTO pitr_markers VALUES ('before-target')" >/dev/null
target_time="$(exec_query "$pitr" "$pitr_db" "SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US') || ' UTC'")"
sleep 2
docker exec "$pitr" psql -U postgres -d "$pitr_db" -X -v ON_ERROR_STOP=1 \
  -c "INSERT INTO pitr_markers VALUES ('after-target')" >/dev/null
docker exec "$pitr" psql -U postgres -d postgres -X -v ON_ERROR_STOP=1 -c "SELECT pg_switch_wal()" >/dev/null
sleep 4

archive_count="$(find "$pitr_wal" -maxdepth 1 -type f | wc -l | tr -d ' ')"
test "$archive_count" -ge 1 || { docker logs "$pitr" >&2 || true; fail "no WAL segments archived"; }
docker cp "$pitr:/tmp/pitr-base" "$work/pitr-base"
test -f "$work/pitr-base/PG_VERSION" || fail "physical base backup missing PG_VERSION"

# Use the base-backup files as PGDATA in a separate isolated recovery
# container; the only mounted archive source is the local synthetic WAL dir.
docker create --name "$pitr_target" --network none \
  -e PGDATA=/tmp/pitr-base -e RECOVERY_TARGET_TIME="$target_time" \
  -v "$pitr_wal:/tmp/wal:ro" --entrypoint /bin/bash postgres:17 \
  -lc 'set -e; chown -R postgres:postgres "$PGDATA"; touch "$PGDATA/recovery.signal"; exec gosu postgres postgres -D "$PGDATA" -c "restore_command=cp /tmp/wal/%f %p" -c "recovery_target_time=$RECOVERY_TARGET_TIME" -c "recovery_target_inclusive=on" -c "recovery_target_action=promote" -c "archive_mode=off" -c "archive_command=" ' >/dev/null
docker cp "$work/pitr-base/." "$pitr_target:/tmp/pitr-base/"
docker start "$pitr_target" >/dev/null

pitr_ready=false
for attempt in $(seq 1 60); do
  if docker exec "$pitr_target" pg_isready -U postgres -d "$pitr_db" >/dev/null 2>&1; then
    in_recovery="$(exec_query "$pitr_target" "$pitr_db" "SELECT pg_is_in_recovery()::text" 2>/dev/null || true)"
    if [ "$in_recovery" = "false" ]; then pitr_ready=true; break; fi
  fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$pitr_target" 2>/dev/null || true)" != "true" ]; then
    docker logs "$pitr_target" >&2 || true
    fail "PITR recovery container exited"
  fi
  sleep 2
done
if [ "$pitr_ready" != "true" ]; then docker logs "$pitr_target" >&2 || true; fail "PITR did not complete/promote"; fi

before_present="$(exec_query "$pitr_target" "$pitr_db" "SELECT count(*) FROM pitr_markers WHERE marker='before-target'")"
after_present="$(exec_query "$pitr_target" "$pitr_db" "SELECT count(*) FROM pitr_markers WHERE marker='after-target'")"
test "$before_present" = "1" || fail "PITR omitted a committed marker before target time"
test "$after_present" = "0" || fail "PITR retained a marker committed after target time"
recovered_time="$(exec_query "$pitr_target" "$pitr_db" "SELECT pg_last_xact_replay_timestamp()::text")"
elapsed=$(( $(date +%s) - started_epoch ))

echo "PITR=PASS"
echo "PITR_REQUESTED_TARGET_UTC=$target_time"
echo "PITR_ACTUAL_LAST_REPLAYED_TX=$recovered_time"
echo "PITR_ARCHIVED_WAL_SEGMENTS=$archive_count"
echo "PITR_MARKER_BOUNDARY=PASS (before-target present; after-target absent)"
echo "TOTAL_RECOVERY_TEST_SECONDS=$elapsed"
echo "SCOPE_LIMIT=synthetic disposable PostgreSQL 17 logical restore and physical base+WAL PITR only; no off-host storage, real vault, Coolify state, production or business data validated"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Synthetic PostgreSQL 17 recovery test"
    echo "- Logical restore (central + two tenants): **PASS**"
    echo "- Single-tenant restore to new DB; second-tenant sentinel unchanged: **PASS**"
    echo "- File/object payload checksum + synthetic recovery-key artifact checksum: **PASS**"
    echo "- Separate base-backup + WAL PITR marker boundary: **PASS**"
    echo "- Logical restore seconds: $logical_restore_seconds"
    echo "- Total recovery test seconds: $elapsed"
    echo "- Requested PITR UTC target: $target_time"
    echo "- Last replayed transaction timestamp: $recovered_time"
    echo "- Archived WAL segments observed: $archive_count"
    echo "- Scope limit: isolated synthetic CI only; off-host backup storage/vault, Coolify state, and production are **NOT VERIFIED**."
    echo
    echo "### SHA-256 logical backup/artifact manifest"
    echo '~~~text'
    cat "$work/backup-manifest.sha256"
    echo '~~~'
  } >> "$GITHUB_STEP_SUMMARY"
fi
