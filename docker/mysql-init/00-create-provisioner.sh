#!/usr/bin/env bash
set -Eeuo pipefail

: "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD must be set}"
: "${TENANT_PROVISIONER_DB_PASSWORD:?TENANT_PROVISIONER_DB_PASSWORD must be set}"

# Escape SQL string delimiters without echoing the secret to logs.
escaped_password="$(printf '%s' "$TENANT_PROVISIONER_DB_PASSWORD" | sed "s/'/''/g")"

if [[ -n "${PROVISIONER_INIT_HOST:-}" ]]; then
  mariadb --protocol=tcp \
    --host="$PROVISIONER_INIT_HOST" \
    --port="${PROVISIONER_INIT_PORT:-3306}" \
    --user=root --password="$MARIADB_ROOT_PASSWORD" <<SQL
CREATE USER IF NOT EXISTS 'berkahpos_provisioner'@'%' IDENTIFIED BY '$escaped_password';
ALTER USER 'berkahpos_provisioner'@'%' IDENTIFIED BY '$escaped_password';
SQL
else
  mariadb --protocol=socket --user=root --password="$MARIADB_ROOT_PASSWORD" <<SQL
CREATE USER IF NOT EXISTS 'berkahpos_provisioner'@'%' IDENTIFIED BY '$escaped_password';
ALTER USER 'berkahpos_provisioner'@'%' IDENTIFIED BY '$escaped_password';
SQL
fi
