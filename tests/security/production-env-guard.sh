#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT_DIR/docker/validate-production-env.sh"
VALID_KEY="$(php -r 'echo "base64:".base64_encode(str_repeat("0123456789abcdef", 2));')"

run_guard() {
  local -a environment=(
    "PATH=$PATH"
    "APP_ENV=production"
    "APP_KEY=$VALID_KEY"
    "APP_DEBUG=false"
    "APP_URL=https://pos.example.invalid"
    "SESSION_SECURE_COOKIE=true"
    "SESSION_LIFETIME=30"
    "CENTRAL_DB_HOST=postgres.internal"
    "CENTRAL_DB_PORT=5432"
    "CENTRAL_DB_DATABASE=central_test"
    "CENTRAL_DB_USERNAME=berkah_runtime"
    "CENTRAL_DB_PASSWORD=ci-fixture-password-482"
    "MAIL_MAILER=smtp"
    "MAIL_HOST=smtp.example.invalid"
    "MAIL_PORT=587"
    "MAIL_USERNAME=berkah-mailer"
    "MAIL_PASSWORD=ci-fixture-mail-password-482"
    "MAIL_FROM_ADDRESS=noreply@example.invalid"
  )
  local override name
  for override in "$@"; do
    name="${override%%=*}"
    local -a next=()
    for item in "${environment[@]}"; do
      [[ "${item%%=*}" == "$name" ]] || next+=("$item")
    done
    environment=("${next[@]}" "$override")
  done
  env -i "${environment[@]}" sh "$GUARD"
}

expect_pass() {
  local name="$1"
  shift
  if run_guard "$@" >/dev/null 2>&1; then
    printf 'PASS: %s\n' "$name"
  else
    printf 'FAIL: %s was unexpectedly rejected\n' "$name" >&2
    exit 1
  fi
}

expect_fail() {
  local name="$1"
  shift
  if run_guard "$@" >/dev/null 2>&1; then
    printf 'FAIL: %s was unexpectedly accepted\n' "$name" >&2
    exit 1
  else
    printf 'PASS: %s rejected\n' "$name"
  fi
}

expect_pass 'valid isolated production configuration'
expect_fail 'missing APP_KEY' 'APP_KEY='
expect_fail 'known weak APP_KEY fixture' 'APP_KEY=base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
expect_fail 'APP_DEBUG enabled' 'APP_DEBUG=true'
expect_fail 'non-HTTPS APP_URL' 'APP_URL=http://pos.example.invalid'
expect_fail 'insecure session cookie' 'SESSION_SECURE_COOKIE=false'
expect_fail 'session lifetime above 60 minutes' 'SESSION_LIFETIME=120'
expect_fail 'cluster-admin DB account' 'CENTRAL_DB_USERNAME=postgres'
expect_fail 'development DB-password placeholder' 'CENTRAL_DB_PASSWORD=change-this-local-development-password'
expect_fail 'log mailer in production' 'MAIL_MAILER=log'
expect_fail 'missing SMTP credential' 'MAIL_PASSWORD='

if env -i "PATH=$PATH" APP_ENV=local APP_KEY= sh "$GUARD" >/dev/null 2>&1; then
  printf 'PASS: isolated local environment bypasses production-only validation\n'
else
  printf 'FAIL: local environment was unexpectedly rejected\n' >&2
  exit 1
fi
