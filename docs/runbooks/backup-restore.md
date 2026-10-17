# Runbook — PostgreSQL 17 Backup, Restore, and Recovery Validation

**Status: PLAN ONLY — NOT RUN / NOT VERIFIED.** This runbook is an operational procedure, not evidence of configured backups, successful restore, PITR, or an accepted RPO/RTO. The current owner ADR selects PostgreSQL 17 and prohibits all Supabase product/project access, including read-only access.

## 1. Purpose and safety boundary

Prove that every recoverable component of the accepted topology is represented by a verifiable off-host backup and that central, multi-tenant, single-tenant, file/object, and point-in-time recovery can be performed in an authorized isolated environment.

**Do not proceed** until the SRE lead has a named isolated recovery target, written authorization, isolated network policy preventing production connectivity, synthetic/approved test data, protected backup read access, and protected restore-key access. If any is missing, record NOT RUN / NOT VERIFIED and stop.

Never deploy, change DNS/TLS/firewall/secrets, restore to production, or access either Supabase project. Do not use production DBs for tests. Do not place credentials, database passwords, APP_KEY, private key contents, or live database names in committed evidence, console recordings, or general logs. The restricted operator manifest may contain actual database names only when encrypted and access-controlled; reports must use tenant IDs or pseudonymous tenant references.

## 2. Target topology and coverage contract

The accepted design is one private PostgreSQL 17 service; one central database; one separate database and restricted runtime role per tenant; a shared Laravel application image; Coolify control-plane state; private business file/object storage; and off-host backup/key custody. The KVM2 host is a single-node MVP target, not HA. Capacity and recovery remain unverified until measured.

| Component | Required recovery material | Required verification |
|---|---|---|
| Central PostgreSQL DB (planned name berkahpos_central; verify actual config privately) | Independent logical backup plus cluster physical base backup/WAL coverage | Restore to isolated PostgreSQL 17; schema/data integrity; registry/config/auth metadata consistent |
| Every tenant DB | Per-tenant logical pg_dump archive; covered by physical base + WAL path | Registry-to-catalog-to-backup reconciliation; individual restore of at least two tenant DBs |
| Tenant registry/catalog | Central DB backup plus encrypted restricted backup manifest | Every ACTIVE/PROVISIONING/SUSPENDED/RETENTION state has a defined expected DB/retention disposition; no unaccounted catalog DB |
| PostgreSQL cluster roles/global objects | Protected global-object backup / documented recreation manifest | Restore required non-secret role attributes and grants in isolated target; do not blindly reuse production credentials |
| Business files and objects | Versioned object copies, metadata/index manifest, object checksums | Representative receipts/exports exist and metadata references resolve |
| Coolify control plane | Supported Coolify instance backup for its DB/config/resources/settings | Restore into a separate recovery host; prove service/resource definitions can be understood/recreated |
| Laravel application/config | Immutable image digest, Git source SHA, deployment config schema and non-secret config manifest | Exact image/source identity; startup and safe authenticated smoke checks using isolated test identities |
| Encryption and recovery keys | Vault-held APP_KEY and relevant encrypted-backup/object-storage/key-encryption material | Key identifier/version and retrieval test; never copy raw key values into the evidence bundle |
| Identity/auth dependencies | Documented identity provider configuration, OAuth/Sanctum/session signing dependencies, callback/config references and recovery/admin access path | Test sign-in/token issuance and revocation using isolated identities; prove recovery access does not depend on an unavailable host |
| Scheduler/queue/cache and other state | Inventory of durable versus reconstructable state; queue definitions and retry policy | Reconstruct volatile services; prove no tenant-specific durable data exists only in cache/queue |
| DNS/TLS and external integrations | Inventory and responsible owner/contact only | Documentation completeness only in this drill; do not change DNS/TLS/firewall in this task |

A scheduled-job success flag, configured remote, present backup object, or successful checksum alone is not restore proof.

## 3. Preconditions and evidence bundle

Record these before the run:

- Run ID, operator, independent reviewer, approval reference, start/end timestamps in UTC and Asia/Jakarta.
- Source repository SHA and dirty state (must be a named clean commit); application image digest; Laravel/PHP/PostgreSQL/client-tool versions; schema/migration revision.
- Source backup ID, capture start/end, recovery target timestamp, backup object IDs, remote region/location, retention expiry, encryption/key version, checksum algorithm/value, encrypted manifest hash.
- Isolated target ID, access boundary, confirmation that it has no production route/credentials and cannot connect to either Supabase project.
- Central registry/catalog snapshot IDs and counts, not sensitive raw DB names in the general report.
- Approved RPO/RTO objectives, if formally defined. If not approved, measure observed lag and durations but do not call any value an SLA.

Keep detailed database-name mapping in a separate encrypted, access-controlled manifest. Commit only templates and redacted evidence. Use docs/evidence/templates/tenant-backup-coverage.csv and docs/evidence/templates/restore-drill.csv.

## 4. Backup strategy

### 4.1 PostgreSQL 17 physical base backup and WAL (cluster-wide recovery)

Use a tested PostgreSQL-17-compatible procedure such as pgBackRest or WAL-G, or a documented pg_basebackup plus continuous WAL archiving. Select one implementation before activation; verify its exact version, feature support, encryption behavior, key management, retention enforcement, and documented recovery workflow. Do not assume a Coolify backup job provides WAL/PITR.

1. Confirm PostgreSQL version, instance identity, archive configuration, archive command/receiver health, checkpoint/backup health, disk headroom, and backup identity privileges. The identity must be separate from normal app, tenant runtime, and provisioning identities.
2. Capture a base backup with a recorded backup label/manifest and known start/end time. Confirm the manifest verifies successfully.
3. Verify continuous WAL archive progression and retention beyond the adopted recovery point objective plus an operational margin. Detect missing/invalid segments; do not report coverage beyond the last verified continuous WAL.
4. Encrypt before or during transfer using the selected, tested implementation; transmit over TLS to a separate off-host account/location. Limit delete rights, separate writer and retention-administrator identities, and enable versioning/immutability only after restore/delete behavior has been tested.
5. Read the remote copy back using the supported client; compare cryptographic checksum/backup-manifest verification results with the expected source. Record size, age, last WAL timestamp/LSN, key reference/version, and verification outcome.
6. Test an isolated cluster restore to a fixed timestamp. Prove the requested time falls within continuous verified base+WAL coverage, and record achieved recovery timestamp and gap from target.

Cluster physical recovery restores a whole PostgreSQL cluster, not one independent tenant. A physical restore alone does not prove each tenant database can be independently restored.

### 4.2 Logical database backups

Take a separate central logical backup and a logical backup for every registry tenant database. Use the tested PostgreSQL 17 pg_dump client and custom archive format. Example command shape, only after target authorization and credential injection is configured:

~~~bash
pg_dump --format=custom --no-owner --no-acl --file="$BACKUP_DIR/$SAFE_ARCHIVE_NAME.dump" --dbname="$DB_NAME"
pg_restore --list "$BACKUP_DIR/$SAFE_ARCHIVE_NAME.dump"
sha256sum "$BACKUP_DIR/$SAFE_ARCHIVE_NAME.dump"
~~~

SAFE_ARCHIVE_NAME must be a generated opaque backup identifier, not a tenant's customer-facing name or an unredacted DB name. DB_NAME, connection parameters, and credentials must come from a protected runtime configuration; do not put passwords in argv, shell history, scripts, logs, or Git. Commands above are templates, not executed results.

For each DB:
1. Take a consistent logical dump with a dedicated backup identity and only the privileges the selected PG17 strategy requires.
2. Record dump start/end, exit code, byte size, client/server versions, checksum, pg_restore-list result, source catalog identifier, and encrypted object reference.
3. Encrypt and upload off-host; then read the remote object back and verify its checksum. Local-only storage is not a completed backup.
4. Reconcile expected registry DBs against the private actual pg_database catalog, generated-name contract and completed logical backup manifest. Record counts and redacted/pseudonymous tenant references in the review report.
5. Fail the whole backup cycle if any expected DB lacks a completed verified copy, if any unapproved database is unexplained, or if registry/catalog membership is ambiguous. Alert; never silently skip a failed tenant.
6. Do not log actual tenant DB names in shared dashboards. Restrict the exact registry ↔ database ↔ object mapping to an encrypted manifest.

The initial operational budget suggests a small bounded concurrency (at most three database dumps in parallel) until measurements prove a different level safe. Backup workload must be included in load testing.

### 4.3 Roles, keys, and application recovery dependencies

- Back up PostgreSQL global objects/roles with the selected, tested mechanism. Protect this artifact as sensitive because role definitions may include security-sensitive data. Restore only required object definitions to the isolated cluster and rotate/recreate credentials there; never copy production credentials into a test.
- Back up required Laravel APP_KEY and any field/object encryption keys separately in an approved vault with access logging, separation of duties, version history and tested recovery. A key identifier is safe evidence; a raw key value is not.
- Record how the identity provider, email/SMS provider, app signing/auth dependencies, queue storage, object-storage credentials, and admin break-glass account will be reconstituted. Do not claim identity recovery based solely on restoring the central DB.
- Back up business object bytes and metadata/indexes independently of database dumps. Compare object manifests/checksums and test references from restored DB rows.
- Record immutable app image digest, source SHA, schema/migration version, deployment config schema and non-secret runtime configuration. Restore the exact tested image to the isolated target; do not rebuild dependencies on the KVM2 host as a substitute for an immutable release artifact.

## 5. Registry/catalog coverage reconciliation

For every run, construct a point-in-time inventory from the central registry and a separate inventory from the PostgreSQL catalog. Reconcile both against a per-object backup manifest.

1. Compare tenant registry states and expected DB lifecycle to catalog databases. A retired/never-provisioned tenant may legitimately lack a DB only if its state policy explicitly says so and the disposition is recorded.
2. Validate each catalog database candidate against the generated database-name contract; do not use a broad LIKE pattern as the sole selector. Resolve exact names in the restricted operator process.
3. Compare the registry-derived expected set, observed catalog set and verified-backup set. Record expected, present, backed-up, uploaded, checksum-verified and restore-tested counts.
4. Explain all exceptions (failed tenant, just-provisioned tenant, approved retention deletion, interrupted provisioning) with tenant pseudonym, disposition, owner and expiry. Unexplained extras/missing entries fail coverage.
5. Confirm central DB itself has a successful, off-host verified copy.
6. Store the precise full mapping only in the restricted encrypted manifest. In review evidence publish counts, opaque IDs and redacted references—not raw DB names.

Coverage acceptance: 100% of expected retained databases have a checksum-verified off-host backup; no unexplained catalog/registry difference; remote object can be read; and the chosen restore path passes. A complete manifest is not equivalent to a restore pass.

## 6. Restore drill A — central database plus at least two tenants

Only use authorized synthetic/approved artifacts, an isolated private target, and a PostgreSQL 17-compatible isolated instance. Egress/credentials must make production and both Supabase projects inaccessible.

1. Record source backup ID, backup finish timestamp, intended recovery timestamp and source repo/image/schema revisions. Record the target environment revision/config separately.
2. Provision a clean isolated PG17 target with sufficient capacity and no route/credentials to production. Capture target identity and isolation check evidence.
3. Retrieve the selected encrypted central logical backup and physical/WAL materials needed for PITR. Verify checksums/backup manifest before restore.
4. Restore the cluster/base/WAL to the requested timestamp if testing PITR; otherwise clearly label the run logical point-in-time-of-dump only. Restore the central logical dump if the test design calls for logical recovery. Avoid restoring the same database twice without an explicit test plan.
5. Pick at least two tenant IDs by recorded reproducible seed from the registry snapshot; include one tenant with representative operational rows and another distinct tenant. If the environment has fewer than two eligible tenant DBs, mark the two-tenant drill NOT RUN / NOT VERIFIED; never invent a tenant/data fixture to claim restore coverage.
6. Restore each tenant archive under its expected isolated test database mapping. Apply the reviewed application/schema migration state only according to the chosen recovery sequence; do not run destructive or forward-only migrations casually.
7. Verify per-database archive integrity, required tables/schema, migration state, key row-count and aggregate invariants, tenant registry/domain/device membership consistency, configuration version/hash and service-specific resolution where implemented, plus object references/checksums.
8. Run application-level read-only/safe smoke flows against the isolated target. Test auth with isolated identities. A successful process exit or migration table alone is insufficient.
9. Record target DB pseudonyms, per-step start/end time, duration, error/log reference, checksum/row invariants, application smoke result, target recovery timestamp, observed data-loss window, and issues.

## 7. Restore drill B — single tenant without overwriting another tenant

A single tenant restore must not overwrite the live database belonging to another tenant or mutate the source backup.

1. Choose a tenant ID from the recorded registry snapshot using a reproducible method. Choose a second tenant as a non-target sentinel and record its pre-test schema/data fingerprints.
2. Restore a cluster base + WAL into an isolated scratch cluster when a point-in-time tenant image is needed. Never promote this scratch cluster to production. Extract the selected tenant DB logically into a new, unique recovery database/namespace.
3. For logical-only recovery, restore the selected tenant archive to a new uniquely generated recovery DB name using protected config. Do not drop, rename, recreate or restore over any existing tenant DB in this drill.
4. Verify the selected tenant ID ↔ restored DB mapping from the central snapshot and inspect the restored tenant's internal identity invariants. Reconcile files/object references and identity/config dependencies needed for a usable tenant.
5. Confirm the sentinel tenant remains unchanged (before/after fingerprints and registry mapping equal) and no unrelated database was modified.
6. Test safe app queries against the restored tenant using isolated auth; assert requests for the sentinel/another tenant remain bound to their own unchanged DB. Verify queue/cache context reset if workers are part of the chosen test.
7. Record duration and integrity results. A test that restores only central DB, overwrites source, omits a sentinel, or does not compare before/after fingerprints fails.

The production cutover/overwrite procedure, if ever needed, requires a separate reviewed change and explicit authorization; it is outside this runbook's isolated drill.

## 8. PITR validation

Restore the physical base backup plus a continuous, verified WAL chain to a specific timestamp T in isolated environment. Record the requested T, actual recovery timestamp and available backup/archive edges. Validate rows/checkpoints on both sides of an agreed marker transaction created only in the isolated test dataset (or use a known synthetic test marker). Demonstrate that transactions after T are absent and previously committed transactions before T are present. Compare expected aggregates and checksums. Then separately test extraction of one tenant from the restored cluster without touching another tenant.

If the selected recovery system has no verified WAL coverage for T, stop: PITR is NOT VERIFIED. A successful logical dump restore is not PITR. A successful physical restore to the latest point is not proof of timestamp recovery.

## 9. RPO/RTO measurement and initial retention hypothesis

Record, do not assume:
- Recovery Point: requested timestamp, last archived/verified WAL point, actual restored point, observed time gap, any missing/incomplete objects.
- Recovery Time: incident/test start, operator authorization time, artifact retrieval duration, decrypt/verify duration, restore/replay duration, integrity validation duration, application-ready timestamp, total elapsed time.
- Service recovery order and dependency blockers: keys, identity, object storage, Coolify, application image, central DB, tenant DBs.

The legacy proposed retention starting point is daily 7 days, weekly 4 weeks, monthly 6 months. It is a planning hypothesis—not an adopted policy or SLA. Confirm legal/business policy, cost, deletion controls, retention locks, object-versioning, storage growth, and restore behavior before acceptance. WAL retention must cover the formally adopted RPO plus operational margin. Do not state an RPO/RTO SLA until owner-approved and demonstrated.

## 10. Rollback rehearsal, monitoring, and incident ownership

Rehearse rollback in an isolated staging/recovery environment: deploy known immutable image N, apply only an explicitly reversible/compatible change, validate smoke and sync behavior, then redeploy known-good image N-1 and validate. If a schema change is not backward-compatible, rehearse the documented forward-recovery path instead; code rollback alone is not accepted if schema/data cannot roll back. Record exact image digests, source SHAs, migration IDs, start/end, health, queue/outbox behavior and rollback outcome.

Required alert/incident ownership:
- Backup job, archive/WAL lag, manifest mismatch, checksum/decrypt/remote-read failure, missing tenant coverage, restore failure or key retrieval failure: primary SRE/on-call owns incident; DBA is technical lead; notify security owner if key/access policy may be implicated.
- Disk warning at 70% and critical at 80% per the existing resource-budget draft; paging threshold must be confirmed against actual usable disk and expected recovery workspace.
- Database connection saturation, API/database latency, queue age/retry growth, OOM/swap pressure, CPU and disk growth: SRE incident commander with application/DB owners as responders.
- Failed restore/PITR or an expired recovery key blocks the recovery gate. Do not waive it because scheduled backup ran green.

For every alert, define signal, metric query/source, threshold duration, notification destination, incident severity, owner, escalation timer, runbook link and last alert-delivery test. Do not invent a contact or claim delivery without evidence.

## 11. Cadence and definition of done

- On every backup cycle: reconcile tenant registry/catalog/verified objects and alert on any gap.
- Daily: review last-success age, WAL lag/continuity, off-host checksum/read verification, storage growth and key/vault health.
- Weekly: restore central plus two tenants to an isolated environment, including file references and core integrity checks.
- Monthly: prove single-tenant isolated restore without changing sentinel tenant and rehearse image/schema rollback or forward recovery.
- Quarterly and before risky control-plane changes: restore Coolify's instance backup to a separate recovery host and reconstitute config/key dependencies.
- Before a recovery/retention policy is accepted: test a timestamp PITR path and record measurable RPO/RTO.

Do not mark the gate passed until evidence identifies timestamps, source and target revisions, artifact/key references, integrity/checksum outcomes, duration, PITR result, sentinel non-overwrite result, reviewers and unresolved exceptions. Store a dated record under docs/evidence/restore-YYYY-MM-DD.md and keep restricted identifiers/keys outside Git. No evidence file or no run means **NOT RUN / NOT VERIFIED**.

## 12. Execution record

As at the preparation snapshot on 2026-10-17, this runbook has **not been executed**. No isolated restore target or recovery artifacts were available in the task context. This is not evidence that the user's infrastructure has no backups; it means this task cannot truthfully claim their coverage or recoverability.