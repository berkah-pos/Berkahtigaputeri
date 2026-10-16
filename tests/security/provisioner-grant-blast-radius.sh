#!/usr/bin/env bash
# Reproduce the Phase 2 provisioner blast radius against disposable MariaDB only.
# A successful script means the vulnerability was reproduced; it is NOT a security pass.
set -euo pipefail
set +x
umask 077

: "${MARIADB_ROOT_PASSWORD:?use only the disposable MariaDB 11.4 service}"
HOST="${MARIADB_HOST:-127.0.0.1}"
PORT="${MARIADB_PORT:-3306}"
CENTRAL_PASSWORD="$(openssl rand -hex 24)"
PROVISIONER_PASSWORD="$(openssl rand -hex 24)"
MIGRATOR_PASSWORD="$(openssl rand -hex 24)"
ATTACKER_PASSWORD="$(openssl rand -hex 24)"

# GitHub Actions masks any credential value if a downstream tool unexpectedly echoes one.
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  printf '::add-mask::%s\n' "$MARIADB_ROOT_PASSWORD"
  printf '::add-mask::%s\n' "$CENTRAL_PASSWORD"
  printf '::add-mask::%s\n' "$PROVISIONER_PASSWORD"
  printf '::add-mask::%s\n' "$MIGRATOR_PASSWORD"
  printf '::add-mask::%s\n' "$ATTACKER_PASSWORD"
fi

root_sql() {
  MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb --protocol=tcp --host="$HOST" --port="$PORT" \
    --user=root --connect-timeout=3 --batch --skip-column-names "$@"
}

provisioner_sql() {
  MYSQL_PWD="$PROVISIONER_PASSWORD" mariadb --protocol=tcp --host="$HOST" --port="$PORT" \
    --user=berkahpos_provisioner --connect-timeout=3 --batch --skip-column-names "$@"
}

attacker_sql() {
  MYSQL_PWD="$ATTACKER_PASSWORD" mariadb --protocol=tcp --host="$HOST" --port="$PORT" \
    --user=audit_compromised_principal --connect-timeout=3 --batch --skip-column-names "$@"
}

ready=false
for ((attempt=1; attempt<=60; attempt++)); do
  if root_sql --execute='SELECT 1' >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done
if [[ "$ready" != true ]]; then
  echo "FAIL: disposable MariaDB 11.4 did not become ready."
  exit 1
fi

tenant_a='berkahpos_t_01arz3ndektsv4rrffq69g5fav'
tenant_b='berkahpos_t_01arz3ndektsv4rrffq69g5faw'

# Synthetic tenant names, accounts, and rows only. These are not production identifiers.
root_sql <<SQL
CREATE DATABASE IF NOT EXISTS berkahpos_central CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `$tenant_a` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `$tenant_b` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'berkahpos_app'@'%' IDENTIFIED BY '$CENTRAL_PASSWORD';
CREATE USER 'berkahpos_provisioner'@'%' IDENTIFIED BY '$PROVISIONER_PASSWORD';
CREATE USER 'berkahpos_migrator'@'%' IDENTIFIED BY '$MIGRATOR_PASSWORD';
CREATE TABLE `$tenant_a`.grant_probe (id INT PRIMARY KEY, synthetic_marker VARCHAR(40) NOT NULL);
CREATE TABLE `$tenant_b`.grant_probe (id INT PRIMARY KEY, synthetic_marker VARCHAR(40) NOT NULL);
INSERT INTO `$tenant_a`.grant_probe VALUES (1, 'synthetic-a-only');
INSERT INTO `$tenant_b`.grant_probe VALUES (1, 'synthetic-b-only');
SQL

# Apply the repository's exact init grants, not a hand-written approximation.
root_sql < docker/mysql-init/10-tenant-db-privileges.sql

redact_grants() {
  sed -E \
    -e "s/IDENTIFIED BY PASSWORD '[^']*'/IDENTIFIED BY PASSWORD '[REDACTED]'/g" \
    -e "s/IDENTIFIED BY '[^']*'/IDENTIFIED BY '[REDACTED]'/g"
}

echo "=== ACTUAL SHOW GRANTS FROM DISPOSABLE MARIADB 11.4 (credential clauses redacted) ==="
for principal in berkahpos_app berkahpos_provisioner berkahpos_migrator; do
  printf '%s\n' "--- $principal ---"
  root_sql --execute="SHOW GRANTS FOR '$principal'@'%';" | redact_grants
done

# Model a full compromise of the private provisioner process. No production host,
# shared staging database, or non-disposable service is reachable by this workflow.
provisioner_sql <<SQL
CREATE USER 'audit_compromised_principal'@'%' IDENTIFIED BY '$ATTACKER_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE ON `berkahpos\\_t\\_%`.* TO 'audit_compromised_principal'@'%';
SQL

echo "=== ACTUAL SHOW GRANTS AFTER COMPROMISED PROVISIONER DELEGATES ACCESS ==="
root_sql --execute="SHOW GRANTS FOR 'audit_compromised_principal'@'%';" | redact_grants

count_a="$(attacker_sql --database="$tenant_a" --execute="SELECT COUNT(*) FROM grant_probe WHERE synthetic_marker='synthetic-a-only';")"
count_b="$(attacker_sql --database="$tenant_b" --execute="SELECT COUNT(*) FROM grant_probe WHERE synthetic_marker='synthetic-b-only';")"
[[ "$count_a" == "1" && "$count_b" == "1" ]] || {
  echo "FAIL: delegated principal could not read both synthetic tenant databases as expected."
  exit 1
}

attacker_sql --database="$tenant_a" --execute="UPDATE grant_probe SET synthetic_marker='updated-by-compromised-provisioner' WHERE id=1;" >/dev/null
attacker_sql --database="$tenant_b" --execute="UPDATE grant_probe SET synthetic_marker='updated-by-compromised-provisioner' WHERE id=1;" >/dev/null

updated_a="$(attacker_sql --database="$tenant_a" --execute="SELECT COUNT(*) FROM grant_probe WHERE synthetic_marker='updated-by-compromised-provisioner';")"
updated_b="$(attacker_sql --database="$tenant_b" --execute="SELECT COUNT(*) FROM grant_probe WHERE synthetic_marker='updated-by-compromised-provisioner';")"
[[ "$updated_a" == "1" && "$updated_b" == "1" ]] || {
  echo "FAIL: delegated principal could not update both synthetic tenant databases as expected."
  exit 1
}

echo "PROOF: compromised provisioner created an independent account (CREATE USER ON *.*) and delegated DML to the wildcard tenant schema pattern."
echo "PROOF: the delegated account SELECTed and UPDATEd synthetic tenant A and tenant B rows."
echo "SECURITY GATE: FAIL — the current grant model permits a compromised provisioner to read/write across tenant databases."
