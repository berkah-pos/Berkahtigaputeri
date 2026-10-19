#!/usr/bin/env sh
# Fail closed for production before any Laravel web or worker process starts.
# This script never prints the value of a secret.
set -eu

# Local/test environments use explicit isolated fixtures and are not subject to
# the production-only credential policy below.
[ "${APP_ENV:-production}" = "production" ] || exit 0

fail() {
  printf 'Startup blocked: %s\n' "$1" >&2
  exit 1
}

required() {
  name="$1"
  eval "value=\${$name-}"
  [ -n "$value" ] || fail "$name is required in production"
}

reject_placeholder() {
  name="$1"
  value="$2"
  lowered="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    ''|password|postgres|local-only-change-this|change-this-local-development-password|changeme|change-me|your-password|replace-me|example|test-only|*change-this*|*local-only*|*replace-me*)
      fail "$name contains a known development placeholder"
      ;;
  esac
}

required APP_KEY
if ! php -r '
  $value = getenv("APP_KEY");
  $raw = is_string($value) && strncmp($value, "base64:", 7) === 0
      ? base64_decode(substr($value, 7), true)
      : $value;
  if (!is_string($raw) || strlen($raw) !== 32 || count(count_chars($raw, 1)) < 8) {
      exit(1);
  }
' >/dev/null 2>&1; then
  fail 'APP_KEY must be a valid high-entropy 32-byte key'
fi

case "${APP_DEBUG:-false}" in
  true|TRUE|True|1|yes|YES|on|ON) fail 'APP_DEBUG must be false in production' ;;
esac

required APP_URL
case "${APP_URL}" in
  https://*) ;;
  *) fail 'APP_URL must use HTTPS in production' ;;
esac

case "${SESSION_SECURE_COOKIE:-false}" in
  true|TRUE|True|1|yes|YES|on|ON) ;;
  *) fail 'SESSION_SECURE_COOKIE must be enabled in production' ;;
esac

session_lifetime="${SESSION_LIFETIME:-120}"
case "$session_lifetime" in
  ''|*[!0-9]*) fail 'SESSION_LIFETIME must be an integer from 1 to 60 minutes' ;;
esac
[ "$session_lifetime" -ge 1 ] 2>/dev/null && [ "$session_lifetime" -le 60 ] 2>/dev/null   || fail 'SESSION_LIFETIME must be an integer from 1 to 60 minutes'

for name in CENTRAL_DB_HOST CENTRAL_DB_PORT CENTRAL_DB_DATABASE CENTRAL_DB_USERNAME CENTRAL_DB_PASSWORD; do
  required "$name"
done

case "$(printf '%s' "$CENTRAL_DB_USERNAME" | tr '[:upper:]' '[:lower:]')" in
  postgres|root|admin|superuser)
    fail 'central runtime DB username must not be a cluster/root/admin account'
    ;;
esac
reject_placeholder CENTRAL_DB_PASSWORD "$CENTRAL_DB_PASSWORD"

case "${MAIL_MAILER:-log}" in
  log|array)
    fail 'MAIL_MAILER must not log authentication recovery messages in production'
    ;;
  smtp)
    for name in MAIL_HOST MAIL_PORT MAIL_USERNAME MAIL_PASSWORD MAIL_FROM_ADDRESS; do
      required "$name"
    done
    reject_placeholder MAIL_PASSWORD "$MAIL_PASSWORD"
    ;;
esac

exit 0
