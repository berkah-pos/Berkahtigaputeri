# Prompt 17 — Independent End-to-End Contract Verification

**Audit date:** 2026-10-21 (Asia/Jakarta)  
**Repository:** berkah-pos/Berkahtigaputeri  
**Reviewed application baseline:** main at `371b7fdf0bf672b37ceb1023e647f114221bf797`  
**Report branch:** `audit/prompt-17-e2e-contract-verification-2026-10-21`  
**Scope:** Cross-node interface contracts, representative local transaction journey, configuration path, sync/acknowledgement, financial reconciliation, identity/tenant boundaries, and exact-SHA evidence only.  
**Change boundary:** Report-only. No application or test files changed; no database, secret, CI workflow, infrastructure, staging, production, or Supabase resource accessed.

## 1. Executive decision

**Disposition: BLOCKED / NO-GO for integrated cloud SaaS acceptance. PARTIAL for the explicitly local-only POS journey.**

The source traces demonstrate a useful local workflow: product master changes and stock receipts are written into SQLite; checkout computes totals from persisted product data; the sale, sale items, physical FEFO allocations, FIFO cost-layer consumption, journal, and pending outbox event are issued inside the same exclusive SQLite transaction. The UI clearly tells the operator that the transaction is local and that cloud sync is not active.

The end-to-end contract stops at that boundary. At the reviewed main SHA:

- The only Laravel API route found is the static GET endpoint `/api/v1/platform-health`. No authenticated login/enrollment, effective-configuration, sale-sync, durable receipt/ACK, conflict, or cloud-reporting endpoint is present in the tracked route/controller implementation.
- Flutter retains `supabase_flutter`, Supabase initialization/authentication, and a `get_effective_config` RPC call. This violates the controlling 2026-10-17 owner decision prohibiting all Supabase product use. A replacement Laravel identity/config/sync path is not connected.
- The local outbox produces a compact summary, not the immutable sale/inventory/journal event needed to reconstruct and reconcile the posted transaction. No current sender, retry state machine, durable server acknowledgement, or conflict lifecycle connects it to PostgreSQL.
- The current main tree lacks the full identity/membership/device-authorization chain and a per-tenant credential/grant broker. Tenant DB environment settings can fall back to central credentials; this is not isolation.
- The workbook import/configuration path does not terminate at a resolver/API connected to the Flutter client on main. Candidate configuration work exists on a separate unmerged PR and cannot be treated as deployed main behavior.
- Source tests exist for portions of local idempotency, FEFO/FIFO and error rollback, but this audit did not execute Flutter, PHPUnit, PostgreSQL, or full integration tests. No current-head application CI run was found.

**The source does not prove a production incident.** These are source-verified gaps and acceptance failures. They are sufficient to prevent an integrated-readiness claim even without production access.

## 2. Authority, method, and evidence classes

The audit followed the controlling repository instruction spine: root AGENTS.md; the canonical configuration decision; the 2026-10-17 owner ADR selecting KVM2/Coolify, Laravel and PostgreSQL 17 while prohibiting Supabase; then the subordinate architecture, roadmap, and relevant offline/accounting contracts. Source-level references were checked against the reviewed main revision. The Prompt 00, 01, 02, 04, 05, 08, 09, 11, 13, 15 and 16 reports were consulted where relevant; reports on open PR branches remain proposed/audit evidence, not merged source or proof that a runtime test passed.

Evidence labels used throughout:

- **SOURCE-VERIFIED:** the named behavior or gap is visible in tracked source at the SHA stated above.
- **TEST-SOURCE-VERIFIED:** a test assertion exists in source; the test has not thereby been shown to pass.
- **CI-OBSERVED:** the identified job actually ran on its recorded SHA. This label is not transferable to another SHA or a different journey.
- **NOT RUN / NOT VERIFIED:** the test, service interaction, grant, runtime, staging or production behavior was not executed/observed.
- **INFERRED FAILURE MODE:** a reproducible risk derived from the source path, not a claim that customer data was affected.

Repository contracts carried into this audit:

1. Configuration order is exactly GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE. The canonical workbook contains 352 entries: 1 global, 3 templates, 100 tenants, 140 service entries and 108 devices. Resolve one requested service at a time; do not merge POS and Akuntansi configuration.
2. Local checkout is expected to atomically persist its local effects and outbox event. FEFO governs physical lot selection; FIFO governs financial stock costing.
3. Rupiah values must use integer/fixed precision. Posted accounting must remain balanced and auditable; corrections require reversals, not edits to posted history.
4. Tenant/device IDs supplied by a client are selectors, not proof of authority. Identity, active membership, device ownership and access to a tenant database must be checked in trusted server/database boundaries.
5. Supabase and the legacy workbook-to-Supabase writer are prohibited by the active owner decision. This audit did not access Supabase or invoke that writer.

### Execution environment and exact-head evidence

A read-only availability check found PHP 8.4.24 and Git 2.47.3 in the local execution environment. Flutter, Dart, Composer, psql, Docker and Podman were not available. Accordingly, no Flutter analyzer/test, Composer/PHPUnit, disposable PostgreSQL 17 test, HTTP integration test or full transaction journey was run as part of Prompt 17.

GitHub Actions metadata for main SHA `371b7fdf0bf672b37ceb1023e647f114221bf797` returned two successful dynamic Dependabot runs only: [39184121515](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39184121515) and [39186055413](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39186055413). The combined-status response had no statuses. These are dependency-update jobs, not application journey evidence. Earlier green runs on other SHAs are historical and do not pass the current-main gate.

No HTTP request was made against a hosted service. Statements about absent API paths below are source-tree findings, not the result of a request to staging or production.

## 3. Representative journey: producer-to-consumer trace

| Journey stage | Source edge and observed behavior | Contract verdict |
|---|---|---|
| App boot and entry | `pos-app/lib/main.dart` opens the local SQLite database and selects a local-only route when no cloud config is supplied. If Supabase build variables are present, it initializes Supabase. `features/auth/login_screen.dart` signs in using Supabase Auth. | **PARTIAL / BLOCKED for cloud.** Local operation is explicit. Cloud entry remains bound to a prohibited backend and has no Laravel replacement path on main. |
| Identity → tenant/device context | `core/config/app_identity_store.dart` persists tenant/device identifiers locally. Central migrations contain users, tenants, subscriptions and device_registry tables. | **NOT VERIFIED / BLOCKED.** Stored identifiers are not authorization. No current Laravel login, membership or enrollment route/middleware establishes trusted caller, tenant and device context. |
| Workbook → importer → resolver → API → UI | DOC_00 declares the five-layer 352-entry contract. Main contains a Python exporter and a Laravel import command, but the command references absent central model classes, imports are not one atomic operation across all tenant device writes, and no effective-config resolver/API endpoint is present on main. Flutter calls the Supabase RPC instead. | **BLOCKED.** No verified, permitted end-to-end configuration response reaches the UI. Service-enabled state and import completeness also require explicit acceptance. |
| Product setup | `features/products/repositories/sqlite_product_repository.dart` saves products in a SQLite transaction. A new product must start at zero stock; stock is added through the receipt path. | **SOURCE-VERIFIED local path.** Current product contract does not model an active/disabled state. No server catalogue sync is connected. |
| Inventory receipt | `features/inventory/inventory_screen.dart` calls `addInventoryLot`. That repository transaction writes the physical lot, FIFO cost layer, product stock increase and receipt movement together. | **SOURCE-VERIFIED structure; tests NOT RUN.** Local source has the intended transaction boundary, but exact-head execution and adversarial failure proof are absent. |
| Cart preview → checkout request | `features/pos/checkout_screen.dart` previews totals from the in-memory product list. Each checkout invocation creates a timestamp-based transaction ID in a local variable. `PaymentRequest` carries product IDs/quantities and request metadata, not a durable quote or expected product version. | **PARTIAL / P1 risk.** A product price or tax-classification change can make the committed total differ from the displayed preview. The request ID is not persisted for recovery after an ambiguous commit. |
| Checkout → sale and stock | `features/pos/checkout/sqlite_sale_repository.dart` opens the exclusive SQLite transaction, looks up an existing transaction ID and fingerprint, reads product values from SQLite, calculates the sale, consumes FEFO lots and FIFO cost layers, then decrements stock and writes sale/header/item/movement records. | **SOURCE-VERIFIED structure; TEST NOT RUN.** A same-ID/same-fingerprint replay is designed to return the prior sale. A same-ID/different-fingerprint request throws a conflict. These invariants still need exact-head execution and an interrupted-process test. |
| Checkout → journal | The repository calls `JournalService.post` using the same transaction executor. The service validates known COA accounts, non-negative single-sided lines, and total debit = total credit before inserting. | **LOCAL SERVICE INVARIANT SOURCE-VERIFIED.** No current cloud posting edge exists. The local service alone does not prove PostgreSQL database-level immutability, closed-period enforcement, accounting_events completeness, or independent server acceptance. |
| Checkout → outbox | The same local transaction inserts one `outbox_events` row with status `pending` and retry_count 0. Its payload contains sale ID, transaction ID, business date, grand total, PPN and payment method. | **LOCAL PENDING EVENT SOURCE-VERIFIED.** Payload is a summary, not a complete immutable posting package. No dispatcher/worker moves it through delivery, server receipt, retry, or conflict states on main. |
| Outbox → API → PostgreSQL → ACK | Main `routes/api.php` only registers GET `/v1/platform-health`. The starter tenant migration has a `sync_receipts` table, but the current route/controller tree does not apply an authenticated event transaction or produce a durable receipt. | **BLOCKED / NOT IMPLEMENTED on main.** A schema row or pending local event is not evidence of server acceptance. |
| Report → reconciliation | `features/home/reports_screen.dart` aggregates all local sales and COGS, shows recent sales, separately labels archived trial rows, and counts every outbox status other than acknowledged. It explicitly says no cloud worker is active. | **PARTIAL / local-only.** No period/status/reversal filter or cross-ledger reconciliation to sale items, journals, inventory movements, cost layers and server receipts is shown. No cloud consolidated report source exists on main. |
| Entitlement and tenant isolation | Central subscription and device registry schema exists; API request authorization chain and real per-tenant DB-role isolation tests are absent from main. `config/database.php` permits tenant DB identity values to fall back to central/global values. | **BLOCKED / NOT VERIFIED.** No tenant A/B request or real PostgreSQL restricted-role isolation journey was executed. |

## 4. Expected-versus-actual representative fixture

The following is a **proposed, unexecuted disposable SQLite acceptance fixture**, not an observed result or a tax-policy approval. It uses the calculator’s current source-defined 11% rate solely to make the arithmetic test deterministic.

**Fixture ID: E2E-LOCAL-001**

- Create one non-exempt product at Rp10,000 per unit, with stock initially 0.
- Receive 3 units through the inventory receipt function at FIFO unit cost Rp4,000.
- Check out 2 units at the stated price, without discounts.
- Capture database counts and contents before and after each operation.

| Assertion | Expected result for this fixture | Actual Prompt 17 result |
|---|---:|---|
| Receipt outcome | Stock 0 → 3; one physical lot; one matching FIFO cost layer; one receipt movement | **NOT RUN** |
| Gross and taxable DPP | Rp20,000 | **NOT RUN** |
| Source-defined PPN arithmetic | Rp2,200 at the hard-coded 11% test rate | **NOT RUN** |
| Grand total | Rp22,200 | **NOT RUN** |
| FIFO COGS | Rp8,000; 2 units × Rp4,000 | **NOT RUN** |
| Final product stock | 1 unit | **NOT RUN** |
| Sale and sale items | Exactly one sale and one corresponding item for this one-line fixture | **NOT RUN** |
| Journal | Exactly one related journal; debit total equals credit total; lines match the accepted COA posting policy | **NOT RUN** |
| Stock/lot/cost effects | Quantity decrements agree across product stock, physical lot allocation, FIFO consumption and movement records | **NOT RUN** |
| Outbox | Exactly one event, pending and unacknowledged, until real durable server acceptance | Local source creates pending event; end-to-end outcome **NOT RUN** |
| Server receipt/ACK | Must not exist before server commit; after commit it must be durable and replay-safe | **BLOCKED:** no current-main sync endpoint/dispatcher found |
| Report | Local totals reconcile to the exact sale/journal/stock data and clearly remain device-local until cloud acceptance | **NOT RUN** |

The fixture is deliberately not marked PASS because the required execution toolchain was unavailable. The 11% value is what the current source implements, not a validation of the legally applicable PPN rule. Tax-policy/version governance must be independently approved before release.

**Fixture ID: E2E-FEFO-FIFO-002**

The test source `pos-app/test/inventory/fefo_checkout_test.dart` includes an example in which physical FEFO chooses the lot with the earlier expiry date while FIFO financial costing consumes the older cost layer, with expected COGS Rp30,000. This is a useful cross-node contract example, but it is **TEST-SOURCE-VERIFIED only** for this audit. It was not executed, and it does not establish server-side inventory parity.

## 5. Cross-node negative-test matrix

All rows below remain unexecuted in this audit. The expected behavior is the acceptance oracle; the actual-state column distinguishes source evidence from a runtime test result.

| ID | Boundary and fault injection | Required expected outcome | Actual state / gap |
|---|---|---|---|
| E2E-ID-01 | Submit no account, expired/revoked session, inactive user, wrong tenant membership, forged tenant ID or foreign device ID. | Protected requests fail closed before reading or mutating tenant data; client-provided identifiers never establish trust. | **BLOCKED:** no Laravel mobile auth/membership/device route found on main; Supabase auth exists only as prohibited legacy client path. |
| E2E-CFG-01 | Resolve a synthetic key set through GLOBAL → TEMPLATE → TENANT → exactly one SERVICE → DEVICE; test missing values versus explicit null/false/zero/empty string; request POS then Akuntansi separately. | Later layers override only explicitly defined fields, absent keys inherit, hashes/versions are deterministic, and a POS result contains no Akuntansi-service merge. | **BLOCKED on main:** no connected Laravel resolver/API/client path. Source contract exists in DOC_00; a separate open configuration PR is not main acceptance. |
| E2E-CFG-02 | Feed importer manifests with wrong inventory count, duplicate/missing keys, wrong tenant/template/device mapping, invalid service, malformed config, and wrong device ownership. | Reject all invalid input before writes; accepted apply has exact counts, stable versions and explicit recovery for interrupted per-tenant work. | **NOT RUN.** Main importer checks the envelope/counts and keyset digest but does not independently validate the full record graph; referenced central model classes are absent on main. |
| E2E-POS-01 | Execute E2E-LOCAL-001 and compare header, items, FEFO/FIFO, stock movement, COGS and journal. | Values reconcile exactly; local transaction effects appear all together. | **NOT RUN.** Source path is transaction-scoped, but this fixture was not executed at the reviewed SHA. |
| E2E-IDEMP-01 | Repeat the same transaction ID and byte-equivalent logical request. | Return the same persisted sale/result; exactly one sale, journal, stock consumption set and outbox event. | **SOURCE-VERIFIED design; NOT RUN.** Existing test source exercises parts of duplicate handling. |
| E2E-IDEMP-02 | Reuse the transaction/event ID with changed quantity, tender or other fingerprinted input. | Reject as explicit conflict; do not change stock, sale, journal or outbox counts. | **TEST-SOURCE-VERIFIED; NOT RUN.** The current local repository compares request fingerprints and throws on mismatch; this has no corresponding server-sync counterpart on main. |
| E2E-CRASH-01 | Kill/restart after local SQLite commit but before the success dialog; retry the unfinished cashier intent. | Reuse a durable operation ID and return the existing sale; no second sale or stock decrement. | **P1 gap SOURCE-VERIFIED:** checkout generates the ID anew for each call and does not persist the intent/request key for process-restart recovery. |
| E2E-ROLLBACK-01 | Use two cart lines: allow the first to consume lot/cost/stock and force the second to fail; separately inject a write error after sale/journal insertion and before outbox completion. | Roll back the complete transaction: no sale, sale item, journal/line, inventory/stock movement, reservation transition or outbox row remains; all quantities and balances return to baseline. | **NOT RUN; existing rollback test is insufficient for late failure.** Its documented insufficient-stock case fails before partial work, so it does not prove rollback after an earlier line has already mutated rows. |
| E2E-PREVIEW-01 | Load cart, change persisted product price or tax exemption before submit. | Show/reconfirm the actual commit amount or reject a stale quote; cashier must not unknowingly commit a different total. | **P1 risk SOURCE-VERIFIED:** UI calculates from in-memory product state, while repository reloads price and tax classification at commit. No immutable versioned quote is present. |
| E2E-SYNC-01 | Submit the local outbox while offline, then with timeout, connection reset, invalid auth, and server transaction rollback. | Event stays pending/retryable until durable server acceptance; local business rows persist; no duplicate effects; retries are bounded/observable. | **BLOCKED:** no network dispatcher or sync handler found on main. Outbox currently stays pending. |
| E2E-SYNC-02 | Send identical event twice to server; then same event ID with different canonical payload. | First commit creates one sale/stock/journal/receipt; identical replay returns the identical durable receipt; payload mismatch yields a conflict and no new mutation. | **BLOCKED / NOT RUN:** no current-main request handler/ACK/idempotency implementation; a starter `sync_receipts` table alone is insufficient. |
| E2E-TENANT-01 | Tenant A attempts CONNECT/read/write to Tenant B and central DB using real restricted PostgreSQL 17 principals; spoof Host/X-Forwarded-Host; forge tenant/device IDs; interleave tenant A/B jobs after an exception. | Every cross-tenant operation is denied; host/domain routing and membership are server-derived; tenant context, DB identity, auth, cache and filesystem are reset between jobs. | **NOT RUN / BLOCKED:** local PostgreSQL tools unavailable; no restricted-role broker/config resolver on main; tenant credentials can fall back to central credentials. |
| E2E-REPORT-01 | Reconcile one accepted synthetic sale and one reversed/voided sale to sale items, journal, inventory/cost layers, outbox receipts, and selected reporting period. | Report totals use a defined financial metric and period; exclude/adjust reversals correctly; reconcile exactly with underlying ledgers and label local/unaccepted values honestly. | **P1 gap SOURCE-VERIFIED:** main report is an unfiltered local aggregate over all sale headers and does not cross-reconcile ledgers or server receipts. |
| E2E-CI-01 | Inspect checks and artifacts for the exact candidate SHA, not a parent/related PR. | Required app, PHP and PostgreSQL 17 jobs actually execute; failures/skips/warnings are preserved; evidence is tied to exact SHA and job. | **CI OBSERVATION:** current main has two dynamic Dependabot runs only, no application journey evidence. Prompt 17 ran no tests. |

## 6. Findings and required closure

Severity is a release prioritization, not evidence that production was exploited. Confidence describes confidence in the source observation. No implementation fixes were made under this prompt.

### E2E-01 — P0 — No permitted end-to-end identity, configuration and transaction API chain

**Confidence:** High.  
**Affected edges:** App boot/login → authenticated Central API → tenant/device context → effective configuration and sale sync.

**Evidence:** `pos-app/pubspec.yaml` still declares `supabase_flutter`; `pos-app/lib/main.dart` initializes Supabase; `features/auth/login_screen.dart` uses Supabase password auth; `core/config/config_service.dart` calls a Supabase RPC. Main `routes/api.php` only declares GET `/v1/platform-health`. No current-main sync/config/auth controller route was found.

**Failure/reproduction:** A local cashier can create an SQLite sale and pending outbox event, but there is no approved, implemented route for that event to establish caller identity, validate tenant/device membership, post to PostgreSQL and receive a durable ACK. The legacy config/auth dependency is prohibited by the latest owner decision.

**Impact:** No defensible cloud SaaS path or cloud data authority can be accepted; local-only use must remain clearly labeled. Do not claim that a platform-health response proves DB readiness or auth/sync availability.

**Closure evidence:** A reviewed Laravel authentication/membership/device trust boundary and effective-config/sync contracts, the Flutter client wired to those contracts, exact-head isolated PostgreSQL/HTTP tests, durable ACK/conflict tests, and removal of prohibited Supabase runtime usage. The sync event must carry enough immutable details to reconcile the local sale.

**Handoff:** Prompt 02 (identity/device trust), Prompt 01 (configuration), Prompt 11 (sync/idempotency), and the owner-approved API/route specialist. Prompt 17 does not implement these components.

### E2E-02 — P0 — Tenant boundary cannot be accepted from schema or fallback configuration

**Confidence:** High for source risk; live privilege state **NOT VERIFIED**.  
**Affected edges:** authenticated client → trusted tenant context → per-tenant PostgreSQL identity → long-lived worker/cache/storage.

**Evidence:** Main has no complete authorization middleware/controller chain, no tracked `config/tenancy.php`, and no evidenced per-tenant DB-credential broker. `config/database.php` permits tenant host/user/password values to fall back to central/global settings. Existing local Compose uses the same PostgreSQL login for both connections. Central tenant/device tables are only storage declarations, not proof of enforced trust.

**Failure/reproduction:** Missing tenant DB settings may resolve to a central identity; a caller-supplied tenant/device ID or hostile host can only be safely rejected if a reviewed trusted boundary actually executes. No actual tenant A/B grant test was run.

**Impact:** Tenant confidentiality and write isolation remain unproven. Application-side filtering or installing a tenancy package cannot substitute for real restricted database role/privilege tests.

**Closure evidence:** A fail-closed per-tenant connection resolver, separate actual PostgreSQL 17 principals and grants, A/B plus central DB denial tests, hostile Host/proxy/membership/device negatives, and worker context reset after success, exception and retry. Preserve sanitized catalog/privilege output tied to exact head.

**Handoff:** Prompt 05 (database roles/grants/isolation), Prompt 02 (identity/device authorization), and Prompt 16 (private runtime configuration/worker boundary).

### E2E-03 — P1 — Workbook configuration has no verified path to the active client

**Confidence:** High.  
**Affected edges:** canonical workbook → exporter/manifest → importer/model/schema → effective resolver → authenticated API → client cache/UI.

**Evidence:** DOC_00 defines a valid five-layer contract and 352-entry inventory. On main, the importer references central model classes not present in the tree; service-enabled mapping and atomic central-plus-device import are incomplete; no effective resolver/API is wired into `routes/api.php`; the client still uses Supabase RPC. Candidate work is on an open, unmerged PR and is not main implementation evidence.

**Failure/reproduction:** A manifest can pass envelope/count checks without the full imported record graph being proven; even if import is proposed, the client has no permitted Laravel response source in main. Separate POS and Akuntansi responses and override/cache freshness therefore cannot be integrated-verified.

**Impact:** Tenant feature gating/configuration and offline config authority are not suitable for a cloud launch.

**Closure evidence:** Offline manifest validation of every row and relationship, exact 352-entry inventory with deterministic SHA-256 manifest artifact, atomic/resumable apply semantics, CAS/audit evidence, positive/negative layer precedence fixtures for both services, and a tested authorized Laravel API/client path. The prohibited legacy workbook-to-Supabase writer must not be executed.

**Handoff:** Prompt 01 (configuration/import/resolver) and Prompt 02 (authorization and cache invalidation). Open [PR #69](https://github.com/berkah-pos/Berkahtigaputeri/pull/69) is a separate configuration candidate; its declared evidence remains branch/SHA-specific and does not make main green.

### E2E-04 — P1 — Outbox summary cannot safely drive server replay/reconciliation

**Confidence:** High.  
**Affected edges:** local sale post → event serializer → sender/retry state → authenticated server transaction → receipt → report.

**Evidence:** Local checkout creates a pending outbox event with only six summary fields and no current sender. Main lacks a sync route/handler and server receipt transaction. A `sync_receipts` table in a migration does not provide behavior. Tenant migration's inventory movement source-event identity is not uniquely enforced. The outbox state is not advanced by a current-main dispatcher.

**Failure/reproduction:** Replaying an event over a future network path cannot be accepted without canonical payload hash, authenticated tenant/device identity, server-side atomic posting, same-ID/same-payload receipt replay and same-ID/different-payload conflict behavior. With no sender/API, timeout/ACK transitions cannot be executed today.

**Impact:** Local pending events may never reach the cloud; simply clearing pending state could lose sales, while retrying without durable idempotency could duplicate business effects.

**Closure evidence:** Full immutable event schema, sender with bounded retry/backoff and explicit error/conflict state, server-side transactional idempotency receipt, durable ACK only after commit, same/conflicting replay tests, and reconciliation of every effect to the accepted receipt.

**Handoff:** Prompt 11 (outbox/client/sync), Prompt 08 (source sale event and idempotent intent), Prompt 05/04 (server schema/privilege contract), and the authenticated API owner. Open [PR #93](https://github.com/berkah-pos/Berkahtigaputeri/pull/93) contains an internal atomic PostgreSQL sale-posting candidate, but is draft/unmerged and explicitly does not expose an authenticated sync route. Its branch tests must not be represented as end-to-end API proof.

### E2E-05 — P1 — Local idempotency is not durable across ambiguous checkout outcome

**Confidence:** High.  
**Affected edges:** cashier intent → generated transaction ID → SQLite commit → success UI → restart/retry.

**Evidence:** `CheckoutScreen._checkout()` creates a new timestamp-derived ID per invocation, held only in a local variable. The repository's fingerprint check can protect replay when the same ID is reused, but the UI does not persist the ID/intent across process termination.

**Failure/reproduction:** Inject process termination immediately after the local DB transaction commits but before the success dialog appears. Restart and repeat the cashier action. The newly generated ID can describe the same real-world sale as a new transaction, bypassing the old key's deduplication.

**Impact:** Duplicate local sale, journal, stock decrease and outbox rows are possible after an ambiguous result. This is a failure mode, not a claim that duplicates were observed.

**Closure evidence:** Persist a pending checkout intent and unique operation ID before the first commit attempt; recover/retry using that ID across restart; test exactly one sale/journal/stock movement/outbox event under the forced crash. Changed payload under the same key must fail without mutation.

**Handoff:** Prompt 08 (checkout key and retry semantics) and the SQLite durability/persistence owner; coordinate with Prompt 11 before any network retries.

### E2E-06 — P1 — Atomic rollback is wired in source but late-failure rollback is not proven

**Confidence:** High for test gap; source shows an outer transaction structure.  
**Affected edges:** checkout loop → FEFO/FIFO updates → sale rows → journal → outbox.

**Evidence:** `PosDatabase.transaction` is exclusive and the repository uses that transaction for the posting sequence. Existing rollback test source uses an insufficient-stock case that fails before the tested operation has made earlier line mutations. This audit did not execute any test.

**Failure/reproduction:** In a disposable database, let the first line update its FEFO lots/FIFO layers/product stock, then force a later line or write to fail; also inject failure after journal inserts but before outbox insertion.

**Impact:** The most consequential invariant—no partial financial/inventory record set—is not independently proven by the current negative fixture.

**Closure evidence:** Test both deterministic injected failure checkpoints; compare pre/post row sets, stock, lot quantities, cost layers, movement counts, reservation state, journal totals and outbox status. All affected values must return exactly to baseline. Also verify the successful counterpart commits one complete consistent record set.

**Handoff:** Prompt 08 (outer transaction acceptance), Prompt 09 (inventory state/fixtures), Prompt 10/accounting integrity (journal/posting assertions), Prompt 11 (outbox atomicity).

### E2E-07 — P1 — No integrated ledger/report reconciliation contract

**Confidence:** High.  
**Affected edges:** sale header/items ↔ journal ↔ stock/lot/cost movements ↔ outbox/receipt ↔ dashboard/report.

**Evidence:** The local reporting query sums every row in `sales` without period/status/reversal filters; `grand_total` includes PPN but is labeled “Penjualan lokal”; COGS is independently summed. No source path reconciles report totals to line items, journal entries, FIFO consumption, physical stock movements or accepted server receipts. Archived trial rows are separately presented and disclosed as incomplete, which is a positive control.

**Failure/reproduction:** Seed one valid sale, one correction/reversal fixture where permitted, and one pending/unaccepted outbox event in a disposable local DB. Compare header arithmetic, line DPP/discount totals, calculated PPN, total, COGS consumption, balanced journal, resulting stock and report metric definition. Require explicit period and accepted-versus-pending provenance.

**Impact:** Reports cannot be promoted from local summaries to accounting-grade, period-close, or multi-device consolidated reports. Pending outbox count is not an accepted-cloud count.

**Closure evidence:** Approved metric definitions and period behavior; testable reconciliation equations; reversal-aware lifecycle; clear local vs server-accepted reporting source; independent regression tests whose outputs are tied to exact main/candidate SHA.

**Handoff:** Prompt 13 (report metrics/reconciliation), Prompt 10/accounting integrity, Prompt 08/09/11 (source transactions, inventory, sync receipts).

### E2E-08 — P1 — Exact-SHA application validation is absent

**Confidence:** High.  
**Affected edges:** source revision → required CI jobs → candidate artifact → release/runtime acceptance.

**Evidence:** On current main SHA, GitHub returned only the two dynamic Dependabot runs, with no relevant app/backend test run or ordinary status records. This Prompt 17 execution environment lacks Flutter/Dart, Composer and PostgreSQL tooling. No application, test, server, staging or production journey was run here.

**Failure/reproduction:** A green dependency-update job or older green run could be incorrectly represented as current app acceptance. The current exact SHA cannot be called green on this evidence.

**Impact:** Integration defects cannot be excluded. Test sources, reports and successful tests on a different SHA are not passes for current main.

**Closure evidence:** Execute required Flutter tests/analyzer and Laravel/PostgreSQL 17 integration suite on the exact reviewed candidate SHA; store complete logs/JUnit and database/test version information; keep skipped, failed, warnings and missing artifacts explicit. Do not invoke the current workbook workflow while it calls the prohibited legacy Supabase writer; resolve that separate CI/policy blocker first.

**Handoff:** Prompt 15 (CI/exact-head release evidence) and the owners of the current workflows. This report does not dispatch/rerun workflows or modify them.

### E2E-09 — P2 — Preview values and committed product values can diverge

**Confidence:** High for representation; execution not performed.  
**Affected edges:** loaded cart/product state → confirmation UI → authoritative SQLite product read → sale commit.

**Evidence:** Checkout preview reads the in-memory product list, while repository commit reloads price and PPN exemption from SQLite. The request contains no expected price/catalogue version or immutable quote.

**Failure/reproduction:** Change the persisted price or tax status after preview but before confirmation; compare screen total to committed header, DPP and PPN. Pass only when the mismatch is visibly reconfirmed or rejected deterministically.

**Impact:** Operator may unknowingly commit a total different from the displayed total.

**Closure evidence:** Owner-approved quote/version behavior and an executable stale-preview test with amounts recorded both before and after the update.

**Handoff:** Prompt 08 checkout request contract and the product catalogue/version owner.

## 7. Required commands and acceptance sequence

These commands were **not run in Prompt 17** because the required tools/dependencies are absent here. Run them in a disposable checkout/database environment once an approved candidate is assembled. Record the exact commit SHA and exit codes.

### A. Local Flutter layer

- From the app project: `flutter analyze --no-pub`
- Then: `flutter test --no-pub --reporter expanded`

Required test additions/fixtures are E2E-LOCAL-001, E2E-FEFO-FIFO-002, E2E-IDEMP-01, E2E-IDEMP-02, E2E-CRASH-01, E2E-ROLLBACK-01, E2E-PREVIEW-01 and E2E-REPORT-01. Current test files include useful source assertions, but their presence is not an execution result. Preserve all output and bind it to the exact tested SHA.

### B. Laravel / disposable PostgreSQL 17 layer

On a reviewed candidate and a new disposable PostgreSQL 17 instance only:

- Validate/install the committed Composer lock and run the repository test entry point: `composer validate --strict --no-check-publish`, `composer install --no-interaction --prefer-dist --no-progress`, then `composer test`.
- Prove central and two tenant DB migrations from clean state.
- Run real connection/role/privilege tests for tenant A, tenant B and central; assert tenant runtime principals cannot CONNECT/read/write another tenant or central DB. Inspect role attributes, owners, CONNECT, schema/table/sequence and PUBLIC grants.
- Run authenticated HTTP integration tests for membership, device, domain/Host/proxy rejection, service entitlement, effective configuration, sale sync, durable receipt replay/conflict and worker context reset.
- Fault-inject transaction rollback and concurrent same-key/last-stock behavior. Preserve PHPUnit/JUnit output, PostgreSQL version, logs and test fixture IDs; redact all credentials.

No such command or PostgreSQL test was executed in this audit. Current main lacks the handlers and resolver required for many of these checks, so a runtime PASS must not be expected merely by running a health endpoint.

### C. Cross-node invariant oracle

For every accepted synthetic transaction, compare the immutable transaction ID and a canonical request fingerprint across local intent, sale header/items, inventory allocation, FIFO consumption, journal, outbox and server receipt. Assert:

- Header subtotal/discount/DPP/PPN/total equals the line-derived calculation under an explicitly approved tax policy.
- Physical FEFO quantity equals the requested sold quantity; FIFO cost consumption and COGS agree with the sale line and stock movements.
- Debit equals credit; every line belongs to exactly one valid journal; any failed write leaves zero partial effects.
- One logical event has one durable server receipt and one set of server effects. Same payload replay returns the same receipt; different payload under the same ID is a conflict.
- Pending/offline state survives timeout/restart and is not labeled acknowledged. ACK is set only after a committed server receipt.
- Report metrics reconcile to the underlying accepted transaction set and clearly distinguish local, pending, accepted, reversed and archived rows.
- Tenant identity/device authority comes from the server and restricted DB grants, not request-supplied IDs or a shared central DB credential.
- Effective configuration is resolved for exactly one service and its effective payload/version/hash match the same canonical workbook fixtures used by the importer.

## 8. Current integration register

| Contract | Current disposition | Required before claim |
|---|---|---|
| Explicit local cashier flow | PARTIAL — source path exists | Exact-head tests including restart and fault injection |
| Local sale + inventory + journal + outbox single transaction | STRUCTURE SOURCE-VERIFIED; runtime NOT RUN | Late-failure rollback and successful invariant tests |
| Same-request idempotency inside local repository | STRUCTURE SOURCE-VERIFIED; runtime NOT RUN | Exact replay/conflict tests and durable retry intent |
| Approved cloud identity / tenant / device boundary | BLOCKED | Laravel auth/membership/enrollment plus real negative tests |
| Five-layer workbook config consumed by Flutter | BLOCKED on reviewed main | Validated importer, effective resolver/API, client integration and per-service parity tests |
| Durable outbox delivery and server ACK | NOT IMPLEMENTED on reviewed main | Sender, API, event contract, receipt/idempotency, retry/conflict tests |
| PostgreSQL per-tenant isolation | NOT VERIFIED; source fallback risk | Independent principals/grants and adversarial A/B tests on disposable PG17 |
| Accounting-grade reporting and reconciliation | BLOCKED | Defined metrics, reversals/period rules and cross-ledger assertions |
| Exact-SHA E2E test acceptance | NOT VERIFIED | Current-candidate app/backend jobs with preserved artifacts |
| Staging/production behavior | NOT VERIFIED; not accessed | Separate owner-authorized environment evidence; not in Prompt 17 scope |

## 9. Owner hand-offs and scope boundary

This report identifies integration acceptance requirements without assigning unrelated implementation work to Prompt 17:

- **Identity/device trust:** Prompt 02.
- **Canonical workbook, importer, resolver, effective configuration and cache:** Prompt 01.
- **Checkout intent, pricing preview and local transaction rollback:** Prompt 08.
- **Physical FEFO, FIFO cost, lot/reservation/stock movements:** Prompt 09.
- **Journal posting, reversals, COA, period close and audit evidence:** accounting-integrity owner / Prompt 10.
- **Outbox payload, delivery, retry, durable receipt and cloud conflict:** Prompt 11.
- **PostgreSQL constraints and real tenant isolation:** Prompts 04 and 05.
- **Reporting definitions and cross-ledger reconciliation:** Prompt 13.
- **Exact-head CI and candidate evidence:** Prompt 15.
- **Private deployment, DB credentials, readiness and operational environment evidence:** Prompt 16.

Related open PRs and audit reports are branch-scoped. In particular, PR #69 is an open/unmerged configuration candidate and PR #93 is an open draft accounting-posting candidate. Their existence, or their recorded branch-specific test runs, is not proof that those components are present on reviewed main or that an authenticated client can reach them end to end. Prompt 17 does not merge, rebase, approve or change those candidates.

No changes were made outside this report. No app/test source was edited; no workflow was dispatched; no live DB, staging, production, Supabase, deployment, secret value, or production customer data was accessed.

## 10. Final recommendation

**Maintain NO-GO for cloud SaaS and end-to-end integration acceptance.** Permit only the currently disclosed local-only testing/use case under its appropriate owner controls. Do not label an outbox event as synchronized merely because it exists locally, do not infer tenant isolation from database schema or package presence, and do not report a green E2E gate from source files or unrelated CI jobs.

The next meaningful acceptance event is a reviewed candidate where the approved Laravel identity/config/sync contracts are wired to the Flutter app, the complete event and receipt semantics exist, and the focused cross-node tests above execute on the exact candidate SHA in disposable local/CI infrastructure. This audit does not authorize implementation or deployment.

## Evidence references

- [Current main source revision](https://github.com/berkah-pos/Berkahtigaputeri/commit/371b7fdf0bf672b37ceb1023e647f114221bf797)
- [Current API route](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/routes/api.php)
- [Flutter app entry](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/main.dart)
- [Flutter effective configuration client](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/core/config/config_service.dart)
- [Local POS database/SQLite schema](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/core/database/pos_database.dart)
- [Local sale repository](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/features/pos/checkout/sqlite_sale_repository.dart)
- [Checkout screen and operation-ID creation](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/features/pos/checkout_screen.dart)
- [Local journal service](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/features/accounting/services/journal_service.dart)
- [Local reports](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/features/home/reports_screen.dart)
- [Local checkout test source](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/test/pos/checkout/payment_service_test.dart)
- [FEFO/FIFO test source](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/test/inventory/fefo_checkout_test.dart)
- [Prompt 00 system node graph — open audit PR](https://github.com/berkah-pos/Berkahtigaputeri/pull/94)
- [Prompt 01 config resolver — open audit PR](https://github.com/berkah-pos/Berkahtigaputeri/pull/95)
- [Prompt 02 identity/device trust — open audit PR](https://github.com/berkah-pos/Berkahtigaputeri/pull/96)
- [Prompt 04 PostgreSQL schema integrity — open audit PR](https://github.com/berkah-pos/Berkahtigaputeri/pull/97)
- [Prompt 05 PostgreSQL tenant isolation — open audit PR](https://github.com/berkah-pos/Berkahtigaputeri/pull/98)
- [Prompt 08 POS checkout transaction — open audit PR](https://github.com/berkah-pos/Berkahtigaputeri/pull/99)
- [Prompt 09 inventory FEFO/FIFO — open audit PR](https://github.com/berkah-pos/Berkahtigaputeri/pull/100)
- [Prompt 11 offline sync/idempotency — open audit PR](https://github.com/berkah-pos/Berkahtigaputeri/pull/101)
- [Prompt 13 reporting/reconciliation — open audit PR](https://github.com/berkah-pos/Berkahtigaputeri/pull/102)
- [Prompt 15 CI/release evidence — open audit PR](https://github.com/berkah-pos/Berkahtigaputeri/pull/103)
- [Prompt 16 infrastructure/backup/observability — open audit PR](https://github.com/berkah-pos/Berkahtigaputeri/pull/104)
