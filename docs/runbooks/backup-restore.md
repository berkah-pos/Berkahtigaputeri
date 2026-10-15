# Runbook — Backup and Restore
Location: docs/runbooks/backup-restore.md
Branch: docs/kvm2-isolated-saas-architecture

**Status:** runbook template; it has not been executed. Select exactly one database-engine path after DG-0. Configure and test object-storage remotes, encryption, key custody, access policies, and credentials before enabling scheduled jobs. Never paste production secrets into shell history or committed files.

## Scope

Must cover:
- Central DB `berkahpos_central`
- Every tenant DB `berkahpos_t_%` (currently 0, scales to 100)
- Coolify instance backup (includes Coolify's own DB + service definitions)
- Private S3 files (receipts, exports)
- Coolify `APP_KEY` + DB encryption keys stored off-host in vault (1Password / Vault)

Coolify's backup feature DOES support selecting All Databases or specific databases for MariaDB. Risk is misconfigured scope or unchecked failed results — not that it cannot backup multiple DBs. Always verify result list.

## Engine-Specific Strategy — Choose after DG-0

### Option A — If MariaDB 11.4 selected

**Full + PITR:**
```bash
# Full with mariabackup (needs provisioner or backup user with RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT)
mariabackup --backup --target-dir="/backup/full/$(date +%F)" --user=berkah_backup
mariabackup --prepare --target-dir="/backup/full/$(date +%F)"

Supply credentials via a protected client option file/secret mechanism with strict file permissions; do not put passwords in command arguments, shell history, logs, or this repository.

# Binary logs for PITR — must enable log_bin in my.cnf
mysqlbinlog /var/lib/mysql/binlog.00000X > /backup/binlog/...

# Encrypt + off-host
restic -r r2:berkah-pos-backups backup /backup/full --tag mariadb
rclone copy /backup/binlog r2:berkah-pos-backups/binlog --transfers 4
```

PITR restore requires full + binlogs replay. Restoring full alone does NOT include binlog changes — test this.

**Logical per-tenant (for quick single-tenant restore):**
```bash
# Run in provisioner service, 3 parallel max
Enumerate tenants from the central registry and reconcile that list against the actual database catalog; do not rely only on a wildcard `LIKE` filter because `_` is a pattern character. For each validated generated database name, run `mysqldump --single-transaction --databases "$db"` with backup credentials injected securely, compress, encrypt, upload to the configured off-host remote, and record a checksum/result row. Use a bounded worker pool of at most three databases.
```

### Option B — If PostgreSQL 17 selected

**Physical + WAL:**
- `pg_basebackup` weekly + WAL archiving to R2 via `archive_command = 'rclone rcat r2:.../%f'`
- Or WAL-G. PostgreSQL physical base backup + WAL is cluster-wide: point-in-time recovery requires restoring a cluster copy to the target timestamp, then logically exporting the requested tenant database. Test that exact single-tenant recovery path.

**Logical per-tenant:**
```bash
Enumerate the central registry and reconcile it against `pg_database`. For each validated tenant DB, run `pg_dump -Fc --dbname="$db"` with credentials from a protected service configuration, encrypt and upload the output, and record result/checksum. Dump `berkahpos_central` separately. Use a bounded worker pool and never put passwords in command-line arguments.
```

### Coolify Instance

- Coolify > Settings > Instance Backup — schedule daily, off-host S3, encrypted.
- Store `APP_KEY` separately. Without it, backup is unrecoverable.

### Retention

- Daily full for 7 days, weekly for 4 weeks, monthly for 6 months
- Binlogs / WAL 7 days
- Encrypted, bucket versioning + Object Lock optional

## Restore Test — Mandatory

Weekly automated job (Sunday 02:00 UTC):

1. Spin isolated Docker `restore-test` (not KVM2)
2. Restore central DB from latest full
3. Randomly pick 2 tenant DBs from list
4. Restore them using the selected engine's documented restore procedure
5. Run:
   - `php artisan tenancy:run --tenant=$id migrate:status` — no pending
   - Checksum: row counts on key tables
   - App smoke: resolve domain -> tenant works
6. Log in `backup_restore_tests` table:
   - date, which DBs, full result, binlog/WAL replay result, duration, recovery time
   - Failure alerts to Slack/email

Definition of done: Restore log exists and is green. No log = no backup.

## Runbook Checklist Before Marking DG-4 Pass

- [ ] Backup scope includes all `berkahpos_t_%` — verified via query, not config file assumption
- [ ] Off-host copy exists and is encrypted
- [ ] APP_KEY vault backup verified
- [ ] One full restore test executed and documented with which DBs
- [ ] PITR tested once (MariaDB: full + original binlogs to a specific timestamp; PostgreSQL: cluster base + WAL to target timestamp, then export a tenant DB)