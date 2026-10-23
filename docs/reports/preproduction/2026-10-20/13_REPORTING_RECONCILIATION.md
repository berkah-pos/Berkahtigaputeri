# Prompt 13 — Reporting and Reconciliation Audit

**Audit date:** 2026-10-21 (Asia/Jakarta)  
**Report path:** `docs/reports/preproduction/2026-10-20/13_REPORTING_RECONCILIATION.md` (retains the requested workstream folder date)  
**Repository:** `berkah-pos/Berkahtigaputeri`  
**Source revision inspected:** `main` at `371b7fdf0bf672b37ceb1023e647f114221bf797`  
**Audit branch:** `audit/preprod-reporting-reconciliation-2026-10-21`  
**Assigned scope:** Home/dashboard totals, local reporting, archive separation, source provenance, and reconciliation acceptance.  
**Execution mode:** Read-only source/document/CI-metadata audit. No application code, migrations, schemas, CI workflows, runtime data, production data, or hosted database resources were changed or queried.

## 1. Executive result

**Acceptance: BLOCKED / PARTIAL — reporting reconciliation is not verified.**

The current Flutter app is accurately described as local-first: the dashboard and report screen label amounts as local, explicitly disclose that cloud sync is not active, and say these amounts are not consolidated multi-device reporting. Legacy trial sales are queried from separate archive tables and rendered under an explicit archive heading rather than included in the current sales aggregate. These are important positive controls.

The current report implementation does not, however, provide evidence-grade financial reconciliation. Its active summary is a lifetime unfiltered aggregate over every row in the local `sales` table. It counts `grand_total` (which includes PPN) under a “Penjualan lokal” label, sums COGS independently, and does not reconcile totals to sale items, journal lines, physical stock movements, financial stock movements, or server acceptance receipts. The `sales` schema has no lifecycle/status field for void or reversal exclusion, and report queries contain no report-period filter. There is no accepted cloud-reporting API: the inspected Laravel API routes expose only a platform-health endpoint, and the Flutter UI says a sync worker is not active.

Source inspection therefore supports a **local-only basic summary**, not an accounting-grade, period-filtered, reversal-aware, tenant-scoped, or cloud-consolidated report. No production report values were recalculated.

### Evidence labels used

- **SOURCE-VERIFIED** — directly inspected in tracked source on the revision named above.
- **DOC-ASSERTED** — documented in a report/runbook but not independently run in this audit.
- **TEST-SOURCE-VERIFIED** — a test's assertions exist in source; this is not evidence that the test passed.
- **CI-OBSERVED** — directly returned current-revision check metadata.
- **TEST-EXECUTED** — a command/test executed during this audit. No Flutter/Dart test or analyzer command was executed here.
- **NOT RUN / NOT VERIFIED** — no current execution evidence was obtained.
- **INFERRED / RISK** — a plausible failure mode derived from inspected implementation; not a claim that affected production transactions exist.

## 2. Scope, provenance, and limits

The following current source files were inspected on the stated main revision:

| Source | Evidence scope | What it establishes |
|---|---|---|
| `pos-app/lib/features/home/home_screen.dart` | Dashboard sales/product/outbox aggregate and user-facing state | Local query semantics and local-only wording; no server report aggregation is shown here. |
| `pos-app/lib/features/home/reports_screen.dart` | Active-sales aggregate, recent-sale list, archived-trial aggregate/list, pending-outbox count | Exactly which local tables/columns feed the current report and how the values are labelled. |
| `pos-app/lib/core/database/pos_database.dart` | SQLite schema | Available sales, sale-item, journal, inventory, outbox, and archive fields, including missing lifecycle and tenant/device keys. |
| `pos-app/lib/features/pos/checkout/sqlite_sale_repository.dart` | Sales posting, item rows, local journal, stock movements, outbox insertion | Local transaction provenance and the outbox payload currently created for a sale. |
| `pos-app/lib/features/pos/cart/sale_calculator.dart` | Calculation rules | Existing definitions for gross, discounts, taxable/exempt DPP, PPN, and invoice total. |
| `pos-app/lib/core/time/business_date.dart` | WIB business-date helper | The source's Asia/Jakarta fixed UTC+7 date calculation. |
| `pos-app/lib/features/accounting/services/journal_service.dart` and `.../repositories/sqlite_journal_repository.dart` | Journal append/validation and persistence | Journal balance rules in application logic and the available journal records; no report-side journal reconciliation. |
| `pos-app/lib/features/products/repositories/sqlite_product_repository.dart` | Physical lot/stock updates and legacy stock helper | Stock-ledger writes and one special legacy-stock check; not a general report reconciliation. |
| `pos-app/test/pos/cart/sale_calculator_test.dart` and `pos-app/test/pos/checkout/payment_service_test.dart` | Calculation/posting/idempotency/rollback test source | Test cases are present; their current-revision execution is unverified. |
| `pos-app/test/database/legacy_trial_importer_test.dart` | Trial archive migration test source | Archive isolation, source preservation, and import-idempotency assertions are present. |
| `pos-app/test/home/combined_home_shell_test.dart` | Navigation smoke test source | The report tab is reachable in the test scenario; summary arithmetic is not tested. |
| `routes/api.php` | Laravel API route source | Only the platform-health endpoint is declared in this file; no sales, report, or accepted-sync endpoint appears there. |
| `docs/HARDENING/POS_ACCOUNTING_STRESS_REPORT.md` | Prior written engineering evidence | Records additional unrun checks; it is documentation, not fresh execution evidence. |

**Limitations:** This audit did not open or install an APK, inspect a physical device, access production data, query any hosted database, execute Flutter/Dart tests, run SQL against application data, or prove a running staging/production deployment. No attempt was made to access Supabase; current owner policy prohibits all Supabase use, including read-only access. Values shown in this report are source definitions, not recalculated live business values.

## 3. Current report flows and metric definitions

### 3.1 Dashboard

**SOURCE-VERIFIED:** `pos-app/lib/features/home/home_screen.dart`, around lines 228–235, uses:

~~~sql
SELECT COUNT(*) AS sale_count,
       COALESCE(SUM(grand_total), 0) AS revenue
FROM sales;
~~~

and separately counts all outbox rows for which `status <> 'acknowledged'`.

The dashboard labels the values as “Transaksi lokal”, “Penjualan lokal”, and “Antrean tertunda”. Nearby copy states that sales and stock changes are stored on this device, cloud sync waits for a service that is not installed, and the device's data is not a consolidated report.

**Interpretation:** the two sales metrics are lifetime local-row count and lifetime invoice-total sum, not period sales, accepted-cloud sales, accounting revenue net of PPN, or a multi-device consolidated total. The product count is a count of local product rows and does not in itself prove that stock ledgers reconcile.

### 3.2 Active local report

**SOURCE-VERIFIED:** `pos-app/lib/features/home/reports_screen.dart`, lines 40–44, aggregates:

~~~sql
SELECT
  COUNT(*) AS sale_count,
  COALESCE(SUM(grand_total), 0) AS revenue,
  COALESCE(SUM(cogs_amount), 0) AS cogs
FROM sales;
~~~

There is no date, lifecycle, tenant, device, cashier, or server-acceptance predicate. The recent-sales list reads from `sales`, orders by `created_at_utc DESC`, limits to 25 rows, and displays `business_date`, `payment_method`, and `grand_total`. Sorting by creation timestamp does not convert the total summary into a business-date report.

The current cards show transaction count, sales amount, HPP/COGS, and unacknowledged outbox count. There are no distinct cards or report breakdowns for gross subtotal, item/transaction discount, taxable DPP, exempt DPP, PPN, margin, stock movement, journal balance, or server-accepted totals.

### 3.3 Trial archive

**SOURCE-VERIFIED:** the current aggregate reads `legacy_sales_archive` separately for its count and `SUM(total_amount)`. The screen renders these under “Arsip riwayat dari aplikasi trial”, identifies the values as archived trial data, warns that the old schema lacks the details required for a verified accounting report, and explicitly states the values are not included in the active totals. The archive is backed by distinct `legacy_sales_archive` and `legacy_sale_items_archive` tables in `pos_database.dart`.

The legacy importer test source asserts that imported trial rows are stored in the archive while the target `sales` and `journals` tables remain empty, and that the original source file is retained and rerunning the import does not duplicate the archived sales.

**Privacy note:** the screen's archive query selects the `email` column even though the rendered list only displays the original sale ID, date, item count, and amount. The email is not shown in the UI, but it is unnecessarily fetched into report state. Remove it from the report projection in a separately assigned implementation change; this audit did not alter it.

### 3.4 Pending outbox

**SOURCE-VERIFIED:** the report count is:

~~~sql
SELECT COUNT(*) AS value
FROM outbox_events
WHERE status <> 'acknowledged';
~~~

The table defines a non-null free-text `status`, `retry_count`, entity type/ID, payload, and timestamp, but the schema does not constrain the status values to a declared state machine. The local sale repository creates one pending outbox event with a small payload containing sale ID, transaction ID, business date, grand total, PPN amount, and payment method.

The UI explicitly says no cloud worker is active. Therefore this count is **local outbox rows not marked acknowledged**, not “events currently ready to sync”, not proof of a network retry queue, and not proof of server-accepted sales. It may count any future non-acknowledged terminal or attention state as if still waiting.

### 3.5 Calculation provenance

**SOURCE-VERIFIED:** the current sale calculator operates in integer Rupiah and defines:

- Gross amount = sum of quantity × unit price.
- Item discount and transaction discount are stored separately; total discount = item discount + transaction discount.
- Transaction discounts are allocated over eligible sale lines using deterministic proportional allocation.
- Taxable DPP and exempt DPP are distinguished.
- DPP = taxable DPP + exempt DPP.
- PPN is currently calculated at 11% of taxable DPP after discounts, with invoice-level integer-Rupiah half-up rounding.
- Grand total = DPP + PPN.
- COGS is calculated and written through the sale posting path using FIFO cost-layer consumption, while physical batch allocation uses FEFO.

This establishes intended calculation fields in source, not that the report currently displays or independently reconciles every field.

## 4. Reconciliation contract required for acceptance

The following are **proposed acceptance equations/tests**, not calculations executed against production or test rows in this audit. Use a disposable SQLite fixture with deterministic IDs and integer-Rupiah values. Recompute expected values from fixture rows; never edit existing posted rows to make totals match.

### 4.1 Sales header versus sale items

For the selected report scope and selected business-date interval, each posted sale must have the expected line set, and its header must reconcile to those lines:

~~~text
sales.gross_amount
  = SUM(sale_items.gross_amount)

sales.item_discount_amount
  = SUM(sale_items.item_discount_amount)

sales.transaction_discount_amount
  = SUM(sale_items.transaction_discount_amount)
    (line values contain the allocated portions of the invoice-level discount)

sales.discount_amount
  = sales.item_discount_amount + sales.transaction_discount_amount
  = SUM(sale_items.discount_amount)

sales.taxable_dpp
  = SUM(sale_items.dpp WHERE ppn_exempt = 0)

sales.exempt_dpp
  = SUM(sale_items.dpp WHERE ppn_exempt = 1)

sales.dpp
  = sales.taxable_dpp + sales.exempt_dpp
  = SUM(sale_items.dpp)

sales.ppn_amount
  = SaleCalculator's integer-Rupiah rounding rule applied to sales.taxable_dpp

sales.grand_total
  = sales.dpp + sales.ppn_amount

sales.cogs_amount
  = SUM(sale_items.cogs_amount)
  = SUM(the corresponding FIFO cost-layer consumption totals)
~~~

Use the same sale-ID boundary for all header/line checks. Detect orphan sale items, duplicate/missing line numbers, header rows with no items, unexpected item totals, and multiple/missing journals. A query returning a plausible total is not evidence that these invariants hold.

### 4.2 Journal reconciliation

For each posted transaction:

- Exactly one local journal is expected under the current source contract keyed by transaction ID.
- `SUM(journal_lines.debit) = SUM(journal_lines.credit)`; no line may have negative values or both debit and credit positive.
- Verify the sale-posting policy maps the invoice total, sales/discount, PPN liability, COGS, and inventory accounts correctly for the exact fixture. Do not infer the posting mapping from a report total alone.
- A reversal/return/correction must be represented by a separately auditable compensating entry and an explicit relationship to the original transaction. Do not mutate or delete the original posted sale or journal merely to make the current report sum smaller.

The journal service validates an individual supplied journal as balanced in application logic and supports balanced reversal entries. The report itself does not query journals or prove that each sale has a matching valid journal.

### 4.3 Inventory reconciliation

Validate quantity and value as distinct dimensions; physical FEFO allocation and financial FIFO costing are not interchangeable.

- For each product, `products.stock_qty = SUM(inventory_lots.on_hand_qty)` for the selected local ledger state, subject to the current explicit inventory policy.
- For each sale line, the quantity of physical lot allocations must equal the line quantity; no allocation may reference a missing/wrong-product lot or violate lot status/reservation constraints.
- Receipt, sale, adjustment, return and correction movements must reconcile to opening quantity and ending lot balances using the defined movement-type contract. A stock return must not silently increase stock without a corresponding auditable movement and valid cost treatment.
- Financial stock movements and FIFO cost-layer consumption totals must reconcile to line/header COGS. A report should not treat physical quantity movement and accounting valuation as the same measure.
- Legacy imported stock starts under review and must not be counted as saleable stock until physical reconciliation; the special legacy helper compares product quantity with the current lot sum but does not constitute a complete movement-history audit.

No dashboard/report query presently performs these cross-checks. Acceptance requires deterministic fixtures that contain receipts, multiple lots, a FEFO allocation and FIFO cost layers, a sale, and (once formally implemented) return/reversal paths.

### 4.4 Outbox and server acceptance

- Locally, the known sale posting path should create the expected sale, sale-item rows, journal, stock movements and associated outbox event atomically.
- Reconcile outbox identity to the originating transaction/entity and confirm exactly-once logical event identity under a retry; unknown or malformed statuses must be visible as anomalies, not counted without explanation as ready-to-sync.
- Do not label a sale “synced” or include it in a server-accepted total until a durable authenticated server receipt is recorded and linked to the transaction/event.
- Once a Laravel sync contract is implemented, the accepted event/receipt, accepted sale, inventory/accounting effects, and idempotency outcome must reconcile on a transaction-ID/event-ID basis. Duplicate same-payload retries should return the previous receipt; changed-payload reuse should be a conflict.
- Never equate the local `acknowledged` flag alone with server acceptance unless the acknowledgement is only written after the server durably commits and responds.

At the inspected revision, `routes/api.php` defines only `GET /api/v1/platform-health`; no reporting, sales acceptance, or sync receipt endpoint appears in that route file. The Flutter reports source explicitly says cloud sync is not active. Cloud-accepted totals and server reconciliation are consequently **NOT IMPLEMENTED / NOT VERIFIED** in this audit.

### 4.5 Archive reconciliation

- Legacy archive row counts and totals are computed only from archive tables.
- The archive must never be joined into active `sales`, active revenue, COGS, tax, inventory, journal, margin, or synced-sales aggregates.
- Re-run the importer acceptance fixture and assert archived count/amount exactly match the test source, active sales/journals stay unchanged, original source file stays present, and the second import is a no-op.
- If archive email or customer/cashier identifiers are not needed by a report, omit them from its SELECT projection and rendering state.

The currently inspected active query reads only `sales`, and the archive uses a separate query/table. This separation is **SOURCE-VERIFIED**. Current live values were not recalculated.

## 5. Provenance labels and presentation requirements

| Data class | Required source/label | Current evidence | Required release rule |
|---|---|---|---|
| Current device-local sales | “Lokal / perangkat ini”, with explicit report scope and date interval | **SOURCE-VERIFIED:** screen and dashboard say local; aggregate reads local SQLite | Do not call this consolidated sales, accounting revenue, or accepted cloud data. State whether total includes PPN. |
| Current device-local COGS | “HPP lokal / perangkat ini” | **SOURCE-VERIFIED:** sums local `sales.cogs_amount` | Reconcile to sale-item COGS and FIFO cost-layer consumption before treating as accounting evidence. |
| Archived trial sales | “Arsip trial”, separate archived count/amount | **SOURCE-VERIFIED:** separate tables/query and explicit warning | Never include in current sales, tax, COGS, journals, stock, margin, or cloud accepted totals by default. Any future migration/reclassification requires an audited owner decision. |
| Unacknowledged outbox | “Event lokal belum diakui server” plus counts by actual state | Current label is “Belum sinkron”; query counts every non-acknowledged status. No sync worker is active according to UI copy. | Until state machine/worker exists, describe as local rows not marked acknowledged, not as a working queue or server reconciliation metric. |
| Server-accepted sales/events | “Diterima server” only from authenticated API receipt and server-confirmed records | **NOT IMPLEMENTED / NOT VERIFIED:** inspected API route file has only health endpoint; UI says no cloud worker | Do not display server accepted totals, cross-device consolidation, or sync success until durable receipt/API/acceptance tests exist. |
| Net sales / revenue excluding tax | Explicit accounting definition, generally DPP after discount and excluding PPN for the selected policy | Not a separate current report metric | Show invoice total and net sales/DPP separately with PPN as a distinct measure; have accounting owner approve labels. |
| Returns / voids / reversals | Original sale and separately posted compensating event/journal with relationship and status | No report-side status, return link, or reversal adjustment found in inspected sales schema/query | Do not silently count a voided/returned transaction as normal net sales; require tested posting/report policy. |

## 6. Findings register

### RPT-01 — Active summary is not reversal-aware

**Severity:** P1 — accounting/report accuracy gate  
**Confidence:** High for the reporting limitation; no claim that live return/void rows currently exist.  
**Evidence:** `reports_screen.dart` aggregates all rows in `sales` with no filter. The SQLite sales table contains no transaction lifecycle/status or explicit reversal reference. `JournalService` supports balanced reversal entries, but the current report does not consult journals or reversal relationships. The prior POS/accounting stress report expressly listed return/void audit trail testing as outstanding.

**Failure mode:** if a void, return or correction is recorded as a separate compensating entry while the original sale remains in the sales table, the summary still includes the original `grand_total` and COGS without applying an approved net-reporting treatment. Conversely, deleting/changing the original row would violate the append-only correction principle.

**Required action / ownership:** route to the transaction-posting/reversal owner (Prompt 10) and report owner (Prompt 13). Define, implement and test the canonical return/void/reversal model in an assigned implementation workstream; this audit makes no source change.

**Acceptance evidence:** fixture containing a sale and a linked full/partial return or reversal. Assert immutable original rows, separate compensating records/journals, reconciled inventory/cost movements, and report totals consistent with an owner-approved gross-vs-net return policy. Test retry/idempotency of the reversal as well.

### RPT-02 — Tenant/device ownership is not a report-query boundary

**Severity:** P2 — conditional local privacy/data-separation risk  
**Confidence:** Medium. The absence of tenant/device keys and predicates is source-verified; a cross-tenant exposure has not been demonstrated.  
**Evidence:** `sales`, `sale_items`, `journals`, `stock_movements`, and `outbox_events` have no tenant/device ownership columns in the inspected SQLite schema, and current dashboard/report queries carry no tenant/device predicate. The app uses a device-local database path. A local-only single-context installation may not expose this risk under its intended use, but the report has no source-enforced boundary if context changes or a database is reused.

**Failure mode:** if an installation is reused across tenant/account/device contexts, rows from the previous context remain queryable by the same unscoped local aggregate/list. UI labels or hiding a tab would not create a data boundary.

**Required action / ownership:** hand off to identity/tenant authorization (Prompt 02) and SQLite/data namespace owner (Prompt 07) to define and enforce local database ownership/tenant-switch behavior. The reporting implementation must consume only the trusted scoped repository/context; client-entered IDs are not authorization.

**Acceptance evidence:** test two distinct tenant/device contexts in a reused install/test database. Attempt normal report, dashboard, archive and outbox reads after context switch; prove records from the prior context are either cryptographically/structurally segregated or the switch is rejected until a supported migration/reset is completed. Include logout, offline mode, restart and malformed/changed identity cases.

### RPT-03 — “Penjualan lokal” is an invoice total including PPN, not a separate net-sales metric

**Severity:** P2 — financial definition/label ambiguity  
**Confidence:** High.  
**Evidence:** report and dashboard sum `sales.grand_total`; the sale calculator defines `grand_total = dpp + ppnAmount`. No separate net-sales/DPP or PPN measure appears in the current report cards.

**Failure mode:** an operator/export consumer may interpret the total as revenue excluding PPN, then compare it to a sales ledger or margin calculation on a different basis. Summing invoice totals and treating the amount as net revenue can overstate sales for accounting analysis.

**Required action / ownership:** keep the existing user-facing local-only caveat; accounting/product owner must approve metric names and definitions. In a later scoped implementation PR, distinguish invoice total including PPN, net sales/DPP after discounts, and PPN amount, and document treatment of exempt items and returns.

**Acceptance evidence:** deterministic taxable, exempt, discounted and mixed-cart fixtures. Confirm gross, each discount type, taxable/exempt DPP, PPN rounding, total including PPN, net sales metric, and approved margin formula reconcile to header, line and journal values.

### RPT-04 — Aggregate summaries have no period/business-date filter

**Severity:** P2 — scope limitation; no existing date-filter defect is asserted  
**Confidence:** High.  
**Evidence:** dashboard and report summary SQL has no WHERE/grouping predicate. Only the recent-sale list displays `business_date`; it orders rows by `created_at_utc`. The helper `BusinessDate.fromUtc` uses `Asia/Jakarta` / UTC+7. The current UI does not expose a date filter.

**Failure mode:** operators may compare a lifetime device-local number against a daily/monthly close and believe the values are intended to match. If date filtering is later added using UTC creation date rather than WIB business date, a sale near midnight can fall into the wrong period.

**Required action / ownership:** report owner should add explicit period scope only through a reviewed UI/data implementation task; this audit did not add or alter filters. Date-range labels must state timezone/business-date semantics.

**Acceptance evidence:** fixture immediately before/after WIB midnight, boundary-date rows, and multiple periods. Assert inclusion/exclusion by `business_date`, chosen inclusive/exclusive boundaries, and consistency with the Asia/Jakarta helper. Include UTC timestamps and the displayed business date in assertion messages.

### RPT-05 — Outbox count mixes all non-acknowledged states

**Severity:** P2 — sync-state provenance/operational ambiguity  
**Confidence:** High for current query and schema; future-state impact is conditional.  
**Evidence:** report count is `status <> 'acknowledged'`; schema status is free text without a CHECK-constrained state machine. The UI says no sync worker is active, while the card may describe the count as events “menunggu sinkronisasi”.

**Failure mode:** after retry, conflict, terminal rejection, or manual attention states are introduced, the count can classify all of them as merely waiting even when they are not automatically retryable. It can also be mistaken for server-accepted-event count, which it is not.

**Required action / ownership:** hand off state definitions to the sync/outbox owner (Prompt 11). Once the worker/state machine is implemented, report counts separately for pending, in-flight, retryable, needs-attention/permanent failure, and durably acknowledged states. Keep “accepted by server” independent of UI/outbox status.

**Acceptance evidence:** fixture with each valid state plus an unknown state. Assert state-specific counts, detection of unknown values, exact retryable total, and no server-accepted count until a durable server receipt is linked. Test interrupted in-flight recovery and duplicate acceptance after retry.

### RPT-06 — No report-level cross-ledger reconciliation or dedicated aggregate test

**Severity:** P1 — release acceptance gap for accounting-grade claims  
**Confidence:** High that the inspected report itself does not perform these checks; test status is unverified.  
**Evidence:** active report queries only the sales header aggregate, recent sales, legacy archive and outbox count. It does not reconcile sale headers to sale items, journals/journal lines, inventory/cost movements, or outbox/server acceptance. `combined_home_shell_test.dart` asserts navigation to the report tab and visible title but does not assert aggregate arithmetic. Calculation/posting tests contain useful cases in source, but no dedicated report aggregate/reconciliation test was found by the repository search performed for this audit.

**Failure mode:** independently plausible KPI totals can conceal a missing line, duplicate movement, unbalanced/missing journal, wrong COGS, or an outbox event that does not represent the complete accepted transaction. A green UI-navigation test would not detect these inconsistencies.

**Required action / ownership:** reporting/QA owners should add a dedicated read-only report repository/test suite in a separately scoped implementation PR. Do not recalculate/write production data; reconciliation runs should produce mismatch records without mutation.

**Acceptance evidence:** a deterministic isolated DB fixture covering receipt, tax-exempt and taxable lines, discounts, multiple cost layers, sale, local retry, pending outbox, archive record and a linked reversal when implemented. Assert each equation in §4 and create clear mismatch output for intentionally corrupted fixture-only copies. Execute analyzer and report/calc/posting tests on the exact candidate SHA and retain logs.

### RPT-07 — Archived cashier email is unnecessarily projected into report state

**Severity:** P3 — data-minimization improvement  
**Confidence:** High.  
**Evidence:** the archive query selects `email`, but the rendering uses original sale ID, creation timestamp, item count and total; the email is not displayed. The legacy archive schema retains the historical field.

**Failure mode:** the report fetches personal data that it does not need, increasing its in-memory exposure and the chance of accidental display/logging in future edits.

**Required action / ownership:** remove the unused field from the report SELECT/state projection in a narrowly scoped future implementation PR, unless a documented reporting purpose is approved. Preserve the historical archive source as required; do not delete archive rows.

**Acceptance evidence:** widget/repository test that the archive list renders required history values and does not query/display email; ensure error/debug output is also free of email.

### RPT-08 — No accepted-cloud report source exists on this revision

**Severity:** P1 — blocks SaaS/consolidated reporting claims  
**Confidence:** High for inspected route/report source; deployment status beyond source is not independently observed.  
**Evidence:** `routes/api.php` declares `GET /api/v1/platform-health` only. The report states the cloud worker is not active, and the report data is read from SQLite. The owner ADR and roadmap treat Laravel API parity, sync and production deployment as separate unverified gates.

**Failure mode:** a future UI could wrongly label device-local sales as accepted/cloud totals, or accept “acknowledged” without proving a server-side durable commit. The current inspected UI avoids this claim, which should remain true until evidence exists.

**Required action / ownership:** backend sync/API owner (Prompt 11) must implement and validate authenticated transaction acceptance and durable idempotent receipts before cloud report fields are exposed. Reporting must consume server-confirmed records/receipts only; do not introduce a Supabase fallback.

**Acceptance evidence:** API integration test for first acceptance, identical retry, changed-payload conflict, atomic sale/item/inventory/journal/receipt transaction, tenant/device denial, and local outbox acknowledgement only after durable server acceptance. Reconcile every accepted receipt against its originating local outbox event and server sale ID. Add cross-device fixture and test that the report explicitly differentiates local pending totals from accepted cloud totals.

## 7. Query-authorization and privacy checks

| Check | Current source finding | Acceptance gate |
|---|---|---|
| Tenant scoping | Current local table/query has no tenant ID or trusted tenant predicate. Conditional context-reuse risk; no exploit demonstrated. | Prove local context binding/namespace or reject an unsupported tenant switch. Do not rely on UI visibility alone. |
| Device scoping | Sales and outbox query has no device ID; the database is device-local by design at present. | Treat these as “this device only” until server-derived device ownership and accepted sync receipts exist. |
| Actor/role scope | The current local report SQL does not filter by authenticated role/actor. There is no evidence in this screen that role-specific access is implemented. | Define which owner/manager/cashier roles may view totals/history before using reports in shared-account contexts; enforce authorization in the trusted repository/API boundary, not only by hiding controls. |
| Host/API trust | Current report is local SQLite. Inspected Laravel route file has only the health route; report API authorization is not yet present in that file. | When report APIs are implemented, derive tenant membership, device ownership and role from authenticated server-side state; reject forged IDs and hostile tenant context. |
| Archive data | Email is stored in the legacy archive and projected by the screen's query, but not shown. | Minimize columns fetched; do not render/emit archive emails without approved need and role permission. |
| Secrets / cloud provenance | No server accepted-report source is present in the inspected report flow. | Never expose secrets in report rows/errors. Never infer cloud acceptance from local tenant/device IDs or a client-side flag. |

## 8. Test and CI evidence status

### Test source present (not executed in this audit)

- **TEST-SOURCE-VERIFIED:** `pos-app/test/pos/cart/sale_calculator_test.dart` checks PPN on post-discount taxable DPP, mixed exempt/taxable allocation, deterministic Rupiah rounding/allocation, and discount validation.
- **TEST-SOURCE-VERIFIED:** `pos-app/test/pos/checkout/payment_service_test.dart` contains assertions for posted sale total/PPN/COGS/journal balance, mixed carts, FIFO costing, identical retry without duplicate sale/journal/outbox/stock movement, changed-payload reuse of a transaction ID, rollback on insufficient stock, and business date after WIB midnight.
- **TEST-SOURCE-VERIFIED:** `pos-app/test/database/legacy_trial_importer_test.dart` checks separate archive rows, no synthetic active sales/journals, preservation of the source file, and idempotent import.
- **TEST-SOURCE-VERIFIED:** `pos-app/test/home/combined_home_shell_test.dart` checks product/cashier/stock/report navigation and the report title. It does not verify aggregate formulas or ledger reconciliation.
- **DOC-ASSERTED:** `docs/HARDENING/POS_ACCOUNTING_STRESS_REPORT.md` says tests for core calculations/journals/FEFO/FIFO exist and lists void/return, outbox replay, load, long offline period and coverage as outstanding/not run.

### Execution status observed now

- **TEST-EXECUTED:** no Flutter analyzer, Flutter test, repository integration test, SQL reconciliation command, or APK/device test was executed during this audit.
- **CI-OBSERVED:** current-main combined-status query returned no status contexts. The available commit-workflow-run query returned no runs for the inspected main SHA (its wrapper is scoped to PR-triggered runs). This is **insufficient evidence to classify current-head CI as PASS or FAIL**.
- **STAGING-VERIFIED:** NOT RUN / NOT VERIFIED.
- **PRODUCTION-VERIFIED:** NOT RUN / NOT VERIFIED.
- No production report totals or rows were recalculated, changed, or exported.

## 9. Prioritized acceptance plan

Run these steps only in an isolated local/disposable test environment and on a named candidate revision:

1. **RPT gate A — establish deterministic ledger fixture.** Seed a clean SQLite DB with products, multiple physical lots/FIFO cost layers, taxable and exempt sale lines, both discount types, inventory movement rows, journal lines, one pending outbox event and a distinct legacy archive record. Do not use production rows.
2. **RPT gate B — assert metric formulas.** Query headers and lines independently; compare gross, each discount type, taxable/exempt DPP, DPP, PPN, invoice total, and COGS equations in §4. Fail on orphan rows, missing lines, duplicate IDs, unexpected item counts or integer-Rupiah differences.
3. **RPT gate C — assert journal and inventory parity.** For every sale ID verify a corresponding balanced journal, correct posting map, FIFO consumption totals, lot allocation quantities and product-vs-lot stock balance. Record mismatches instead of silently correcting the fixture.
4. **RPT gate D — archive isolation.** Seed an archive-only trial transaction; assert it appears in archive totals but never changes active sales/COGS/PPN/journals/inventory totals, including if archive rows reference migrated products.
5. **RPT gate E — lifecycle and dates.** Once return/void behavior has an accepted model, test full/partial reversal without deleting the original record or double counting. Add WIB business-date boundary fixtures and enforce an explicit report period.
6. **RPT gate F — outbox vs server receipt.** Until a Laravel sync API exists, assert there is no “server accepted” display. After it exists, test retries, changed-payload conflict, state-specific outbox counts and durable receipt linkage, including tenant/device denial.
7. **RPT gate G — context and privacy.** Test context switch and role restrictions against a reused local DB; ensure archive email is not projected/rendered unless purpose-approved. Include offline/restart behavior.
8. **RPT gate H — execute exact-head CI.** Run Flutter formatting/analyzer and all relevant tests in CI/local environment on the exact candidate SHA; retain command, exit code, logs/artifacts and the CI run URL. A passing test source is not execution evidence.
9. **RPT gate I — reviewer sign-off.** Independent accounting/QA reviewer checks mismatch handling, report labels, date semantics, and evidence coverage before any accounting-grade/consolidated report claim.

Do not mark a gate PASS because code or a test file exists. If a required environment or implementation is absent, retain **NOT RUN / NOT VERIFIED** with the exact blocker.

## 10. Final disposition and handoff

**Disposition: Do not claim reporting/reconciliation acceptance for pre-production release yet.** The current local-only labeling and archive separation should be preserved. Accounting-grade reporting remains gated by reversal/return semantics, tenant/device context policy, explicit metric definitions, date scope, outbox state semantics, and executed report-vs-ledger reconciliation tests. Cloud/consolidated reporting remains unavailable until the accepted Laravel sync and durable-receipt model is implemented and tested.

| Handoff | Assigned scope | Concrete next acceptance |
|---|---|---|
| Prompt 10 — transaction/accounting posting owner | Reversal/return/void posting model and immutable compensating entries | Original + full/partial reversal remains auditable, balanced and idempotent; stock/COGS effects reconcile. |
| Prompt 02 / Prompt 07 — identity and local DB scope owner | Trusted tenant/device context and local database namespace/switch policy | Two-context test demonstrates separation or fails closed. |
| Prompt 11 — sync/outbox/API owner | State machine, authenticated Laravel sync, durable server receipts | Replay/conflict/authorization tests pass; acknowledgement is after commit only. |
| Prompt 13 — reporting owner / independent QA | Metric naming, read-only reconciliation checks and dedicated report tests | All equations and mismatch cases pass against disposable fixtures; exact-head test evidence attached. |
| Accounting/product owner | Decide net-sales basis, PPN display, return/void presentation and report period semantics | Definitions approved in writing and represented consistently in report labels. |

### Evidence status summary

| Gate | Status |
|---|---|
| Active/archive separation | **SOURCE-VERIFIED PASS** — separate tables and summaries; archived values explicitly labelled and not included in active total SQL |
| Local-only provenance labels | **SOURCE-VERIFIED PASS** — UI discloses local-device totals and no cloud worker |
| Calculation unit tests exist | **TEST-SOURCE-VERIFIED; EXECUTION NOT VERIFIED** |
| Report-specific reconciliation tests | **NOT FOUND IN INSPECTED SEARCH / NOT VERIFIED** |
| Header/item/journal/inventory reconciliation | **NOT IMPLEMENTED IN REPORT / NOT VERIFIED** |
| Return/void-aware reporting | **NOT IMPLEMENTED IN REPORT / NOT VERIFIED** |
| Period/business-date filtered totals | **NOT IMPLEMENTED IN CURRENT SUMMARY / NOT VERIFIED** |
| Trusted tenant/device/role data scope | **NOT VERIFIED** |
| Outbox/server-accepted reporting | **LOCAL OUTBOX ONLY; SERVER ACCEPTANCE NOT IMPLEMENTED / NOT VERIFIED** |
| Current-head CI | **NOT VERIFIED** |
| Staging / production values | **NOT RUN / NOT VERIFIED** |
