#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
need() { command -v "$1" >/dev/null 2>&1 || { printf 'ERROR: required command unavailable: %s\n' "$1" >&2; exit 2; }; }
for command in age sha256sum awk stat rclone tr; do need "$command"; done
: "${APP_KEY_FILE:?Set APP_KEY_FILE to recovered APP_KEY material without printing it}"
: "${EXPECTED_APP_KEY_SHA256:?Set expected APP_KEY fingerprint from the vault}"
: "${AGE_IDENTITY_FILE:?Set AGE_IDENTITY_FILE to recovered private age identity}"
: "${AGE_KEY_CHECK_OBJECT:?Set AGE_KEY_CHECK_OBJECT to the encrypted nonsecret sentinel}"
: "${EXPECTED_AGE_SENTINEL_SHA256:?Set sentinel SHA-256 from the vault}"
: "${FILE_PROBE_RCLONE_PATH:?Set FILE_PROBE_RCLONE_PATH to a known non-sensitive stored object}"
: "${FILE_PROBE_SHA256:?Set FILE_PROBE_SHA256 to the recorded object fingerprint}"
for file in "$APP_KEY_FILE" "$AGE_IDENTITY_FILE"; do
  [[ -r "$file" ]] || { echo "ERROR: recovery material unreadable" >&2; exit 1; }
  mode="$(stat -c '%a' "$file")"
  (( (8#$mode & 077) == 0 )) || { echo "ERROR: recovery key permissions are too broad" >&2; exit 1; }
done
key_value="$(tr -d '\r\n' < "$APP_KEY_FILE")"
[[ -n "$key_value" ]] || { unset key_value; echo "ERROR: APP_KEY file empty" >&2; exit 1; }
app_hash="$(printf '%s' "$key_value" | sha256sum | awk '{print $1}')"
unset key_value
[[ "$app_hash" == "$EXPECTED_APP_KEY_SHA256" ]] || { echo "FAIL: APP_KEY fingerprint mismatch" >&2; exit 1; }
echo "PASS: recovered APP_KEY fingerprint matched; secret value was not printed."
sentinel_hash="$(age -d -i "$AGE_IDENTITY_FILE" "$AGE_KEY_CHECK_OBJECT" | sha256sum | awk '{print $1}')"
[[ "$sentinel_hash" == "$EXPECTED_AGE_SENTINEL_SHA256" ]] || { echo "FAIL: age recovery identity check failed" >&2; exit 1; }
echo "PASS: age private identity decrypted the key-check sentinel and hash matched."
probe_hash="$(rclone cat "$FILE_PROBE_RCLONE_PATH" | sha256sum | awk '{print $1}')"
[[ "$probe_hash" == "$FILE_PROBE_SHA256" ]] || { echo "FAIL: private object file recovery checksum mismatch" >&2; exit 1; }
echo "PASS: private file/object probe checksum matched."
echo "PASS: key/file recovery checks completed. Database restore and production cutover remain separate gates."
