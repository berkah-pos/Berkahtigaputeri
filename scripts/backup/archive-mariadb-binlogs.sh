#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
need() { command -v "$1" >/dev/null 2>&1 || { printf 'ERROR: required command unavailable: %s\n' "$1" >&2; exit 2; }; }
for command in mariadb mariadb-binlog age rclone sha256sum awk stat date mktemp tr; do need "$command"; done
: "${MYSQL_CLIENT_CNF:?Set MYSQL_CLIENT_CNF to a protected backup client option file}"
: "${AGE_RECIPIENTS_FILE:?Set AGE_RECIPIENTS_FILE to approved public recipients}"
: "${RCLONE_REMOTE:?Set RCLONE_REMOTE to a named remote:path}"
[[ -r "$MYSQL_CLIENT_CNF" && -r "$AGE_RECIPIENTS_FILE" ]] || { echo "ERROR: protected input missing" >&2; exit 2; }
mode="$(stat -c '%a' "$MYSQL_CLIENT_CNF")"
(( (8#$mode & 077) == 0 )) || { echo "ERROR: MYSQL_CLIENT_CNF must be mode 0600 or stricter" >&2; exit 2; }
[[ "$RCLONE_REMOTE" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*:.+ ]] || { echo "ERROR: named rclone remote:path required" >&2; exit 2; }

logs="$(mariadb --defaults-extra-file="$MYSQL_CLIENT_CNF" --batch --skip-column-names -e 'SHOW BINARY LOGS')"
mapfile -t rows < <(printf '%s\n' "$logs" | awk 'NF')
(( ${#rows[@]} >= 1 )) || { echo "ERROR: SHOW BINARY LOGS returned no logs" >&2; exit 1; }
remote_dir="${RCLONE_REMOTE%/}/binlogs"
rclone mkdir "$remote_dir"
listing="$(rclone lsf "$remote_dir" --files-only 2>/dev/null || true)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The final SHOW BINARY LOGS entry is active and mutable; only archive closed/rotated logs.
for ((i=0; i<${#rows[@]}-1; i++)); do
  log="$(printf '%s\n' "${rows[$i]}" | awk '{print $1}')"
  [[ "$log" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: unsafe binlog filename" >&2; exit 1; }
  artifact="$log.age"
  printf '%s\n' "$listing" | grep -Fxq "$artifact" && continue
  raw="$work/$log"
  mariadb-binlog --defaults-extra-file="$MYSQL_CLIENT_CNF" --read-from-remote-server --raw --result-file="$work/" "$log"
  [[ -s "$raw" ]] || { echo "ERROR: remote binary log download empty: $log" >&2; exit 1; }
  plain_sha="$(sha256sum "$raw" | awk '{print $1}')"
  age -R "$AGE_RECIPIENTS_FILE" -o "$work/$artifact" "$raw"
  cipher_sha="$(sha256sum "$work/$artifact" | awk '{print $1}')"
  printf '%s\t%s\t%s\n' "$log" "$plain_sha" "$cipher_sha" > "$work/$artifact.sha256"
  rclone copyto "$work/$artifact" "$remote_dir/$artifact" --immutable
  rclone copyto "$work/$artifact.sha256" "$remote_dir/$artifact.sha256" --immutable
  remote_sha="$(rclone cat "$remote_dir/$artifact" | sha256sum | awk '{print $1}')"
  [[ "$remote_sha" == "$cipher_sha" ]] || { echo "ERROR: remote binlog checksum mismatch: $log" >&2; exit 1; }
  listing="${listing}"$'\n'"$artifact"
  printf 'ARCHIVED %s encrypted_sha256=%s bytes=%s\n' "$log" "$cipher_sha" "$(stat -c %s "$work/$artifact")"
done
echo "NOTE: the active binlog is not archived by this closed-log pass. Continuous active-tail archival and target-time replay remain required before any RPO/PITR claim."
