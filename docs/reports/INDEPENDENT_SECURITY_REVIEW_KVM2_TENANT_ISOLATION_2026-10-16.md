# Independent Security Review — KVM2 tenant isolation

**Review date:** 2026-10-16 (Asia/Jakarta)  
**Historical candidate reviewed:** security/independent-kvm2-isolation-review-20261016; Phase 4 head c6b0cf27ebafbba9e4407fb61d130e4438af3c44  
**Authority checked:** current main; owner ADR commit d7ee23cfaada3405416b01d9e127e32b07fb1a38  
**Status:** **FAIL — do not merge/promote the MariaDB candidate; live isolation gates remain NOT VERIFIED.**  
**Scope:** source audit and a dependency-free, disposable MariaDB 11.4 grant-capability reproduction. This is not a production or shared-staging test.

## Executive determination

The reviewed candidate's provisioning policy violates the intended least-privilege boundary. Its private provisioner grant file grants global CREATE USER and tenant-pattern SELECT, INSERT, UPDATE, DELETE WITH GRANT OPTION. If an attacker controls that worker, process isolation and the missing public port do not constrain those SQL privileges to the tenant currently being provisioned: the role can operate across the matching tenant database-name pattern and create additional database principals or delegate matching DML. The accompanying scripts/check_provisioner_grants.py already detects this as a security failure; its existence is not evidence that the behavior was executed.

There is a separate architecture gate: the owner-approved ADR on current main selects PostgreSQL 17 and rejects MariaDB 11.4 as the migration target. The MariaDB grants and tests are therefore a historical candidate to characterize, not a valid target implementation. The PostgreSQL-specific broker/role boundary required by the accepted ADR remains unimplemented and unverified in the evidence accessible for this review. Do not port this MariaDB grant scheme to PostgreSQL or interpret this MariaDB reproduction as proof of PostgreSQL isolation.

## Threat model

### Assets and trust boundaries

- **Central control plane:** tenant/domain registry, membership, devices, subscriptions/entitlements, configuration metadata, and encrypted tenant connection material.
- **Tenant database:** each tenant's operational POS/accounting records, credentials, and configuration overrides.
- **Public web process / default queue:** authenticated but untrusted request/job inputs; may access central metadata and initiate tenant-context operations. They must not hold root, migrator, or global provisioning credentials.
- **Private provisioner process:** privileged orchestration worker with no published port. Treat code execution in this worker as a plausible compromise; private network placement is not a SQL least-privilege boundary.
- **Database control plane:** elevated user/role creation and per-tenant grants. It must validate one server-side tenant reservation at a time and must not let a caller select a grant target by arbitrary SQL identifier.
- **Long-lived queue process:** mutable tenancy, connection, auth, cache, locale, and filesystem context must be reset between jobs.
- **Host/domain selector:** HTTP Host can route a request but is not identity proof; X-Forwarded-Host must only be trusted under a verified proxy contract and must not override the canonical routing decision.

### Attacker assumptions

An attacker may gain code execution in the private provisioning worker, compromise a normal web/default queue process, send arbitrary authenticated/unauthenticated HTTP headers and IDs, or cause tenant A work to be followed by tenant B work in a reused queue process. This review does not assume access to root, the host, production credentials, or the Supabase staging projects.

### Intended impact boundary

A compromised single-tenant runtime connection should not read or alter central metadata or any other tenant database. A compromised provisioner should be constrained to one authorized provisioning operation/tenant reservation and should not be able to read, write, delete, or delegate access across existing tenant databases. A compromise of the shared Laravel web process is a different, larger threat; per-tenant databases alone do not provide isolation from that process if it can recover every tenant credential.

## Prioritized findings

### F-01 — HIGH: Provisioner can administer and delegate across the tenant DB pattern

**Evidence (source verified):**
- Candidate grant SQL: [docker/mysql-init/10-tenant-db-privileges.sql](https://github.com/berkah-pos/Berkahtigaputeri/blob/security/independent-kvm2-isolation-review-20261016/docker/mysql-init/10-tenant-db-privileges.sql)
- Provisioning implementation: [TenantDatabaseProvisioner.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/security/independent-kvm2-isolation-review-20261016/app/Services/TenantDatabaseProvisioner.php)
- Existing policy checker: [check_provisioner_grants.py](https://github.com/berkah-pos/Berkahtigaputeri/blob/security/independent-kvm2-isolation-review-20261016/scripts/check_provisioner_grants.py)

The relevant statements are:

    GRANT CREATE ON berkahpos\_t\_%.* TO 'berkahpos_provisioner'@'%';
    GRANT CREATE USER ON *.* TO 'berkahpos_provisioner'@'%';
    GRANT SELECT, INSERT, UPDATE, DELETE
      ON berkahpos\_t\_%.* TO 'berkahpos_provisioner'@'%' WITH GRANT OPTION;

**Impact if the statements behave as granted:** a compromised provisioner can read, insert, update and delete data from any matching tenant database; create additional matching databases; create arbitrary MariaDB accounts; and attempt to delegate tenant DML to another account. The DML scope is wider than one in-flight tenant provisioning request. This finding does **not** claim global DROP, global DDL, or full root privileges.

**Runtime proof status:** the dedicated CI job below runs only against an ephemeral MariaDB 11.4 service and preserves redacted SHOW GRANTS/probe output. The previous Phase 2/4 Laravel CI did not reach its tests: draft PR #47 reports Composer dependency-resolution failure before MariaDB grants, HTTP, or queue tests ran. A source guard cannot substitute for actual SHOW GRANTS and capability attempts.

**Required remediation:** do not promote this MariaDB candidate. For the selected PostgreSQL 17 target, implement a reviewed private broker/definer design that accepts a server-side tenant reservation, maps it to exactly one prevalidated database and role, grants only that tenant's runtime permissions, and cannot accept arbitrary role/database names from a request. Test actual role attributes, database owner, PUBLIC/CONNECT, schema/table/sequence/default grants, DDL boundaries, and negative direct A↔B access using real disposable PostgreSQL roles. If a global control-plane capability remains unavoidable, the owner must explicitly accept the documented compromise blast radius rather than describe it as tenant-isolated.

### F-02 — HIGH: Shared APP_KEY makes every encrypted tenant runtime DB password available to web/default queue code

**Evidence (source verified):**
- [docker-compose.yml](https://github.com/berkah-pos/Berkahtigaputeri/blob/security/independent-kvm2-isolation-review-20261016/docker-compose.yml) correctly excludes PROVISIONER_*, MIGRATOR_*, and MariaDB root credentials from app and the default queue. The private tenant-provisioner service receives the provisioner/migrator secrets.
- The same Compose file supplies the shared APP_KEY to all these Laravel services and supplies central DB credentials to app and queue.
- [TenantDatabaseProvisioner.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/security/independent-kvm2-isolation-review-20261016/app/Services/TenantDatabaseProvisioner.php) saves each tenant DB password encrypted with Laravel Crypt in central tenant provisioning metadata.
- [TenantDatabaseManager.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/security/independent-kvm2-isolation-review-20261016/app/Database/TenantDatabaseManager.php) decrypts that value with Crypt::decryptString when opening tenant connections.

**Impact:** excluding global provisioning credentials is necessary but not sufficient. Code execution in a normal Laravel process with access to central tenant metadata and the same APP_KEY can potentially decrypt stored tenant runtime passwords and connect directly to other tenant databases. That is a larger compromise boundary than “a normal app process only gets the tenant credential currently in context.”

**Required remediation:** document and decide this shared-app compromise model explicitly. Do not claim tenant-database isolation contains a web-process compromise while that process can decrypt every tenant password. Prefer an access boundary that does not expose all recoverable tenant passwords to the public web/default queue (for example, brokered per-tenant connection capability with strict caller/tenant binding, short-lived credentials, and no API that can mint arbitrary cross-tenant access). At minimum, prove that credentials for tenant B cannot be recovered or used from a request/normal worker operating as tenant A; document residual risk of full shared-app process compromise.

### F-03 — HIGH: Required tenant A/B and middleware tests are designed but not executed

**Evidence:** Draft [PR #47](https://github.com/berkah-pos/Berkahtigaputeri/pull/47) reports Composer advisory resolution failure for the unlocked Laravel 11 / Filament 3 dependency graph before the requested MariaDB grant, HTTP Host/domain, and same-worker A→B suites ran. The current owner ADR selects Laravel 13 / PHP 8.4 / Filament 5 / stancl/tenancy v3.10.1 candidate / PostgreSQL 17 instead; see [owner ADR on main](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md).

**Impact:** no passing source guard, defined test, or unrelated green CI establishes runtime isolation. The stale MariaDB tests do not verify the approved PostgreSQL target.

**Required remediation:** rebase/implement on the approved stack and make clean dependency installation and real disposable PostgreSQL A/B, broker, HTTP, and long-lived worker tests mandatory. Keep the gate red until exact-head tests execute and artifacts are retained.

### F-04 — MEDIUM: Laravel health check conflicts with the fail-closed Host boundary

**Evidence:** Compose checks http://127.0.0.1/up in [docker-compose.yml](https://github.com/berkah-pos/Berkahtigaputeri/blob/security/independent-kvm2-isolation-review-20261016/docker-compose.yml). The global [HostDomainBoundary.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/security/independent-kvm2-isolation-review-20261016/app/Http/Middleware/HostDomainBoundary.php) treats Host as the routing selector, and only configured central domains bypass registered-tenant resolution. The loopback IP is not declared a central domain in this candidate configuration.

**Impact:** the readiness request may be rejected as an unknown host, causing an otherwise running container to fail health checks. This is a source-level interaction, not a recorded deployment failure.

**Remediation:** make the health probe present an explicitly configured central Host and test it through the real kernel/proxy contract, or expose a private readiness mechanism that cannot be reached as a public bypass. Execute the health check in the built image before deployment.

### F-05 — MEDIUM: Effective-config domain is optional and cannot be treated as an authorization assertion

**Evidence:** [EffectiveConfigController.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/security/independent-kvm2-isolation-review-20261016/app/Http/Controllers/Api/V1/EffectiveConfigController.php) accepts domain as sometimes/nullable. [EffectiveConfigResolver.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/security/independent-kvm2-isolation-review-20261016/app/Services/EffectiveConfigResolver.php) returns from assertDomainBelongsToTenant when the value is null/blank.

**Counter-evidence / bounds:** absence of domain does not, by itself, bypass the resolver's other source-level checks: active user, active tenant, membership (except super-admin), active registered device tied to the tenant, device owner, valid subscription state, and enabled service. Do not classify this as a demonstrated cross-tenant authorization bypass.

**Remediation:** decide whether the central API contract needs a domain assertion. If it does, make the field required and compare it to the central registry; otherwise remove it from the endpoint contract so callers and reviewers do not mistake it for a mandatory check. Verify inactive domain and Host routing in HTTP integration tests.

### F-06 — MEDIUM: Subscription selection mixes “latest record wins” with “active beats trial”

**Evidence:** EffectiveConfigResolver::selectAuthoritativeSubscription first rejects when the newest all-status record is unusable, then returns active before trial from all nonexpired active/trial records. EnsureTenantSubscriptionIsActive only validates the newest all-status record before tenant initialization.

**Behavioral ambiguity:** if the latest record is an unexpired trial but an older active row remains unexpired, the resolver's second query returns the older active row because of the active-first CASE expression. A newer suspended/canceled record is not bypassed. Source comments establish an intent, but not whether a newest valid trial should supersede the old paid entitlement.

**Remediation:** have the owner choose whether latest record is authoritative or active ranks above trial, then enforce one policy in middleware and resolver and test active+trial overlap, newest trial, newer suspension/cancellation, and expiry-boundary timestamps.

### F-07 — MEDIUM / NOT VERIFIED: SQL errors may carry generated DB passwords into exception paths

**Evidence:** TenantDatabaseProvisioner quotes the generated password into a CREATE USER ... IDENTIFIED BY <literal> SQL statement and rethrows Throwable after safe application logging. The framework/queue exception-reporting path and failed-job storage for this exact failure were not executed.

**Risk:** some database/framework exception representations contain SQL text, which may expose that generated password in exception messages or failed-job records even when the custom structured log omits it. No actual secret leak was observed in this review.

**Remediation:** avoid emitting generated passwords in exception/SQL telemetry, use a parameterized/driver-supported credential statement where verified, sanitize exception messages before they leave the provisioning boundary, and execute failure injection followed by an explicit secret-leak scan of logs, HTTP errors, and failed-job payloads.

## Evidence status and acceptance matrix

Statuses distinguish static inspection from tests actually executed. A test file, source guard, passing lint, or test plan is not a test result.

| Gate | Status | Evidence / required next step |
|---|---|---|
| Current architecture authority / exact target branch | **FAIL** | Current main owner ADR selects PostgreSQL 17 and rejects MariaDB 11.4 as migration target; rebase and audit the PostgreSQL candidate. |
| Historical MariaDB grant source | **FAIL — SOURCE-VERIFIED** | Grant SQL grants global CREATE USER and tenant-pattern DML WITH GRANT OPTION. |
| Actual MariaDB 11.4 version and raw SHOW GRANTS | **NOT VERIFIED** | Run [#38918471151](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38918471151) completed failure with 0 jobs and 0 artifacts; no DB version, raw grant, or probe output was produced. Treat this as workflow/test startup failure, not a security-test result. |
| Provisioner compromised-service blast radius | **FAIL by source design; runtime proof status follows the disposable job** | See F-01; process separation is not SQL least-privilege proof. |
| Public web/default queue lack PROVISIONER/MIGRATOR/root environment variables | **PASS — SOURCE-VERIFIED only** | Compose allowlist confirms absence. This does not imply no cross-tenant credential access. |
| Normal-process access to all encrypted tenant credentials is contained | **FAIL — SOURCE-VERIFIED risk** | Shared APP_KEY + central metadata access + decrypting manager; see F-02. |
| Guessed IDs, wrong membership/device, inactive tenant/domain, subscription expiry | **NOT VERIFIED** | Source checks exist; Laravel HTTP tests did not execute. |
| Hostile Host / X-Forwarded-Host; central-versus-tenant panel/API | **NOT VERIFIED** | Middleware and test definitions inspected; no kernel test execution evidence. |
| Direct tenant A↔B/central DB access denial | **NOT VERIFIED** | Existing MariaDB tests did not execute; they do not satisfy PostgreSQL 17 acceptance. |
| Cache collision and tenant file paths | **NOT VERIFIED** | Source prefixes keys and files by tenant hash; execution must be recorded against two disposable tenants. Object-store isolation is NOT VERIFIED; only local filesystem disks are configured in this candidate. |
| One long-lived queue worker doing A then B | **NOT VERIFIED** | Test exists in PR #47, but dependency installation blocks execution per PR report. |
| Error/log/output leakage | **NOT VERIFIED** | Source identifies generated-password exception risk; inject failure and scan captured outputs. |
| Optional domain semantics | **FAIL — design ambiguity, not an authorization bypass proven** | Optional/null value skips only the domain consistency assertion; other checks remain present. |
| Latest subscription vs active-first overlap semantics | **NOT VERIFIED at runtime / owner policy needed** | Source behavior described in F-06; add deterministic overlapping-row tests. |
| Host health-check behavior through middleware | **NOT VERIFIED** | Source indicates URL Host may be rejected; run built-container health check. |
| Production/shared staging unchanged | **PASS — process boundary** | This review performed source/connector inspection only and configured the grant reproduction for a throwaway CI service. No production or shared-staging access was attempted. |

## Disposable MariaDB reproduction

Workflow: [Security review — historical MariaDB provisioner blast radius](https://github.com/berkah-pos/Berkahtigaputeri/blob/security/remediate-kvm2-isolation-20261016/.github/workflows/security-review-mariadb-grants.yml)  
Fixture: [historical grant fixture — explicitly NOT FOR RUNTIME](https://github.com/berkah-pos/Berkahtigaputeri/blob/security/remediate-kvm2-isolation-20261016/audit/security/fixtures/rejected-mariadb-11.4-phase2-grants.sql)  
Probe: [disposable blast-radius test](https://github.com/berkah-pos/Berkahtigaputeri/blob/security/remediate-kvm2-isolation-20261016/scripts/security/reproduce_mariadb_provisioner_blast_radius.sh)

When it runs, the job is designed to create only synthetic tenant A/B schemas and random throwaway account passwords. It emits server version and SHOW GRANTS output with authentication material redacted, then probes tenant B read/update/insert/delete, creation of a tenant-pattern database, global account creation, and delegation to a third synthetic account. Run #38918471151 did not allocate a job and the artifact endpoint returned zero artifacts, so these operations and raw SHOW GRANTS were NOT EXECUTED / NOT VERIFIED. No output may be inferred from the workflow definition.

**Important limitation:** this job characterizes the rejected MariaDB grant policy only. It does not test Laravel HTTP authorization, a long-running worker, or the owner-approved PostgreSQL target.

## Remediation decision

1. Keep the MariaDB candidate/PR stack blocked; do not weaken security checks or approve process isolation as a substitute for least privilege.
2. Implement the owner-approved PostgreSQL 17 model on a dedicated restacked branch with a private narrowly validating provisioning broker, isolated owner/migrator/runtime roles, explicit PUBLIC/CONNECT policy, and real disposable tenant A/B grants.
3. Make the complete requested negative-test matrix mandatory against exact candidate SHA, then inspect sanitized raw DB-role/grant evidence and captured application errors/logs.
4. Retain this review and raw disposable MariaDB grant artifact as historical proof of why the previous privilege scheme cannot be accepted; do not call it a PostgreSQL test result.
