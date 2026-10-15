#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
need() { command -v "$1" >/dev/null 2>&1 || { printf 'ERROR: required command unavailable: %s\n' "$1" >&2; exit 2; }; }
for command in mariadb mariadb-dump age rclone sha256sum awk diff sort stat date tr; do need "$command"; done
: "${MYSQL_CLIENT_CNF:?Set MYSQL_CLIENT_CNF to a mode-0600 backup option file}"
: "${AGE_RECIPIENTS_FILE:?Set AGE_RECIPIENTS_FILE to approved age recipient keys}"
: "${RCLONE_REMOTE:?Set RCLONE_REMOTE to an off-host rclone remote:path}"
CENTRAL_DB="${BACKUP_CENTRAL_DB:-berkahpos_central}"
[[ -r "$MYSQL_CLIENT_CNF" && -r "$AGE_RECIPIENTS_FILE" ]] || { echo "ERROR: backup option/recipient file unreadable" >&2; exit 2; }
mode="$(stat -c '%a' "$MYSQL_CLIENT_CNF")"
(( (8#$mode & 077) == 0 )) || { echo "ERROR: MYSQL_CLIENT_CNF must be mode 0600 or stricter" >&2; exit 2; }
[[ "$RCLONE_REMOTE" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*:.+ ]] || { echo "ERROR: local path is not accepted; configure a named rclone remote:path" >&2; exit 2; }
[[ "$CENTRAL_DB" =~ ^[A-Za-z0-9_]+$ ]] || { echo "ERROR: invalid central database identifier" >&2; exit 2; }
sql() { mariadb --defaults-extra-file="$MYSQL_CLIENT_CNF" --batch --skip-column-names "$@"; }
dump() { mariadb-dump --defaults-extra-file="$MYSQL_CLIENT_CNF" "$@"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

central_exists="$(sql -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$CENTRAL_DB'")"
[[ "$central_exists" == "$CENTRAL_DB" ]] || fail "central database is missing"
registry_raw="$(sql -e "SELECT tenancy_db_name FROM $CENTRAL_DB.tenants WHERE tenancy_db_name IS NOT NULL ORDER BY tenancy_db_name")"
mapfile -t expected < <(printf '%s\n' "$registry_raw" | awk 'NF')
for database in "${expected[@]}"; do
  [[ "$database" =~ ^berkahpos_t_[0-9abcdefghjkmnpqrstvwxyz]{26}$ ]] || fail "registry has non-canonical tenant DB name: $database"
done
catalog_raw="$(sql -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME REGEXP '^berkahpos_t_[0-9abcdefghjkmnpqrstvwxyz]{26}$' ORDER BY SCHEMA_NAME")"
mapfile -t catalog < <(printf '%s\n' "$catalog_raw" | awk 'NF')
diff -u <(printf '%s\n' "${expected[@]}" | sort) <(printf '%s\n' "${catalog[@]}" | sort) \
  || fail "central registry and MariaDB tenant catalog differ; refusing partial coverage"
sql -e 'SHOW BINARY LOGS' >/dev/null || fail "MariaDB binary logging is unavailable; PITR cannot be accepted"

set_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
remote_path="${RCLONE_REMOTE%/}/${set_id}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
manifest="$work/manifest.tsv"
printf 'kind\tdatabase\tartifact\tsha256_encrypted\tbytes\n' > "$manifest"
printf '%s\n' "$CENTRAL_DB" "${expected[@]}" > "$work/databases.txt"
rclone mkdir "$remote_path"

record() {
  local kind="$1" database="$2" artifact="$3" sha bytes
  sha="$(rclone cat "$remote_path/$artifact" | sha256sum | awk '{print $1}')"
  [[ "$sha" =~ ^[a-f0-9]{64}$ ]] || fail "remote checksum read-back failed for $artifact"
  bytes="$(rclone cat "$remote_path/$artifact" | wc -c | tr -d ' ')"
  [[ "$bytes" =~ ^[0-9]+$ ]] || fail "remote size read-back failed for $artifact"
  printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$database" "$artifact" "$sha" "$bytes" >> "$manifest"
}

all_dbs=("$CENTRAL_DB" "${expected[@]}")
dump --single-transaction --master-data=2 --routines --events --triggers --hex-blob --databases "${all_dbs[@]}" \
  | gzip -1 | age -R "$AGE_RECIPIENTS_FILE" | rclone rcat "$remote_path/full.sql.gz.age" --retries 3
record full '*' full.sql.gz.age

dump --single-transaction --routines --events --triggers --hex-blob --databases "$CENTRAL_DB" \
  | gzip -1 | age -R "$AGE_RECIPIENTS_FILE" | rclone rcat "$remote_path/$CENTRAL_DB.sql.gz.age" --retries 3
record central "$CENTRAL_DB" "$CENTRAL_DB.sql.gz.age"

for database in "${expected[@]}"; do
  artifact="$database.sql.gz.age"
  dump --single-transaction --routines --events --triggers --hex-blob --databases "$database" \
    | gzip -1 | age -R "$AGE_RECIPIENTS_FILE" | rclone rcat "$remote_path/$artifact" --retries 3
  record tenant "$database" "$artifact"
done

(
  cd "$work"
  sha256sum manifest.tsv databases.txt > manifest.sha256
)
rclone copyto "$manifest" "$remote_path/manifest.tsv" --immutable
rclone copyto "$work/databases.txt" "$remote_path/databases.txt" --immutable
rclone copyto "$work/manifest.sha256" "$remote_path/manifest.sha256" --immutable
rclone cat "$remote_path/manifest.tsv" | cmp - "$manifest"
rclone cat "$remote_path/manifest.sha256" | cmp - "$work/manifest.sha256"
rclone cat "$remote_path/databases.txt" | cmp - "$work/databases.txt"
mariadb --defaults-extra-file="$MYSQL_CLIENT_CNF" -e 'FLUSH BINARY LOGS'
printf 'BACKUP_SET_ID=%s\nREMOTE_SET=%s\nDATABASES=%s\n' "$set_id" "$remote_path" "$((1 + ${#expected[@]}))"
echo "PASS: encrypted database objects and manifest were remotely read back and SHA-256 verified."
echo "PITR still requires contiguous archived binlogs and an isolated checkpoint replay."
