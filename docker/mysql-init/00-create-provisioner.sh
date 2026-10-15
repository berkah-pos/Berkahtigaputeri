#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

: "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD must be set for the database init container}"
: "${CENTRAL_DB_PASSWORD:?CENTRAL_DB_PASSWORD must be set}"
: "${PROVISIONER_DB_PASSWORD:?PROVISIONER_DB_PASSWORD must be set}"
: "${MIGRATOR_DB_PASSWORD:?MIGRATOR_DB_PASSWORD must be set}"

# Escape string literals without printing or tracing any credential values.
sql_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g"
}
central_password="$(sql_escape "$CENTRAL_DB_PASSWORD")"
provisioner_password="$(sql_escape "$PROVISIONER_DB_PASSWORD")"
migrator_password="$(sql_escape "$MIGRATOR_DB_PASSWORD")"

run_sql() {
  if [[ -n "${PROVISIONER_INIT_HOST:-}" ]]; then
    mariadb --protocol=tcp \
      --host="$PROVISIONER_INIT_HOST" \
      --port="${PROVISIONER_INIT_PORT:-3306}" \
      --user=root --password="$MARIADB_ROOT_PASSWORD" "$@"
  else
    mariadb --protocol=socket --user=root --password="$MARIADB_ROOT_PASSWORD" "$@"
  fi
}

run_sql <<SQL
CREATE USER IF NOT EXISTS 'berkahpos_app'@'%' IDENTIFIED BY '$central_password';
CREATE USER IF NOT EXISTS 'berkahpos_provisioner'@'%' IDENTIFIED BY '$provisioner_password';
CREATE USER IF NOT EXISTS 'berkahpos_migrator'@'%' IDENTIFIED BY '$migrator_password';
SQL

unset central_password provisioner_password migrator_password
