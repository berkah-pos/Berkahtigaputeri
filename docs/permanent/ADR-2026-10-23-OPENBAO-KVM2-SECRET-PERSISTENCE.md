# ADR Supplement — OpenBao secret persistence on Hostinger KVM2 + Coolify

**Decision date:** 2026-10-23  
**Status:** SELECTED TARGET; implementation is under review and deployment is NOT VERIFIED  
**Authority:** Supplements, but does not replace, the 2026-10-17 owner platform ADR.  
**Scope:** Persistent secrets, tenant database credential references, and provisioning/runtime access boundaries.

## Decision

Use self-hosted OpenBao as the intended secret store on the existing Hostinger KVM2 workload host, deployed as a private Coolify-managed service. Start with one OpenBao instance using Integrated Storage (Raft) on a dedicated persistent volume. PostgreSQL 17 remains the private relational system of record. OpenBao is a security service, not a replacement for PostgreSQL.

This selects a design; it does not prove an OpenBao instance, volume, Coolify compatibility, backup, restore, or production deployment exists.

## Host and persistent storage

- Keep OpenBao private to the KVM2/Coolify service network. Do not attach a public domain or publish its API/UI or PostgreSQL ports to the Internet. Laravel and the isolated provisioning worker use verified HTTPS.
- Configure the storage "raft" stanza with a stable path such as /openbao/data and mount a dedicated Coolify/Docker named volume or host-managed persistent path there. Data must survive container replacement, redeploy and VPS restart; the container writable layer is not persistent storage.
- Keep Raft data, configuration, TLS private key, seal shares, snapshot artifacts and snapshot-encryption keys as separately protected assets. Apply permissions for the pinned image's runtime UID. Do not assume the KVM2 disk or volume is encrypted at rest.
- Pin a reviewed OpenBao image version and digest. Configure TLS verification, a stable Raft node ID, private listeners, health checks and disk-space alerts. Never deploy a floating latest tag.
- KVM2 is a single physical host. Persistent Raft storage does not provide host-level high availability. Host loss interrupts secret access until service and storage are recovered.

## Coolify compatibility boundary

Coolify's current documentation describes integrations for Doppler, Infisical and HashiCorp Vault with a KV v2 flow; it does not name OpenBao as a separately supported provider. OpenBao provides a Vault-style API, but its own API documentation currently warns that backward compatibility is not guaranteed for every API area/version.

Therefore keep Coolify as the deployment/control plane, but do not declare the OpenBao/Coolify provider integration compatible until tested against the exact pinned versions. Laravel's explicit KV v2 adapter handles dynamically created tenant credentials; Coolify deployment-time environment substitution alone is not the runtime secret store. Until a compatibility test is recorded, direct provider compatibility is NOT VERIFIED.

## Credential layout

Use KV v2 mount secret initially, configurable via OPENBAO_KV_MOUNT. Paths are canonical and narrow:

- tenant/<CANONICAL_ULID>/runtime — restricted PostgreSQL runtime-role password.
- tenant/<CANONICAL_ULID>/migrator — tenant schema-migration role password.

The central tenant database registry stores only a non-secret reference, for example openbao:kv-v2:secret/tenant/<ULID>/runtime. It must never contain a PostgreSQL password, OpenBao token, owner credential or cluster/provisioner credential.

The Laravel runtime resolver validates that the reference matches the authenticated tenant and ends in runtime. It cannot resolve migrator credentials, list secret names, accept arbitrary secret paths or fall back to a central-DB password. Unconfigured, invalid or unavailable credentials fail closed.

### Runtime token policy

For mount secret, the runtime token should have only:

~~~hcl
path "secret/data/tenant/+/runtime" {
  capabilities = ["read"]
}
~~~

Do not grant it list, metadata, create, update, delete, migrator, system or administrative capabilities.

### Provisioning token policy

The provisioning worker needs narrowly reviewed permissions to write runtime/migrator values, read the migrator value for schema migrations and remove KV v2 metadata during compensation:

~~~hcl
path "secret/data/tenant/+/runtime" {
  capabilities = ["create", "update"]
}
path "secret/data/tenant/+/migrator" {
  capabilities = ["create", "update", "read"]
}
path "secret/metadata/tenant/+/runtime" {
  capabilities = ["delete"]
}
path "secret/metadata/tenant/+/migrator" {
  capabilities = ["delete"]
}
~~~

This is a privileged automation identity for the tenant-secret namespace. It must only be available to the non-public provisioning worker, never web or ordinary queue containers. The root token must not be used by Laravel, Coolify workloads or provisioning automation. Verify effective OpenBao capabilities after creating policies; source snippets alone are not proof.

The shared Laravel runtime token can read runtime passwords for all tenants, though not migrator passwords. This is a residual shared-process blast-radius risk. Protect the app runtime and consider per-tenant or dynamically scoped identities before claiming strong resistance to a compromised shared app process.

## Provisioning lifecycle

The private Laravel command tenants:provision-database is gated behind OPENBAO_PROVISIONER_MODE=true, OPENBAO_PROVISIONER_TOKEN and a dedicated PROVISIONER_DB_* connection. These values must be absent from web and ordinary queue environments.

1. Reserve a central registry row with status provisioning, canonical database/role names and a non-secret OpenBao reference.
2. Generate distinct runtime/migrator passwords and store them in OpenBao KV v2.
3. Create the tenant PostgreSQL database and restricted owner/runtime/migrator roles through the PostgreSQL broker.
4. Read the migrator password only from the provisioning worker and run tenant migrations.
5. Mark the central registry active only after all migrations succeed; clear the transient migrator password and purge the dynamic connection.
6. On ambiguous partial failure, fail closed and mark status failed when possible. Never automatically drop databases or roles. Reconcile OpenBao paths, PostgreSQL resources and the central registry before an owner-reviewed retry.

Do not activate a tenant merely because a secret was stored or a database was created. A failed registry row intentionally blocks blind retry/adoption.

## Seal, backup and recovery requirements

- Raft data persistence is mandatory and separate from container/image lifecycle.
- With Shamir seal, a restart can leave OpenBao sealed until the required quorum of unseal shares is supplied. In this state lookups and provisioning must fail closed. Store shares offline in multiple controlled locations, not on the KVM2 host, Docker volume, Git, app container or OpenBao KV store.
- Use OpenBao's supported Raft snapshot operation. Encrypt snapshot artifacts before transfer and store them off the KVM2 host and outside the same storage failure domain. Keep the snapshot-encryption key separate from the snapshot.
- A Raft snapshot does not contain the offline unseal shares. Preserve configuration, TLS replacement materials/process, pinned image identity and recovery instructions as separately protected assets.
- Verify snapshot checksum, restore to an isolated OpenBao instance, unseal it with matching shares, and test positive and denied policy operations using synthetic secrets. Do not treat copying a live Raft directory as the primary backup method.
- Back up PostgreSQL central/per-tenant databases independently. OpenBao snapshots do not replace database backups, and database backups do not replace OpenBao snapshots.

## Deployment settings

config/openbao.php defines:

- OPENBAO_ADDR — HTTPS API endpoint reachable on the private network.
- OPENBAO_KV_MOUNT — KV v2 mount, secret by default.
- OPENBAO_RUNTIME_TOKEN — runtime read token.
- OPENBAO_PROVISIONER_TOKEN — privileged worker-only token.
- OPENBAO_CA_BUNDLE — optional PEM bundle for a private CA; TLS verification cannot be disabled.
- OPENBAO_CONNECT_TIMEOUT_SECONDS and OPENBAO_TIMEOUT_SECONDS — bounded request timeouts.
- OPENBAO_PROVISIONER_MODE — false/absent outside the dedicated worker.

These are deployment inputs, not values to commit. Never place real tokens/passwords in documentation, issue descriptions, source, fixtures or CI output.

## Acceptance gates

Do not accept OpenBao for production until evidence proves: the volume survives container replacement and host restart; private network/TLS works; effective read/write/delete policies are verified; runtime and provisioner tokens are distinct; the pinned Coolify/OpenBao integration is tested; live KV v2 retrieval works from the private application network; tenant provisioning activates only after successful migrations; PG17 cross-tenant denials still pass; encrypted off-host snapshots exist; and clean restore/unseal succeeds.

**Current evidence boundary:** the PR adds a Laravel adapter and a synthetic HTTP + disposable PostgreSQL integration test. Live OpenBao deployment, Coolify integration, durable-volume persistence, seal/restart, off-host backups and restore remain NOT VERIFIED.

## Official references checked 2026-10-23

- Coolify, Use a Secret Manager: https://coolify.io/docs/integrations/security/using-secret-managers
- Coolify, Secret Manager Credentials and supported provider list: https://coolify.io/docs/integrations/security/secret-managers
- OpenBao KV v2 path and policy behavior: https://openbao.org/docs/secrets/kv/kv-v2/
- OpenBao ACL policy syntax and capabilities: https://openbao.org/docs/concepts/policies/
- OpenBao Integrated Storage (Raft) persistence and configuration: https://openbao.org/docs/configuration/storage/raft/
- OpenBao storage and backup considerations: https://openbao.org/docs/concepts/storage/
- OpenBao seal/unseal concepts: https://openbao.org/docs/concepts/seal/
- OpenBao API transport and compatibility caveat: https://openbao.org/api-docs/
