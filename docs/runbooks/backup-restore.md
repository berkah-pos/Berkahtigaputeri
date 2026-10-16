# Runbook — Backup and Restore
Location: `docs/runbooks/backup-restore.md`
**Status:** runbook template; it has not been executed. The owner ADR selects PostgreSQL 17; Option B is the target path. Option A is a rejected MariaDB alternative retained for comparison only, not an operational instruction. Configure and test object-storage remotes, encryption, key custody, access policies and credentials before enabling scheduled jobs. Never paste production secrets into shell history or committed files.

## Scope

Must cover:
- Central DB `berkahpos_central`
- Every tenant DB matching the validated `berkahpos_t_<ulid_lower>` registry, currently expected to be empty until provisioning starts and potentially up to 100
- Coolify instance backup (Coolify's own database, project/resource definitions, settings, deployment history)
- Private S3-compatible business files (receipts, exports) and relevant object metadata
- Coolify `APP_KEY` + database encryption/restore keys held off-host in a vault

Do not assume Coolify's selected backup feature supports PostgreSQL WAL/PITR or includes every tenant database. Verify the exact engine/version and feature support, then reconcile each backup result against the central tenant registry and PostgreSQL database catalog. A job configured or marked successful is not proof of complete backup coverage.

## Engine-specific strategy — selected PostgreSQL 17 path

### Rejected alternative — MariaDB 11.4 (comparison only; not the target)

**Physical full backup + point-in-time recovery (PITR)**

1. Use a dedicated backup service/identity with only the backup privileges required by the selected `mariabackup` build (review `RELOAD`, `PROCESS`, `LOCK TABLES`, and `REPLICATION CLIENT` requirements). Do not reuse the tenant provisioner credential.
2. Store backup credentials in a protected client option file or approved secret-injection mechanism with strict file permissions. Never include passwords in shell command arguments, CI logs, or this repository.
3. Run the tested procedure equivalent to:

```bash
mariabackup --backup --target-dir="/backup/full/$(date +%F)" --user=berkah_backup
mariabackup --prepare --target-dir="/backup/full/$(date +%F)"
```

4. Enable and configure binary logging before relying on PITR. Archive the original binary-log segments off-host with checksums and defined retention. Do not use decoded SQL output as the only retained PITR artifact.
5. Encrypt and upload full backups and original binlogs to the selected S3-compatible remote. Confirm the uploaded objects can be read and their checksums match.

PITR restore requires the full backup plus the required original binary logs replayed from the backup's recorded position/GTID. Restoring the full backup alone does not include later binlog changes. Test restoration to a specific timestamp in an isolated environment.

**Logical per-tenant dumps for single-tenant recovery**

- Enumerate expected tenant databases from the central registry and reconcile that list against the actual MariaDB database catalog.
- Do not rely only on a wildcard `LIKE 'berkahpos_t_%'` filter because underscores are pattern characters. Validate every candidate against the generated-name contract before backup.
- Use a dedicated backup identity and a bounded worker pool with at most three tenant databases in parallel. For each database, run the selected version's tested `mysqldump --single-transaction --databases "$db"` equivalent, encrypt/compress, upload off-host, and record checksum, size, and result.
- Treat any missing/unexpected database or failed dump as an incomplete backup run and alert.

### Selected target — PostgreSQL 17

**Physical backup + WAL**

- Use a tested `pg_basebackup` strategy plus WAL archiving, or WAL-G, with encrypted off-host storage and verified retention.
- PostgreSQL physical backup/WAL recovery is cluster-wide. To restore one tenant to a point in time, restore a cluster copy to the desired timestamp in an isolated environment, then logically export/restore the selected tenant database. Test that exact single-tenant recovery path.
- Never assume a physical cluster backup alone proves each tenant database can be restored independently.

**Logical per-tenant dumps**

- Enumerate tenant databases from the central registry and reconcile against `pg_database`; validate every database name against the generated-name contract.
- Use a dedicated backup identity and a bounded worker pool. For each tenant, run a tested `pg_dump -Fc --dbname="$db"` equivalent with credentials supplied by a protected service configuration. Encrypt, upload, and record checksum/size/result. Dump `berkahpos_central` separately.
- Grant only the permissions needed by the backup strategy. Never put database passwords in command-line arguments.

## Coolify Instance Recovery

- Configure Coolify's own instance backup (database/configuration/resources) daily to encrypted off-host storage.
- Back up `APP_KEY` separately in a secure vault. Coolify's instance database backup does not contain that key; without it, restored encrypted secrets cannot be decrypted.
- Test restoration to a separate recovery host at least quarterly and before risky control-plane upgrades. A tar of `/data/coolify` alone is not considered proof of recoverability.

## Retention and protection

- Proposed starting retention: daily 7 days, weekly 4 weeks, monthly 6 months; tune based on verified policy and storage capacity.
- Keep binary logs/WAL long enough to cover the promised recovery point objective plus operational margin.
- Encrypt at rest and in transit, restrict delete permissions, and consider bucket versioning/object lock only after validating retention and recovery operations.
- Use off-host storage; snapshots in the same data centre are supplementary and are not the only recovery copy.

## Restore Test — Mandatory

Schedule a weekly automated restore exercise (the proposed slot is Sunday 02:00 UTC, subject to operations approval):

1. Start an isolated Docker test environment that cannot connect to production.
2. Restore `berkahpos_central` from the selected tested backup path.
3. Select two tenant DBs from the current inventory using a recorded reproducible random seed.
4. Restore both tenant DBs and their required file/object references.
5. Validate migration state using the command supported by the selected Laravel/tenancy versions; no pending migrations is necessary but not sufficient.
6. Verify checksums/row-count invariants on key tables, configuration resolution, tenant-domain mapping, and an application smoke test.
7. Record DB names/IDs tested, backup timestamps, integrity checksums, PITR result if tested, restore duration, and recovery-time result in `docs/evidence/restore-YYYY-MM-DD.md`. Alert on failure.

**Definition of done:** the restore log exists and is green. No log means the backup/restore gate is **NOT VERIFIED**.

## Checklist Before Marking DG-4 Pass

- [ ] Scope includes central DB and every tenant DB—verified by reconciling the registry, catalog and per-database backup results.
- [ ] Off-host encrypted copies exist and checksums match.
- [ ] Coolify instance backup and `APP_KEY` recovery material verified.
- [ ] One full restore exercised and documented.
- [ ] Single-tenant restore exercised without overwriting another tenant.
- [ ] PITR tested once for the selected engine (MariaDB: full + original binlogs to a timestamp; PostgreSQL: cluster base + WAL to a timestamp, then tenant export).
- [ ] RPO/RTO measurements recorded; no SLA claimed until reviewed.
