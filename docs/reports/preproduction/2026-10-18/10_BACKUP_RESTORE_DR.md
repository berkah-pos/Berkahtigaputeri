# 10 — Backup / Restore / Disaster Recovery Audit

- **Workstream status:** **BLOCKED / NOT VERIFIED**. No production backup, production-data access, Supabase access, infrastructure changes or database modifications were made.
- **Repository:** berkah-pos/Berkahtigaputeri
- **Base SHA:** 371b7fdf0bf672b37ceb1023e647f114221bf797 (main ref observed before edits)
- **Branch:** audit/preprod-backup-restore-2026-10-18
- **Final commit SHA / PR / CI run:** pending branch update and direct GitHub observation; do not infer these identifiers.
- **Ownership:** PostgreSQL backup inventory, encrypted/off-host retention, uploaded files/config/key recovery, restore drills, RPO/RTO, and separation of application rollback from database recovery.

## 1. Executive summary

The current owner decision selects private PostgreSQL 17 with one central database and a separate database plus restricted runtime role per tenant. At the inspected base SHA, the existing backup/restore runbook identified itself as an unexecuted template and retained a rejected MariaDB alternative. Current source directly verifies only a local Compose PostgreSQL volume and Laravel local filesystem disks. Source does not prove off-host backups, PITR/WAL, production storage, key-vault recovery, Coolify recovery or an authoritative tenant-to-database map.

This branch adds a PostgreSQL-only operational runbook, a synthetic-only disposable PG17 restore harness, an exact-set backup coverage validator and six positive/negative tests, plus an isolated GitHub Actions workflow. A prototype was syntax-checked and the validator tests passed in a temporary staging directory; this environment lacks Docker/PostgreSQL executables, so no local database restore occurred. Candidate-SHA CI must be observed before claiming the harness passes. Even successful synthetic CI does not prove production backups, remote retention, PITR, tenant privileges or live vault/Coolify recovery.

## 2. Scope, authority and files

Required reading order completed before scoped source inspection: root AGENTS.md; DOC_00_CANONICAL_ARCHITECTURE_DECISION.md; ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md; ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md; DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md; DOC_00_MASTER_ROADMAP.md; docs/permanent/README.md; DOC_12; DOC_13; DOC_01_3_LAYER_CONFIG.md; .cursor/rules/berkah-pos.mdc; .github/muse-instructions.md; root README.md; docs/HARDENING/README.md; then backup runbook, DB/filesystem config, Compose, Dockerfile, migrations and PG17 workflow sources.

Current platform authority is the 2026-10-17 no-Supabase owner ADR. The earlier 2026-10-16 ADR is subordinate where conflicting. No Supabase tool, project or product was accessed. The configuration contract and 352-entry workbook were not changed.

Owned paths:
- docs/runbooks/backup-restore.md
- scripts/backup_restore/disposable_pg17_drill.sh
- scripts/backup_restore/validate_database_coverage.py
- scripts/backup_restore/test_validate_database_coverage.py
- .github/workflows/backup-restore-disposable.yml
- docs/reports/preproduction/2026-10-18/10_BACKUP_RESTORE_DR.md

No business logic, permanent authority document, DNS, production infrastructure, production secret or customer data was changed/accessed.

## 3. Source-verified findings

| Evidence | Direct observation | Status and limit |
|---|---|---|
| config/database.php and .env.example | Central and tenant PostgreSQL connections/defaults are defined. | **SOURCE-VERIFIED**; not deployed-state evidence. |
| docker-compose.yml, PG service and volume | Local postgres:17 binds 127.0.0.1:5432 and stores state in local volume postgres17_data. | **SOURCE-VERIFIED**; no off-host backup/PITR control shown. |
| config/filesystems.php | Only local storage/app/private and storage/app/public disks are defined. | **SOURCE-VERIFIED**; actual production file path or object provider is NOT VERIFIED. |
| central migration create_central_platform_tables.php, tenants table | Tenant ID/template metadata exists; no approved tenant database-name mapping is established by this migration. | **SOURCE-VERIFIED**; cannot safely infer backup enumeration. |
| docs/runbooks/backup-restore.md at base | The old runbook says not executed and has rejected MariaDB alternative text. | **DOC-ASSERTED**; not recovery evidence. |
| prior PG17 baseline CI run 39005405149 | Historical documentation ties it to SHA aab154f87342f2a02a1319e1d370ce831dbef522. | **CLAIMED / historical**, different SHA and not backup/restore evidence. |

## 4. Acceptance gates

| ID | Criterion | Status | Evidence / blocker |
|---|---|---|---|
| BR-01 | Central + all tenant DBs identified; registry, catalog and verified remote backup sets exactly match | **BLOCKED** | Coverage validator added; authoritative tenant-ID→DB map must come from provisioning owner. |
| BR-02 | Restore central + two tenant DBs to a distinct disposable PG17 target | **NOT RUN / BLOCKED locally** | Harness and CI workflow added; Docker unavailable in this environment. Need actual run result and sanitized artifact. |
| BR-03 | Restored migration metadata compatible with tested app version | **NOT RUN** | Harness checks migration status after restore; actual drill remains pending. |
| BR-04 | Files/key recovery integrity | **PARTIAL / NOT VERIFIED** | Only synthetic file checksums and synthetic key encrypt/decrypt are in the proposed harness; no real provider/vault test. |
| BR-05 | Encrypted off-host backup, retention, immutability and remote read-back | **BLOCKED** | Provider/account, config, credentials and read-back evidence not available; no real backup job run. |
| BR-06 | WAL/PITR to an explicit timestamp | **BLOCKED / NOT RUN** | No active pgBackRest/WAL archive or tested timestamp restore found. |
| BR-07 | Single-tenant recovery without swap/overwrite or impact to other tenants | **PARTIAL / NOT VERIFIED** | Synthetic A/B marker separation planned; no authoritative mapping or independent tenant-only recovery drill. |
| BR-08 | Coolify control-plane, deployment config, APP_KEY/certificate recovery | **BLOCKED** | No deployed Coolify/vault inventory or separate-host recovery evidence. |
| BR-09 | Owner-approved, measured RPO/RTO | **PROPOSED only** | Proposed targets below are unapproved and unmeasured. |
| BR-10 | App image rollback separated from schema/data recovery | **DOC-VERIFIED / NOT EXERCISED** | Runbook forbids destructive schema rollback as app rollback; compatible image rollback still needs rehearsal. |

## 5. Proposed recovery objectives, schedule and retention

**PROPOSED — owner approval required:** database RPO ≤15 minutes if continuous off-host WAL archive lag is measured and stays within target; file/object RPO ≤1 hour; full host/platform RTO ≤8 hours; single-tenant database RTO ≤4 hours. These are not SLAs or measured results. Nightly logical dumps by themselves cannot meet a 15-minute database RPO.

**PROPOSED cadence:** pgBackRest weekly full + daily differential + continuous WAL archive with target archive_timeout 300 seconds; preserve a complete WAL chain for 35 days. Nightly central and per-tenant custom-format pg_dump copies provide a second logical restore path. Copy private files/objects hourly and create daily checksum manifests/read-back checks. Back up Coolify control-plane state daily and before upgrades. Run a synthetic central + two-tenant drill weekly, PITR monthly, and Coolify/key recovery quarterly and before major upgrades.

**PROPOSED retention:** daily 14 days, weekly 8 weeks, monthly 12 months, WAL/PITR window 35 days. Alert on failed/stale backup, inventory mismatch, checksum/decryption/read-back failure, WAL lag over 10 minutes, DB backup older than 26 hours, file backup older than 2 hours, remote quota failure, vault retrieval error or missing drill artifact. No scheduler or retention policy has been enabled or verified.

## 6. Tests and commands

Prototype checks ran in temporary directory /tmp/backup-workstream, not yet on the repository branch SHA. This evidence is for that local prototype only; exact branch content requires CI execution.

| Exact command | Environment | Result / exit | Artifact / interpretation |
|---|---|---|---|
| bash -n scripts/backup_restore/disposable_pg17_drill.sh | temporary prototype | **PASS, 0** | Syntax-only; no database assertion. |
| python3 -m py_compile scripts/backup_restore/validate_database_coverage.py scripts/backup_restore/test_validate_database_coverage.py | temporary prototype | **PASS, 0** | Python syntax check. |
| python3 -m unittest discover -s scripts/backup_restore -p 'test_*.py' -v | temporary prototype | **PASS, 0; 6 tests** | Exact-set success, missing tenant dump, unexpected DB, duplicate IDs, invalid identifier, missing central DB. Not current-branch CI. |
| command -v docker; command -v podman; command -v psql; command -v pg_dump | task container | **each exit 1** | Required local runtime utilities are absent. |
| bash scripts/backup_restore/disposable_pg17_drill.sh | task container, preflight | **BLOCKED, exit 2** | Aborted before creating any container/network or contacting a database; no restore artifact exists. |
| .github/workflows/backup-restore-disposable.yml | GitHub Actions | **PENDING / NOT VERIFIED** | Record run ID, attempt, tested SHA, status, URL, per-job conclusion and artifact only after direct observation. Historical run 39005405149 is unrelated. |

The proposed harness uses fresh PostgreSQL 17 source and target containers, internal-only Docker networking with no published DB ports, synthetic central/tenant markers, encrypted local temporary dumps, marker and migration checks, synthetic file/key checksums, a sanitized result JSON, and cleanup. It is not a production backup and does not test off-host retention or actual vault/key custody.

## 7. Findings

### BR-F01 — Tenant DB backup inventory has no verified authority
**Severity P1; confidence High; status SOURCE-VERIFIED / BLOCKED.** The current tenant migration does not prove a tenant-ID→database-name mapping, and no approved live registry/catalog manifest was available. Missing or misdirected tenant backups can appear complete. Provisioning owner must provide an authoritative mapping; a backup run must fail unless registry, pg_database and remote checksum-verified DB sets match exactly. Closure requires a tested A/B single-tenant restore and proof other tenant/central state did not change.

### BR-F02 — Independent encrypted off-host copy and key custody are not evidenced
**Severity P1; confidence High; status SOURCE-VERIFIED / BLOCKED.** Inspected active sources show local storage; no approved remote, vault/KMS, immutability or read-back checksum evidence. Host compromise/loss could take primary and backup copies together; key loss could make ciphertext unrecoverable. Owner must select an independent provider/account, least-privilege write and recovery roles, retention/delete protection and a tested authorized key-recovery procedure without printing values.

### BR-F03 — Actual restore and WAL/PITR remain unproven
**Severity P1; confidence High; status NOT RUN.** Existing runbook was non-executed; no configured WAL archive or PITR result was found. Logical-only copies cannot provide arbitrary timestamp recovery and may lose up to a day if run nightly. Run pgBackRest full/differential + WAL and restore a disposable cluster to an explicit time between two synthetic writes; validate pre/post target records and measure the data-loss window/duration.

### BR-F04 — Files, Coolify and recovery keys may not be recoverable
**Severity P1; confidence High; status BLOCKED / NOT VERIFIED.** Source shows local Laravel disks, but production storage and key/deployment restore are unknown. A restored DB may reference missing files, or the app may be unable to decrypt protected values. Identify deployed object/disk resources, checksum-verify every needed object, recover key references through an authorized vault test, and rehearse Coolify/image recovery on a separate host.

## 8. Dependencies, residual risk and next steps

- **Provisioning / PostgreSQL security owner:** provide approved tenant database mapping and inspect actual role attributes, ownership, CONNECT, schema/table/sequence and default privileges. The backup workstream must not invent this authority.
- **Infrastructure owner:** identify actual private database, Coolify resources, file/object backend, separate recovery host, remote account/region and alert destination.
- **Secrets owner:** select vault/KMS and custodians, key-wrap/recovery/rotation/revoke process, break-glass policy and no-plaintext evidence format.
- **Release owner:** approve proposed RPO/RTO and test schema-compatible immutable image rollback/forward-fix plan.

Residual risk is **HIGH**. Do not mark DG-4 or production readiness PASS. A passed synthetic CI drill would prove only the scripted disposable path. Off-host encrypted backup, PITR, real tenant grants and single-tenant restore, real vault/certificate recovery, Coolify recovery, storage consistency and owner-approved RPO/RTO remain independent blockers.

**Recommended status: BLOCKED / NOT VERIFIED.**
