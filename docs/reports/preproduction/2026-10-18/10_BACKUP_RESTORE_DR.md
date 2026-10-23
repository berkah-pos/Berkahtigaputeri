# 10 — Backup / Restore / Disaster Recovery Audit

- **Workstream status:** **BLOCKED / NOT VERIFIED**. No production backup, production-data access, Supabase access, infrastructure changes or database modifications were made.
- **Repository:** berkah-pos/Berkahtigaputeri
- **Base SHA:** 371b7fdf0bf672b37ceb1023e647f114221bf797 (main ref observed before edits)
- **Branch:** audit/preprod-backup-restore-2026-10-18
- **Restore-harness implementation SHA executed by CI:** 5af40b4c57858110cbb96338bbe7df0c8dfc0967. Subsequent report/evidence commit  cca3764990dc6105c0d09ccc36a67a583ecd2f32 changed documentation/evidence only; no drill source changed after the tested implementation commit. **PR:** [#88 — Preproduction hardening: PostgreSQL backup, restore and DR](https://github.com/berkah-pos/Berkahtigaputeri/pull/88), still open/draft. **CI run:** [39226145671, attempt 1](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39226145671), conclusion SUCCESS. Its pull-request merge checkout SHA is 0ee245656e13c217968cde6cbc99db5c1be78b75 (base 371b7fdf0bf672b37ceb1023e647f114221bf797 plus implementation SHA above). No merge or release was performed.
- **Ownership:** PostgreSQL backup inventory, encrypted/off-host retention, uploaded files/config/key recovery, restore drills, RPO/RTO, and separation of application rollback from database recovery.

## 1. Executive summary

The current owner decision selects private PostgreSQL 17 with one central database and a separate database plus restricted runtime role per tenant. At the inspected base SHA, the existing backup/restore runbook identified itself as an unexecuted template and retained a rejected MariaDB alternative. Current source directly verifies only a local Compose PostgreSQL volume and Laravel local filesystem disks. Source does not prove off-host backups, PITR/WAL, production storage, key-vault recovery, Coolify recovery or an authoritative tenant-to-database map.

This branch adds a PostgreSQL-only operational runbook, a synthetic-only disposable PG17 restore harness, an exact-set backup coverage validator and six positive/negative tests, plus an isolated GitHub Actions workflow. A prototype was syntax-checked and the validator tests passed in a temporary staging directory; this environment lacks Docker/PostgreSQL executables, so no local database restore occurred. CI is now observed for candidate head 5af40b4c57858110cbb96338bbe7df0c8dfc0967 via run 39226145671 (attempt 1, SUCCESS), using merge checkout SHA 0ee245656e13c217968cde6cbc99db5c1be78b75. The CI harness restored synthetic central + two tenant DBs and then tenant A into a new recovery DB. Even this success does not prove production backups, remote retention, PITR, tenant privileges or live vault/Coolify recovery.

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



## 9. Execution addendum — 2026-10-19 (supersedes earlier pending CI statements)

### Exact CI evidence

- Workflow: Backup Restore - Disposable PostgreSQL 17 Drill.
- Run ID / attempt: 39226145671 / 1.
- Run URL: https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39226145671
- Job ID: 117972803120; conclusion SUCCESS. Syntax/coverage tests, disposable restore, and artifact upload all completed successfully.
- PR candidate head SHA: 5af40b4c57858110cbb96338bbe7df0c8dfc0967.
- Actual pull-request merge checkout SHA recorded in the drill result: 0ee245656e13c217968cde6cbc99db5c1be78b75, whose parents are base 371b7fdf0bf672b37ceb1023e647f114221bf797 and candidate head 5af40b4c57858110cbb96338bbe7df0c8dfc0967. Do not describe the merge SHA as the PR branch head.
- Artifact: [backup-restore-drill artifact 12172824741](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39226145671/artifacts/12172824741), expires 2026-11-18 08:56:43 UTC. GitHub-reported and independently computed ZIP digest: sha256:5e2dac1bac89f9c439e8b51186036bcbff5e35095cceb65268c3a821397e62c5.
- Artifact integrity: sha256sum -c artifact-checksums.txt returned exit 0 for result.json and the two synthetic checksum manifests. ZIP contains sanitized summaries and hashes, not database dump files.
- Synthetic backup identifier: synthetic-pg17-20261019085450891215732. Started 2026-10-19T08:54:50Z; finished 2026-10-19T08:56:42Z; elapsed 112 seconds. These are mechanics-test timings, not production RTO measurements.
- Database: PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2); image ID sha256:327daa8fae7178d61f93142f146b098467b345e10997b9eb79f63bd58e5c8f3c3. No ports were published for the source/target containers; the drill used a dedicated internal-only disposable Docker network. No production endpoint or data was used.
- Six coverage tests passed: exact set independent of ordering; missing tenant backup fails; unexpected DB fails without revealing its name; duplicate identifier rejected; malformed identifier rejected; central DB required.
- Restore assertions passed: central has two synthetic tenant registry rows; Tenant A and Tenant B each contain their own marker; cross-tenant marker counts are zero. Tenant A was restored from its own dump into new DB berkahpos_tenant_a_recovery: A marker count 1, B marker count 0, central row count remains 2, original Tenant B marker remains 1. Migration-status checks reported no pending migrations for restored central/tenant targets and the isolated tenant-A recovery target.
- Synthetic file/object archive and content checksums validated after copy/restore. Synthetic non-production key material passed encrypt/decrypt checksum comparison. These do not validate an actual object-store provider, KMS or vault.

### Updated gate status from this run

| Gate | Current status | Scope proved / not proved |
|---|---|---|
| Script syntax + six coverage regression tests | PASS — TEST-EXECUTED | Run 39226145671 on merge checkout SHA above. |
| Central + two-tenant logical dump/restore | PASS — TEST-EXECUTED (synthetic only) | Disposable PG17 source to separate target; markers, migration metadata and checksums validated. |
| Independent single-tenant restore | PASS — TEST-EXECUTED (synthetic only) | Tenant A restored to a new DB; Tenant B and central stayed unchanged in test. |
| Local file/key integrity mechanics | PASS — TEST-EXECUTED (synthetic only) | No actual provider, production key, vault or certificate was used. |
| Encrypted off-host remote, retention and read-back | BLOCKED / NOT VERIFIED | CI did not configure or test an external backup provider. |
| Live tenant registry ↔ pg_database ↔ remote backup reconciliation | BLOCKED / NOT VERIFIED | Authoritative tenant-to-database map and live catalog unavailable. CI uses synthetic identifiers and rows. |
| Physical backup/WAL and timestamped PITR | NOT RUN / NOT VERIFIED | No actual WAL chain accessed or recovered. |
| Real storage, Coolify, APP_KEY/KMS/vault and TLS recovery | NOT RUN / NOT VERIFIED | Synthetic local file/key tests do not close real provider/control-plane recovery. |
| Approved and measured RPO/RTO | PROPOSED only / BLOCKED | 112-second synthetic duration is not a service objective or representative recovery benchmark. |
| Workbook 352-entry verification | NOT RUN in this workstream | Binary XLSX was not readable by UTF-8-only repository fetch. The prohibited legacy Supabase sync script was not executed. Do not infer the count from documentation alone. |

### Precise disposition

The direct CI evidence upgrades the central/two-tenant and single-tenant synthetic restore mechanics from NOT RUN to PASS for this workflow run. It does not upgrade real DR readiness: BR-F01 through BR-F04 remain open, and the workstream recommendation remains BLOCKED / NOT VERIFIED until the owner-approved database map, encrypted off-host backups, PITR, actual file/key/Coolify recovery, owner-approved RPO/RTO and a separately authorized staging drill have evidence. PR #88 remains open/draft; no merge, deployment, or release approval occurred.


## 10. Latest exact-head verification — 2026-10-19

This section supersedes the earlier run/attempt/artifact references in §9 for the newest available candidate, and confirms the previous successful run as historical exact-SHA evidence.

- **Current branch head under review:** \`4b75f8b88b4b5a3648ca14f8fb04fad9257af7f6\`.
- **Workflow:** Backup Restore - Disposable PostgreSQL 17 Drill.
- **Run ID / attempt:** \`39227102530\` / \`1\`; **conclusion SUCCESS**.
- **Run URL:** https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39227102530
- **Job ID:** \`117975939700\`; syntax/coverage tests, isolated PG17 drill and artifact upload all concluded SUCCESS.
- **PR head SHA:** \`4b75f8b88b4b5a3648ca14f8fb04fad9257af7f6\`.
- **Actual merge checkout SHA tested by Actions:** \`a1e14add2f79a02823a220ba34a2d8bafe978bc7\`; its parents are base \`371b7fdf0bf672b37ceb1023e647f114221bf797\` and PR head above. The checkout SHA and PR head are distinct; this report does not mislabel one as the other.
- **Artifact:** [backup-restore-drill, artifact ID 12174327830](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39227102530/artifacts/12174327830); expires 2026-11-18 09:04:30 UTC. GitHub-reported SHA-256 digest and locally recomputed ZIP SHA-256 both equal \`96981a71eb09a4ae3b3a0a7eb343d65b0f0e1ab671c4fcdb787f59c16170cfb6\`.
- **Artifact checksum verification:** downloaded ZIP to temporary analysis storage; \`sha256sum -c artifact-checksums.txt\` returned exit code 0 for \`result.json\`, \`synthetic-file-checksums.txt\` and \`synthetic-database-backup-checksums.txt\`. The ZIP contains summaries/checksum manifests only, not database dumps.
- **Synthetic backup identifier:** \`synthetic-pg17-20261019090242460754911\`; UTC start \`2026-10-19T09:02:42Z\`, end \`2026-10-19T09:04:29Z\`; duration **107 seconds**, for mechanics only (not production RTO).
- **Engine:** PostgreSQL \`17.11 (Debian 17.11-1.pgdg13+2)\`; image ID \`sha256:327daa8fae7178d61f93142f146b098467b345e10997b9eb79f63bd58e5c8f3c3\`. Image was referenced by the mutable major tag \`postgres:17\`; immutable digest pinning remains a reproducibility improvement.
- **Coverage tests:** all six passed: exact set/order independence; missing tenant backup rejected; unexpected database rejected without disclosing name; duplicate identifier rejected; malformed identifier rejected; central database required.
- **Restore result assertions:** central contained two synthetic tenant metadata rows; Tenant A and Tenant B each had one distinct marker; both cross-tenant marker counts were zero. Tenant A's own dump was restored into new database \`berkahpos_tenant_a_recovery\`: Tenant A marker count 1, Tenant B marker count 0, central metadata still 2 rows, original Tenant B still 1 marker. Restored migration status had no pending migration for central, Tenant A, Tenant B and the new single-tenant recovery database.
- **Files/key mechanics:** synthetic file/archive checksum copy and restore succeeded; synthetic non-production key material passed local encrypt/decrypt/checksum. This did **not** use or prove an actual object-storage provider, KMS/vault, production APP_KEY, TLS certificate, or off-host retention.
- **Commands recorded in workflow:** \`bash -n scripts/backup_restore/disposable_pg17_drill.sh\` — exit 0; \`python3 -m py_compile scripts/backup_restore/validate_database_coverage.py scripts/backup_restore/test_validate_database_coverage.py\` — exit 0; \`python3 -m unittest discover -s scripts/backup_restore -p 'test_*.py' -v\` — exit 0 / 6 tests; \`bash scripts/backup_restore/disposable_pg17_drill.sh\` — exit 0 in GitHub-hosted Ubuntu 24.04 with disposable Docker/PostgreSQL containers.
- **Safety boundary in artifact:** \`production_backup_used=false\`, \`off_host_provider_tested=false\`, \`pitr_tested=false\`, \`real_vault_tested=false\`. No production/Supabase endpoint or customer data was used.

### Updated gate disposition

| Gate | Latest status | Evidence boundary |
|---|---|---|
| Syntax + six DB coverage tests | **PASS — TEST-EXECUTED** | Run \`39227102530\`, attempt 1, merge checkout SHA \`a1e14add2f79a02823a220ba34a2d8bafe978bc7\` |
| Synthetic central + two-tenant PG17 dump/restore | **PASS — TEST-EXECUTED** | Disposable PG17 only; exact artifact above |
| Synthetic single-tenant restore to new DB without tenant B/central change | **PASS — TEST-EXECUTED** | Independent Tenant A dump restored into \`berkahpos_tenant_a_recovery\`; marker assertions passed |
| Synthetic migration status, file/key checksum mechanics | **PASS — TEST-EXECUTED** | No pending migrations in synthetic targets; synthetic file/key only |
| Actual off-host encrypted backup, retention/read-back and coverage reconciliation | **BLOCKED / NOT VERIFIED** | No actual remote provider, live catalog or approved tenant DB map |
| Actual file/object provider and Coolify/vault/key/certificate recovery | **NOT RUN / NOT VERIFIED** | Synthetic material is not real recovery evidence |
| PITR/WAL at explicit timestamp | **NOT RUN / NOT VERIFIED** | No actual configured/retained WAL chain exercised |
| Owner-approved and measured RPO/RTO | **PROPOSED only / BLOCKED** | 107-second mechanics run is not representative production RTO or SLA |

**Final status remains BLOCKED / NOT VERIFIED.** The CI result is positive direct evidence for this disposable synthetic workflow only. BR-F01 through BR-F04 remain open until the approved tenant database map, external encrypted backup/read-back, PITR, actual files/key/Coolify recovery, owner-approved RPO/RTO and separately authorized staging recovery have evidence. PR #88 remains open/draft; no merge, release, deployment or final go-live approval occurred.
