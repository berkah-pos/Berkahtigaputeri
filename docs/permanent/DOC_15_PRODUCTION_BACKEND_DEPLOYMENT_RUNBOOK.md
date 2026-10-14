# DOC_15 — Production Backend Deployment Runbook (Ubuntu + Managed Supabase)

**Status:** ACTIONABLE RUNBOOK — deployment not yet performed  
**Created:** 2026-10-14  
**Repository:** `berkah-ajb-dev/Berkahtigaputeri`  
**PR:** [#39 — Supabase backend foundation and IDCloudHost rollout guardrails](https://github.com/berkah-pos/Berkahtigaputeri/pull/39)  
**Read with:** `AGENTS.md`, `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`, `DOC_00_MASTER_ROADMAP.md`, `DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md`, `DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md`, and `DOC_14_SUPABASE_IDCLOUDHOST_BACKEND_FOUNDATION.md`.

> This file is the approved implementation checklist and operating contract. A documented target is not proof that a machine was purchased, provisioned, secured, deployed, or certified. Do not mark a gate complete without dated evidence.

## 1. Direct decision: will IDCloudHost use Ubuntu?

**Yes, Ubuntu is the selected operating system for the Berkah POS application VM. It is not automatically guaranteed by the Rp225,000/month plan name.** IDCloudHost's own provisioning guide tells the operator to choose an OS and the Ubuntu version during VM creation.

- Select **Ubuntu Server 24.04 LTS, 64-bit** if listed in the live provisioning catalogue.
- Do not install Ubuntu Desktop or a graphical desktop environment on the production VM.
- If Ubuntu Server 24.04 LTS is not offered, pause provisioning and record the exact available image/version and a compatibility decision before choosing another supported LTS.
- Use IDCloudHost's VM/Cloud VPS provisioning panel, not a generic shared-web-hosting panel.

Official references:
- [IDCloudHost: choose Ubuntu during VM provisioning](https://idcloudhost.com/panduan/cara-melakukan-building-instalasi-server-private-cloud-dengan-menggunakan-os-ubuntu/)
- [IDCloudHost Cloud VPS pricing](https://idcloudhost.com/cloud-vps/#pricing)

### Pre-purchase checks

The current working assumption is **Basic Standard, Rp225,000/month, 2 CPU cores, 4 GB RAM, 60 GB storage**. Verify all of the following in the live checkout; pricing, quota, availability, and tax can change:

- Exact product SKU, billing interval, renewal rate, taxes, and any public IPv4 or storage/network add-on charge.
- Available region and actual OS image/version.
- CPU, RAM and disk capacity after the VM is built.
- Public IPv4 availability and an SSH public-key input.
- Whether provider snapshots/backup are available and what they actually cover. Provider snapshots are not a replacement for application/database restore tests.

**Do not put the full self-hosted Supabase stack on this VM.** Supabase documentation lists 4 GB RAM / 2 CPU cores / 40 GB SSD as the minimum for all services and recommends 8 GB+ RAM / 4+ cores / 80 GB+ SSD. The selected VM is therefore a poor place to host both the entire Supabase stack and the Berkah POS API. Keep Supabase managed.

Reference: [Supabase self-hosting system requirements and limitations](https://supabase.com/docs/guides/self-hosting/docker).

## 2. Approved target architecture

| Component | Responsibility | Release constraint |
|---|---|---|
| Flutter Android POS | SQLite local-first checkout, durable outbox, explicit sync states, retry and user-visible pending/accepted status | Offline sales are not reported as cloud-accepted before server acknowledgement |
| Supabase managed PostgreSQL | Cloud system of record for accepted/synchronized transactions and approved tenant/configuration data | Keep staging and production separate; tenant isolation and migrations must be verified |
| Supabase Auth | User identity and signed session tokens | Membership/role authorization is server-owned; client metadata is not authority |
| PostgreSQL RLS and RPC | Defense-in-depth row access and constrained database operations | Validate every tenant/device/service relationship; preserve the canonical five-layer configuration RPC |
| Supabase Storage | Private file/object storage for product images and business documents | Private by default; authorize each object path by server-verified tenant/record ownership |
| Realtime | Live updates only for features that require them | Subscribe only to authorized channels and tenant-scoped data |
| Edge Functions | Short-lived API/webhook/event functions where they fit | Validate authentication, signatures, payload sizes, replay protection, and authorization |
| IDCloudHost VM | Laravel API, queue worker(s), scheduler, and HTTPS reverse proxy after implementation exists | No managed database moved here by default; no public database/Redis/Docker ports |
| GitHub Actions | CI and deployment orchestration | GitHub-hosted `ubuntu-24.04` runners only; no dependency on Fedora, VirtualBox, or a self-hosted runner |

The Laravel/API deployment is a **target, not an implemented service** at the time of writing. Before creating it, the assigned backend change must follow the existing app/auth/schema contracts and add tests. Do not create duplicate tables where existing schema already owns the data.

## 3. How Supabase Select 2026 features are to be applied

The article [Build anything: Supabase from code, and an MCP server for your app](https://supabase.com/blog/select-2026-build-anything) describes several capabilities. Apply them in the following order:

1. **Code-first configuration and migrations.** Keep CLI configuration and reviewed schema changes in Git. Use the local CLI and GitHub CI for reproducible validation. For this repository, do not enable Declarative Schemas / `pg-delta` until the existing staging history and full schema have been reconciled; current inspection found 12 recorded staging-clone migrations but only 2 SQL migration files in the repository.
2. **Managed Auth, database, RLS/RPC, Storage, Realtime and Edge Functions.** Adopt each where useful, with policy tests and least-privilege rules. Avoid adding a second API path for the same feature without an architecture decision.
3. **Security/performance/health advisors and logs.** Use results as triage inputs, inspect exposure and grants, and record remediation. Do not remove RLS or create blanket permissive policies just to silence findings.
4. **Managed backups and PITR.** Verify plan entitlements, retention, restore method, and incremental cost in the actual project. Test restoration; do not assume a checkbox or a successful backup means data is recoverable.
5. **Supabase Compute.** The Select article describes it as private alpha. Do not make production availability or this deployment dependent on its enrollment or public availability.
6. **Berkah POS app-specific MCP server.** Defer until ordinary tenant authorization, OAuth/session identity, signing keys, per-tool permissions, audit logging, rate limits, and hostile tenant tests pass. Every tool must execute as the authorized signed-in user with RLS enforcement. Never expose unrestricted SQL, a service-role key, or general tenant-admin capability to store users.

References:
- [Supabase Select 2026 — build anything](https://supabase.com/blog/select-2026-build-anything)
- [Supabase Select 2026 recap](https://supabase.com/blog/supabase-select-2026-recap)
- [Supabase self-hosting limitations](https://supabase.com/docs/guides/self-hosting)

## 4. Mandatory schema/history reconciliation before remote migration automation

This repository must not blindly push migrations to a remote project:

- The connected project inventory returned staging and staging-clone; no project positively identified as production. Treat them as staging unless and until a real production project is explicitly confirmed.
- The connected staging-clone had 12 migration-history entries at the audit time; only two SQL migration files are checked into this repository.
- `supabase/config.toml` is local-only and contains no remote project reference or credentials. The `pg-delta` switch remains disabled.
- Do not run `supabase db reset`, destructive schema changes, migration repair, bulk policy changes, or a migration push against staging/production as a shortcut.
- Reconcile each migration version/name and schema object with the owner/source of truth in an isolated workspace. Export/pull a reviewed schema snapshot using a supported Supabase CLI; review functions, triggers, views, grants, RLS, Storage policies, Auth configuration, extensions, seed/data dependencies, and migration checksums. Store secrets and data exports securely and do not commit production data.
- Only after reviewers confirm an accurate baseline should an incremental migration be generated, tested against a fresh isolated database and a staging clone, and merged through a PR.

**Gate:** tracked SQL/config accurately represent reviewed schema changes and the migration plan has a documented rollback/recovery strategy. Do not claim schema-as-code is complete before this gate passes.

## 5. Identity, tenant isolation, and database access

Before implementing transaction sync, define and test the complete chain:

`Supabase Auth user → server-verified tenant membership → enrolled device → tenant-owned transaction`

Required properties:

- Verify access tokens against the intended issuer, audience, expiry, and supported signing keys; or use a trusted Supabase Auth validation method. Reject invalid, expired, or wrong-project tokens.
- Resolve tenant membership and device assignment from server-controlled records. A client-supplied `tenant_id`, device ID, email, or user-editable `user_metadata` is not permission.
- Keep the Supabase publishable key in clients only as intended; never ship service-role/secret keys, PostgreSQL administrator passwords, or long-lived privileged tokens in Flutter, HTML, Git, workflow logs, or artifacts.
- The Laravel API must use least-privilege server credentials and explicitly designed RLS/transaction context for tenant-scoped writes. Do not casually bypass RLS with a privileged connection. Document which server-side operation is permitted to run privileged, why, and what authorizes the caller.
- Preserve the canonical configuration precedence **GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE**. The app uses the authenticated `get_effective_config` RPC for remote effective configuration and caches only a result scoped to the exact tenant/device/service tuple.
- Test Tenant A positive paths, Tenant B denial paths, wrong-device, wrong-service, expired-session, disabled membership, duplicate replay, and privilege escalation. Include Storage paths and subscription endpoints as those features are introduced.

**Gate:** adversarial Tenant A/B tests pass against isolated staging on the revision intended for deployment. Existing source files or RLS being enabled is not sufficient evidence.

## 6. Implementing the Laravel API and reliable sync

The Laravel server must be implemented as a separate reviewed change; do not claim it exists based only on this runbook.

- Pin the PHP/Laravel version, Composer dependencies, container base image, and lockfile. Verify the chosen versions against the repository's CI and IDCloudHost VM limits before deployment.
- Define stable API versions, payload schemas, request-size limits, timeouts, request IDs, and authenticated tenant/device authorization.
- On cloud acceptance, validate product/price/tax snapshots and business invariants on the server. Use fixed-precision/integer monetary values, database constraints, and transactions.
- Make a sale acceptance, sale lines, stock movements, accounting entries required by the approved ledger design, idempotency key, and sync receipt atomic where they comprise one business event.
- The same event and same payload must return the original outcome on retry; the same idempotency key with a different payload must be rejected as a conflict.
- Implement outbox polling or bounded batch sync with retries/backoff, explicit accepted/rejected acknowledgements, payload schema versions, durable error records, and safe handling of permanent failures. Do not remove a local event until its server outcome has been persisted locally.
- Use a database-backed queue first unless workload measurements show a durable need for Redis. Do not spend the VM's limited memory on unnecessary services.
- Test timeout-after-commit, duplicate requests, transaction rollback, app restart, network loss, out-of-order events, stock conflicts, returns/reversals, and tenant mismatch.

**Gate:** no accepted event creates duplicate financial or inventory effects; no required cloud write is partially committed; pending/rejected states are visible to the operator.

## 7. Ubuntu 24.04 host provisioning and hardening

Run this section only after the VM is purchased and the actual Ubuntu Server image/version is confirmed. Use IDCloudHost's web console as a recovery path until SSH access is verified.

### 7.1 Provisioning choices

- OS: Ubuntu Server 24.04 LTS, 64-bit (or a reviewed compatible supported LTS if not offered).
- Initial size: selected Basic Standard as quoted; record actual CPU/RAM/disk from the live VM.
- Authentication: use an SSH public key belonging to the deployment/operator identity; do not put private keys in the VM creation form.
- Create a named administrator account with sudo. Do not run app containers as root.
- Add a public IPv4 only if needed for direct ingress. DNS and TLS require a confirmed domain; do not invent a domain name.
- Save the provider VM ID, region, OS image/build, public address, create date, resource limits, renewal rate, console recovery route, and support contact in the private operations inventory (not in a public issue).

### 7.2 Baseline packages and patching

After connecting through the provider console or SSH, confirm the host identity and OS first:

```bash
cat /etc/os-release
uname -m
nproc
free -h
df -h /
```

Expected OS evidence includes Ubuntu 24.04 LTS and a 64-bit architecture. Do not proceed if the actual image/resources differ from the approved plan without recording the deviation.

Apply updates and install basic maintenance tooling:

```bash
sudo apt-get update
sudo apt-get full-upgrade
sudo apt-get install --yes ca-certificates curl gnupg ufw unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

Review and schedule reboots after kernel/security updates. Do not hide or indefinitely defer security updates. Pin and document the Docker Engine/Compose versions using the vendor's official Ubuntu instructions; do not install arbitrary shell scripts from unverified URLs.

### 7.3 Network and SSH policy

- Permit inbound HTTPS (443) and HTTP (80, for redirect/ACME certificate issuance) at the provider firewall and host firewall. Permit SSH (22) only from the operator's trusted source IP/range where practical.
- Do not expose Postgres (5432), Redis (6379), Docker daemon (2375/2376), Laravel internals, queue dashboards, or management ports to the public internet.
- Before enabling UFW, add the intended SSH allow rule and confirm that a second session or provider console can recover access. Docker can insert network rules that affect UFW assumptions, so enforce the provider/network firewall too and ensure application containers publish only the reverse proxy's ports.
- After public-key login is proven, disable SSH password/root login in a reviewed SSH daemon configuration change, validate the config with `sshd -t`, and reload SSH without terminating the verified recovery session.
- Restrict SSH access; rotate any credential exposed in terminal history or logs. Store backups and secrets off-host.

### 7.4 Docker and runtime process model

- Install supported Docker Engine and the Compose plugin from the official Docker Ubuntu repository. Pin application image tags/digests and record upgrade approvals.
- Deploy only the application services that exist in the reviewed implementation: reverse proxy/TLS, Laravel API, queue worker, and scheduler as needed.
- Keep environment secrets in a server-side environment file owned by the deployment user with restrictive permissions or an approved secret manager; never copy secrets into the image or repository.
- Use non-root containers where compatible, read-only filesystem where practical, health/readiness checks, CPU/memory limits, restart policies, logs with rotation, and named volumes only for data that must persist. Do not treat container layers as durable storage.
- Keep database access to managed Supabase over TLS using the intended connection endpoint and least-privilege DB roles. Verify network restrictions/connection pooler details against the actual Supabase plan. Avoid unnecessary persistent database connections on a small VM.
- Do not deploy self-hosted Supabase Studio, gateway, Postgres, Auth, Storage or Realtime to this VM.

## 8. GitHub CI/CD: deployment is a separate gate

Current repository CI performs checks/builds; it does not prove a production deployment exists.

A deployment workflow may be added only after:
1. The Laravel API, Docker/Compose files, health endpoint, and deployment/rollback scripts exist and are tested.
2. The VM is provisioned, SSH key login and firewall are verified, and a domain/TLS path is agreed.
3. GitHub Environment `production` is configured with least-privilege deploy secrets and approval rules where available.
4. Deployment has a safe staging rehearsal and immutable release/rollback artifact.

Required characteristics:
- Run build/test jobs on GitHub-hosted `ubuntu-24.04`.
- Deploy only from an approved protected branch/ref and an approved GitHub Environment. Use a restricted deployment user/key; do not copy the Supabase service key, DB administrator password, or server root key into generic CI variables.
- Build an immutable artifact/image once and promote that exact revision. Record Git SHA and release identifier.
- Check migrations separately from app rollout; require explicit approval for production database migration. Never run a destructive schema reset from CI.
- Perform preflight and health checks, verify the new app, retain the last known-good release, and stop/roll back on a failed health check.
- Never create an idle GitHub self-hosted runner on the VPS. CI jobs are temporary; production API processes are the long-running services.

## 9. Monitoring, backup, incident recovery

Monitor the app and the managed database separately. Establish dashboards/alerts for API availability and latency, 5xx rate, auth failures, database connection saturation/slow queries, worker queue lag, CPU/RAM/disk, TLS certificate expiry, backup status, and storage growth.

- Use structured logs and request/correlation IDs. Never log passwords, tokens, API keys, full payment credentials, private file content, or unnecessary customer data.
- Enable Supabase security/performance/health advisors and inspect relevant service logs. Triage findings by actual schema exposure, intended role, query patterns and impact; do not blanket grant access or create every suggested index without review.
- Verify the selected Supabase plan's backup frequency, retention, PITR availability, restore procedure and additional cost in the live dashboard.
- Configure file-object recovery independently of PostgreSQL recovery.
- Before public production, run a staged restore drill for database and files. Record the restore time, integrity queries, object references checked, and any missing records/files.
- Propose and approve explicit RPO/RTO targets with the business owner before production. The targets are not considered met until a restore drill demonstrates them.
- Document contacts, incident severity, rollback procedure, token/secret rotation, and a post-incident evidence record.

## 10. Supabase and application CI acceptance

Do not mark this runbook complete based on static CI alone. The release checklist must show:

- [ ] Local Supabase configuration parses, and no secret is tracked.
- [ ] Migration/schema ownership and remote history are reconciled.
- [ ] CI validates canonical configuration inheritance and the 352-key inventory.
- [ ] Tenant A/B adversarial tests pass for auth, RPC, SQL/RLS, API and storage paths in isolated staging.
- [ ] Server transaction idempotency, rollback, retries and durable outbox acknowledgement pass tests.
- [ ] Offline checkout still works without a network, and pending sales survive app restarts.
- [ ] Laravel build is reproducible with pinned dependencies and an immutable revision.
- [ ] Ubuntu release, SSH, network firewall, HTTPS and deployment identity are evidenced.
- [ ] Database and file backup restore drill passes and approved RPO/RTO are recorded.
- [ ] Monitoring, alert routing, log redaction, resource limits and rollback are tested.
- [ ] No unresolved critical/high security issue; production owner explicitly approves release.

## 11. Evidence status as of 2026-10-14

### Verified from source/tool inspection
- IDCloudHost's published provisioning guide tells users to choose an OS and Ubuntu version during VM creation.
- The two connected Supabase projects discovered during the audit are named staging and staging-clone; production was not positively identified.
- The staging-clone reported 12 recorded database migration versions and the repository currently contains 2 migration SQL files.
- The inspected staging-clone contained 352 `app_config` rows with RLS enabled.
- Supabase advisors returned informational findings that require triage; their presence is not equivalent to a production test.

### Implemented in Git branch / CI
- Local-only `supabase/config.toml`, backend-foundation guardrails, and a static CI workflow are present on PR #39.
- This runbook and an explicit Ubuntu provisioning choice are being added through the same reviewed PR.
- Successful foundation CI verifies repository-level checks only; it does not verify a live VM, deployment, or database changes.

### Not run / not verified
- Purchase/provisioning of the IDCloudHost VM, selected OS on the actual VM, domain/DNS/TLS, SSH hardening, Docker installation, and Laravel deployment.
- Migration history reconciliation, destructive-free full schema snapshot review, Declarative Schemas / `pg-delta` rollout, Tenant A/B API security tests, real sync/load tests, backup restore drill, and production health checks.
- Production Supabase project, actual backup/PITR entitlement, live resource budgets, credentials, and operational RPO/RTO.

No production release is certified by this document.

## 12. Live migration reconciliation update — 2026-10-14

The current read-only ledger is in [DOC_16 — Supabase Migration and Schema Reconciliation Ledger](DOC_16_SUPABASE_MIGRATION_RECONCILIATION.md). It records 139 migration-history rows on staging, 12 on staging-clone, zero exact version matches for the two checked-in migration filenames, schema fingerprint drift, and a clone SECURITY DEFINER execution-grant warning. The baseline is **BLOCKED**; do not run `supabase db push`, `supabase migration repair`, or `supabase db reset` on either existing project until missing SQL sources are recovered and clean-replay gates pass.


## Sources

- [IDCloudHost Ubuntu provisioning guide](https://idcloudhost.com/panduan/cara-melakukan-building-instalasi-server-private-cloud-dengan-menggunakan-os-ubuntu/)
- [IDCloudHost Cloud VPS pricing](https://idcloudhost.com/cloud-vps/#pricing)
- [Supabase Select 2026: code-first backend and app MCP](https://supabase.com/blog/select-2026-build-anything)
- [Supabase Select 2026 recap](https://supabase.com/blog/supabase-select-2026-recap)
- [Supabase self-hosting documentation](https://supabase.com/docs/guides/self-hosting)
- [Supabase Docker requirements](https://supabase.com/docs/guides/self-hosting/docker)
