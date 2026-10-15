# Runbook — Encrypted Off-Host Backup, Restore, PITR and Recovery Materials

**Status:** procedure and automation are source-defined; production backup, off-host configuration, restore and PITR evidence are **NOT RUN / NOT VERIFIED** until a dated isolated-host result is reviewed. A script or a successful backup command is not verified restore evidence.

## Recovery scope

1. Central DB berkahpos_central.
2. Every tenant DB named in the central tenant registry that reconciles exactly with the live MariaDB catalog.
3. A coordinated full logical snapshot including MariaDB binary-log starting file/position, plus separately restorable central and per-tenant SQL dumps.
4. Original MariaDB binary logs required from the recorded snapshot coordinate through the PITR target.
5. Private object-store files and metadata, including a non-sensitive recovery probe whose SHA-256 is known.
6. Application APP_KEY, age private decryption identity, off-host storage access, TLS/domain credentials and Coolify control-plane backup, recovered through separate vault custody and never committed to Git.

**Canonical tenant DB name:** berkahpos_t_<lowercase-ULID>. The 26-character lowercase ULID is stored in tenants.database_ulid and the full name in tenants.tenancy_db_name and provisioner audit metadata. Legacy names using berkahpos_tenant_<sha256-prefix> are not renamed or automatically adopted. Inventory every legacy DB, verify ownership/data and use a reviewed backup/migration/cutover plan; never drop or recreate an unverified data-bearing schema.

Coolify control-plane backup is separate from application databases. A tar of /data/coolify alone is not complete recovery. Never store plaintext SQL as the only copy or expose credentials/keys in Git, shell arguments or logs.

## Preconditions and secret hygiene

1. Confirm the deployed DB engine decision and schema inventory. DG-0 remains blocked until its reviewed schema/function/extension inventory and ADR are accepted.
2. Use a dedicated backup identity, not root, provisioner, migrator or a tenant runtime account. Review exact read/lock, routines/events/triggers and binary-log inspection privileges for the deployed MariaDB build.
3. Store client credentials in a mode-0600 option file. Never pass passwords in command-line arguments or shell history.
4. Configure an approved named rclone remote to a separate off-host account/bucket with least privilege, versioning/retention, access logging and monitoring. A local directory or CI alias does not prove production off-host redundancy.
5. Create age public recipients and retain two recovery-approved private identities in separate vault custody.
6. Enable MariaDB binary logging and monitor archive lag, gaps and retention. The included archive script copies closed/rotated logs and deliberately skips the active log. Without a tested active-tail mechanism and contiguous replay, no zero-loss RPO can be claimed.
7. Record start UTC, source revision/image digest, central registry, live catalog, disk space and current log coordinates before the run.

## Scheduled full + per-tenant backup

On the protected database client host, inject approved values through the operations environment:

    chmod 600 "$MYSQL_CLIENT_CNF"
    export AGE_RECIPIENTS_FILE=/secure/path/age-recipients.txt
    export RCLONE_REMOTE=approved-offsite:berkah-pos-backups
    scripts/backup/backup-mariadb-offhost.sh

The script reads tenants.tenancy_db_name, validates each against berkahpos_t_<26 lowercase ULID>, reconciles registry and MariaDB catalog, verifies binary logs are available, and streams one coordinated full snapshot plus one central dump and one dump for every tenant through gzip and age to the remote. Plaintext SQL is not persisted locally. Every ciphertext object is read back and SHA-256 checked. A manifest is published only after all database artifacts are present.

The backup rotates the binary log so the snapshot's starting log can close. Preserve the BACKUP_SET_ID and REMOTE_SET operations output without secrets. Reconcile the final manifest with tenants and information_schema.SCHEMATA.

## Rotated binary-log archive

Run scripts/backup/archive-mariadb-binlogs.sh on a controlled cadence (initial proposal: five minutes), and monitor archive lag/gaps:

    export MYSQL_CLIENT_CNF=/secure/path/backup-client.cnf
    export AGE_RECIPIENTS_FILE=/secure/path/age-recipients.txt
    export RCLONE_REMOTE=approved-offsite:berkah-pos-backups
    scripts/backup/archive-mariadb-binlogs.sh

Only closed logs are archived. The script encrypts them, writes plaintext/ciphertext SHA-256 sidecars and reads ciphertext back to verify. It does not capture the active mutable log. Do not purge local logs until corresponding remote copies are verified and sequence coverage is confirmed. A full dump without contiguous replayable logs is not PITR.

## Verify an encrypted backup set

Download a chosen set into a protected workspace (only ciphertext is downloaded):

    rclone copy approved-offsite:berkah-pos-backups/<SET_ID> /secure/restore-input/<SET_ID>
    export BACKUP_SET_DIR=/secure/restore-input/<SET_ID>
    export AGE_IDENTITY_FILE=/secure/vault/age-restore-identity.txt
    scripts/backup/verify-backup-set.sh

The verifier checks manifest integrity, artifact presence, size, ciphertext SHA-256, age authentication and gzip integrity. Verify binlog checksums/sidecars separately before replay.

## Full isolated restore

Use an isolated disposable host with Docker available. The restore script creates MariaDB 11.4 with network none and no published ports, then removes only that temporary container/workspace on exit. Its guard is mandatory:

    export RESTORE_CONFIRM=ISOLATED_DISPOSABLE_ONLY
    export BACKUP_SET_DIR=/secure/restore-input/<SET_ID>
    export AGE_IDENTITY_FILE=/secure/vault/age-restore-identity.txt
    scripts/backup/restore-drill-mariadb.sh full

Full mode checks the central DB and every manifest tenant contains tables. Record UTC start/end, candidate commit/image digest, table counts, duration, logs and CPU/RAM/disk high-water.

## Central + two tenant restore; single-tenant isolated restore

Choose two disposable tenant names from a verified manifest:

    scripts/backup/restore-drill-mariadb.sh sample berkahpos_t_<ULID_1> berkahpos_t_<ULID_2>
    scripts/backup/restore-drill-mariadb.sh single-tenant berkahpos_t_<ULID_1>

Sample mode restores central plus exactly two selected tenants and rejects any other tenant DB. Single-tenant mode restores one tenant in a separate disposable instance. These prove dump readability/isolation only, not production cutover. Before a real recovery, separately validate central tenant metadata, canonical database name, runtime DB user/grants, membership, domains and subscription.

## Point-in-Time Recovery

PITR requires the full snapshot's --master-data=2 coordinate and the original contiguous binary-log sequence. It must prove a business checkpoint, not merely SQL replay.

1. Download the verified full snapshot and every encrypted log from the baseline through the target time. Check sequence, sidecars and decryption; refuse gaps.
2. Establish a known non-sensitive disposable checkpoint after the snapshot and before target UTC. Its assertion SQL must return exactly PASS when recovery is correct.
3. Run:

    export RESTORE_CONFIRM=ISOLATED_DISPOSABLE_ONLY
    export BACKUP_SET_DIR=/secure/restore-input/<SET_ID>
    export AGE_IDENTITY_FILE=/secure/vault/age-restore-identity.txt
    export BINLOG_ARCHIVE_DIR=/secure/restore-input/binlogs
    export PITR_TARGET_UTC='2026-10-16 02:45:00'
    export PITR_ASSERT_SQL_FILE=/secure/fixtures/pitr-checkpoint.sql
    scripts/backup/restore-drill-mariadb.sh pitr

4. Record actual start file/position, target UTC, last archived log, sequence checks, assertion and recovery duration. If the active log tail, sequence continuity or business assertion is absent, PITR remains NOT RUN / NOT VERIFIED. Never infer an RPO from a successful full restore.

## File/key recovery validation

After retrieving known fingerprints and keys from the independent vault, run scripts/backup/verify-recovery-materials.sh:

    export APP_KEY_FILE=/secure/vault/recovered-app-key.txt
    export EXPECTED_APP_KEY_SHA256=<vault-recorded-sha256>
    export AGE_IDENTITY_FILE=/secure/vault/age-restore-identity.txt
    export AGE_KEY_CHECK_OBJECT=/secure/restore-input/key-sentinel.age
    export EXPECTED_AGE_SENTINEL_SHA256=<vault-recorded-sentinel-sha256>
    export FILE_PROBE_RCLONE_PATH=approved-offsite:private-files/recovery-probe.txt
    export FILE_PROBE_SHA256=<previously-recorded-object-sha256>
    scripts/backup/verify-recovery-materials.sh

The helper never prints the APP_KEY or private identity. APP_KEY rotation can make existing encrypted application data unreadable and is a separate reviewed operation. Verify Coolify state, TLS and DNS recovery separately, and record key-custody separation and a second authorized operator's restore when required.

## Evidence and acceptance

Commit the operator's dated result at docs/evidence/restore-YYYY-MM-DD.md and upload redacted logs and manifest as workflow artifacts. Include exact candidate commit/image, isolated host role, database names (no customer identity), commands, hashes, file/key results, restore/PITR checkpoint, duration and resource high-water. Never commit dumps, plaintext secrets, credentials or the private age identity.

DG-4 stays NOT RUN / NOT VERIFIED until full restore, central + two-tenant restore, single-tenant restore and PITR with a positive business checkpoint have all run, plus off-host checksum and file/key recovery checks. A CI local-alias remote proves CI script behavior only, not production off-host redundancy or KVM2 capacity.
