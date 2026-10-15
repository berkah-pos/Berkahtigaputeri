#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
need() { command -v "$1" >/dev/null 2>&1 || { printf 'ERROR: required command unavailable: %s\n' "$1" >&2; exit 2; }; }
for command in age sha256sum gzip awk stat; do need "$command"; done
: "${BACKUP_SET_DIR:?Set BACKUP_SET_DIR to a complete downloaded encrypted set}"
: "${AGE_IDENTITY_FILE:?Set AGE_IDENTITY_FILE to a recovered private age identity}"
[[ -d "$BACKUP_SET_DIR" && -r "$AGE_IDENTITY_FILE" ]] || { echo "ERROR: set or decryption identity unavailable" >&2; exit 2; }
[[ -f "$BACKUP_SET_DIR/manifest.tsv" && -f "$BACKUP_SET_DIR/manifest.sha256" && -f "$BACKUP_SET_DIR/databases.txt" ]] || { echo "ERROR: final backup manifest missing" >&2; exit 1; }
(
  cd "$BACKUP_SET_DIR"
  sha256sum -c manifest.sha256
)
count=0
while IFS=$'\t' read -r kind database artifact expected_sha expected_bytes; do
  [[ "$kind" == "kind" ]] && continue
  [[ -n "$artifact" && "$artifact" != */* ]] || { echo "ERROR: unsafe artifact path in manifest" >&2; exit 1; }
  path="$BACKUP_SET_DIR/$artifact"
  [[ -r "$path" ]] || { echo "ERROR: encrypted artifact missing: $artifact" >&2; exit 1; }
  actual_sha="$(sha256sum "$path" | awk '{print $1}')"
  [[ "$actual_sha" == "$expected_sha" ]] || { echo "ERROR: SHA-256 mismatch: $artifact" >&2; exit 1; }
  actual_bytes="$(stat -c %s "$path")"
  [[ "$actual_bytes" == "$expected_bytes" ]] || { echo "ERROR: byte count mismatch: $artifact" >&2; exit 1; }
  case "$artifact" in
    *.sql.gz.age) age -d -i "$AGE_IDENTITY_FILE" "$path" | gzip -t ;;
    *) echo "ERROR: unexpected artifact extension in database manifest: $artifact" >&2; exit 1 ;;
  esac
  count=$((count + 1))
  printf 'VERIFIED %s sha256=%s bytes=%s\n' "$artifact" "$actual_sha" "$actual_bytes"
done < "$BACKUP_SET_DIR/manifest.tsv"
(( count > 0 )) || { echo "ERROR: no database objects in manifest" >&2; exit 1; }
echo "PASS: $count encrypted SQL objects passed ciphertext SHA-256, age authentication and gzip integrity."
echo "PITR binlogs, key recovery and database restore are separate checks."
