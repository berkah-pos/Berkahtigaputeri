# ADR-2026-10-16 — Provisioner Privilege Boundary and Compromise Blast Radius

**Status: BLOCKED — decision owner approval required.** This document records the current privilege model and requires an explicit decision; it is not an acceptance by the authoring agent.
**Date:** 2026-10-16
**Repository:** `berkah-pos/Berkahtigaputeri`
**Candidate reviewed:** `security/phase-6-kvm2-backup-budget-audit-20261016` at `8ba62ca1c6daad8582eb0edc6e12fce37681dd6a`
**Scope:** MariaDB 11.4 account creation, tenant database privileges, and compromise of the private tenant-provisioning service.

## Decision required

The current grant model gives the private provisioner:
- global `CREATE USER` on `*.*`;
- `CREATE` on the tenant database-name pattern;
- `SELECT, INSERT, UPDATE, DELETE` on that same tenant pattern **with GRANT OPTION**.

The private migrator also has `SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES` over the wildcard tenant pattern. The private provisioner service receives both provisioner and migrator credentials. These are not per-tenant credentials.

A compromise of the private service therefore permits direct reads/writes of all matching tenant databases, account creation at the server scope, and delegation of matching-schema DML to a new principal. Separate runtime tenant users do not constrain this compromised-service path. A private queue/no-ingress boundary reduces exposure probability; it does not reduce the impact after compromise.

The current source contract and prior Phase 2 report do **not** contain an owner-approved exception accepting this cross-tenant blast radius. The main security gate remains **FAIL** until the owner approves a bounded design or explicitly accepts the service compromise impact.

## Alternatives

### A — Narrow broker/definer boundary (preferred)

Replace direct tenant-wide DDL/DML and global account creation in the PHP provisioner with a separately reviewed MariaDB broker or tightly constrained definer routine. Before implementation, the design must establish how the broker independently verifies the central tenant reservation and the exact database/user tuple. It must not trust arbitrary caller-supplied database names, usernames, tenant IDs, or mutable registration values controlled by the caller. The broker should support only the intended per-tenant create/grant operation, return no unrelated tenant data, and reject access to any database other than the one verified tuple. Migration DDL must be separately bounded; do not simply move the wildcard migrator credential into another process without validating the new boundary.

Acceptance tests must prove on disposable MariaDB 11.4 that:
1. the PHP provisioner cannot create a MariaDB account directly;
2. it cannot issue arbitrary `GRANT` or read/write tenant schemas directly;
3. authorized provisioning for one reservation only affects that one database/account;
4. a malicious request for tenant B while provisioning A is denied;
5. direct tenant A credentials cannot connect to, SELECT, INSERT, UPDATE, or DELETE tenant B or central data;
6. a compromised ordinary web/default queue identity cannot invoke the broker with arbitrary reservations;
7. actual `SHOW GRANTS` output for app, provisioner, broker, migrator and runtime accounts matches the policy.

### B — Explicitly accept the isolated-service blast radius

The decision owner may instead accept that the private `tenant-provisioner` process is a **platform-wide trust boundary**. Such acceptance must explicitly acknowledge that compromise of this service can expose or alter data in every tenant database and can create new MariaDB principals. It must not be described as database-enforced cross-tenant isolation from a provisioner compromise.

If this option is selected, the owner must sign off on the exact current grant set, the service isolation controls, the incident-response assumption, and the residual all-tenant confidentiality/integrity impact. The acceptance should be time-bounded and reviewed after broker hardening. Merely labeling the service “private” or omitting its credentials from the normal web/default queue is not acceptance.

## Required status until a decision is recorded

- No implicit acceptance is inferred from DOC_14 or from a source guard.
- The current SQL and wildcard migrator grant remain a blocking risk.
- The review's standalone disposable-MariaDB probe captures actual `SHOW GRANTS` and demonstrates the potential impact using synthetic tenant databases only.
- Do not deploy this privilege model to production or shared staging as “isolation verified.”
- The owner must select Alternative A or explicitly sign Alternative B. Until then, provisioning-security gate = **FAIL**.

## References

- `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` — canonical target architecture and required tenant isolation.
- `docker/mysql-init/10-tenant-db-privileges.sql` — current grants under review.
- `app/Services/TenantDatabaseProvisioner.php` — current per-tenant account/grant issuance.
- `docs/reports/PHASE_2_PROVISIONING_SECURITY_2026-10-15.md` — prior DG-3 report marked PARTIAL / BLOCKED.
- `docs/reports/PHASE_4_HOST_DOMAIN_TENANT_ISOLATION_2026-10-15.md` — adversarial runtime gate marked RED / NOT VERIFIED.
