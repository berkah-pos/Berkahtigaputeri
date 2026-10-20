# Prompt 00 — System Node Connection Graph

**Audit date:** 2026-10-20 (Asia/Jakarta)  
**Repository:** berkah-pos/Berkahtigaputeri  
**Reviewed main SHA:** 371b7fdf0bf672b37ceb1023e647f114221bf797  
**Audit branch:** audit/prompt-00-system-node-connection-graph-2026-10-20  
**Scope:** System-wide node inventory, cross-node interface map, dependency graph, specialist hand-offs, and evidence reconciliation only.  
**Execution status:** SOURCE REVIEW COMPLETE FOR THE MAPPED BASELINE; TESTS NOT RUN BY THIS AUDIT. No app/schema/workflow/dependency/infrastructure changes were made. No live database, Supabase project, staging, or production was accessed.

## 1. Executive status

**Recommendation: NO-GO for production SaaS release.** The intended architecture is clear, but the current source graph does not connect Flutter to an approved cloud transaction/configuration API. The main Laravel API route is only a static platform-health response; no tracked app/Http implementation was found in the inspected tree and no /api/v1/sync route exists. Flutter still has active source references to supabase_flutter, Supabase initialization, email/password sign-in, and get_effective_config RPC calls, conflicting with the latest owner ADR prohibiting all Supabase product use. The local SQLite path writes business records and a pending outbox event, but no verified network sender, server acknowledgement, conflict receipt, or cloud reconciliation path connects that outbox to PostgreSQL.

The central/tenant migrations and a workbook importer command exist, but they are scaffolding, not an end-to-end service. The importer references six App\Models\Central model classes absent from the checked-in model tree except User.php. A per-tenant credential/grant broker has not been evidenced, and the configured tenant connection can fall back to central database credentials. These are source-level interface/privilege concerns, not claims that production credentials or a live database were inspected.

### Evidence status and tested revision

| Item | Status | Evidence boundary |
|---|---|---|
| Reviewed main HEAD | SOURCE-VERIFIED | 371b7fdf0bf672b37ceb1023e647f114221bf797; this commit adds acceptance-matrix evidence documentation to parent ef167189fa7fcde9e761e50128c0fcf7c44c2285. |
| Exact-SHA application/backend CI on reviewed HEAD | NOT RUN / NOT VERIFIED | The commit status endpoint returned no statuses for 371b7fdf0bf672b37ceb1023e647f114221bf797. The latest relevant baseline/workbook runs located are 39029945646 and 39029945653 on parent SHA ef167189fa7fcde9e761e50128c0fcf7c44c2285; these are not exact-HEAD evidence. |
| Earlier backend scaffold CI | CI-OBSERVED, LIMITED | Run 39005405149 passed initial Composer, Laravel boot/route, disposable PostgreSQL 17 migration, and production-image smoke on SHA aab154f87342f2a02a1319e1d370ce831dbef522. It proves the starter scaffold only, not API parity, tenant grants, restore, deployment or production acceptance. See docs/reports/LARAVEL_PG17_BASELINE_ACCEPTANCE_2026-10-17.md. |
| Earlier Flutter checks | CI-OBSERVED, LIMITED / STALE FOR MAIN | Existing acceptance-matrix records Flutter-only passes on PR #48 SHA 6e31574ecc04ecae6a535fe409cf415ec18655cc and PR #52 SHA ef3a71894db8461a596db5cd51b6bdf764c8f039. They do not prove current-main tests, server parity or cloud sync. |
| This audit's own test execution | NOT RUN | No Flutter, PHPUnit, Docker build, SQL, tenancy, restore, load, staging or production command was executed during this audit. |

No results from different SHAs or narrower workflows are combined to create an aggregate green status.

## 2. Source-of-truth and authority table

| Concern | Authoritative source | Current interpretation |
|---|---|---|
| Agent safety, reading order, reporting and change control | AGENTS.md | Must be followed before source/architecture changes; explicitly forbids Supabase use (including read-only) and execution of scripts/sync_excel_to_supabase.py. |
| Configuration inheritance/workbook inventory | docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md | Exactly GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE; 352 entries = 1 global + 3 templates + 100 tenants + 140 service rows + 108 devices; one requested service per response. |
| Current hosting/platform/no-Supabase decision | docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md | Hostinger KVM2 + Coolify, PHP 8.4/Laravel 13/Filament 5/Sanctum, private PostgreSQL 17, central DB plus separate tenant DB and restricted role per tenant; no Supabase product or project access. |
| Compatible historical platform decision | docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md | Subordinate to the 2026-10-17 ADR wherever they differ; historical source designations are not permission to connect to Supabase. |
| Tenant architecture and required evidence gates | docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md | Target only; real PostgreSQL grants, API, tenant-A/B denial, recovery and deployment remain separate implementation gates. |
| Roadmap order and acceptance | docs/permanent/DOC_00_MASTER_ROADMAP.md | Canonical Phase 0–7 order. Old PR titles do not redefine the roadmap phases. |
| Offline POS, ledger, idempotency and evidence semantics | docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md | SQLite atomicity/outbox and server-durable receipt are separate states; source presence is not executed evidence. |
| Legacy Flutter integration snapshot | docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md | Historical evidence of local behavior and cloud-sync gaps; not permission to use its Supabase runtime path. |
| Actual implementation state | Current main source tree, exact-SHA test/CI logs, then staging/production evidence | A selected design, migration file, test file or green older run cannot prove current runtime behavior. No current exact-SHA product gate was observed. |
| Cross-specialist boundary | Prompt-pack Section 3A and Prompts 01–18 | Prompt 00 owns the graph and hand-offs, not domain implementation or remediation. |

The canonical workbook/config contract and no-Supabase platform policy are compatible and have different ownership. Old Supabase SQL/client paths are archival or migration gaps only. Until an approved, tested Laravel API is connected to Flutter, the accepted target architecture is not the actual end-to-end cloud path.

## 3. Node catalogue

Statuses describe the code/evidence inspected, not inferred runtime health.

| ID | Node / responsibility | Source and evidence | Inputs / outputs and owner hand-off |
|---|---|---|---|
| N01 | Canonical workbook / configuration source | config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx; DOC_00 | Input to N02. Contract is 352 rows, five layers, separate POS/Akuntansi service rows. Owner: Prompt 01. Runtime parity: NOT VERIFIED. |
| N02 | Workbook exporter / validator | scripts/export_workbook_for_laravel.py exists; .github/workflows/canonical-workbook-validate.yml invokes scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352 at line 68 | Workbook-to-manifest edge is PARTIAL. Workflow execution of the prohibited legacy script is a governance conflict. Owner: Prompt 01, with Prompt 15 for workflow guard. |
| N03 | Canonical importer | app/Console/Commands/ImportCanonicalWorkbook.php (signature line 17; first GlobalConfig use line 67; tenant initialization line 129) | Accepts JSON manifest; writes central configuration and device configs. Imports DeviceRegistry, GlobalConfig, Subscription, Tenant, TenantConfig and Template from App\Models\Central, but these model files were not found in the current tree (only User.php is tracked there). Source dependency edge: MISSING in inspected tree; command execution: NOT RUN. Owner: Prompt 01, schema Prompt 04, provisioning Prompt 05. |
| N04 | Central normalized configuration persistence | database/migrations/central/2026_10_17_000001_create_central_platform_tables.php | Creates global_configs, templates, tenant_configs, tenant_services and related tables. Starter migration only; not proof the app imports/resolves config. Owner: Prompt 04. |
| N05 | Effective-config resolver / version contract | DOC_00 and DOC_14 specify target behavior; no tracked resolver/controller was found | Must resolve five layers in order, one requested service, version/hash and authorized tuple. Connection from central config to active Laravel resolver/API: MISSING in inspected source. Owner: Prompt 01 / Prompt 03. |
| N06 | Central identity / membership | app/Models/Central/User.php; central migration users table | User model and Sanctum dependency exist. Membership resolution, token-authenticated API handlers and negative auth tests were not found. The table has nullable tenant_id; a complete membership relation is not evidenced. Owner: Prompt 02, Prompt 04. |
| N07 | Device identity / enrollment | Central migration device_registry; pos-app/lib/core/config/app_identity_store.dart | Client stores tenant/device IDs in SharedPreferences with empty defaults. IDs are selectors, not authorization. Device-to-user enrollment and active server-side authorization flow: NOT VERIFIED. Owner: Prompt 02. |
| N08 | Flutter composition root / login | pos-app/lib/main.dart lines 3, 11, 35; pos-app/lib/features/auth/login_screen.dart | Initializes Supabase when legacy build defines are supplied, passes SupabaseClient into login/config paths and also allows explicit local mode. Source conflicts with latest ADR. Owner: Prompt 06 and Prompt 02. |
| N09 | Flutter effective-config client/cache | pos-app/pubspec.yaml line 16; pos-app/lib/core/config/config_service.dart lines 60, 85–86 | Calls Supabase get_effective_config RPC and caches result by tenant/device/service tuple. Not the approved Laravel API; prohibited by latest ADR. Laravel config request edge: MISSING; old path: CONFLICTING. Owner: Prompt 01 / Prompt 06. |
| N10 | Product catalogue/local persistence | pos-app/lib/core/database/pos_database.dart; product repositories and screens | SQLite-backed local products and migrations exist. Cross-device authoritative catalogue sync: NOT VERIFIED. Owner: Prompt 07; UI composition Prompt 06. |
| N11 | Cashier/cart/pricing/payment request | pos-app/lib/features/pos/cart/**; pos-app/lib/features/pos/checkout/**; checkout screen | Calls local SaleRepository/PaymentService. Local request validation and checkout path are source-present; current-main test result: NOT VERIFIED. Owner: Prompt 08. |
| N12 | Local sale transaction | pos-app/lib/features/pos/checkout/sqlite_sale_repository.dart | Source transaction writes sale, sale items, stock movements, journal and outbox within SQLite transaction; transaction/idempotency code exists. Tested behavior on this exact main SHA: NOT VERIFIED. Owner: Prompt 08. |
| N13 | Physical lot selection / FEFO | pos-app/lib/features/inventory/services/fefo_engine.dart; inventory repository; SQLite sale repository | FEFO lot allocation is called from local sale posting. Cross-node inventory consistency and current-main acceptance are NOT VERIFIED. Owner: Prompt 09. |
| N14 | Financial cost layers / FIFO / COGS | pos-app/lib/features/inventory/services/fifo_cost_engine.dart; SQLite sale repository | FIFO consumption and COGS are wired into local checkout source. Server parity and current-main acceptance are NOT VERIFIED. Owner: Prompt 09. |
| N15 | Journal validation/posting | pos-app/lib/features/accounting/services/journal_service.dart; sqlite_journal_repository.dart | Journal posting is called during local checkout. Source wiring exists; double-entry integrity and append-only behavior need current test evidence. Cloud authoritative journal posting is MISSING. Owner: Prompt 10. |
| N16 | Durable local outbox | pos-app/lib/core/database/pos_database.dart; pos-app/lib/features/pos/checkout/sqlite_sale_repository.dart; home/reports screens | Checkout inserts a pending outbox event; home/reports count unacknowledged events. No current source consumer/uploader was found in the inspected tree. Local write edge: PARTIAL; delivery/ACK edge: MISSING. Owner: Prompt 11. |
| N17 | Laravel transaction sync API / server receipt | routes/api.php | Only GET /api/v1/platform-health is declared (route line 5). No POST /api/v1/sync, durable receipt service, duplicate/conflict contract or transaction-acceptance controller was found. Edge from N16 to cloud: MISSING. Owner: Prompt 03 / Prompt 11. |
| N18 | Central and tenant PostgreSQL schemas | Central migration and database/migrations/tenant/2026_10_17_000001_create_tenant_pos_tables.php | Starter central/tenant tables exist. Tenant migration has starter sales, sale_items, inventory_movements, journal and sync_receipts tables, but no API uses them. Fresh migration smoke was CI-observed on earlier SHA only. Owner: Prompt 04. |
| N19 | Tenant DB selection / provisioning / grants | config/database.php lines 12, 26–27; docker-compose.yml; DOC_14 | Tenant connection can fall back to central DB user/password, and local Compose supplies the same central credentials to tenant connection. No config/tenancy.php or reviewed PostgreSQL broker was present in inspected tree. This does not prove production credentials, but least-privilege edge is NOT VERIFIED and fallback is a P1 source risk. Owner: Prompt 05 and Prompt 04. |
| N20 | Subscription/entitlement | Central migration subscriptions table; importer default trial logic; DOC_12 / roadmap | Table and initial defaulting logic exist. Server-side entitlement middleware/route enforcement, lifecycle transitions and idempotent provider events were not found. Table presence is not enforcement. Owner: Prompt 12. |
| N21 | Reports / aggregates | pos-app/lib/features/home/reports_screen.dart and home screen | Reports read device-local SQLite and show pending outbox counts; UI describes figures as local. Cloud-consolidated, tenant-authorized reports and cross-device reconciliation: MISSING. Owner: Prompt 13. |
| N22 | Central Admin / privileged operations | app/Providers/Filament/CentralPanelProvider.php; bootstrap/providers.php; app/Models/Central/User.php; app/Filament/Central/{Pages,Resources}/.gitkeep | Provider configures panel path central/admin and an active/super-admin check exists in User model. No custom resources/pages were found beyond placeholders; privileged tenant provisioning/configuration/audit workflows and route/domain separation tests: NOT VERIFIED. Owner: Prompt 14. |
| N23 | CI / exact-SHA evidence | .github/workflows/laravel-pg17-baseline.yml; canonical-workbook-validate.yml; pos-app-ci.yml; berkah-pos-aab.yml | CI workflows exist. Backend baseline validates a scaffold and migrates as postgres superuser; this is not tenant-grant acceptance. Relevant last green runs are not tied to reviewed main SHA. Owner: Prompt 15 / Prompt 17. |
| N24 | Container / local development boundary | Dockerfile; docker-compose.yml; .env.example | PostgreSQL 17 and app Compose services exist with local ports bound to loopback. Compose is development scaffold, not deployment evidence or credential separation proof. Owner: Prompt 16. |
| N25 | Android artifact / release gate | pos-app/android/**; .github/workflows/berkah-pos-aab.yml | Workflow blocks publisher-signed release while legacy Supabase runtime strings remain (lines 181–190); it can still produce a debug-signed test artifact. No current-head accepted publisher-signed bundle, matched certificate, device update test or Play acceptance was verified. Owner: Prompt 15. |
| N26 | Staging / production / monitoring / restore | DOC_14, roadmap, runbooks and reports; no current deployment proof observed | Coolify production, private host/DB boundary, monitoring, encrypted off-host backup, central/two-tenant restore, capacity and rollback: NOT VERIFIED. Owner: Prompt 16 / Prompt 17 / Prompt 18. |

## 4. Target dependency graph

This is the owner-approved target contract, not a claim of current implementation.

~~~text
Canonical workbook (352 entries)
  -> validated deterministic manifest
  -> normalized central configuration import
  -> resolver: GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
  -> authenticated Laravel config API + version/hash
  -> Flutter cache for exact tenant/device/service

Flutter UI
  -> domain validation / checkout
  -> one SQLite transaction
       -> sale + immutable line snapshots
       -> FEFO physical lots + stock movements
       -> FIFO cost layers / COGS
       -> balanced append-only journal
       -> durable outbox + stable idempotency key
  -> authenticated Laravel sync API
  -> server auth + active membership + enrolled device + entitlements
  -> server-derived tenant context
  -> provisioned tenant PostgreSQL database + restricted runtime role
  -> atomic sale/stock/journal/idempotency receipt
  -> durable acknowledgement after commit
  -> client outbox accepted; failures/conflicts remain visible

Central identity / device / subscription / domain policies
  -> API authorization
  -> tenant and configuration scope
  -> Filament Central Admin with audit trail

Reviewed source + exact-SHA CI
  -> immutable image and signed Android artifact evidence
  -> isolated staging verification
  -> backup/restore, monitoring, rollback and measured capacity
  -> explicit release decision
~~~

## 5. Graph verified in current source

~~~text
Workbook/export tooling -------------------------------+
  -> legacy validator workflow (calls prohibited script)|
  -> ImportCanonicalWorkbook command -------------------+-> [partial / blocked]
      -> central model dependencies not tracked
      -> configured tenant connection / Tenancy::initialize (unverified)

Flutter startup
  -> legacy Supabase initialization/login (CONFLICTING)
  -> legacy Supabase effective-config RPC (CONFLICTING)
  -> optional local-only mode
  -> local SQLite catalogue + local checkout transaction
       -> sale / sale_items
       -> FEFO lot allocation / FIFO consumption
       -> local journal / stock movements
       -> pending outbox event
  -> local device reports only

Pending outbox -X-> Laravel sync endpoint (MISSING)
Laravel API routes -> static platform-health JSON only
Starter migrations -> central + one configured tenant connection (no accepted API edge)
Central Admin provider -> Filament path/login/access hook; custom domain actions NOT VERIFIED
Current source/CI -> older-SHA smoke evidence only
Staging / production / backup restore -> NOT VERIFIED
~~~

### Key interpretation

The actual source graph stops before the cloud transaction-acceptance boundary. The only network-side API shape in the tracked route file is a platform-health JSON response. The existence of central/tenant tables, Sanctum, Filament, the tenancy package, or a sync_receipts table does not establish that requests authenticate, select the correct tenant database, apply a transaction, or return durable receipts.

## 6. Interface and edge status matrix

VERIFIED means the relevant source edge and required acceptance evidence are present for its stated scope. PARTIAL means only part of the contract is wired. MISSING means the required producer/consumer implementation was not found. CONFLICTING means an existing edge violates the accepted platform contract. NOT VERIFIED means available source/docs do not establish runtime behavior or required tests. This audit did not execute behavior-level tests, so source-present local edges remain SOURCE-VERIFIED / PARTIAL, never full end-to-end VERIFIED.

| Edge | Producer → consumer / contract | Auth, transaction, retry and idempotency boundary | Status / evidence |
|---|---|---|---|
| E01 | Workbook → exporter/manifest | Required tabs, IDs, 352 counts, deterministic hash; dry-run/no DB write | PARTIAL — tool exists; no new exact-head manifest/test was executed here. Owner Prompt 01. |
| E02 | Manifest → central importer | Schema version/count/hash checks; resumable writes | PARTIAL — command exists; references absent model classes; explicitly warns import may be partial across central and tenant operations (ImportCanonicalWorkbook.php lines 17, 40, 67, 129). Owner Prompt 01 / 04 / 05. |
| E03 | Central configuration → five-layer resolver | Preserve order, one service per request, version/hash, CAS and fail-closed tenant/device binding | MISSING — no active Laravel resolver/controller found; DOC_00 is target contract. Owner Prompt 01 / 03. |
| E04 | Flutter login → Laravel identity/session | Sanctum, token expiry/revocation, active membership | MISSING — no Laravel login/API handler in tracked route tree; current login is Supabase based. Owner Prompt 02 / 03 / 06. |
| E05 | Authenticated user → tenant membership + device enrollment | Server-side binding; client IDs not trusted; active/disabled checks | NOT VERIFIED / MISSING API — table fragments exist, but no full handler, enrollment flow or negative tests found. Owner Prompt 02. |
| E06 | Flutter config client → approved central config API | Authenticated route, allowed service, exact tuple cache | CONFLICTING + MISSING target edge — current code calls Supabase RPC (pubspec.yaml line 16; config_service.dart lines 60, 85–86); no Laravel replacement found. Owner Prompt 01 / 06. |
| E07 | Cashier → local sale domain | Validate quantities/pricing/tax/discounts; Rupiah-safe amount model | PARTIAL — source path is wired into local transaction; exact-main executed tests not available. Owner Prompt 08. |
| E08 | Sale domain → local SQLite transaction | Atomic sale, lines, lots, stock, journal, outbox; rollback on error | PARTIAL — transaction source in sqlite_sale_repository.dart; local tests exist but are not current-SHA evidence. Owner Prompt 07 / 08 / 09 / 10. |
| E09 | FEFO allocations → local lot ledger | Eligible lots, expiry/holds/reservations; quantity matches request | PARTIAL — engine/repository call path exists; acceptance status current main NOT VERIFIED. Owner Prompt 09. |
| E10 | FIFO costs → COGS/journal | Cost layer consumption and ledger/journal balance | PARTIAL — source code wired; accounting-invariant execution evidence not available on current SHA. Owner Prompt 09 / 10. |
| E11 | Checkout → outbox event | Same local transaction; stable event/transaction ID and payload fingerprint | PARTIAL — insert present in local sale transaction; runtime behavior current SHA NOT VERIFIED. Owner Prompt 08 / 11. |
| E12 | Outbox → HTTP sync uploader | Bounded retry/backoff, timeout recovery, authentication and payload version | MISSING — no uploader/dispatcher found in inspected tree. Owner Prompt 11. |
| E13 | HTTP sync → Laravel server commit | Validate ownership, atomic sale/items/stock/journal/receipt, idempotent replay/conflict | MISSING — no /api/v1/sync route or sync controller found. Owner Prompt 03 / 11. |
| E14 | API request → provisioned tenant DB/restricted role | Actual PG17 database/role selection; tenant A cannot connect to/read/write tenant B or central private data | NOT VERIFIED / MISSING implementation evidence — no reviewed broker; static tenant connection may fall back to central credentials (config/database.php lines 12, 26–27). Owner Prompt 04 / 05. |
| E15 | Server commit → client acknowledgement | Ack only after durable commit; same-key/same-payload replay stable; conflicting payload explicit | MISSING — no end-to-end receipt API/client ACK implementation found. Owner Prompt 11. |
| E16 | Central subscription state → protected API/UI | Server-authoritative entitlement, status transitions, expiry and grace | MISSING — schema/default trial logic exists, but no server-side enforcement path found. Owner Prompt 12 / 03. |
| E17 | Accepted cloud records → consolidated reports | Tenant-scoped sales/journal/stock aggregates and reconciliation | MISSING — current report reads local SQLite; no server reporting route/API. Owner Prompt 13 / 03. |
| E18 | Filament/Central Admin → privileged operations | Active/super-admin check, central-only routing, explicit policies, audit events | PARTIAL / NOT VERIFIED — panel provider and User gate exist; privileged resources/domain policies and negative route tests are not evidenced. Owner Prompt 14 / 02. |
| E19 | Source commit → relevant CI result | Exact triggered SHA, executed job commands, artifact identity | NOT VERIFIED on reviewed HEAD — no current-SHA application/backend status; green parent-SHA runs do not satisfy exact-head gates. Owner Prompt 15 / 17. |
| E20 | CI image → Coolify staging/production | Immutable digest, environment separation, TLS, rollback | NOT VERIFIED — local Compose and CI image smoke exist; no dated staging/production deployment evidence. Owner Prompt 16. |
| E21 | Central + each tenant + files/keys → recovery | Encrypted off-host coverage, manifest, successful central and single-tenant restore | NOT VERIFIED — no executed restore proof was located. Owner Prompt 16 / 17. |
| E22 | Release build → accepted Android application | Signed artifact, cert identity, installed update, Play checks | NOT VERIFIED — workflow blocks publisher-signed release while Supabase path remains, but no current-head publisher-signed artifact/certificate/device proof. Owner Prompt 15 / 17. |
| E23 | Workbook CI → validation command | Dry-run must not use prohibited Supabase writer | CONFLICTING — canonical-workbook-validate.yml line 68 executes scripts/sync_excel_to_supabase.py --dry-run despite AGENTS.md prohibition on executing it. A dry-run flag does not override the operating contract. Owner Prompt 15; Prompt 01 supplies approved offline validator interface. |

## 7. Disconnected and conflicting edges

1. **Approved mobile-to-cloud path is disconnected.** The current UI's remote authentication/config path is Supabase-based and disallowed; no Laravel replacement API exists in the route tree. Local-only work is possible, but is not the required integrated multi-tenant SaaS flow.
2. **Outbox delivery is disconnected.** A local event can be written and counted, but no event sender, HTTP sync endpoint, atomic server consumer, durable receipt response, or client ACK was found. No proof exists that a sold item is cloud-accepted or appears in a consolidated report.
3. **Importer-to-model dependencies are unresolved.** The command imports six central model classes that do not appear in the checked-in model tree. It was not executed in this audit; runtime result is NOT RUN, and a focused boot/import test is needed before claiming a definitive execution failure.
4. **Tenant credentials are not wired to the required isolation boundary.** Tenant DB connection credentials can fall back to central credentials, and local Compose uses the central user for the tenant connection. There is no evidence of a private provisioning broker creating per-tenant restricted roles and proving grants on PostgreSQL 17.
5. **Server-side identity, membership, device and entitlement checks have no active API edge.** Having table columns or a User model does not implement login, token verification, membership resolution, device enrollment, entitlement gates, or denial behavior.
6. **Reports terminate at local data.** The UI reads local SQLite and explicitly warns against treating local values as consolidated. It does not consume accepted server records.
7. **Workbook CI contradicts the script prohibition.** The workflow executes the legacy Supabase writer with a dry-run flag. It must not be relied on as an approved new-runtime validator while it calls the prohibited program.
8. **Admin route declaration is only a panel entry point.** Filament provider wiring and a User access check exist, but custom central operations/pages, per-domain authorization, audit trail for privileged actions, and route crossover denials are not established.
9. **Static health is not readiness.** /api/v1/platform-health returns fixed JSON without checking PostgreSQL or required dependencies. Its test deliberately says it works without database access. Do not cite it as DB readiness or production health.
10. **Release and operations edges have no current release evidence.** Existing workflows and local Compose describe possible processes. They do not prove a current SHA's accepted AAB, Coolify deployment, tenant isolation, restore, capacity, or production approval.

## 8. Dependency order and phase gates

Use the roadmap's canonical Phase 0–7 numbering.

1. **Phase 0 — scope/evidence freeze:** keep this node map on the exact inspected revision; identify the final candidate SHA; preserve evidence labels and no-Supabase constraints.
2. **Phase 1 — workbook/config contract:** Prompt 01 validates offline workbook/export manifest without Supabase tooling, resolves importer model/connection edges, and test-gates five-layer contract and service isolation.
3. **Phase 2 — central/tenant data contract:** Prompt 04 verifies full PostgreSQL 17 schema, model connection declarations, relationships, monetary representation, transactions and migrations. Current schema migration smoke is only a starter pass.
4. **Phase 3 — PostgreSQL isolation:** Prompt 05 implements and tests a broker and distinct restricted tenant runtime roles against actual PostgreSQL grants; fix credential fallback edge before deployment.
5. **Phase 4 — identity and API entry boundary:** Prompt 02 plus Prompt 03 implement authentication, membership, device enrollment, domain/host rules and protected route contracts; Prompt 14 tests privileged Central Admin boundaries.
6. **Phase 5 — configuration/client/sync integration:** Prompt 03 plus Prompts 01, 06, 11 connect Flutter only to Laravel APIs; remove active Supabase code and build defines; implement durable idempotent sync receipt/ack and explicit conflict state; Prompt 13 integrates reports with authoritative server records.
7. **Phase 6 — cross-domain security and recovery:** Prompt 17 executes integration negative tests; Prompts 15–16 prove exact-SHA CI, secrets/dependency/manifest gates, immutable image, actual grants, isolation, monitoring, measured workload and restore.
8. **Phase 7 — isolated staging/release verification:** Prompt 18 reconciles each required edge against evidence from one exact release-candidate SHA. Data continuity may use only an already available owner-controlled offline artifact outside Supabase; otherwise remains NOT VERIFIED.
9. **Production decision:** only after integrated acceptance gates pass and the human owner explicitly approves. Prompt 00 does not approve production.

No downstream specialist may mark its domain complete from a source file or separate older SHA alone. Prompt 00's graph remains preliminary until each relevant edge has its owner report and exact evidence.

## 9. Cross-specialist issue register

Severity: P0 is release-stopping; P1 is high priority and must be closed before the relevant product/production gate; P2 is material verification/design risk; P3 is lower-priority cleanup. Confidence refers to evidence for the source fact, not a claim of observed production exploitation.

| Finding | Severity / confidence | Affected nodes/edges and evidence | Failure scenario / business impact | Required acceptance test | Owner hand-off |
|---|---|---|---|---|---|
| F00-01: No authorized cloud transaction/configuration path; legacy client path conflicts with owner ADR | P0 / High | N08–N09–N17; pubspec.yaml:16, main.dart:3,11,35, config_service.dart:85–86; routes/api.php:5 | Required SaaS path either depends on a prohibited service or cannot authenticate/configure/sync on selected Laravel platform. No accepted cloud transaction or cross-device truth exists. | Build from source with no active Supabase SDK/init/endpoints; authenticate via Laravel, fetch authorized five-layer config, submit a sale idempotently, receive durable receipt, and verify tenant-scoped server report on that exact candidate SHA. | Prompts 02, 03, 06, 11; Prompt 18 final verification. |
| F00-02: Outbox has no remote consumer/ACK edge | P0 / High for release gate | N16–N17; sqlite_sale_repository.dart writes outbox; routes/api.php has only platform-health | Offline sales remain on a device. Retry/duplicate/conflict handling and cloud acceptance cannot be claimed; cross-device stock/accounting/report state can diverge. | Replay same key/payload; submit same key with altered payload; simulate timeout-after-commit and app restart; prove exactly one accepted sale/journal/stock effect and ACK only after durable server commit. | Prompt 11 with Prompt 03; integrated test Prompt 17. |
| F00-03: Tenant least-privilege boundary not wired/evidenced; tenant creds can fall back to central creds | P1 / High source confidence, production exposure NOT VERIFIED | N19; config/database.php:12,26–27; docker-compose.yml; no broker found | A tenant request/import could use a privileged shared connection rather than explicitly restricted tenant role, undermining database-per-tenant isolation. | On disposable PG17, inspect role attributes, owners, PUBLIC CONNECT, schema/table/sequence/default grants; prove tenant A cannot connect/read/write tenant B or central DB; assert web/ordinary queue env lacks provisioner/migrator/root credentials. | Prompt 05 primary; Prompt 04 connection selection; independent Prompt 17. |
| F00-04: Importer references central models absent from tracked model tree | P1 / High source evidence; runtime result NOT RUN | N03 → N04/N18; ImportCanonicalWorkbook.php:67 and imports at file top; only Central/User.php present | Import command may stop at class autoload and configuration/device mapping may not be produced; partial writes could leave central and tenant data divergent. | Laravel boot and no-write manifest validation, disposable PG17 importer test, rerun/recovery test, exact 352 manifest and deterministic hash. No production writes. | Prompt 01 with explicit Prompt 04/05 hand-off. |
| F00-05: Workbook CI invokes a prohibited legacy writer | P1 / High | N02/E23; canonical-workbook-validate.yml:68; AGENTS.md prohibits execution | CI may execute mutation-capable Supabase code; dry-run flag contradicts the explicit operating prohibition and can normalize a forbidden path. | CI succeeds through approved offline validator and static guard proves no workflow invokes either legacy Supabase sync script. | Prompt 15, Prompt 01 supplies approved offline contract. |
| F00-06: Missing full identity/membership/device authorization API | P1 / High source evidence | N06–N07–N17; route tree lacks auth/controller endpoints; User tenant_id alone is not membership service | Forged tenant/device IDs, inactive membership/devices or invalid token states may not be rejected because no demonstrated request pipeline exists. | Positive/negative Sanctum auth, tenant membership, device ownership, inactive/suspended and client-ID spoofing tests against real routes. | Prompts 02 and 03; Prompt 14 for domain boundaries. |
| F00-07: Server subscription entitlements not connected to API | P1 / High source evidence | N20 → N17/N22; schema only, no enforcement route/service found | UI/API could accept actions inconsistent with plan/status/expiry; default trial logic does not equal reviewed entitlement policy. | Exercise active/trial/past-due/grace/suspended/expired against protected operations; verify audited idempotent transitions and no business-data deletion on expiry. | Prompt 12 and Prompt 03. |
| F00-08: Exact-current-main acceptance evidence absent | P1 / High | N23; reviewed SHA 371b7 has no status; last backend/workbook pass on parent ef167 | Release decision could aggregate historical or narrow green results and miss current defects. | All required checks/artifacts bind to current candidate SHA; jobs must execute; skipped/missing gates fail closed. | Prompts 15 and 17; reconcile via Prompt 18. |
| F00-09: Health route may be misread as readiness | P2 / High | N17/N24; routes/api.php:5 and PlatformSmokeTest.php checks without DB access | Monitoring/release could infer dependency readiness from a static response when PostgreSQL is unavailable. | Separate liveness/readiness semantics; readiness fails when required DB/API dependencies are unavailable. | Prompt 16; Prompt 17 integration. |
| F00-10: Central Admin operations and route separation lack acceptance evidence | P1 / Medium-high | N22/E18; CentralPanelProvider; placeholders only; no negative route tests found | Panel login/access check may be mistaken for complete privileged operations/domain isolation, risking unauthorized central actions or unusable workflows. | Test anonymous/non-admin/inactive-user denials, route crossover, hostile Host/X-Forwarded-Host, audit events and authorized Central Admin lifecycle. | Prompt 14 with Prompts 02 and 17. |
| F00-11: No executed backup/restore, capacity or deployed runtime evidence | P1 / High for production gate | N24–N26; runbooks/scaffold only | Image smoke could be misread as operable deployment; failure could lose central/tenant data or overrun single-node resources. | Isolated Coolify staging; encrypted off-host backup of central/all tenant DBs and required files/keys; restore central + two tenants and a single tenant independently; measure load/headroom and rollback. | Prompts 16 and 17; Prompt 18 gate synthesis. |
| F00-12: Current-main publisher artifact/certificate not verified | P1 / High | N25; AAB workflow blocks signed release while Supabase remains; earlier build success is not current release evidence | Debug/test artifact could be confused with Play-ready release; signing identity/update path or compliance could be wrong. | Build reviewed candidate with no active Supabase path; record artifact hash, signer fingerprint and version; compare to accepted upload key and test device install/update before Play submission. | Prompts 15 and 17. |

## 10. P0/P1 blocker summary

### P0 — blocks integrated SaaS release

- **No approved cloud API flow end-to-end:** tracked Laravel API has only static platform-health; Flutter still has the prohibited Supabase runtime path; cloud sync is absent.
- **No sync acceptance/acknowledgement boundary:** local outbox creation exists but uploader, server atomic receipt, idempotent replay/conflict response and client acknowledgement edge are missing.
- **Do not attempt production release or claim production SaaS readiness from this baseline.** Local-only POS and earlier scaffold-smoke pass do not satisfy the target product contract.

### P1 — close before production acceptance

- PostgreSQL provisioning/tenant credential isolation is not demonstrated; tenant connection configuration has source-level fallback to central credentials.
- ImportCanonicalWorkbook dependencies are absent from the checked-in model tree; runtime/import recovery remains untested.
- Workbook workflow invokes the prohibited Supabase writer during validation even with --dry-run.
- Identity/membership/device enrollment and server entitlement enforcement APIs are missing or not evidenced.
- Current exact-SHA acceptance, privileged admin route tests, release signing, deployment, backup/restore and capacity proof are missing.

## 11. Integrated acceptance checklist

Every line below must be closed by domain owners on a single release-candidate SHA before Prompt 18 may recommend GO:

- [ ] Approved workbook validator runs offline without invoking any Supabase code; exact 352 inventory and deterministic SHA-256 manifest are captured.
- [ ] Importer model/connection dependencies resolve; validated import is repeatable/idempotent and partial-failure recovery is demonstrated on disposable PG17.
- [ ] Five-layer resolver precedence, missing-field inheritance, one-service isolation, expected-version writes and version/hash determinism pass tests.
- [ ] Authenticated Laravel endpoints implement identity, tenant membership, device enrollment, configuration, entitlements and durable transaction sync; no active Supabase package/path remains in Flutter or release build config.
- [ ] Tenant database/role broker passes actual PG17 grant inspection and tenant A/B + central denial, including PUBLIC/default/sequence grants, hostile identifiers/Host headers and worker-context reset.
- [ ] Local SQLite sale/outbox atomicity, FEFO physical allocation, FIFO cost, balanced append-only journals, rollback, restart and retry/conflict tests pass on current SHA.
- [ ] Server sync is idempotent for same payload, deterministic conflict for reused key/different payload, and acknowledges local outbox only after durable commit.
- [ ] Reports separate local pending data from server-accepted tenant-wide aggregates and reconcile inventory/accounting sources.
- [ ] Central Admin and tenant domains/privileges pass negative route, membership, device and audit tests.
- [ ] All required CI checks execute and pass at exactly the candidate SHA; image/AAB hashes and signer evidence are recorded.
- [ ] Isolated Coolify staging accepts candidate; HTTPS, readiness, secrets, rollback and monitoring are verified.
- [ ] Encrypted off-host backup and tested restore include central DB, each tenant DB, file data and recovery keys; performance and resource headroom are measured.
- [ ] Independent security/QA review reports no unresolved critical/high findings; owner gives explicit release approval.

## 12. Final recommendation

**NO-GO.** The source tree has useful partial foundations—canonical configuration contract, workbook import command, central/tenant migration scaffolding, local SQLite checkout with FEFO/FIFO and journals, an outbox write, Filament provider configuration, and baseline CI/Docker files—but the graph is not integrated across the mobile/cloud boundary. The target Laravel Central API, actual per-tenant privilege boundary, approved mobile configuration/auth path, transaction sync acceptance/ACK, server-side entitlement gates, consolidated reports and operational recovery are missing or unverified. At least two production-critical edges are confirmed missing in source: Flutter outbox → sync API and active Flutter → approved Laravel config/auth APIs.

This is an audit recommendation, not authorization to deploy, migrate, mutate a live database, or alter production resources. No implementation remediation was performed in Prompt 00. Domain owners should close the registered hand-offs in roadmap dependency order, then Prompt 18 must reconcile all direct evidence on one exact candidate SHA before any GO decision.

## Evidence references

- AGENTS.md
- docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md
- docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md
- docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md
- docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md
- docs/permanent/DOC_00_MASTER_ROADMAP.md
- docs/permanent/README.md
- docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md
- docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md
- docs/permanent/DOC_01_3_LAYER_CONFIG.md
- .cursor/rules/berkah-pos.mdc
- .github/muse-instructions.md
- app/Console/Commands/ImportCanonicalWorkbook.php
- app/Models/Central/User.php
- routes/api.php; routes/web.php
- config/database.php
- database/migrations/central/2026_10_17_000001_create_central_platform_tables.php
- database/migrations/tenant/2026_10_17_000001_create_tenant_pos_tables.php
- pos-app/pubspec.yaml; pos-app/lib/main.dart; pos-app/lib/core/config/config_service.dart; pos-app/lib/core/config/app_identity_store.dart
- pos-app/lib/features/pos/checkout/sqlite_sale_repository.dart
- pos-app/lib/features/inventory/services/fefo_engine.dart; pos-app/lib/features/inventory/services/fifo_cost_engine.dart
- pos-app/lib/features/accounting/services/journal_service.dart
- pos-app/lib/features/home/reports_screen.dart
- .github/workflows/laravel-pg17-baseline.yml; .github/workflows/canonical-workbook-validate.yml; .github/workflows/pos-app-ci.yml; .github/workflows/berkah-pos-aab.yml
- docs/reports/LARAVEL_PG17_BASELINE_ACCEPTANCE_2026-10-17.md
- docs/reports/ACCEPTANCE_MATRIX_CI_EVIDENCE_2026-10-16.md
- docs/reports/acceptance-matrix-ci-evidence-2026-10-16.json
