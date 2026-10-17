# Berkah POS Database/Schema Forensics Report — 2026-10-17

**Disposition: PARTIAL INVENTORY COMPLETE; MIGRATION/CUTOVER BLOCKED**

**Canonical repository:** `berkah-pos/Berkahtigaputeri`  
**Reviewed main SHA:** `08af86065addcbcae0b03dbf085a2943fc8362bf`  
**Owner source-of-record:** `cztlmwzfrhyafgawphgw`  
**Comparison clone:** `txwzhesvcjftybrlhnzs`  
**Audit date/time zone:** 2026-10-17, Asia/Jakarta

## 1. Authorization and method

The user explicitly approved a strictly read-only metadata audit for the two exact project IDs in this conversation. Access used the existing authenticated Supabase integration; no credentials were pasted into chat or included in the artifacts. All database statements issued for this audit were SELECT-only metadata/catalog queries. Supabase management metadata APIs were used to identify projects, migration records, extensions and Edge Functions.

**Access caveat:** the connected integration offers write-capable operations, so the underlying identity being restricted to a database read-only role is **NOT VERIFIED**. This work enforces the approved scope by using only read-only operations; it does not establish least-privilege credentials.

No customer/business rows were queried or exported. No project was changed. No historical migration SQL was executed. The legacy `scripts/sync_excel_to_supabase.py` script was not run. No grants were revoked, no project was reset/paused/deleted, and nothing was imported into the target.

## 2. Current live project evidence

| Field | Source | Clone |
|---|---|---|
| Project ID | `cztlmwzfrhyafgawphgw` | `txwzhesvcjftybrlhnzs` |
| Project label | `berkahtigaputeri-pos-staging` | `berkahtigaputeri-pos-staging-clone` |
| Supabase status | `ACTIVE_HEALTHY` | `ACTIVE_HEALTHY` |
| PostgreSQL | `17.6.1.171` | `17.11.0.003` |
| Region | `ap-southeast-1` | `ap-southeast-1` |
| Non-system schemas | 13 | 12 |
| Relations including sequences | 120 | 120 |
| Indexes | 292 | 291 |
| Constraints | 756 | 757 |
| Routines (catalog entries) | 278 | 236 |
| Non-internal triggers | 58 | 49 |
| Policies | 44 | 42 |
| Installed extensions | 6 | 5 |
| Table privilege records | 1076 | 2150 |
| Routine privilege records | 546 | 635 |
| Auth users/identities column metadata entries | 44 | 44 |
| Storage buckets / object metadata rows | 0 / 0 | 0 / 0 |
| Active Edge Functions | 3 | 0 |

The manifest contains the sanitized object-level inventories, role attributes/memberships, ACL metadata, Auth table shape/FK metadata, Storage counts/buckets, Realtime publication maps, installed extensions, migration history version/name records, and Edge Function dependency identifiers. Definition-bearing metadata (function/trigger/index/constraint definitions and RLS expressions) is represented by SHA-256 digests instead of raw definitions.

## 3. Findings requiring owner/architect review

### 3.1 Migration-history discrepancy — FAIL

Fresh Supabase migration metadata reports **139 records on the source and 12 on the clone**. The version-ID intersection is **0**. The source and clone histories must therefore not be treated as common/continuous history. Their same-named `phase5_tenant_isolation_hardening` entries use different version IDs: source `20261013085934`, clone `20261013085912`.

Current `main` contains only these two active migration files:
- `supabase/migrations/20261008131700_p0_rls_identity_config_runtime_prep.sql` (blob 07768fe035fec700b9b836b65f8a15657a9e4fe5; version prefix 20261008131700)
- `supabase/migrations/20261013120000_phase5_tenant_isolation_hardening.sql` (blob e4b487e66e041025e1d56796428e98826855b506; version prefix 20261013120000)

Neither active file's 14-digit version prefix occurs in either live history. This is not proof that no equivalent SQL exists elsewhere, but it means active files cannot reconcile either live migration history by exact version. Clone-only migration records explicitly naming clone-only/test-helper fixtures are **provisionally expected clone drift based on their names only**; owner-approved drift classification is not established. All other differences require file/history reconciliation.

### 3.2 Security differences — FAIL

- **Clone grants:** `anon` currently has table privileges across **54 public tables** for each of DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE and UPDATE. `authenticated` has the same seven privilege types over **63 public objects**. RLS is enabled on all 64 clone public tables, but RLS does **not** constrain TRUNCATE; do not infer safety from RLS alone.
- **Source grants:** the focused application-schema privilege inventory shows no `anon` table grants in `public`/`private`, while `authenticated` has narrower grants there but still has TRUNCATE on 3 public objects. Full security approval remains unearned for either environment.
- **Role/default ACL metadata:** role attributes and role membership metadata are present in the manifest. `service_role` has `BYPASSRLS` and `postgres` has elevated role/database/replication attributes in both projects; these are privileged roles, not proof of application-runtime safety. Default-privilege records differ (**27 source vs 24 clone**).
- **Edge Functions:** source has 3 active functions and clone has 0. Source `subscription-api` is active with `verify_jwt=false`. Its observed table references are `plans`, `subscription_events`, `subscriptions`, and RPC references include `apply_midtrans_payment`, `apply_play_subscription`, `bind_license_device`, and `get_license_private_key`. Actual API-gateway/authentication/consumer behavior is not established here.
- **RLS/policy drift:** both projects have 42 policies in the audited application namespaces, but the source has all 42 in `public`, while the clone has 40 in `public` and 2 in `private`. Policy-expression hashes differ. All source public tables and all clone public tables report RLS enabled, but application-scope relations do not force RLS. Predicate semantics and actual role-based isolation remain unverified.

Do **not** attempt a live grant fix as part of this audit. Review this separately under explicit change authorization with rollback evidence.

### 3.3 Unexplained schema/platform drift — FAIL pending explanation

- Source has the `cron` schema and installed `pg_cron`; neither is present on the clone.
- Both have a `supabase_realtime` publication with the same publication flags, but source maps `public.client_status` to that publication and clone maps no tables.
- Current app-namespace fingerprints differ for relations, routines, indexes, constraints, triggers and policies. The counts/fingerprints are recorded in the manifest; a differing digest identifies a real inventory difference but does not by itself explain why it is intended.
- Edge Function source bundle hashes and sanitized data/RPC/environment-variable references are recorded. No raw function source or secret values were included.

The manifest classifies explicitly named clone-only test-helper migrations as provisional expected drift; it does not silently label the rest of the clone as safe or expected.

## 4. Required evidence statuses

| Required item | Status | Evidence/result |
|---|---|---|
| Approved read-only scope | **PASS** | User approved exact project IDs/categories/prohibitions in this conversation |
| Credential-delivery/access method | **PASS** | Existing integration-managed authenticated connection; no secrets exchanged in chat |
| Underlying credential is a database read-only role | **NOT VERIFIED** | Tool interface includes write-capable operations; not a DB privilege attestation |
| Schema objects | **PASS** | Non-system schema inventory exported |
| Migrations/history | **FAIL** | 139 vs 12; zero shared version IDs |
| Tables/views | **FAIL** | Relation inventory differs (120 vs 120); per-object records are in the manifest |
| Indexes | **FAIL** | 292 vs 291; hashes differ |
| Constraints | **FAIL** | 756 vs 757; hashes differ |
| Routines/RPCs | **FAIL** | 278 vs 236; definition hashes/signatures differ |
| Triggers | **FAIL** | 58 vs 49; trigger-definition hashes differ |
| Extensions | **FAIL** | 6 vs 5; source-only `pg_cron`/cron |
| Policies/RLS | **FAIL** | Different placement and predicate hashes; isolation tests not run |
| Grants/role attributes/default privileges | **FAIL** | Broad clone grants; default ACL counts differ; security review required |
| Auth/identity metadata | **PASS** | Auth users/identities structural columns and Auth-referencing FK metadata exported; user identity row values not queried |
| Storage object metadata | **PASS** | Zero buckets and zero object-metadata rows observed on each project |
| Realtime/publications | **FAIL** | Source publication maps `public.client_status`; clone map empty |
| Edge Function dependencies | **FAIL** | 3 active source functions / 0 clone; `subscription-api.verify_jwt=false` |
| Object counts and metadata checksums | **PASS** | Counts, definition hashes, migration hash and Edge Function bundle hashes recorded |
| Export completeness | **NOT VERIFIED** | This is a sanitized catalog metadata export, not a full database/business-data export |
| Backup integrity and restore verification | **NOT VERIFIED** | No backup or restore was performed or evidenced |
| Expected clone drift | **NOT VERIFIED** | Test-helper names are provisional; owner confirmation is still required |
| Unexplained drift | **FAIL** | cron/extension, publication, grants, Edge Functions and object fingerprints differ |
| Migration-history reconciliation | **FAIL** | No exact version overlap; repository version prefixes absent from both live histories |
| Security reconciliation | **FAIL** | Broad clone privileges and JWT-verification-disabled active function need review |
| Current production traffic | **NOT VERIFIED** | Not independently inspected |
| Cutover readiness | **BLOCKED** | Migration-history, security/parity, backup/restore and consumer gates remain open |

## 5. Checksums and reproducibility

The JSON manifest includes normalized SHA-256 catalog fingerprints for the application namespaces (`public`, `private`, `accounting_private`, `inventory_private`), a SHA-256 migration-history fingerprint for each project, and the Supabase-provided Edge Function source-bundle hashes. The exact field ordering and input scope for the core catalog fingerprints are recorded in the manifest. Re-run the same ordered catalog stream against the same project to reproduce a category fingerprint.

These fingerprints are **metadata checksums**, not business-data checksums or backup checksums. No full SQL dump, data export or restore test was generated.

## 6. Not inspected / limitations

- No business/customer rows, Auth user records, or identity-provider row values were read.
- Storage object names/paths/content were not retrieved; only bucket metadata and exact object-metadata row counts were collected.
- Routine/trigger/index/constraint source definitions and policy expressions are not retained; their hashes are included to minimize disclosure and avoid copying potential embedded secrets. Edge Function source was processed in memory only to extract sanitized references; raw source was not exported.
- No secret values, private connection URLs, service-admin keys, or tokens were copied to the report or manifest. The absence of a match from a heuristic secret-pattern check is not proof that source contains no hard-coded secrets.
- Live consumer traffic, access logs, API gateway behavior and complete external consumer inventory were not inspected.
- No full database export/backup, integrity validation of a data backup or restore test was performed.
- Calls were read-only, but database and Supabase Management API calls were not one atomic transaction across both projects.
- No target import, schema mutation, grant mutation, migration repair, reset, pause, deletion or cutover action was performed.

## 7. Handoff

**Principal Architect / Decision Owner:** approve or reject the observed clone drift classifications; review the 139-vs-12 migration-history gap and the source-only active functions; arrange least-privilege read-only credential attestation if required; separately authorize any security remediation.

**Laravel Platform Lead:** use this metadata baseline to map required RPC/table behavior and decide which Supabase dependencies are retained, rewritten or retired. Do not treat the live clone as a source baseline or import data on the strength of counts alone.

**Database/Schema Forensics Lead:** preserve the manifest, resolve SQL-file/history mapping without executing archived migrations, collect approved backup/export integrity and restore proof via an approved mechanism, and keep migration/cutover blocked until the owner review is documented.
