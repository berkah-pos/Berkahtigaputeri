# Runbook: PostgreSQL 17 Backup, Restore, DR and Application Rollback

**Status: PROPOSED — NOT EXECUTED.** This runbook is not authorization to touch production. Use only a named disposable target unless the owner separately authorizes a production operation. Supabase is prohibited, including read-only access. Never put plaintext secrets, customer data, private keys, or complete connection strings in this repository, shell history, or artifacts.

## 1. Recovery inventory and ownership

| State | Required recovery treatment | Evidence required |
|---|---|---|
| Central PostgreSQL DB | Independent logical dump plus cluster-level physical/PITR chain | DB identifier, backup ID/time, pg_dump/pgBackRest version, checksum and remote read-back |
| Every tenant PostgreSQL DB | Dump every mapped tenant DB; reconcile approved tenant registry, pg_database catalog, completed uploads exactly | Reviewed tenant-ID→database map; exact-set coverage manifest; checksum per encrypted dump |
| PostgreSQL cluster/WAL | pgBackRest (or reviewed WAL-G) base/full + differential/incremental backups and continuous WAL archive | Stanza check, archive health/lag, complete restore chain, tested timestamp recovery |
| Uploaded files/object bytes | Private persistent disk or selected private S3-compatible storage; independent off-host copy/versioning | Tenant-aware object manifest, key, byte size, SHA-256, version, read-back and DB/file consistency |
| Deployment configuration | Versioned non-secret templates plus encrypted environment/config export held off-host | Git/image digest, configuration version, decryption/restore test |
| Key/certificate recovery | Vault/KMS recovery procedure; re-issue/restore TLS certificates; sealed APP_KEY/database-encryption/object-wrapping key material | Authorized retrieval audit and synthetic decrypt test; never export secret values |
| Migration/version metadata | Central and each tenant's migrations table, app image digest, Composer lockfile/schema version | After restore, inspect actual migration table and run non-mutating migration status |
| Coolify control plane | Coolify-managed database and resource/project configuration backup; separate recovery-host procedure | Separate-host restore and re-deploy rehearsal; never assume /data archive is enough |
| Operational evidence | Inventory manifest, backup logs, checksums, alerts, RPO/RTO measurements, DR decisions | Sanitized evidence with source/target identity but no customer rows/secrets |

Current source shows a local PostgreSQL 17 Compose volume and Laravel local filesystems only. Actual production resource IDs, storage backend, tenant DB mapping, Coolify state and vault are NOT VERIFIED. The accepted central schema must not be treated as a database mapping authority merely because a tenant row exists.

## 2. Recovery objectives — PROPOSED, not owner-approved

- Database RPO: ≤15 minutes, only after continuous off-host WAL archive lag is measured and stays within target.
- File/object RPO: ≤1 hour, only after scheduled copy/version state and checksum read-back are measured.
- Full platform/host-loss RTO: ≤8 hours.
- Single-tenant database RTO: ≤4 hours.

These are planning values, not SLAs. Nightly logical dumps alone cannot meet a 15-minute database RPO. Owner approval is required before these are treated as service objectives. Measure restore duration and data-loss window during repeated drills; revise values from evidence, not assumption.

## 3. Cadence and retention — PROPOSED

- PostgreSQL pgBackRest: weekly full, daily differential, continuous WAL archive, target archive_timeout 300 seconds; retain a complete WAL chain for 35 days. Validate support/space before enabling.
- Central and every tenant: nightly custom-format pg_dump as an independently restorable convenience copy; compress/encrypt before remote upload.
- Private files/objects: copy hourly to a separate off-host account/region or separately administered storage; daily object manifest and read-back checksums.
- Coolify control-plane state and deployment metadata: daily off-host backup; before upgrades, capture a tested control-plane backup and a record of restore keys.
- Restore drills: disposable central + two tenants weekly; PITR monthly; Coolify/key recovery quarterly and before major upgrades.

Suggested retention: daily 14 days, weekly 8 weeks, monthly 12 months, PITR WAL window 35 days. These are cost-sensitive defaults awaiting owner approval. A remote copy in the same host or sole storage account is not disaster recovery. Enable object lock/versioning only after delete/restore behavior is tested. Alert on missing/failed backup, inventory mismatch, bad checksum, failed decryption/read-back, WAL archive lag >10 minutes, newest DB backup age >26 hours, file backup age >2 hours, remote quota failure, and missing drill evidence. Route alerting to an actively monitored channel.

## 4. Least privilege, encryption and completeness

Use a dedicated backup role/service identity, not the provisioning or application runtime credentials. Grant only permissions required by the selected pgBackRest/pg_dump design; review table/sequence access and PostgreSQL version behaviour against actual roles. Separate remote writer and recovery-reader capabilities; day-to-day writers must not be able to delete all retained copies. Restrict the backup network path to private PostgreSQL and the remote endpoint. Require MFA/break-glass audit for vault and destructive retention actions.

Encrypt in transit and at rest using a provider-managed or approved envelope-encryption method. Store wrapping keys in a separate vault/KMS with documented custodians, recovery quorum, rotation, revoke/reissue, and compromise procedure. Key material is not part of the same backup set as ciphertext. Do not commit plaintext .env files, APP_KEY, PEM/PFX/JKS, database passwords, access tokens, signed URLs or customer payloads. Record only key IDs/version references and retrieval procedure.

For each run: capture an allowlisted registry manifest, query pg_database, validate all names against the provisioning team's approved generated-name contract, run dump, encrypt, upload, read back to a separate worker, verify SHA-256 and decrypt test. Fail the run if expected, catalog and checksum-verified remote backup sets differ. The validator in scripts/backup_restore/validate_database_coverage.py compares exact sets and hashes mismatching names in output; it cannot create the authoritative registry itself. Never silently skip a tenant.

## 5. Restore drill — separate disposable target only

The synthetic CI harness at scripts/backup_restore/disposable_pg17_drill.sh is a test of mechanics, not a production backup. It starts fresh PG17 source and target containers with no published DB ports, creates synthetic central + tenant A/B markers, dumps and restores to a distinct target, validates migration metadata and file/key test material, writes a sanitized artifact and destroys the disposable environment. It must not accept production endpoints or credentials. The harness being present is not proof it executed.

For an authorized real staging drill, record source backup ID/time/LSN, PG major/minor and pgBackRest/pg_dump versions; isolate network and credentials; restore central first; validate tenant map; restore at least two tenants and all required object versions; validate row/count/balance invariants without logging business rows; compare SHA-256 and migration state; time each step and end-to-end restore; verify application/API health on a separate app instance; and retain sanitized logs. A failed check means do not route traffic to the target.

Single-tenant restore: restore the cluster to an isolated scratch service if using physical PITR, logically export only the selected tenant DB into a fresh database, verify the reviewed tenant→DB mapping and schema/image compatibility, then prove other tenant DBs and central data were not modified. Never restore over the original tenant DB and never infer mapping from a caller-provided ID.

PITR: choose an explicit timestamp between two synthetic writes; restore the complete base + required WAL chain into a disposable cluster, prove writes before the target timestamp exist and writes after it do not, and measure RPO/RTO. If no tested WAL chain exists, mark PITR unavailable; do not present a logical dump as PITR.

## 6. Incident playbooks

- Latest backup absent/corrupt: alert owner, pin last known checksum-verified recoverable point, check off-host history/WAL chain, estimate actual data-loss window, restore to scratch and report measured RPO. Never overwrite the only copy during investigation.
- Database corruption: stop writes or isolate affected service according to incident command, preserve logs/forensics, restore a verified point into a new private cluster, run catalog/migration/business invariants, replay accepted events/forward repairs only under reviewed plan, then cut traffic over.
- Credential compromise: revoke affected identities, stop attacker write access, preserve audit evidence, rotate credentials/keys via vault workflow, assess copied backup exposure, verify restore/decryption with new credentials. Never log compromised values.
- Host failure: rebuild clean host, restrict network exposure, recover Coolify/control-plane config and key references from off-host vault, restore PostgreSQL/WAL and object versions into private resources, deploy immutable reviewed image by digest, validate TLS and health before traffic.
- Missing or lost key/certificate: use the tested vault recovery/re-issue process and DNS/domain control; if encryption key loss makes ciphertext unreadable, declare affected backup set unrecoverable instead of fabricating a recovery claim.

## 7. Application rollback is separate from database recovery

Rollback application code/image to the prior approved immutable digest only when that image is compatible with the current database schema. Do not run a destructive schema down/rollback as an application rollback. Use additive/expand-contract migrations; preserve data-bearing structures. If the previous image is schema-incompatible, use a reviewed forward-fix or restore database into a separate recovery target and reconcile accepted writes before traffic switching. Preserve transaction logs, idempotency receipts and accounting audit trails. Any point-in-time database restore may discard accepted writes after the target time; require business reconciliation before opening the service.

## 8. Closure gates

Require exact coverage for central + every approved tenant database, checksum-verified encrypted off-host objects, key/vault recovery, Coolify recovery, central + two-tenant restore, independently verified single-tenant restore, a timestamped PITR exercise, migration/image compatibility, and measured owner-approved RPO/RTO. An empty artifact directory, static test, or successful dump does not meet a restore gate. Status remains BLOCKED / NOT VERIFIED until dated direct evidence exists.
