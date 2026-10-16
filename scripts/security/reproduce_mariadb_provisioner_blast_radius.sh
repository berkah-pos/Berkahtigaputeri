#!/usr/bin/env bash
# Disposable proof-of-impact for the historical MariaDB 11.4 grants.
# Never run against a shared, staging, or production database.
set -Eeuo pipefail
umask 077
set +x

: "${MARIADB_ROOT_PASSWORD:?Ephemeral disposable MariaDB root password required}"
MARIADB_HOST="${MARIADB_HOST:-127.0.0.1}"
MARIADB_PORT="${MARIADB_PORT:-3306}"
SECURITY_EVIDENCE_FILE="${SECURITY_EVIDENCE_FILE:-/tmp/mariadb-show-grants-redacted.txt}"

MYSQL=(mariadb --protocol=tcp --host="$MARIADB_HOST" --port="$MARIADB_PORT" --batch --skip-column-names)
admin() { MYSQL_PWD="$MARIADB_ROOT_PASSWORD" "${MYSQL[@]}" --user=root "$@"; }

# Use only generated credentials and synthetic records in the throwaway service.
PROVISIONER_PASSWORD="$(openssl rand -hex 32)"
MIGRATOR_PASSWORD="$(openssl rand -hex 32)"
DELEGATE_PASSWORD="$(openssl rand -hex 32)"
CREATED_USER_PASSWORD="$(openssl rand -hex 32)"
DB_A="berkahpos_t_security_probe_a"
DB_B="berkahpos_t_security_probe_b"
DB_CREATED="berkahpos_t_security_created"
DELEGATE_USER="berkahpos_security_delegate"
CREATED_USER="berkahpos_security_created"

mkdir -p "$(dirname "$SECURITY_EVIDENCE_FILE")"
: > "$SECURITY_EVIDENCE_FILE"
chmod 600 "$SECURITY_EVIDENCE_FILE"

admin <<SQL
CREATE DATABASE berkahpos_central;
CREATE DATABASE $DB_A;
CREATE DATABASE $DB_B;
CREATE USER 'berkahpos_app'@'%' IDENTIFIED BY 'unused-app-account';
CREATE USER 'berkahpos_provisioner'@'%' IDENTIFIED BY '$PROVISIONER_PASSWORD';
CREATE USER 'berkahpos_migrator'@'%' IDENTIFIED BY '$MIGRATOR_PASSWORD';
CREATE USER '$DELEGATE_USER'@'%' IDENTIFIED BY '$DELEGATE_PASSWORD';
CREATE TABLE $DB_B.security_canary (
  id INT PRIMARY KEY,
  marker VARCHAR(80) NOT NULL
);
INSERT INTO $DB_B.security_canary (id, marker) VALUES (1, 'synthetic-tenant-b-canary');
SQL

# Apply a policy equivalent of the historical candidate's grant file.
admin < audit/security/fixtures/rejected-mariadb-11.4-phase2-grants.sql

safe_show_grants() {
  local username="$1"
  local raw
  raw="$(admin --execute="SHOW GRANTS FOR '$username'@'%';")"
  {
    printf '%s\n' "--- SHOW GRANTS FOR '$username'@'%'; (authentication material redacted) ---"
    printf '%s\n' "$raw" | sed -E "s/(IDENTIFIED BY PASSWORD +)'[^']*'/\1'[REDACTED]'/Ig; s/(IDENTIFIED BY +)'[^']*'/\1'[REDACTED]'/Ig"
  } | tee -a "$SECURITY_EVIDENCE_FILE"
}

{
  printf '%s\n' '=== Disposable server ==='
  admin --execute='SELECT VERSION();'
  printf '%s\n' '=== Raw grants from the real MariaDB privilege tables ==='
} | tee -a "$SECURITY_EVIDENCE_FILE"
safe_show_grants berkahpos_provisioner
safe_show_grants berkahpos_migrator

provisioner_sql() {
  MYSQL_PWD="$PROVISIONER_PASSWORD" "${MYSQL[@]}" --user=berkahpos_provisioner --database="$DB_A" --execute="$1"
}
delegate_sql() {
  MYSQL_PWD="$DELEGATE_PASSWORD" "${MYSQL[@]}" --user="$DELEGATE_USER" --database="$DB_B" --execute="$1"
}

confirmed=0
probe() {
  local label="$1"
  local sql="$2"
  local output
  local error_file
  error_file="$(mktemp)"
  if output="$(provisioner_sql "$sql" 2>"$error_file")"; then
    printf 'VULNERABILITY CONFIRMED: compromised provisioner successfully performed: %s\n' "$label" | tee -a "$SECURITY_EVIDENCE_FILE"
    if [[ -n "$output" && "$label" == "read tenant B canary without tenant B credentials" ]]; then
      printf '  Result: synthetic canary row count=%s (no tenant data contents emitted)\n' "$output" | tee -a "$SECURITY_EVIDENCE_FILE"
    fi
    confirmed=$((confirmed + 1))
  else
    printf 'Probe denied / NOT REPRODUCED: %s\n' "$label" | tee -a "$SECURITY_EVIDENCE_FILE"
    if [[ "$label" == "delegate SELECT on tenant B to another principal" ]]; then
      error_code="$(sed -nE 's/.*ERROR ([0-9]+) \(([^)]*)\):.*/\1 (\2)/p' "$error_file" | head -n 1)"
      printf '  Delegation denial: MariaDB error code %s (statement/password text not emitted)\n' "${error_code:-unavailable}" | tee -a "$SECURITY_EVIDENCE_FILE"
    fi
  fi
  rm -f "$error_file"
}

probe "read tenant B canary without tenant B credentials" "SELECT COUNT(*) FROM $DB_B.security_canary;"
probe "modify tenant B data" "UPDATE $DB_B.security_canary SET marker='modified-by-provisioner' WHERE id=1;"
probe "insert into tenant B data" "INSERT INTO $DB_B.security_canary (id, marker) VALUES (2, 'inserted-by-provisioner');"
probe "delete tenant B data" "DELETE FROM $DB_B.security_canary WHERE id=2;"
probe "create another matching tenant database" "CREATE DATABASE $DB_CREATED;"
probe "create an arbitrary global database principal" "CREATE USER '$CREATED_USER'@'%' IDENTIFIED BY '$CREATED_USER_PASSWORD';"
probe "delegate SELECT on tenant B to another principal" "GRANT SELECT ON $DB_B.* TO '$DELEGATE_USER'@'%';"

if delegate_output="$(delegate_sql 'SELECT COUNT(*) FROM security_canary;' 2>/dev/null)"; then
  printf 'VULNERABILITY CONFIRMED: delegated principal reads tenant B using newly granted access (synthetic row count=%s).\n' "$delegate_output" | tee -a "$SECURITY_EVIDENCE_FILE"
  confirmed=$((confirmed + 1))
else
  printf '%s\n' 'Delegated-principal verification denied / NOT REPRODUCED.' | tee -a "$SECURITY_EVIDENCE_FILE"
fi

printf '=== Summary: %s compromised-provisioner capabilities reproduced ===\n' "$confirmed" | tee -a "$SECURITY_EVIDENCE_FILE"
if (( confirmed > 0 )); then
  printf '%s\n' 'SECURITY GATE: FAIL. This historical MariaDB privilege policy is not tenant-isolated; do not promote it or treat process separation as least privilege.' | tee -a "$SECURITY_EVIDENCE_FILE"
  exit 1
fi

printf '%s\n' 'SECURITY GATE: NOT VERIFIED. No capability was reproduced; investigate failures and do not infer isolation.' | tee -a "$SECURITY_EVIDENCE_FILE"
exit 2
