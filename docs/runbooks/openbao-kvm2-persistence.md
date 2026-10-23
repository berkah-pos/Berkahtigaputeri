# Runbook — OpenBao persistence on Hostinger KVM2 + Coolify

**State:** operational procedure template; no live OpenBao service is certified by this document.  
**Related decision:** ../permanent/ADR-2026-10-23-OPENBAO-KVM2-SECRET-PERSISTENCE.md.

## 1. Intended shape

OpenBao runs as a private Coolify-managed service on the existing KVM2 workload host. Use single-node Raft first, with a dedicated persistent volume mounted at /openbao/data. Laravel web/app containers, the isolated provisioning worker, PostgreSQL 17 and OpenBao communicate only over private service networks. This procedure does not publish the OpenBao API/UI or PostgreSQL to a public interface.

The KVM2 baseline is constrained: 2 vCPU, 8 GB RAM and 100 GB NVMe. Measure headroom for Laravel, PostgreSQL, Coolify and OS operations. Monitor memory, disk and volume use. Do not claim high availability from a single VPS.

## 2. Before creating the service

1. Select and pin a reviewed OpenBao image tag and digest. Do not deploy latest; record the exact image identity.
2. Create a dedicated durable Coolify/Docker volume or host-managed persistent path. Mount it at the storage "raft" path, for example /openbao/data. Verify container recreation/redeploy will not remove it and the pinned image UID can read/write it. Never store Raft state only in the container writable layer.
3. Configure private DNS/service discovery and a TLS certificate valid for the API hostname. Laravel OPENBAO_ADDR must use https://; the code refuses http://. Set OPENBAO_CA_BUNDLE only when a private CA certificate bundle is needed.
4. Keep API/UI/cluster listeners private; do not assign a public domain or public port. Access operator tools through a controlled private administration path.
5. Restrict who can edit Coolify resources, mounted config and deployment variables. Never copy real tokens to Git, logs or chat.

## 3. Configuration shape

Use a reviewed configuration equivalent to this example; adjust certificate paths and service names to the exact pinned image and private network:

~~~hcl
ui = false
api_addr = "https://openbao.internal:8200"
cluster_addr = "https://openbao.internal:8201"

storage "raft" {
  path = "/openbao/data"
  node_id = "berkahpos-kvm2-openbao-1"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_cert_file = "/openbao/tls/tls.crt"
  tls_key_file = "/openbao/tls/tls.key"
}
~~~

This is illustrative, not a tested Coolify manifest. Confirm the cluster address and certificate SANs before deployment. Never disable TLS verification to bypass a certificate issue.

## 4. Initialize and protect root access

In a controlled operator session, initialize OpenBao and store the generated unseal shares and initial root token outside the host. Follow the official initialization/unseal process. Do not paste the generated values into shell history, CI variables, Git, ticket text, logs or the OpenBao KV store itself.

Use the root token only to enable KV v2, apply reviewed policies, configure token issuance and validate the service. Create distinct runtime and provisioning identities with least privilege; revoke the initial root token after bootstrap, preserving a reviewed break-glass process. Keep unseal shares and the only encrypted snapshot copy outside the KVM2 host and outside the same failure domain.

With Shamir sealing, a restart can leave OpenBao sealed. It is not ready until unsealed and health/secret-read checks pass. Do not make a same-host plaintext share file an automatic-unseal shortcut.

## 5. KV v2 mount and policies

Enable a KV v2 mount matching OPENBAO_KV_MOUNT (default secret), then apply and test the policy intent in the ADR supplement.

- Laravel runtime identity: read on secret/data/tenant/+/runtime only. No listing, metadata, writes, deletes, migrator or system access.
- Provisioning worker identity: only the required data create/update operations, migrator read, and KV v2 metadata deletion for compensation.
- Do not reuse the token between the two resources. Keep OPENBAO_PROVISIONER_TOKEN and PROVISIONER_DB_* absent from web and ordinary queue containers.
- Use synthetic secrets to prove runtime can read runtime but cannot read migrator or list paths. Prove provisioning can store/remove controlled secrets. Test both identities against admin/system endpoints and expect denial.
- Record token issuance, expiry, rotation and revocation procedures. Static token injection into a deployment variable is an interim lifecycle, not proof of short-lived/renewable identity.

## 6. Coolify compatibility and Laravel settings

Coolify's published docs list HashiCorp Vault, Infisical and Doppler, but do not name OpenBao as a distinct provider. Vault-style integration is NOT VERIFIED until tested against the exact Coolify and OpenBao versions.

Test in an isolated resource: configure provider credentials; browse/read a harmless synthetic value; deploy an app that consumes it; and verify redeploy/restart behavior without exposing values in logs. If compatibility fails, do not disable TLS or widen access policies to force it through. Use an approved secure way to inject a narrowly scoped bootstrap credential while a reviewed integration approach is selected.

Laravel runtime requires OPENBAO_ADDR, OPENBAO_KV_MOUNT, OPENBAO_RUNTIME_TOKEN and optionally OPENBAO_CA_BUNDLE. The isolated provisioning worker additionally requires OPENBAO_PROVISIONER_MODE=true, OPENBAO_PROVISIONER_TOKEN and its private PROVISIONER_DB_* variables. Do not place worker-only variables in a shared web/queue environment group. Normal web and queue services remain fail-closed when OpenBao or required credentials are absent.

## 7. Snapshot and off-host backup

Use OpenBao's supported Raft snapshot operation against the running, unsealed instance, for example:

~~~sh
bao operator raft snapshot save <snapshot-file>
~~~

Do not use a live copy of the Raft data directory as the primary consistency mechanism.

1. Write the snapshot to a restricted temporary path accessible only to the operator.
2. Verify the snapshot can be read and calculate a checksum.
3. Encrypt it before transfer using the approved off-host backup mechanism. Store its decryption key separately from the artifact.
4. Copy encrypted artifact and checksum to the approved off-host destination outside the KVM2 host and its storage failure domain; configure retention and access logging. This document does not select or provision that destination.
5. Store unseal shares in separate offline-controlled locations. They are not part of the Raft snapshot. Do not place shares, plaintext snapshots or encryption keys in Coolify volumes or Git.
6. Take another snapshot before upgrades, token-policy migrations or secret-engine changes.

Record timestamp, image/version, checksum, encrypted artifact location, operator identity and pass/fail outcome; never record tokens or secret values.

## 8. Restore drill

Perform the first restore in isolation, never by overwriting production directly.

1. Create a clean isolated OpenBao instance from the recorded image/configuration and a separate durable volume.
2. Restore the encrypted snapshot using OpenBao's supported Raft snapshot restore operation and the matching seal material.
3. Unseal through the approved quorum procedure and verify health/Raft status.
4. Use synthetic identities to check runtime path read succeeds; migrator path, list, write and admin requests are denied to runtime; and provisioning permissions are confined to the intended namespace.
5. Point a disposable Laravel instance at the restored OpenBao and resolve a synthetic runtime secret. Run the database connection integration tests against disposable PostgreSQL 17.
6. Record versions, commands, artifact checksum, test outcomes and recovery duration. Repeat after material upgrades or configuration changes.

A snapshot file on disk is not restore evidence; the restored service and its allow/deny tests must execute.

## 9. Tenant provisioning safety

The Laravel command is php artisan tenants:provision-database <ULID>. It runs only in an isolated non-public worker with OPENBAO_PROVISIONER_MODE=true. It reserves the central registry row, stores runtime and migrator credentials in OpenBao, creates the isolated PostgreSQL database and roles, migrates under the migrator role and activates the registry only after migration success. It stores no password centrally and clears the transient migrator password from the connection config.

On failure, the command marks the registry failed when possible and never auto-drops a database or role. Inspect OpenBao, PostgreSQL and the central registry together. Do not delete the failed row or rerun blindly; reconcile all resources through an owner-reviewed recovery procedure.

## 10. Production gate

- [ ] OpenBao image/version/digest pinned and recorded.
- [ ] Dedicated /openbao/data volume survives container replacement/restart.
- [ ] Private-only API and verified TLS are observed.
- [ ] Seal material stored separately; root token is not used by workloads.
- [ ] Runtime/provisioning tokens are distinct; effective policy denials are tested.
- [ ] Coolify/OpenBao compatibility is tested and recorded.
- [ ] Disposable PG17 provisioning/migration and runtime retrieval pass.
- [ ] Encrypted off-host snapshot and checksum are verified.
- [ ] Clean restore/unseal and post-restore positive/negative tests pass.
- [ ] Monitoring covers health, sealed state, disk usage, backup freshness and failures.

Until all criteria have direct evidence, OpenBao is not production accepted.

## Official operator references

- Coolify secret manager integration workflow: https://coolify.io/docs/integrations/security/using-secret-managers
- Coolify secret manager credentials/provider list: https://coolify.io/docs/integrations/security/secret-managers
- OpenBao Raft storage: https://openbao.org/docs/configuration/storage/raft/
- OpenBao snapshots/storage recovery: https://openbao.org/docs/concepts/storage/
- OpenBao seal/unseal: https://openbao.org/docs/concepts/seal/
- OpenBao KV v2: https://openbao.org/docs/secrets/kv/kv-v2/
- OpenBao ACL policies: https://openbao.org/docs/concepts/policies/
