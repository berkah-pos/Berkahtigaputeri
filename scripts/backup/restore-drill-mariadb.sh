#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
need() { command -v "$1" >/dev/null 2>&1 || { printf 'ERROR: required command unavailable: %s\n' "$1" >&2; exit 2; }; }
for command in docker age gzip sha256sum awk sed grep date openssl mktemp stat find sort cut; do need "$command"; done
: "${RESTORE_CONFIRM:?Set RESTORE_CONFIRM=ISOLATED_DISPOSABLE_ONLY}"
: "${BACKUP_SET_DIR:?Set BACKUP_SET_DIR to a complete local encrypted backup set}"
: "${AGE_IDENTITY_FILE:?Set AGE_IDENTITY_FILE to the recovered private identity}"
[[ "$RESTORE_CONFIRM" == "ISOLATED_DISPOSABLE_ONLY" ]] || { echo "ERROR: isolated-disposable confirmation missing" >&2; exit 2; }
[[ -d "$BACKUP_SET_DIR" && -r "$AGE_IDENTITY_FILE" ]] || { echo "ERROR: restore inputs unavailable" >&2; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/verify-backup-set.sh"
mode="${1:-sample}"
CENTRAL_DB="${BACKUP_CENTRAL_DB:-berkahpos_central}"
MARIADB_IMAGE="${MARIADB_IMAGE:-mariadb:11.4}"
[[ "$CENTRAL_DB" =~ ^[A-Za-z0-9_]+$ ]] || { echo "ERROR: invalid central DB name" >&2; exit 2; }

manifest_artifact() {
  local kind="$1" database="$2"
  awk -F '\t' -v k="$kind" -v d="$database" 'NR > 1 && $1 == k && $2 == d {print $3; count++} END {if (count != 1) exit 1}' "$BACKUP_SET_DIR/manifest.tsv"
}
need_tenant() {
  [[ "$1" =~ ^berkahpos_t_[0-9abcdefghjkmnpqrstvwxyz]{26}$ ]] || { echo "ERROR: tenant name fails the canonical lowercase ULID contract" >&2; exit 2; }
}
work="$(mktemp -d)"
chmod 700 "$work"
container="berkahpos-restore-drill-$(date -u +%Y%m%d%H%M%S)-$$"
root_password="$(openssl rand -hex 24)"
printf '%s\n' "$root_password" > "$work/root-password"
printf '[client]\nuser=root\npassword=%s\n' "$root_password" > "$work/root.cnf"
chmod 600 "$work/root-password" "$work/root.cnf"
unset root_password
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

docker run -d --name "$container" --network none --memory 3g --cpus 1.5 \
  -e MARIADB_ROOT_PASSWORD_FILE=/run/secrets/root-password \
  -v "$work/root-password:/run/secrets/root-password:ro" \
  -v "$work/root.cnf:/run/secrets/root.cnf:ro" "$MARIADB_IMAGE" >/dev/null
ready=false
for _ in $(seq 1 90); do
  if docker exec "$container" mariadb-admin --defaults-extra-file=/run/secrets/root.cnf ping --silent >/dev/null 2>&1; then ready=true; break; fi
  sleep 2
done
[[ "$ready" == true ]] || { docker logs "$container"; echo "ERROR: disposable restore MariaDB did not start" >&2; exit 1; }
started="$(date -u +%FT%TZ)"
printf 'RESTORE_DRILL_START_UTC=%s\nRESTORE_MODE=%s\nRESTORE_CONTAINER=%s\nMARIADB_IMAGE=%s\nNETWORK=none\n' "$started" "$mode" "$container" "$MARIADB_IMAGE"

target_sql() {
  docker exec "$container" mariadb --defaults-extra-file=/run/secrets/root.cnf --batch --skip-column-names "$@"
}
import_artifact() {
  local artifact="$1"
  [[ -r "$BACKUP_SET_DIR/$artifact" ]] || { echo "ERROR: encrypted dump missing: $artifact" >&2; exit 1; }
  age -d -i "$AGE_IDENTITY_FILE" "$BACKUP_SET_DIR/$artifact" | gzip -dc \
    | docker exec -i "$container" mariadb --defaults-extra-file=/run/secrets/root.cnf
}
assert_database() {
  local database="$1" count
  [[ "$database" =~ ^[A-Za-z0-9_]+$ ]] || { echo "ERROR: unsafe database identifier" >&2; exit 1; }
  count="$(target_sql -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$database'")"
  [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]] || { echo "ERROR: database missing/no tables after restore: $database" >&2; exit 1; }
  printf 'RESTORED_DB=%s TABLE_COUNT=%s\n' "$database" "$count"
}

case "$mode" in
  full)
    artifact="$(manifest_artifact full '*')"
    import_artifact "$artifact"
    assert_database "$CENTRAL_DB"
    while IFS=$'\t' read -r kind database artifact _; do
      [[ "$kind" == "tenant" ]] && assert_database "$database"
    done < "$BACKUP_SET_DIR/manifest.tsv"
    ;;
  sample)
    [[ "$#" -eq 3 ]] || { echo "Usage: $0 sample TENANT_DB_1 TENANT_DB_2" >&2; exit 2; }
    tenant1="$2"; tenant2="$3"
    need_tenant "$tenant1"; need_tenant "$tenant2"
    [[ "$tenant1" != "$tenant2" ]] || { echo "ERROR: select two different tenant databases" >&2; exit 2; }
    import_artifact "$(manifest_artifact central "$CENTRAL_DB")"
    import_artifact "$(manifest_artifact tenant "$tenant1")"
    import_artifact "$(manifest_artifact tenant "$tenant2")"
    assert_database "$CENTRAL_DB"
    assert_database "$tenant1"
    assert_database "$tenant2"
    other="$(target_sql -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME REGEXP '^berkahpos_t_[0-9abcdefghjkmnpqrstvwxyz]{26}$' AND SCHEMA_NAME NOT IN ('$tenant1','$tenant2')")"
    [[ "$other" == "0" ]] || { echo "ERROR: sample restore unexpectedly contains an unselected tenant DB" >&2; exit 1; }
    echo "PASS: central plus exactly two selected tenant databases were restored."
    ;;
  single-tenant)
    [[ "$#" -eq 2 ]] || { echo "Usage: $0 single-tenant TENANT_DB" >&2; exit 2; }
    tenant="$2"; need_tenant "$tenant"
    import_artifact "$(manifest_artifact tenant "$tenant")"
    assert_database "$tenant"
    others="$(target_sql -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME REGEXP '^berkahpos_t_[0-9abcdefghjkmnpqrstvwxyz]{26}$' AND SCHEMA_NAME <> '$tenant'")"
    [[ "$others" == "0" ]] || { echo "ERROR: isolated tenant restore includes another tenant database" >&2; exit 1; }
    echo "PASS: one selected tenant database restored with no other tenant DB."
    ;;
  pitr)
    : "${PITR_TARGET_UTC:?Set PITR_TARGET_UTC to YYYY-MM-DD HH:MM:SS in UTC}"
    : "${BINLOG_ARCHIVE_DIR:?Set BINLOG_ARCHIVE_DIR to locally downloaded encrypted closed binlogs}"
    : "${PITR_ASSERT_SQL_FILE:?Set PITR_ASSERT_SQL_FILE to SQL returning exactly PASS}"
    [[ "$PITR_TARGET_UTC" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] || { echo "ERROR: invalid PITR target time" >&2; exit 2; }
    [[ -d "$BINLOG_ARCHIVE_DIR" && -r "$PITR_ASSERT_SQL_FILE" ]] || { echo "ERROR: PITR binlog folder or checkpoint SQL unavailable" >&2; exit 2; }
    artifact="$(manifest_artifact full '*')"
    coordinate="$(age -d -i "$AGE_IDENTITY_FILE" "$BACKUP_SET_DIR/$artifact" | gzip -dc | grep -m1 'CHANGE MASTER TO MASTER_LOG_FILE=')"
    start_file="$(printf '%s\n' "$coordinate" | sed -E "s/.*MASTER_LOG_FILE='([^']+)'.*/\1/")"
    start_pos="$(printf '%s\n' "$coordinate" | grep -oE 'MASTER_LOG_POS=[0-9]+' | cut -d= -f2)"
    [[ "$start_file" =~ ^[A-Za-z0-9_.-]+$ && "$start_pos" =~ ^[0-9]+$ ]] || { echo "ERROR: snapshot binlog coordinate could not be parsed" >&2; exit 1; }
    import_artifact "$artifact"
    mkdir -p "$work/binlogs"
    for encrypted in "$BINLOG_ARCHIVE_DIR"/*.age; do
      [[ -f "$encrypted" ]] || continue
      name="$(basename "$encrypted" .age)"
      [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: unsafe archived binlog filename" >&2; exit 1; }
      age -d -i "$AGE_IDENTITY_FILE" "$encrypted" > "$work/binlogs/$name"
      expected_plain="$(awk -F '\t' -v n="$name" '$1 == n {print $2}' "$encrypted.sha256" 2>/dev/null || true)"
      actual_plain="$(sha256sum "$work/binlogs/$name" | awk '{print $1}')"
      [[ -z "$expected_plain" || "$actual_plain" == "$expected_plain" ]] || { echo "ERROR: plaintext binlog checksum mismatch: $name" >&2; exit 1; }
    done
    [[ -s "$work/binlogs/$start_file" ]] || { echo "ERROR: snapshot starting binlog is missing" >&2; exit 1; }
    mapfile -t logs < <(find "$work/binlogs" -maxdepth 1 -type f -name 'mariadb-bin.*' -printf '%f\n' | sort)
    sequence=false
    replay=()
    last_number=''
    start_seen=false
    for name in "${logs[@]}"; do
      if [[ "$name" == "$start_file" ]]; then start_seen=true; fi
      [[ "$start_seen" == true ]] || continue
      number="${name##*.}"
      if [[ -n "$last_number" ]]; then
        expected_number=$((10#$last_number + 1))
        [[ "$((10#$number))" -eq "$expected_number" ]] || { echo "ERROR: archived binlog sequence has a gap after $last_number" >&2; exit 1; }
      fi
      replay+=("$work/binlogs/$name")
      last_number="$number"
    done
    (( ${#replay[@]} > 0 )) || { echo "ERROR: no binary logs available from the snapshot coordinate" >&2; exit 1; }
    docker_paths=()
    for file in "${replay[@]}"; do docker_paths+=("/binlogs/$(basename "$file")"); done
    TZ=UTC docker run --rm --network none -v "$work/binlogs:/binlogs:ro" "$MARIADB_IMAGE" \
      mariadb-binlog --start-position="$start_pos" --stop-datetime="$PITR_TARGET_UTC" "${docker_paths[@]}" \
      | docker exec -i "$container" mariadb --defaults-extra-file=/run/secrets/root.cnf
    checkpoint="$(docker exec -i "$container" mariadb --defaults-extra-file=/run/secrets/root.cnf --batch --skip-column-names < "$PITR_ASSERT_SQL_FILE")"
    [[ "$checkpoint" == "PASS" ]] || { echo "ERROR: PITR business checkpoint did not return exactly PASS" >&2; exit 1; }
    echo "PASS: PITR binary-log replay checkpoint returned PASS."
    assert_database "$CENTRAL_DB"
    ;;
  *)
    echo "Usage: $0 {full|sample TENANT_DB_1 TENANT_DB_2|single-tenant TENANT_DB|pitr}" >&2
    exit 2
    ;;
esac
ended="$(date -u +%FT%TZ)"
printf 'RESTORE_DRILL_END_UTC=%s\n' "$ended"
echo "PASS: disposable restore checks completed. Review logs, duration, host metrics and business checkpoint before classifying DG-4."
