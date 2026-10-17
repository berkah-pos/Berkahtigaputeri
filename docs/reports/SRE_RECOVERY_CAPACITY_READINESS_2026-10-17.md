# SRE Readiness Evidence — Recovery and Capacity (2026-10-17)

**Overall disposition: PLAN PREPARED; EXECUTION NOT RUN / NOT VERIFIED.**  
**Repository:** berkah-pos/Berkahtigaputeri  
**Canonical main SHA observed:** 5b0ad4d5808008c33e6cb66176e3433fad5902a0  
**Inspection time:** 2026-10-17, Asia/Jakarta  
**Target:** Hostinger KVM2-class single node, Coolify, Laravel/PHP 8.4, private PostgreSQL 17, one central DB and one DB/restricted runtime role per tenant  
**Change scope:** operational runbooks, measurement templates and this evidence report only. No application code or privilege code changed.

## 1. Authority and exact revision evidence

Source materials inspected from the canonical repository at main SHA 5b0ad4d5808008c33e6cb66176e3433fad5902a0:

| Source | Blob SHA | Operational interpretation |
|---|---|---|
| docs/KVM2_RESOURCE_BUDGET.md | d62f317ef964691338271cc9c8becc57d428663a | Budget is explicitly planning-only, not measured/certified; KVM2 starts as 2 vCPU / 8 GB RAM / 100 GB NVMe |
| docs/runbooks/backup-restore.md | c176efab817567555ed6a52720fd511ffd6a46a3 | Existing runbook was a template; no restore evidence in the file |
| docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md | 6d73f431ec8959e548d8ae69c27a33fcfab218ff | Target selected but not implemented/deployed; capacity, tenant count, recovery and production are NOT VERIFIED |
| docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md | 5477b92e975213cf74aef6d15d4c89607935427d | Latest owner authority: private PG17, KVM2/Coolify, no use/access of either Supabase project |
| docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md | 388f07297cf406ee240f6941d6fd835c95f4186f | Owns only canonical configuration inheritance/workbook contract; does not prove running API |
| docs/permanent/DOC_00_MASTER_ROADMAP.md | 6f38fbfe9b93b1ede076cf7f7d8bc6324fa7e7ca | Phases 6–7 require measured workload, encrypted off-host backup and successful restore evidence |

### CI evidence boundary

- Current-main exact-SHA workflow observed: [Canonical Workbook Validation run 39006381253](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39006381253), commit 5b0ad4d5808008c33e6cb66176e3433fad5902a0, conclusion SUCCESS. This is workbook validation only.
- The exact commit-status endpoint for that SHA returned zero status checks and aggregate state pending. No full PostgreSQL recovery or KVM2 load test was found/claimed for this SHA.
- Historical baseline CI [run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) passed dependency/bootstrap, disposable PostgreSQL 17 central/tenant migration smoke and production-image smoke on older baseline SHA aab154f87342f2a02a1319e1d370ce831dbef522. It is not restore, PITR, tenant privilege, staging, production or capacity evidence.

## 2. Execution findings

No authorized isolated recovery/load target, source backup inventory, protected vault/key verification, workload generator run or measured host metrics were made available in this task context. No infrastructure commands were run. This does not prove the owner has no backups; it means their existence, integrity, off-host status and recoverability could not be verified here.

| Gate | Status | Evidence needed to change status |
|---|---|---|
| Central + every tenant DB inventory against registry and pg_database | **NOT RUN / NOT VERIFIED** | Dated redacted coverage manifest; no unexplained expected/present/backup-set difference |
| Encryption at rest/in transit and vault/key retrieval | **NOT RUN / NOT VERIFIED** | Protected-key version/reference and read/decrypt verification; no raw secrets in report |
| Off-host retention, remote read, checksum integrity | **NOT RUN / NOT VERIFIED** | Exact remote object refs, retention expiry, checksum before/after upload and readback |
| Central restore to isolated PG17 | **NOT RUN / NOT VERIFIED** | Start/end timestamps, source backup ID/revision, target revision, archive integrity and application checks |
| At least two tenant DB restores | **NOT RUN / NOT VERIFIED** | Two registry-derived tenant IDs / pseudonyms, deterministic seed, each integrity and application check |
| Single-tenant recovery without overwriting another tenant | **NOT RUN / NOT VERIFIED** | Restore to a new isolated DB/namespace; sentinel tenant pre/post fingerprint unchanged |
| PostgreSQL PITR to an exact timestamp | **NOT RUN / NOT VERIFIED** | Base backup + verified continuous WAL path, requested/actual target timestamps, known-marker boundary checks |
| Files/objects, Coolify, APP_KEY and identity/config recovery dependencies | **NOT RUN / NOT VERIFIED** | Off-host artifact/key inventory, restore to separate host/target and dependency smoke evidence |
| RPO/RTO | **NOT MEASURED** | Approved objectives (if any) plus observed recovery point gap and elapsed recovery phases |
| Rollback/forward recovery rehearsal | **NOT RUN / NOT VERIFIED** | Exact image N/N-1 digests, schema compatibility path, timestamps, post-recovery sync/correctness |
| KVM2 CPU/RAM/connection/DB/API/disk/queue/retry headroom | **NOT RUN / NOT VERIFIED** | Representative staged workload; raw samples and distribution summaries; thresholds fixed before run |
| Alerts and incident ownership | **PLAN NOT EXECUTED** | Real metric rules, named internal owner/contact, escalation path and alert-delivery test |

## 3. Workload assumptions for the next authorized test

The proposed scenario ladder in docs/runbooks/load-capacity.md is a test plan, not claimed capacity: baseline one tenant/1–2 clients; five tenants/15 clients; stepped 1/5/10/20 concurrent clients; reconnect bursts replaying up to 200 sales per device; stable idempotent retries and conflicting payload tests; cross-tenant sentinel tests under load; two-to-four-hour soak at the highest previously passing level; backup-overlap sampling; and isolated rollback/forward recovery.

Run only progressively, using synthetic data and a pre-tested stop path. The client must model local SQLite + durable outbox semantics if the claim concerns offline sync; a server-only generator cannot prove end-to-end mobile sync. The currently documented central/API/tenant-privilege and Flutter transition gates remain incomplete or unverified. If required APIs or test-data cleanup are missing, mark the scenario BLOCKED instead of synthesizing a pass.

Candidate lab thresholds are in the load runbook and require product-owner ratification before they become release gates. Protective aborts remain mandatory. No tenant-count, API latency, uptime, RPO, RTO or HA guarantee is made by this report.

## 4. Outputs prepared in this change

- docs/runbooks/backup-restore.md — PostgreSQL 17-only operator procedure for base/WAL and per-DB logical backups, registry/catalog coverage, encryption/off-host verification, central + two-tenant restore, single-tenant restore with sentinel integrity, PITR, files/keys/identity/Coolify recovery, RPO/RTO logging, rollback and incident ownership.
- docs/runbooks/load-capacity.md — isolated load ladder, metric definitions, protective abort gates, candidate acceptance thresholds, headroom method, monitoring ownership and rollback rehearsal.
- docs/evidence/templates/tenant-backup-coverage.csv — one-row-per expected central/tenant database coverage reconciliation.
- docs/evidence/templates/restore-drill.csv — restore/PITR/single-tenant/sentinel measurements and source/target revision record.
- docs/evidence/templates/load-test-samples.csv — time-series workload, CPU/RAM/connection/latency/disk/queue/retry samples.

Templates have headers only. No measurements have been fabricated or written into them.

## 5. Safety invariants preserved

- No production deployment or restoration.
- No DNS/TLS/firewall/secret change.
- No use of either Supabase project, including read-only.
- No application implementation or database privilege/provisioner code modified.
- Actual tenant database names and secret values must remain only in a separately protected encrypted operator manifest; use pseudonymous references in shared evidence.
- Configured jobs, backup objects, runbooks and prior CI smoke are not substitute evidence for successful restoration or measured capacity.

## 6. Exit criteria

Do not mark recovery or capacity green until runs are executed in an authorized isolated environment and reports contain timestamps, exact source/target revisions and image digests, integrity/checksum outcomes, measured duration/headroom, alert tests, rollback result, reviewer and unresolved exceptions. On current evidence, overall disposition remains **NOT RUN / NOT VERIFIED**.