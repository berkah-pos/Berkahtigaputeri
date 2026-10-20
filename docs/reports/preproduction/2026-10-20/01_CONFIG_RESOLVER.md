# Prompt 01 — Configuration Workbook, Importer & Effective-Config Resolver Audit

**Audit date:** 2026-10-20 (Asia/Jakarta)  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Audited revision:** `main` at `371b7fdf0bf672b37ceb1023e647f114221bf797`  
**Workstream:** Prompt 01 only — workbook validation/export, manifest validation/import, normalized configuration storage, effective-config resolution, version/hash/cache contract, and their caller/test edges.  
**Disposition:** **RED / BLOCKED — source audit only; configuration pipeline is not accepted.**  
**Change control:** This report is the only file added by this workstream. No application source, workbook, migration, CI workflow, dependency, database, secret, infrastructure, or production resource was changed. No Supabase command, SDK operation, endpoint, or project was invoked.

## 1. Executive finding

The expected five-layer contract is documented clearly, and a dedicated offline workbook exporter plus a Laravel import command now exist in source. However, the end-to-end path is incomplete on the audited `main` revision:

- The Laravel importer references six `App\\Models\\Central` classes whose expected source paths were not present at the audited revision.
- `app/Services/EffectiveConfigResolver.php` and `app/Services/VersionedConfigWriter.php` are missing; `routes/api.php` exposes only a platform-health route, not an effective-configuration API.
- The exporter checks the expected workbook keyset using a hard-coded MD5. It does not emit a canonical manifest SHA-256, although the acceptance matrix requires the manifest digest and a repeat-export equality artifact.
- The Laravel import command validates the manifest envelope and row counts, but does not independently validate all row-level keys, relationships, service/device mappings and config shapes before writing.
- Workbook service `enabled` values are exported but are not persisted to the central `tenant_services` table by the importer.
- Central writes commit before the separate per-device tenant database writes. The command can therefore leave a partly applied import. Version increments are calculated using read/modify/write, without expected-version compare-and-swap.
- The existing Flutter config caller still uses the prohibited legacy Supabase RPC path. Its broad exception fallback can return cached config after a server-side refusal, and its cache code does not enforce a version/hash freshness or expiry policy.
- The active workbook-validation workflow still invokes `scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352`. The current owner ADR prohibits running that mutation-capable legacy program, including for read-only/dry-run validation. It was not run during this audit.

There is **no confirmed P0 finding** from this source review. The P1 findings below are release/configuration acceptance blockers, not a claim that a live production exploit or data corruption was observed.

## 2. Authoritative contract

The controlling logical configuration authority is [DOC_00_CANONICAL_ARCHITECTURE_DECISION.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md). The current platform authority is [ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md). DOC_14 and the roadmap are implementation/evidence guides subordinate to those authorities.

The required contract is:

- Inheritance order: **GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE**. A later layer overrides only fields that it actually defines; absent fields remain inherited.
- Canonical workbook: `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`.
- Required sheet order: `README_PRODUCTION`, `TEMPLATES`, `GLOBAL`, `TENANTS_MASTER`, `DEVICES`, `SERVICES`, `APP_CONFIG_EXPORT`.
- Exact exported inventory: **352 unique entries** — global 1, templates 3 (`BASIC`, `PRO`, `ENTERPRISE`), tenants 100, service entries 140, devices 108.
- Canonical key forms include `global`, `template:<TEMPLATE_ID>`, `tenant:<tenant_id>`, `tenant:<tenant_id>:service:<service>`, and `device:<device_id>`.
- A resolution request must identify one requested service; POS and Akuntansi must never be merged. The server must verify the active device belongs to the requested tenant before returning effective configuration.
- Effective output must include an explicit version/hash for its exact tenant/device/service tuple. Normal writes require expected-version/optimistic concurrency. Offline use is limited to a previously server-returned effective result for that exact tuple under an explicit freshness/entitlement policy.
- No Supabase use or project access is authorized. Historical Supabase code and reports are archive evidence only.

## 3. Node/edge map — actual versus target

```text
[Canonical XLSX workbook]
  |  required tabs / IDs / 352 entries / mappings
  v
[scripts/export_workbook_for_laravel.py]
  |  validates and creates local JSON manifest
  |  current digest: fixed keyset MD5 only; no manifest SHA-256
  v
[JSON manifest file]
  |  importer checks schema_version + fixed MD5 + counts
  |  row-level mapping/shape validation is incomplete
  v
[artisan config:import-workbook]
  |
  +--> [central transaction]
  |      global_configs / templates / tenants / tenant_configs /
  |      subscriptions
  |      Service 'enabled' is not written to tenant_services
  |
  +--> [central device_registry] --separate writes-->
         [tenant DB device_configs, one device at a time]
         cross-database partial-import window
                   |
                   X  [EffectiveConfigResolver.php: MISSING]
                   X  [VersionedConfigWriter.php: MISSING]
                   X  [authenticated effective-config API: MISSING]
                   |
                   X  target response version/hash and one-service
                      resolution cannot be established on main

[Flutter pos-app ConfigService]
  |  current caller still invokes Supabase get_effective_config RPC
  |  cache key is tuple-scoped but cache freshness/revocation rules
  |  are not enforced in this implementation
  v
[legacy client cache]  --not an accepted current runtime path
```

The graph records the current source shape, not a successfully executed data flow. The workbook itself, a PostgreSQL import, and a live effective-config response were **not** executed or observed in this audit.

## 4. Evidence ledger

| Evidence class | Source/revision and observation | What it proves / limitation |
|---|---|---|
| SOURCE-VERIFIED | [`scripts/export_workbook_for_laravel.py`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/scripts/export_workbook_for_laravel.py), especially expected-sheet/count constants and `build_manifest` | Offline exporter source checks sheet order, counts, duplicate/empty keys, basic template/tenant/service/device relationships, JSON-object values and fixed keyset MD5. It does not emit a manifest SHA-256. |
| SOURCE-VERIFIED | [`app/Console/Commands/ImportCanonicalWorkbook.php`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/app/Console/Commands/ImportCanonicalWorkbook.php#L16-L220) | Command exists and validates basic manifest envelope/counts; it writes central scopes then per-device tenant config. It has no completed-run manifest ledger or CAS writer. |
| MISSING | Expected current-main paths: `app/Models/Central/DeviceRegistry.php`, `GlobalConfig.php`, `Subscription.php`, `Tenant.php`, `TenantConfig.php`, `Template.php` | Direct file retrieval at the audited SHA returned 404 for these expected PSR-4 paths; the importer imports/references these classes. No alternate implementation was found in repository search. The command was not executed; runtime failure is inferred from missing class paths and standard Laravel PSR-4 loading. |
| MISSING | `app/Services/EffectiveConfigResolver.php`; `app/Services/VersionedConfigWriter.php` | These are referenced as assigned/planned files in the architecture conflict register and required in the acceptance matrix, but do not exist on audited main. |
| SOURCE-VERIFIED | [`routes/api.php`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/routes/api.php#L1-L12) | Only `GET /api/v1/platform-health` is declared in this file. No effective-config route is present in the inspected API route source. |
| SOURCE-VERIFIED | [Central migration](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/database/migrations/central/2026_10_17_000001_create_central_platform_tables.php#L48-L107) | Defines normalized `global_configs`, `templates`, `tenant_configs`, `tenant_services`, `audit_events`, and `device_registry` central tables. |
| SOURCE-VERIFIED | [Tenant migration](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/database/migrations/tenant/2026_10_17_000001_create_tenant_pos_tables.php#L10-L22) | Defines `device_configs` in the tenant database, which the importer writes. This needs reconciliation with the target statement that central owns configuration scopes/versioning. |
| SOURCE-VERIFIED | [Workbook validation workflow](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/.github/workflows/canonical-workbook-validate.yml#L46-L62) | The current workflow invokes the legacy `scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352`; it does not run the new Laravel exporter. This audit did not execute that workflow or script. |
| SOURCE-VERIFIED | [`config/ci/required-check-matrix.json`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/config/ci/required-check-matrix.json) | Acceptance specification requires repeatable SHA-256 manifest evidence and resolver/writer tests. The file labels itself a specification not yet wired into CI. The referenced `scripts/test_canonical_workbook_contract.py` was not present at the requested path on audited main. |
| SOURCE-VERIFIED | [Flutter config service](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/core/config/config_service.dart#L45-L143), [pubspec](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/pubspec.yaml#L10-L20), [main](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/main.dart#L1-L53) | Flutter still imports `supabase_flutter`, initializes a Supabase client, calls `get_effective_config`, and persists a tuple-keyed local result. These are legacy caller paths and are incompatible with the current no-Supabase decision. |
| DOC-ASSERTED / historical | [`docs/reports/ACCEPTANCE_MATRIX_CI_EVIDENCE_2026-10-16.md`](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/reports/ACCEPTANCE_MATRIX_CI_EVIDENCE_2026-10-16.md) and [baseline report](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/reports/LARAVEL_PG17_BASELINE_ACCEPTANCE_2026-10-17.md) | Historical workbook pass applies only to an older candidate SHA; basic Laravel/PG17 scaffold smoke does not cover importer/resolver/API parity. Do not reuse it as current Prompt 01 acceptance. |
| CI-OBSERVED | Combined status query for exact `371b7fdf0bf672b37ceb1023e647f114221bf797` returned no status rows | No exact-head check result was established by that query; this is not a pass or failure result. |
| NOT RUN / NOT VERIFIED | Actual workbook validation/export, Laravel importer command, resolver tests, PostgreSQL-backed parity, tenant/device hostile cases, current-head workflow execution, Flutter tests, staging and production | No commands/tests were executed in this audit. The actual binary workbook was not made available in the runtime used for this review. No database or hosted project was accessed. |

## 5. Findings

### CFG-01 — Active CI workflow invokes a prohibited legacy Supabase program

- **Severity:** P1 — release/policy blocker
- **Confidence:** High
- **Affected edge:** workbook change → `.github/workflows/canonical-workbook-validate.yml` → `scripts/sync_excel_to_supabase.py`
- **Evidence:** Workflow step around lines 59–62 invokes the legacy program with `--dry-run --expect-keys 352`. Root instructions and the 2026-10-17 owner ADR prohibit running that script, including to validate a workbook; dry-run does not supersede the prohibition.
- **Failure scenario:** A qualifying workbook/document PR or push triggers the workflow, which executes a mutation-capable legacy integration path in CI.
- **Impact:** The pipeline violates the current platform access boundary and can no longer be considered a safe, source-independent validation path. This report does not claim that the script was executed or that data was read/written.
- **Acceptance test:** On an isolated PR, assert every validation step uses only the offline exporter and pure tests; statically fail if any active workflow, shell command or test invokes `sync_excel_to_supabase.py`, `sync_excel_to_supabase_legacy.py`, any Supabase SDK/API/CLI, or old RPC. Execute the safe exporter only after the workflow is corrected and reviewed. Confirm no Supabase credentials are provisioned to the job.
- **Owner hand-off:** CI/workflow maintainer; Configuration Contract Lead reviews that the safe validation still enforces the canonical workbook contract. This audit deliberately made no workflow edit.

### CFG-02 — Import command references model classes absent from their expected current-main paths

- **Severity:** P1 — import blocker
- **Confidence:** High for source absence; runtime failure inferred, not executed
- **Affected edge:** `config:import-workbook` → central models → normalized central storage
- **Evidence:** `ImportCanonicalWorkbook.php` imports `App\\Models\\Central\\DeviceRegistry`, `GlobalConfig`, `Subscription`, `Tenant`, `TenantConfig`, and `Template`. Corresponding expected model files were absent at the audited revision; only `App\\Models\\Central\\User` was found at its expected location. Repository search did not identify alternate definitions for these six classes.
- **Failure scenario:** Invocation reaches `GlobalConfig::query()` or another missing model reference and autoload fails before the import can complete.
- **Impact:** Central configuration cannot be imported through the intended command, so the exporter/importer edge is not established on main.
- **Acceptance test:** After the owning implementation PR supplies the models and their central connection/casts/relationships, run `php artisan config:import-workbook` against a **disposable PostgreSQL 17** instance with a synthetic manifest. Prove command registration, all model resolution, expected central/tenant rows, and error output on a deliberately absent dependency. Preserve logs tied to exact SHA.
- **Owner hand-off:** Configuration/API Contract Lead, coordinating with Laravel Platform Lead for model/connection contracts. No model files were created in this audit.

### CFG-03 — Effective-config resolver, versioned writer and API response node are missing

- **Severity:** P1 — core product path absent
- **Confidence:** High
- **Affected edge:** normalized central configuration → resolver → version/hash response → caller
- **Evidence:** `app/Services/EffectiveConfigResolver.php` and `app/Services/VersionedConfigWriter.php` are absent on main. The inspected `routes/api.php` contains only `/v1/platform-health`. The acceptance matrix requires `EffectiveConfigResolverTest`, `VersionedConfigWriterTest`, and canonical Laravel/Flutter fixtures, but no implementation or current-main test run was found.
- **Failure scenario:** A client asks for effective configuration, but there is no current Laravel resolver/API route to authorize the exact tuple, select the appropriate central rows, merge the five layers, and return a version/hash.
- **Impact:** The documented inheritance contract is not delivered end-to-end; Admin/API/client parity and version-safe offline configuration remain unproven.
- **Acceptance test:** On disposable PostgreSQL 17, implement and test an authenticated resolver that: (1) derives/validates tenant membership and active registered device, (2) allowlists one service, (3) loads exactly GLOBAL, assigned TEMPLATE, TENANT, requested SERVICE and the same tenant-owned DEVICE override, (4) merges only explicitly supplied fields in canonical order, and (5) returns deterministic payload, version and SHA-256 for the exact tenant/device/service. Test both POS and Akuntansi separately and all negative authorization cases.
- **Owner hand-off:** Configuration/API Contract Lead owns resolver/writer/fixtures; API/auth owner supplies the verified actor/device context. Keep those ownership boundaries separate.

### CFG-04 — Importer trusts envelope counts and a hard-coded keyset digest rather than validating the manifest’s records

- **Severity:** P1 — fail-closed import integrity blocker
- **Confidence:** High
- **Affected edge:** JSON manifest → `validateManifest` → central/tenant writes
- **Evidence:** `validateManifest()` checks schema version, a fixed `keyset_md5` literal, category counts and array lengths, plus that `global_config` is an array. It does not recalculate a digest from manifest contents or exhaustively validate each row's keys, record shape, uniqueness, tenant/service/device relationship, canonical template/service identifiers or config object types before starting writes. The exporter performs more checks, but the importer accepts a JSON file as an independent input and cannot assume its bytes stayed identical after export.
- **Failure scenario:** A modified or stale JSON manifest preserves the expected top-level counts and hard-coded MD5 field but redirects a service/device `app_config_key`, duplicates/reassigns IDs, uses an unknown template/service, or supplies malformed per-row config; the importer proceeds with records that its own validation did not reject.
- **Impact:** Wrong-tenant or wrong-service configuration can be written, required configuration can be missed, or the import can fail midway after writes have begun.
- **Acceptance test:** Build a valid synthetic manifest, then mutate one field per case while keeping the envelope counts and fixed digest literal unchanged. Include duplicate IDs, unexpected template, invalid service, incorrect `app_config_key` cross-mapped to another tenant, device ID mapped to a different device key, tenant/device mismatch, missing/extra keys, and non-object config. Every invalid case must fail before the first database write; assert all central and tenant row counts/versions/checksums are unchanged. Validate manifest content with a deterministic content digest, not a caller-supplied constant.
- **Owner hand-off:** Configuration/API Contract Lead. QA Evidence Steward defines the fail-closed fixture matrix.

### CFG-05 — Workbook service enabled flags are exported but not imported into service-enable state

- **Severity:** P1 — configuration semantics lost
- **Confidence:** High
- **Affected edge:** `SERVICES.enabled` → manifest → central `tenant_services`
- **Evidence:** The exporter includes `enabled` in each service entry. The central migration creates `tenant_services(tenant_id, service, enabled)` with `enabled=false` by default. In `ImportCanonicalWorkbook::importCentral()`, the service loop writes only `TenantConfig` config values; it does not upsert `tenant_services` and does not persist the manifest's `enabled` field there.
- **Failure scenario:** A workbook service row has `enabled=true`, but the import only creates/updates its `tenant_configs` row, leaving the separate service-enable projection at its default or stale value.
- **Impact:** Effective configuration can disagree with the service availability/entitlement projection. Enabling/disabling POS vs Akuntansi cannot be considered preserved by the import.
- **Acceptance test:** Use fixtures with explicit true/false values for both services across tenants. Run import twice. Assert the central enablement state matches all 140 workbook service rows, each effective-config request honors the selected service state, and importing POS never changes the Akuntansi row. Verify idempotency and that unrelated service versions are unchanged.
- **Owner hand-off:** Configuration/API Contract Lead; coordinate service-entitlement semantics with the subscription/authorization owner rather than inventing a new business rule in this workstream.

### CFG-06 — Central import and per-device writes do not form one atomic import

- **Severity:** P1 — consistency blocker until recovery is proven
- **Confidence:** High
- **Affected edge:** `importCentral()` commit → loop of central device-registry writes and per-tenant `device_configs` writes
- **Evidence:** Central rows are wrapped in a transaction, then `importDevices()` executes afterward. Each device registry upsert and tenant `device_configs` write occurs separately; `Tenancy::end()` is in a `finally` block. The catch path itself warns “Import may be partially complete” and asks the operator to rerun. No manifest import-state/checkpoint/reconciliation ledger was found.
- **Failure scenario:** The process exits or a tenant database fails after central rows commit and after some of 108 devices have been handled. Central base/service config is now current while a subset of device overrides or registry state remains old/missing.
- **Impact:** The same effective-config tuple can resolve inconsistently between devices until a retry completes, and an operator cannot use one committed status record to distinguish “fully applied” from “partially applied.”
- **Acceptance test:** On disposable PostgreSQL 17, inject failures before the first tenant-device write, midway through the device list, and after a tenant database is provisioned but before config commit. Require a durable manifest/run identifier and explicit states (e.g. pending, applying, failed/resumable, completed); rerunning the same manifest must converge to one expected state without duplicates, data loss, or unintended version increments. The system must not report success while any layer is incomplete. If global ACID across databases is not feasible, specify and test a resumable reconciliation protocol.
- **Owner hand-off:** Configuration/API Contract Lead coordinates with Laravel Platform/tenant lifecycle owner. Tenant provisioning policy itself remains outside this workstream.

### CFG-07 — Version increment is not compare-and-swap and can lose concurrent updates

- **Severity:** P1 — version integrity blocker
- **Confidence:** High
- **Affected edge:** configuration read → `nextConfig()` → configuration write
- **Evidence:** `nextConfig()` removes `version` from the current/incoming config and calculates `currentVersion + 1` when data changes. The write is not guarded by `WHERE version = expectedVersion` and accepts no expected-version token. No current-main `VersionedConfigWriter` implements the documented optimistic concurrency contract.
- **Failure scenario:** Two imports/writers read version N concurrently. Both derive N+1 with differing content; the later write can replace the earlier write without a version conflict being surfaced.
- **Impact:** Configuration changes may be lost while the stored version appears monotonic; consumers cannot reliably detect the conflict.
- **Acceptance test:** From two independent database sessions and the same initial version, concurrently submit two different updates with expected version N. Exactly one may commit; the other must receive a deterministic version-conflict response and must not partially change config/hash/audit records. Recheck that an identical idempotent replay does not increment version and a changed payload does. Preserve executed race logs.
- **Owner hand-off:** Configuration/API Contract Lead. PostgreSQL-specific locking/constraint review belongs to the database specialist.

### CFG-08 — Device override storage differs from the documented central configuration ownership

- **Severity:** P2 — architecture/data ownership conflict
- **Confidence:** High that source locations differ; impact awaits resolver implementation
- **Affected edge:** manifest device scope → importer → tenant `device_configs` vs documented central configuration/versioning ownership
- **Evidence:** DOC_14 says central data owns configuration scopes/versioning and the normalized central tables include device registry/overrides. The central migration includes `device_registry`; the tenant migration separately defines `device_configs`; the importer writes the device override to the tenant database. Since the actual resolver is missing, there is no implementation evidence that both locations can be resolved without split ownership or drift.
- **Failure scenario:** A later resolver reads central config versions but loads device override through the tenant DB (or vice versa), leaving no single defined ordering/version/hash when an import is partial or versions differ.
- **Impact:** Effective configuration may have ambiguous ownership, cache invalidation or audit history across tenant databases.
- **Acceptance test:** Decide the authoritative storage location in one reviewed contract and align migration/import/resolver accordingly. With tenant A/B and devices A/B, prove the device override exists in one authoritative place, applies only to its registered tenant/device, participates last in the merge, and is covered by the same result version/hash and audit entry.
- **Owner hand-off:** Configuration/API Contract Lead with Laravel Platform Lead. Do not resolve by adding a second runtime source of truth.

### CFG-09 — Current Flutter caller still depends on Supabase and can fall back to cached config on a server refusal

- **Severity:** P1 — platform compliance and offline-authority blocker
- **Confidence:** High for source behavior; runtime behavior not executed
- **Affected edge:** Flutter `ConfigService` → legacy RPC → local cache
- **Evidence:** `pos-app/lib/core/config/config_service.dart` imports `supabase_flutter`, checks a Supabase session, invokes RPC `get_effective_config`, and stores output under `p6.effective.<tenant>.<device>.<service>`. Its catch covers any exception from the RPC, response decoding, and preference write and then returns the cached result when present. `pos-app/pubspec.yaml` still includes `supabase_flutter`; `main.dart` still initializes Supabase from build defines. The current owner ADR prohibits all Supabase product use/access.
- **Failure scenario:** The current remote call fails due to network loss, malformed response, or a server-side denial (e.g. inactive device/service); the client catch cannot distinguish these cases and may return cached config as though this were safe offline fallback. No explicit cache expiry/version/hash or entitlement freshness check is enforced in the inspected method.
- **Impact:** The production client path is not compliant with the selected Laravel platform and may treat revoked/stale configuration as usable locally. Server-side APIs must still enforce authorization, but offline business actions and displayed capabilities can diverge from server authority.
- **Acceptance test:** Replace the legacy caller with the authenticated Laravel API under the assigned Flutter workstream; no old RPC/table/SDK fallback may remain in active code/workflows. Test distinct outcomes for network timeout, 401/403 or inactive device/service, malformed payload, outdated config version and expired offline grace. Only a previously server-issued result for the exact tuple may be used when the explicit offline policy allows it; authentication/authorization refusal and invalid payload must not be silently transformed into a cached success. Confirm server version/hash and cache expiry handling.
- **Owner hand-off:** Flutter/Sync Lead owns client migration/cache behavior; Configuration/API Contract Lead owns the result schema/version contract. Do not run the legacy RPC during the migration.

### CFG-10 — Required SHA-256 / deterministic manifest gate is not met by the exporter

- **Severity:** P2 — validation/evidence gate missing
- **Confidence:** High
- **Affected edge:** workbook → exporter → manifest artifact → CI
- **Evidence:** The exporter calculates a sorted-key MD5 and returns `keyset_md5`; it does not include a SHA-256 of canonical manifest bytes/config contents. The acceptance matrix requires source workbook hash, canonical manifest, manifest SHA-256, two clean exports, and byte/hash equality. `config/ci/required-check-matrix.json` also specifies `scripts/test_canonical_workbook_contract.py`, which was not present at that path on this SHA. The current workflow instead runs old sync inventory tests and the prohibited legacy program.
- **Failure scenario:** A workbook retains the same set of keys but changes values or mappings; the fixed keyset MD5 is unchanged and cannot attest those changed contents or prove identical manifest output.
- **Impact:** CI evidence does not establish that the exact imported configuration content is deterministic or tied to the approved workbook bytes.
- **Acceptance test:** On an isolated runner, SHA-256 the source workbook; export the validated manifest twice into clean directories using the safe exporter; canonicalize serialization and assert byte equality; emit and archive manifest SHA-256 and type counts. Then change a config value without changing the keyset and assert the manifest SHA-256 changes. Invalid workbook and invalid keyset must fail without database writes.
- **Owner hand-off:** Configuration Contract Lead with QA Evidence Steward.

## 6. Invalid-manifest test matrix (must fail before any write)

At minimum, create a canonical valid fixture and mutate exactly one dimension at a time. For every negative case, snapshot central and tenant row counts, config versions, effective payload hashes and audit-event counts before invocation; assert no changes occur when validation rejects the manifest.

| Case | Mutation | Required result |
|---|---|---|
| IM-01 | Missing/extra sheet or changed required sheet order | Export validation fails closed. |
| IM-02 | 351 or 353 entries; duplicate/empty key; wrong type count | Export validation fails; no manifest accepted. |
| IM-03 | Unknown/missing template ID or duplicate tenant/device ID | Exporter and importer reject; no database writes. |
| IM-04 | Valid counts and supplied expected MD5 but tampered config value/content | Importer detects manifest-content digest mismatch; no writes. |
| IM-05 | Valid counts with missing row config or config that is not an object / has invalid version | Importer rejects before central transaction. |
| IM-06 | Service row points to a valid key belonging to another tenant or to the wrong service | Importer rejects relationship mismatch. |
| IM-07 | Device row points to another device's config key or a device owned by another tenant | Importer rejects relationship mismatch. |
| IM-08 | Invalid service name/case/alias, duplicate (tenant, service) pair or 140 rows with wrong service coverage | Importer rejects; POS/Akuntansi remain isolated. |
| IM-09 | Inactive/unregistered or mismatched device has active workbook flag without valid server-side registration/ownership | Import must not imply valid device enrollment; resolver/API must fail closed. |
| IM-10 | Unsupported schema version, missing required manifest field or unknown scope | Importer rejects before writes and records a safe diagnostic. |

The exporter catches some of IM-01/02/03/08 on its current code path. The importer cannot rely on that exporter always being the only producer of a manifest; current source does not prove the complete matrix above passes.

## 7. Race, retry, and partial-failure matrix

| Case | Setup | Acceptance oracle |
|---|---|---|
| RC-01 Identical reimport | Import the same canonical manifest twice | First run creates the expected rows; second run makes no content change and does not spuriously increment versions. |
| RC-02 Changed config | Change one scope's config content without changing its key | Exactly the affected scope's version/hash changes; unrelated layers/services keep versions. |
| RC-03 Stale version | Writer imports based on expected version N after another writer commits N+1 | Explicit conflict; stale input cannot overwrite the newer value. |
| RC-04 Concurrent writers | Two database sessions update the same scope from N with different payloads | One commit at most; loser receives deterministic conflict; no lost update or partial audit/hash update. |
| RC-05 Failure mid-device loop | Inject failure after a specified device in the 108-device list | Import status is not completed; resume/reconcile reaches one consistent full state and reports exact remaining work. |
| RC-06 Tenant DB failure | Central transaction succeeds but one target tenant DB is unavailable | Durable partial/failure status, no green/success response; safe retry does not duplicate subscriptions/device records or increment unchanged versions. |
| RC-07 Provisioning side effect | Fail tenant database creation/configuration after tenant metadata save | No untracked database/tenant state is silently assumed complete; retry is idempotent and reconciles metadata/resource state. |
| RC-08 Concurrent reimport + operator config edit | Workbook import and versioned API write target the same scope | Contractually selected winner/conflict, with optimistic concurrency and audit evidence; no silent last-writer-wins. |
| RC-09 Tenant context reset | Force an exception during tenant A device config write, then continue with tenant B | Tenant connection/context is always cleared; the B write cannot touch A's database. |
| RC-10 Disabled service transition | Concurrently/import-sequence enable and disable for one service | Versioned state remains correct; a POS update never changes Akuntansi service-enable state. |

These are acceptance criteria only. None of these tests ran as part of this audit.

## 8. Required exact-head acceptance gates

Do not mark Prompt 01 green until each gate below passes on one reviewed candidate SHA; do not aggregate old PR successes with current-main state.

1. **Workbook structure (TEST-EXECUTED):** safe offline exporter verifies exact sheet list/order, 352 unique keys, 1/3/100/140/108 counts, template IDs, valid row associations and keyset. Preserve source workbook SHA-256, manifest bytes and manifest SHA-256.
2. **Determinism (TEST-EXECUTED):** two clean exports from the same workbook are byte-identical and have equal manifest SHA-256; a content/mapping change alters that digest.
3. **Manifest rejection (TEST-EXECUTED):** IM-01 through IM-10 run against disposable PostgreSQL 17 and prove invalid input is rejected before any change.
4. **Importer dependencies (TEST-EXECUTED):** the command boots and resolves every model/service referenced by the import path; fresh central/tenant imports use the selected PG17 stack. All rows/relationships match manifest expectations.
5. **Import recovery (TEST-EXECUTED):** RC-01, RC-05 through RC-09 pass; explicit manifest/run status distinguishes pending, failed/resumable and completed imports. No success response while device/tenant writes remain incomplete.
6. **Service enablement (TEST-EXECUTED):** every workbook service-enabled value maps to central `tenant_services`, and requested service state is respected without cross-service mutation.
7. **Version/CAS (TEST-EXECUTED):** RC-02 through RC-04 and RC-08 prove version/hash determinism, idempotence, stale-write rejection and audit consistency.
8. **Effective resolution (TEST-EXECUTED):** all five-layer precedence/inheritance fixtures, tenant/device negative cases, and POS-vs-Akuntansi isolation pass using PostgreSQL 17.
9. **Cache/client contract (TEST-EXECUTED):** API response contains tuple-bound version/hash; offline cache is bound to exactly tenant/device/service and obeys explicit expiry/entitlement rules; 401/403 and malformed payload do not silently become cached success.
10. **CI safety (CI-OBSERVED):** active workflow calls only approved local validators and current-stack tests; static scan confirms no Supabase script, endpoint, CLI, SDK or credential is invoked by validation/test workflows. The check is executed on the exact SHA, not inferred from workflow source alone.
11. **Caller parity (TEST-EXECUTED):** Admin/API/Flutter consume the same fixtures and canonical effective JSON/hash; no active Flutter Supabase caller or direct raw-table read remains.
12. **Exact revision evidence (CI-OBSERVED):** test commands, exit codes, job/run IDs, checked-out SHA, stack fingerprint and artifacts are retained; missing or skipped required checks remain RED.

Only isolated synthetic PostgreSQL 17 environments should be used for destructive/replay/race tests. There is no permission to connect to Supabase or another live business database.

## 9. Ownership and next step

- **Configuration/API Contract Lead:** exporter/manifest format, importer validation, normalized config ownership, resolver, version/hash/CAS behavior, service mapping and shared fixtures.
- **Laravel Platform Lead:** required model/connection wiring and disposable PostgreSQL test harness; coordinate rather than create parallel competing schemas.
- **Flutter/Sync Lead:** replace the legacy client path only after the accepted Laravel API contract exists; implement cache error classification and freshness rules under that contract.
- **QA Evidence Steward / CI maintainer:** remove the prohibited legacy script path through a separately reviewed workflow change, wire the required checks, and preserve exact-head artifacts.

**Single next action:** open a coordinated implementation PR after the Configuration/API Contract Lead approves the manifest schema and device-config ownership decision. In that PR, fix the missing model/resolver/API nodes and wire the importer/test harness; do not claim acceptance until the gates above execute on the exact candidate SHA.

## 10. Actions performed and limitations

- Inspected the authoritative docs and relevant current-main source at `371b7fdf0bf672b37ceb1023e647f114221bf797`.
- Checked current-main source presence for the importer models, effective resolver/writer and named workbook acceptance test; absent paths are recorded as MISSING.
- Inspected current workflow source, configuration tables/migrations, API routes, Flutter config caller and acceptance-matrix requirements.
- Queried the combined status for the audited SHA; no status rows were returned.
- **NOT RUN:** actual workbook export/validation, `php artisan config:import-workbook`, PHP/Laravel tests, Flutter tests, PostgreSQL runtime tests, CI workflow execution, staging, production, or any Supabase-related operation. The binary workbook was not available to the local execution runtime, and the existing workflow invokes a prohibited legacy script, so neither was run.

This report is an engineering source audit, not proof of successful import, runtime resolver behavior, staging parity, or production readiness.
