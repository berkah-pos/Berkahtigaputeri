# Prompt 11 — Durable Outbox, Laravel Sync, Idempotency & Conflict Lifecycle

**Audit status: BLOCKED — local persistence exists; end-to-end cloud sync is NOT IMPLEMENTED / NOT VERIFIED.**

## 1. Scope and revision

- **Assigned workstream:** Offline Synchronization Specialist — outbox creation, versioned payload, authenticated upload, server idempotency, acknowledgement, retry/backoff, conflict lifecycle and client/server consistency.
- **Repository:** [berkah-pos/Berkahtigaputeri](https://github.com/berkah-pos/Berkahtigaputeri)
- **Audited base:** main at SHA **371b7fdf0bf672b37ceb1023e647f114221bf797** (2026-10-20).
- **Audit branch:** audit/prompt-11-offline-sync-2026-10-20, created from that exact SHA.
- **Changes:** this report only. No application, schema, migration, dependency, workflow, environment, database, data or infrastructure changes were made.
- **Execution boundary:** repository source, current route/schema and Actions metadata were inspected through GitHub. No Flutter/PHP commands, HTTP requests, database sessions, staging tests, production tests or live data access were run.
- **Platform constraint:** the latest owner ADR selects Laravel Central API + private PostgreSQL 17 and prohibits all Supabase product use, including read-only access. No Supabase project or legacy RPC was accessed. See the [current owner ADR](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md).

## 2. Executive finding

The audited source has a **local SQLite atomic checkout/outbox write path**. Checkout runs inside the database transaction, writes sales and their items, inventory/lot/cost effects and accounting journal data, and inserts one pending outbox row before returning. The local sales table has a unique transaction ID and request fingerprint. Local test source covers same-request replay, a changed request under the same ID, and rollback after a stock validation failure.

However, **no end-to-end sync path is implemented or verified on this main SHA**:

- The tracked Flutter tree contains no outbox repository/dispatcher, sync worker or Laravel API client.
- The only current route in routes/api.php is GET /api/v1/platform-health; there is no POST /api/v1/sync route or sync handler.
- A starter tenant migration creates sync_receipts and some source_event_id columns, but no handler was found that authenticates a caller, resolves the tenant/device from trusted context, applies the sale atomically, hashes the canonical payload or returns a durable receipt.
- The current client event contains only a six-field sale summary, not enough immutable detail to recreate or reconcile the sale lines, inventory/lot/cost movements and journal.
- The outbox schema has status and retry_count; the checkout code only inserts pending / zero. No current code changes statuses, increments attempts, schedules backoff, persists acknowledgement receipts or handles conflicts.
- The Flutter manifest, main.dart and configuration service still use the legacy Supabase client/RPC path. This is incompatible with the latest owner ADR and must not be used as a sync fallback.
- The exact-head Actions query returned only Dependabot dynamic runs 39184121515 and 39186055413, not Flutter/Laravel application test runs. The combined-status endpoint returned no statuses. Test source and old CI records are not proof of execution on this SHA.

**Release consequence:** keep cloud-sync acceptance and any cloud-connected SaaS release **RED / BLOCKED**. A pending outbox is local durable storage, not a cloud sync receipt.

## 3. End-to-end sequence

### 3.1 Existing source path

~~~mermaid
sequenceDiagram
    participant UI as Flutter cashier
    participant Repo as SqliteSaleRepository
    participant DB as Local SQLite
    UI->>Repo: PaymentRequest with transaction ID and lines
    Repo->>DB: Begin exclusive SQLite transaction
    Repo->>DB: Read existing sale by transaction ID
    alt Same ID and same fingerprint
        Repo->>DB: Read existing journal
        Repo-->>UI: Return existing result without second posting
    else New sale
        Repo->>DB: Write sale lines, inventory/cost effects and journal
        Repo->>DB: Insert pending outbox summary
        DB-->>Repo: Local transaction commits
        Repo-->>UI: Sale saved locally
    end
    Note over DB: No tracked dispatcher, upload, durable ACK or conflict resolver
~~~

Source: [SQLite sale repository](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/features/pos/checkout/sqlite_sale_repository.dart#L20-L343) and [SQLite schema](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/core/database/pos_database.dart#L397-L499).

### 3.2 Required target path — NOT IMPLEMENTED / NOT VERIFIED

~~~mermaid
sequenceDiagram
    participant Client as Flutter outbox sender
    participant API as Authenticated Laravel API
    participant Auth as Auth/membership/device resolver
    participant TenantDB as Resolved tenant PostgreSQL DB
    Client->>API: Versioned event, stable ID and canonical payload hash
    API->>Auth: Authenticate and resolve active membership/device
    Auth-->>API: Trusted tenant/device context or deny
    API->>TenantDB: Begin transaction and check durable receipt
    alt Receipt exists and payload hash matches
        TenantDB-->>API: Return original receipt without duplicate writes
    else Receipt exists and hash differs
        TenantDB-->>API: Return conflict; preserve accepted event
    else New event
        API->>TenantDB: Validate payload and dependencies
        API->>TenantDB: Write sale, lines, stock, journal and receipt atomically
        TenantDB-->>API: Commit succeeds
        API-->>Client: Post-commit durable receipt
    end
    Client->>Client: ACK only after validating matching receipt
    Note over Client,TenantDB: Retried request after lost response must reuse the same ID and body
~~~

This is the target contract, not a diagram of working code. Payload-supplied tenant/device identifiers must not establish authorization. The server must resolve identity, membership, device ownership and tenant DB from trusted authentication context.

## 4. Component evidence

| Component | Source facts at audited SHA | Evidence boundary |
|---|---|---|
| Local transaction | PosDatabase.transaction uses a SQLite transaction; SqliteSaleRepository writes sale, inventory/accounting effects and outbox within it | SOURCE-VERIFIED structure; no injected-failure test was executed during this audit |
| Local duplicate protection | sales.transaction_id is unique; request_fingerprint is checked on repeat | Local idempotency only; not server idempotency or timeout-after-commit replay |
| Outbox creation | ID is outbox:sale:<transactionId>; entity_type=sale; payload is six summary values; status=pending; retry_count=0 | The initial write exists; no sender or lifecycle was found |
| Flutter UI | Home/report screens count non-acknowledged records; home explicitly says “Cloud sync belum aktif” | UI accurately signals local-only status; it does not implement sync |
| Laravel API | routes/api.php exposes the platform-health route only | No authenticated sync endpoint, request validator or sync controller/service found |
| Tenant schema | Migration creates sales, sale_items, inventory_movements, journal_entries/lines and sync_receipts | Schema scaffolding only; no handler found using it |
| Authentication/config | pubspec.yaml, main.dart and config_service.dart retain supabase_flutter, Supabase.initialize and the legacy config RPC | Current client is non-compliant with no-Supabase ADR; no Supabase connection was attempted |
| CI acceptance | required-check-matrix.json says it is a specification only / not wired into CI; AC-09 is not_run | Acceptance definition is not execution evidence |

Pinned sources:
- [Atomic checkout and outbox insert](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/features/pos/checkout/sqlite_sale_repository.dart#L20-L343)
- [Local sale/accounting/outbox schema](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/core/database/pos_database.dart#L397-L499)
- [Current API routes](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/routes/api.php)
- [Tenant receipt migration](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/database/migrations/tenant/2026_10_17_000001_create_tenant_pos_tables.php)
- [Local replay/conflict/rollback test source](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/test/pos/checkout/payment_service_test.dart#L243-L405)
- [UI cloud-sync status](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/features/home/home_screen.dart#L385-L410)
- [Flutter manifest](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/pubspec.yaml)
- [Required AC-08/AC-09 matrix](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/config/ci/required-check-matrix.json#L285-L340)

## 5. Event contract and server schema

### 5.1 Current local event

| Field | Current value | Assessment |
|---|---|---|
| id | outbox:sale:<transactionId> | Stable only while the transaction ID remains stable; uniqueness scope and ID-generation contract are not proven |
| entity_type / entity_id | sale / sale:<transactionId> | Present |
| payload | saleId, transactionId, businessDate, grandTotal, ppnAmount, paymentMethod | Incomplete for deterministic server replay/reconciliation |
| status | pending at insert | Only initial state is source-verified |
| retry_count | 0 at insert | No increment, schedule, limit or resume logic found |
| created_at_utc | Client timestamp | Present; no server ordering or clock-skew policy verified |

The payload currently omits payload/schema version, canonical body digest, full immutable sale-line snapshots, product/quantity/price/discount/tax details, lot allocations, cost consumptions, inventory movements and journal lines. Do not reconstruct historical sale facts later from mutable product/stock data. A retry must represent the same immutable business event.

### 5.2 Server dedupe schema — placeholder only

The tenant migration defines:
- sales.source_event_id as nullable and unique;
- journal_entries.source_event_id as nullable and unique;
- inventory_movements.source_event_id as nullable and indexed, not unique;
- sync_receipts.event_id as primary key, plus device_id, payload_sha256, JSON response and accepted_at.

These could support deduplication once an API transaction exists. No handler was found that hashes/canonicalizes the request, compares receipt hashes, returns an old receipt, rejects same-key/different-body replay, or writes all domain effects with the receipt in one transaction. A unique receipt key alone does not prove the rest of the transaction is atomic; the inventory movement index alone does not enforce unique event effects.

A data-shape mismatch also requires a documented mapping: local Flutter uses integer Rupiah amounts and detailed lot/cost/journal tables, while the starter PostgreSQL migration uses decimal money/quantity fields and a reduced sale shape. Exact units, precision, rounding and canonical payload hashing must be agreed and tested. Do not use binary floating point for authoritative money.

### 5.3 Minimum proposed versioned envelope (not implemented)

A reviewed v1 contract should carry:
- immutable event_id generated once and persisted in the outbox;
- event_type, schema_version and content type;
- transaction_id, source app version, local schema version and occurred-at UTC timestamp;
- canonical payload hash/fingerprint with documented serialization rules;
- complete immutable sale header and line snapshots, including unit price, quantity, discount, tax treatment, totals, payment method and business date/timezone;
- inventory/lot allocations and cost-consumption facts plus journal header/lines, or a reviewed server-derived-effects rule with equivalent invariants;
- optional device/tenant selectors strictly matched to trusted authenticated context, never accepted as authorization;
- dependency IDs/sequence if related events are split rather than uploaded as one complete sale.

This is a design proposal, not current implementation.

## 6. Acknowledgement and failure-state contract

### Required lifecycle

~~~mermaid
stateDiagram-v2
    [*] --> Pending
    Pending --> InFlight: Claim for bounded upload
    InFlight --> Acknowledged: Valid post-commit durable receipt
    InFlight --> RetryScheduled: Timeout / transient network error / eligible 5xx
    RetryScheduled --> Pending: Backoff elapsed
    InFlight --> NeedsAttention: Permanent reject / hash conflict / retry budget exhausted
    NeedsAttention --> Pending: Explicit reviewed repair/retry only
    Acknowledged --> Acknowledged: Duplicate replay returns original receipt
~~~

Only the initial pending state is implemented in the writer; other states are required target behavior.

1. Never ACK when upload starts, after a socket write, on timeout, or on a response without a receipt matching the event ID and canonical payload hash.
2. Server commits sale, lines, inventory/accounting effects and receipt atomically to the correct tenant DB. Success is returned only after commit.
3. If server commits but the response is lost, resend the identical ID/key/body. The API returns the original receipt without repeating effects.
4. Same key + same hash returns the same durable result. Same key + different hash is a conflict, never an overwrite.
5. Network failures, timeouts, throttling and eligible server errors use bounded exponential backoff with jitter. Authentication/authorization failures and deterministic schema/business-rule rejects must not retry forever without state change.
6. After a retry budget or poison-message threshold is reached, surface needs-attention with safe diagnostics and an explicit operator/user resolution path. Never delete pending/rejected local sale data to clear a queue.
7. Keep accepted accounting/inventory history immutable. A sync conflict must not rewrite posted records; resolution needs an explicit audited compensating/business workflow.
8. Define bounded batch size, request timeout, ordering/dependency rules, maximum offline age, clock skew policy and unsupported-version handling. Offline multi-device inventory policy must be explicit; do not imply global stock consistency while devices are disconnected.

## 7. Findings and severity

### F-11-01 — P1: No authenticated Laravel sync endpoint or client dispatcher

**Evidence:** routes/api.php contains only GET /api/v1/platform-health; tracked source search/tree shows no sync worker/API client and no POST /api/v1/sync handler.

**Impact:** outbox data remains local. No cloud accepted-sales reporting or multi-device reconciliation can be claimed.

**Required acceptance:** implement in a separate reviewed workstream and demonstrate an authenticated upload against disposable PostgreSQL 17 with synthetic data, on a pinned candidate SHA.

### F-11-02 — P1: Outbox payload is insufficient to reproduce the sale event

**Evidence:** event contains only six summary fields while local checkout stores line snapshots, stock/lot effects, cost consumption, and journal data.

**Impact:** server cannot faithfully reconstruct or reconcile the original local transaction from this payload; deriving from later mutable data can change results.

**Required acceptance:** approve a versioned immutable envelope, then prove round-trip totals, every line snapshot, timezone/business date, inventory effects, balanced journal and canonical payload hash match.

### F-11-03 — P1: No durable server idempotency/receipt transaction

**Evidence:** sync_receipts and some source_event_id uniqueness constraints exist, but no handler uses them; inventory_movements.source_event_id is only indexed; AC-09 is not_run.

**Impact:** concurrent duplicates and timeout-after-commit replay are unverified. A receipt table by itself does not guarantee all business effects happen exactly once.

**Required acceptance:** same key/same body yields one durable receipt and one set of effects; same key/different hash returns conflict without modifying the original; concurrent replay and response-loss-after-commit are safe on PostgreSQL 17.

### F-11-04 — P1: No ACK, retry, or conflict lifecycle

**Evidence:** current writer creates pending / retry_count 0, and UI counts unacknowledged rows; no state mutation, retry scheduler/backoff, saved receipt or conflict-resolution path was found.

**Impact:** interrupted requests cannot be recovered safely and the product cannot distinguish durable acceptance from an unsent or rejected sale.

**Required acceptance:** implement persisted lifecycle transitions and visible error classification; ACK only after receipt verification. Test transient failure, permanent failure, retry exhaustion, app restart and explicit recovery.

### F-11-05 — P1: Current auth/config client still violates no-Supabase target

**Evidence:** manifest declares supabase_flutter; main.dart calls Supabase.initialize; config_service.dart authenticates against Supabase and calls the legacy config RPC. Owner ADR prohibits Supabase product use.

**Impact:** the app does not yet have the approved Laravel-authenticated identity/device context required for safe sync. A fallback would contradict the accepted platform boundary.

**Required acceptance:** a separate auth/API migration supplies tested Laravel identity, membership, active-device and tenant-resolution behavior; sync must not enable or retain Supabase calls.

### F-11-06 — P2: Lifecycle bounds and protocol policy are absent

**Evidence:** local outbox schema has no event schema version, next-attempt timestamp, last error class, maximum attempt bound, ACK receipt metadata, claim/lease marker or enforced status vocabulary. No explicit ordering, clock skew or offline age policy was found.

**Impact:** once a sender is added, safe restart/concurrency recovery and malformed-event handling remain ambiguous.

**Required acceptance:** document and test allowed states, retry classes, max attempts, exponential backoff/jitter, event-version negotiation, batching, ordering, maximum offline age, clock skew and poison messages. Prevent multiple workers claiming one event unsafely.

### F-11-07 — P2: Local and PostgreSQL payload/storage parity is unverified

**Evidence:** Flutter stores Rupiah as integers and keeps detail for physical lots, FIFO cost, movements and journal lines; the starter tenant migration uses decimal columns and different reduced structures.

**Impact:** implicit rounding/conversion or incomplete writes could create inconsistent sale totals, inventory and journals.

**Required acceptance:** approve a canonical mapping and precision policy, then assert exact reconciliation between payload, receipt and every persisted server row.

## 8. Mandatory acceptance tests

All are **NOT RUN on SHA 371b7fdf0bf672b37ceb1023e647f114221bf797**. Test-source presence is not execution evidence.

| ID | Scenario | Required assertions |
|---|---|---|
| SYNC-01 | Local success | Sale, lines, stock/lot effects, cost consumption, balanced journal and pending outbox commit together |
| SYNC-02 | Local failure injection | Inject a failure at each write stage; all related rows roll back; no orphan outbox |
| SYNC-03 | Local duplicate and conflict | Same transaction ID/body causes no second posting; changed body is rejected without second mutation |
| SYNC-04 | Restart recovery | Close/reopen on-disk SQLite with pending/in-flight event; keep the same event ID/body and safely resume |
| SYNC-05 | Payload/version | v1 event round-trips immutable fields, hash, totals, business date/timezone; unsupported version fails safely |
| SYNC-06 | Auth/tenant/device negatives | Missing/revoked credentials, inactive membership/device and forged tenant/device claims reject without writes |
| SYNC-07 | Server atomic acceptance | One authenticated event creates all required tenant records and durable receipt in one transaction |
| SYNC-08 | Identical replay | Same key/hash returns the same receipt; one sale, stock mutation, journal and receipt exist |
| SYNC-09 | Key reused with changed body | Deterministic conflict; accepted original ledger remains unchanged |
| SYNC-10 | Timeout after commit | Drop response after commit; retry gets prior receipt, then client ACKs; no duplicate effects |
| SYNC-11 | Concurrent replay | Concurrent identical requests yield one commit and one durable result |
| SYNC-12 | Retry and poison event | Bounded exponential backoff/jitter for transient errors; permanent rejects classified; maximum retries stop hot loops |
| SYNC-13 | ACK guard | No ACK on request-start, timeout, invalid/mismatched receipt or non-durable response |
| SYNC-14 | Ordering/offline/clock | Verify documented dependencies, out-of-order delivery, maximum offline age, clock skew and schema incompatibility |
| SYNC-15 | Tenant isolation | Real disposable tenant DB credentials prove A cannot connect/read/write B or central records |
| SYNC-16 | Current-head CI | Run Flutter analysis/tests and Laravel/PostgreSQL integration suite on the exact candidate SHA; retain raw logs, JUnit, payload hashes, receipts and row assertions |

Suggested commands (not executed here):
- From pos-app/: flutter pub get; flutter analyze --no-pub; flutter test --no-pub --reporter expanded.
- Run locked Laravel dependency checks and feature/integration tests against fresh disposable PostgreSQL 17 central/tenant databases with synthetic data and restricted DB identities.
- Store actual command, SHA, environment, exit code and artifacts. Do not substitute pseudocode or the acceptance matrix for executable tests.

The required-check-matrix.json explicitly describes itself as specification only / not yet wired into CI. AC-08 is partial and AC-09 is not_run. Current exact-head Actions results are Dependabot-only, not application test results.

## 9. Evidence ledger

| Evidence class | Result |
|---|---|
| SOURCE-VERIFIED | SQLite transaction wrapper; sale/outbox schema and insert; local transaction-ID/fingerprint checks; local test source for replay/conflict/rollback; API route/migration/manifest inspection at exact main SHA |
| TEST-EXECUTED | None during this audit. Flutter, PHP, PostgreSQL and HTTP tests were not run |
| CI-OBSERVED | Only Dependabot runs 39184121515 and 39186055413 appeared for the exact head; successful Dependabot jobs do not verify the app. Combined commit status had no checks |
| STAGING-OBSERVED | None; no staging request/database check performed |
| PRODUCTION-OBSERVED | None; no production access or action |
| NOT VERIFIED | Sync endpoint; authenticated upload; tenant/device authorization; atomic receipt writes; replay/conflict semantics; ACK, retry/backoff and crash recovery; ordering/offline policy; tenant isolation; current-head test pass; production sync |

## 10. Ownership boundary and next gate

1. **Laravel/API + identity owner:** define and implement the authenticated request context, tenant resolver, sync route and atomic receipt transaction in a separately reviewed implementation workstream.
2. **Flutter/Sync owner:** after the API contract is approved, implement the versioned immutable payload, sender, persisted outbox lifecycle and UI states. Preserve the current local sale/accounting algorithms. No Supabase fallback.
3. **PostgreSQL DBA/security reviewer:** validate actual per-tenant roles/grants and test tenant-A/B sync access with real disposable DB identities.
4. **QA/evidence owner:** wire AC-08/AC-09 into required CI and preserve exact-SHA logs, JUnit, receipt/row assertions and replay/concurrency transaction output.

**Next gate:** no sync release claim until a reviewed event v1 contract and authenticated Laravel endpoint exist, and disposable PostgreSQL 17 tests prove atomic acceptance, durable-receipt replay, mismatched-payload conflict and ACK-after-commit.

## 11. Acceptance decision

**BLOCKED / NOT VERIFIED.** Local atomic outbox creation is source-verified, but Prompt 11 acceptance fails because the Laravel upload/receipt path and client lifecycle are absent, the active Flutter auth/config client remains Supabase-based contrary to owner policy, and current-head application tests were not run. This report is not evidence of completed cloud sync or production approval.
