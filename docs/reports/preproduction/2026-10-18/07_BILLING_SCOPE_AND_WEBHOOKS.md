# Billing, Subscription, Webhook & Entitlement — Pre-production Audit

**Status: BLOCKED — recommend billing/payment/webhooks OUT OF SCOPE for RC1 pending explicit owner decision.**  
**Evidence date:** 2026-10-19 (Asia/Jakarta). Requested report directory remains `2026-10-18`.  
**Canonical repository:** `berkah-pos/Berkahtigaputeri`  
**Workstream branch:** `audit/preprod-billing-boundary-2026-10-18`  
**Base SHA captured before edits:** `371b7fdf0bf672b37ceb1023e647f114221bf797`  
**Implementation/test SHA immediately before report publication:** `db52f44706ec744bbd55aae90cbfd55c3eb7aadc`  
**PR:** [#82](https://github.com/berkah-pos/Berkahtigaputeri/pull/82), open/unmerged; no merge or release approval performed.  
**Scope ownership:** subscription/payment/webhook implementation and server-side entitlement. Product scope is a recommendation only; the owner and release-scope owner retain the final decision.

## 1. Executive summary

The Laravel/PostgreSQL implementation in the inspected source is a platform scaffold, not a working billing subsystem. The explicit Laravel route files expose a home/status response and an API platform health response; no payment-initiation route, payment-provider callback, subscription mutation API, entitlement endpoint, or billing scheduler was found in the inspected active sources. The central migration creates a `subscriptions` table, but the table is not evidence of billing behavior. Its original defaults were `plan=trial` and `status=trial`, and the canonical workbook importer created a 14-day trial subscription for every new imported tenant. That was an unsafe implicit grant for an RC with no owner-approved billing/entitlement flow.

Changes made on the dedicated branch:
- Removed automatic creation of `trial` subscription rows from `ImportCanonicalWorkbook`.
- Added a follow-up central migration that changes future `subscriptions` insert defaults to `plan=unconfigured` and `status=inactive`, preserving the original migration file and migration history. Its rollback deliberately retains the fail-closed defaults.
- Added `BillingOutOfScopeTest` to guard against reintroducing payment/webhook/subscription/entitlement routes, the trial-by-default importer behavior, and unsafe schema defaults.

The two added PHP files passed `php -l` on local scratch copies (exit code 0). **PHPUnit, PostgreSQL migration execution, exact-head CI, provider sandbox tests, and live deployment tests have not run in this environment.** The branch does not yet prove runtime enforcement or production readiness. The fail-closed changes are a narrow mitigation, not a completed entitlement system.

## 2. Architecture authority read

Read from the canonical repository in the AGENTS-required authority order:
1. `AGENTS.md` — current agent contract, no-Supabase rule, evidence/ownership requirements.
2. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — five-layer and 352-entry configuration contract.
3. `docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` — current owner platform decision; supersedes conflicting platform/source-access clauses.
4. `docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` — read as subordinate/historical where superseded.
5. `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` — target architecture and required acceptance gates.
6. `docs/permanent/DOC_00_MASTER_ROADMAP.md` — phase/gate order.
7. `docs/permanent/README.md` — authority/evidence index.
8. `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md` — subscription domain guidance; specifically says provider and pricing model are not selected and must not be integrated before approval.
9. `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` — historical Flutter implementation and known gaps.
10. `docs/HARDENING/README.md`, root `README.md`, `docs/HARDENING/PAYMENT_HARDENING_REPORT.md`, scoped routes, migration, importer, Flutter checkout/login/home and package manifests.

The current owner ADR prohibits all Supabase products, including read-only access; no Supabase project was contacted, queried, synced, or migrated. Historical Supabase functions, keys, SQL, docs, and the superseded Midtrans proposal are not an approved runtime. The canonical configuration contract remains `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE`; it is unchanged by this workstream.

## 3. Decision table — proposed RC1 scope

| Capability | RC1 recommendation | Source evidence / reason | Owner/dependency |
|---|---|---|---|
| Subscription/payment checkout for Berkah POS SaaS | **OUT** until explicit owner approval | No gateway SDK/service/route/provider receipt verification was found. A local POS payment-method enum is not a SaaS gateway. | Product owner + release-scope owner |
| Payment-provider webhook | **OUT** | No active handler/signature validation/replay protection/event-ID table or provider configuration was found. | Billing owner, after provider selection |
| Server-side entitlement mutations and paid feature unlock | **OUT / unavailable** | No entitlement API/policy/service was found. Subscription schema presence alone grants no proof of authority. | Central API / auth owner; must be implemented before paid access |
| Automatic trial creation from workbook import | **REMOVED** on this branch | Importing configuration should not imply customer activation or create a 14-day entitlement. | This workstream |
| Default status for newly inserted subscription | **FAIL CLOSED** on this branch | Follow-up migration changes defaults to inactive/unconfigured. Existing row values are not rewritten by this migration. | This workstream; database execution still required |
| Local POS tender labels: cash, QRIS, transfer bank | **IN only as a local tender record** | `pos-app/lib/features/pos/checkout/payment_service.dart` enumerates local tender methods. No QRIS/acquirer/payment API integration is established. | POS checkout owner |
| Trial app “Mulai Trial Gratis” / “dapat dicoba tanpa pembayaran” text | **REVIEW / remove or relabel if RC1 excludes trial entitlement** | `berkah-pos-trial/lib/main.dart:128-156` promises local trial and calls an email-only status endpoint; network failure yields `unknown`, and navigation still continues. This is client-local behavior, not server entitlement. | UI/release-scope owner; not changed here |
| WhatsApp Sales CTA | **IN as informational contact only** | Launches `wa.me` with an activation-information message; no checkout URL or payment request is issued by this code. | UI/release-scope owner |
| Supabase billing/Edge Function/Secrets | **PROHIBITED** | Current owner ADR supersedes historic Supabase function/security documentation. | All workstreams |

**Owner decision still required:** approve billing/payment/trial as an explicit RC1 feature or confirm it is out of scope. This report recommends the latter. This is not the final product decision.

## 4. Active route, job, provider, and CTA inventory

| Surface | Evidence | Assessment |
|---|---|---|
| `GET /` | `routes/web.php:5-14` | Static API/root status response; no billing action. |
| `GET /api/v1/platform-health` | `routes/api.php:5-12` | Health/status only; no billing action. |
| `GET /up` | `bootstrap/app.php:11-12` | Framework health route; no billing action. |
| `routes/console.php` | `routes/console.php:1-5` | No scheduled billing command is declared there. Full `artisan schedule:list` was not run. |
| `config:import-workbook` | `app/Console/Commands/ImportCanonicalWorkbook.php:18+` | Active-looking Artisan command source. The implicit trial-creation statement was removed. It still saves tenant records and comments that tenant creation provisions an isolated DB; provisioning/payment-gate behavior belongs to the provisioning owner and requires separate review. Do not run the importer against any live/shared environment. |
| External `GET https://api.berkahtigaputeri.co.id/check-status?email=...` | `berkah-pos-trial/lib/main.dart:10, 92-102` | Client reference only. Server handler is not in this repository and was not probed. Email-only status is not identity/authentication. |
| Trial entry CTA | `berkah-pos-trial/lib/main.dart:128-156` | Starts local UI after a status lookup; it does not initiate payment. It presents a trial promise despite the server status not being an authorization boundary. UI is outside this agent's unique ownership. |
| WhatsApp Sales CTA | `berkah-pos-trial/lib/main.dart:113-120, 156`; `pos-app/lib/features/home/home_screen.dart:492-502, 670-676` | Information/contact links; no gateway transaction is started. |
| Payment provider SDK/config | `composer.json`, `pos-app/pubspec.yaml`, source searches for Midtrans/Xendit/payment gateway | No provider integration/dependency or active provider-secret reference found in the inspected runtime. Search results in `docs/archive/superseded/DOC_14_MALFORMED_DUPLICATE_PROPOSAL_2026-10-15.md` are historical proposal only. |
| Webhook/controller/resource | Repository searches for `WebhookController`, `PaymentController`, `SubscriptionResource`, `midtrans`, `webhook`, `billing` | No current handler/resource found. Search is source evidence only; `php artisan route:list` was not run. |
| Timer/recurring billing job | `routes/console.php` / `bootstrap/app.php` and source search for `Schedule::` / `withSchedule` | No billing expiry/renewal job found in inspected sources. Runtime schedule discovery was not run. |

The repository's central migration defines `subscriptions` with `tenant_id`, `plan`, `status`, `expires_at`, and `provider_reference` (`database/migrations/central/2026_10_17_000001_create_central_platform_tables.php:48-57`). This is schema scaffolding, not gateway integration or an entitlement contract.

## 5. Findings

### F-01 — Importing workbook implicitly granted trial subscription rows
- **Severity / confidence:** P1 / High.
- **Status:** VERIFIED in source; mitigation committed on this branch; runtime behavior NOT RUN.
- **Original evidence:** `app/Console/Commands/ImportCanonicalWorkbook.php` imported `Subscription` and called `Subscription::query()->firstOrCreate(..., ['plan' => ..., 'status' => 'trial', 'expires_at' => now()->addDays(14)])`. The central schema also defaulted plan/status to `trial`.
- **Impact:** a configuration-data import could be interpreted as granting a 14-day trial despite the provider, subscription terms, and server-side entitlement flow not being approved. This mixes configuration ingestion with commercial activation.
- **Change:** removed the Subscription model import and auto-create call; retained an explicit comment that workbook imports cannot create a trial/entitlement. Preserved the original migration and added `database/migrations/central/2026_10_19_000001_fail_closed_subscription_defaults.php` to set new-row defaults to `unconfigured/inactive`.
- **Negative/regression test added:** `tests/Feature/BillingOutOfScopeTest.php` checks the importer has no subscription/trial creation code. It has not yet executed under PHPUnit.
- **Residual:** the migration changes defaults only; it does **not** rewrite existing subscription rows. No migration has been run against any database. Any future existing rows must be independently reconciled before a billing-enabled release.

### F-02 — No gateway, webhook, subscription lifecycle or server-side entitlement API exists in the inspected implementation
- **Severity / confidence:** P1 / High for any attempt to sell/activate subscriptions; not a claim that an unimplemented endpoint is exploitable.
- **Status:** VERIFIED in inspected source; integration gate BLOCKED.
- **Evidence:** `routes/api.php` has only platform health; `routes/web.php` has a root status response; no `Subscription.php`, `PaymentController`, `WebhookController`, billing resource, or provider package/config was found in the tracked paths/searches. Current root API is only a Laravel baseline. `docs/HARDENING/PAYMENT_HARDENING_REPORT.md` independently records the historical search result, but this conclusion is based on current source inspection too.
- **Impact:** no payment state can be validated or reconciled; there is no trusted source of paid/grace/refund state and no implementation that can be certified as blocking/allowing paid SaaS capabilities server-side.
- **Recommendation:** do not expose or market billing as active in RC1. If owner later brings it into scope, implement the provider, signature validation, replay/idempotency, event state reconciliation, and server-side checks in a reviewed dedicated change with sandbox evidence.

### F-03 — Client-side local-trial messaging can be confused with subscription authorization
- **Severity / confidence:** P2 / High.
- **Status:** VERIFIED in client source; no UI change made because ownership sits with UI/release-scope.
- **Evidence:** `berkah-pos-trial/lib/main.dart:92-102` maps API booleans/status words including `active` and `trial` to client status. On exception/non-2xx/unknown response it returns `unknown`; `login()` still navigates at lines 128-140. Lines 152-156 present “Aplikasi dapat dicoba tanpa pembayaran”, “Mulai Trial Gratis”, and the Sales CTA. The screen explicitly says status checking does not restrict local data.
- **Impact:** the CTA conveys a commercial trial promise even though authentication, server-side membership, billing, and entitlement are not implemented here. Because the product is local-only, this is not evidence that a client claim grants server access; however, UI copy must not be used as proof of an authorized SaaS trial.
- **Action required:** UI/release-scope owner to confirm copy and local-only behavior for RC1. If trial is out of scope, remove/relabel “Mulai Trial Gratis” and avoid wording that implies a remotely activated subscription. No payment flow should be added as part of the UI fix.

### F-04 — Workbook importer saves tenant records and implies provisioning independent of activation
- **Severity / confidence:** P2 / Medium.
- **Status:** SOURCE-VERIFIED statement; actual provisioning side effect NOT RUN.
- **Evidence:** `app/Console/Commands/ImportCanonicalWorkbook.php` calls `$tenant->save()` and comments that tenant creation provisions the isolated database. The resource-budget guidance states tenant DBs should be provisioned only after an approved activation/payment gate.
- **Impact:** a workbook import can potentially allocate per-tenant resources regardless of billing approval. No database/import command was run to test the side effect.
- **Dependency:** route this to the tenant-provisioning owner. Do not broaden this PR to change provisioning semantics without coordination. Until gated/reviewed, do not use `config:import-workbook` as a production tenant onboarding action.

### F-05 — Card-data/logging claims cannot be certified because no billing flow exists
- **Severity / confidence:** P2 / Medium.
- **Status:** UNSUPPORTED / NOT VERIFIED.
- **Evidence:** inspected migration has no explicit card-number/CVV columns; no payment handler or provider event logger was found. The generic `audit_events.metadata` JSON field can hold arbitrary metadata, so its safety cannot be inferred from schema alone.
- **Impact:** there is no basis to claim card-data storage/processing compliance or that provider payloads would be safely redacted in logs.
- **Action required:** do not collect or store card data. If billing is approved later, store only provider references and minimal redacted event metadata; test logs with synthetic webhook/card-like payloads and prove secrets/tokens/full payment payloads are excluded.

No P0 finding was proven by direct reproduction in this workstream.

## 6. Server-side entitlement and fail-closed assessment

| Check | Status | Evidence / limitation |
|---|---|---|
| Client cannot call a current payment-initiation endpoint | SOURCE-VERIFIED in inspected route files; full route-list execution NOT RUN | No billing/payment route is declared in `routes/api.php` / `routes/web.php`. Route discovery via Laravel was not executed. |
| Server does not accept client claim to set `paid/active` | NOT VERIFIED as an entitlement control | No endpoint was found that accepts such a claim; equally, no entitlement API/policy exists to certify. Absence of an endpoint is not proof that a complete entitlement enforcement system exists. |
| Fresh subscription inserts default inactive/unconfigured | SOURCE-VERIFIED in new migration; DB behavior NOT RUN | `2026_10_19_000001_fail_closed_subscription_defaults.php`. The follow-up migration is additive and does not mutate existing rows. |
| Workbook import does not create trial records | SOURCE-VERIFIED change; regression test added but NOT RUN | `ImportCanonicalWorkbook.php` no longer references the Subscription model or creates trial records. |
| Expiry/grace/past-due/refund policy | UNSUPPORTED | No approved rules/state machine or provider implementation exists. Do not invent one. |
| Entitlement checked on every privileged server route | BLOCKED / NOT VERIFIED | The current Laravel API scaffold exposes only health. Product APIs, authentication/tenant authorization, and central entitlement policy remain separate roadmap gates. |

This is a fail-closed **billing-out-of-scope guard for the scaffold**, not a claim that tenant APIs or SaaS entitlement are production-secure. There is no active paid-access contract to certify.

## 7. State-transition and webhook test matrix

For RC1 the recommended disposition for every row below is **OUT OF SCOPE / NOT IMPLEMENTED**, pending owner decision. Consequently none is reported as passed. If billing is later approved, every applicable row becomes a mandatory sandbox/disposable test.

| ID | Scenario | Required eventual assertion | Current status |
|---|---|---|---|
| ST-01 | Create payment / `pending` | Server creates a provider-bound reference; amount, currency, tenant and order are server-derived | NOT IMPLEMENTED / NOT RUN |
| ST-02 | Valid signed webhook `pending → paid` | Signature and timestamp validated against raw request; exact order/amount/currency/reference reconciled | NOT IMPLEMENTED / NOT RUN |
| ST-03 | Invalid signature / altered bytes | Reject with no subscription state change or entitlement | NOT IMPLEMENTED / NOT RUN |
| ST-04 | Duplicate webhook / same provider event ID | Idempotent receipt; exactly one state transition/audit event | NOT IMPLEMENTED / NOT RUN |
| ST-05 | Replay / stale timestamp | Reject or safely no-op according to approved provider contract; no repeated grant | NOT IMPLEMENTED / NOT RUN |
| ST-06 | Out-of-order / late webhook | Terminal/refund/expiry state cannot be incorrectly resurrected by an older event | NOT IMPLEMENTED / NOT RUN |
| ST-07 | `failed` / `expired` | No paid entitlement; retry policy does not change a failed state into paid without valid evidence | NOT IMPLEMENTED / NOT RUN |
| ST-08 | `refunded` / chargeback | Reconcile provider refund state; revoke applicable entitlements server-side without deleting business history | NOT IMPLEMENTED / NOT RUN |
| ST-09 | Wrong tenant/order/provider reference | Reject cross-tenant or mismatched-reference webhook; no side effects | NOT IMPLEMENTED / NOT RUN |
| ST-10 | Client forges plan/status/expiry/trial/grace in request | Server ignores/rejects all client-owned entitlement fields and uses central authoritative state only | NOT IMPLEMENTED / NOT RUN |
| ST-11 | Missing/invalid amount or currency mismatch | Reject and audit only safe, minimal metadata | NOT IMPLEMENTED / NOT RUN |
| ST-12 | Concurrent duplicate deliveries | Lock/unique constraint prevents more than one accepted transition | NOT IMPLEMENTED / NOT RUN |
| ST-13 | Pending at deployment/worker interruption | Restart/retry does not lose event or create an implicit grant | NOT IMPLEMENTED / NOT RUN |
| ST-14 | Logs / audit events | No secrets, bearer tokens, raw card data, CVV, or unredacted provider payload | NOT IMPLEMENTED / NOT RUN |

## 8. Acceptance gates

| ID | Criterion | Status | Evidence | Blocker |
|---|---|---|---|---|
| BG-01 | Owner-approved RC1 billing scope | **BLOCKED** | Recommendation to exclude billing is recorded here | Owner decision needed |
| BG-02 | Enumerate active provider/payment/webhook routes and jobs | **PARTIAL / SOURCE-VERIFIED** | Inspected route/console files and source searches; route:list/schedule:list not run | Laravel runtime environment required |
| BG-03 | No implicit trial created by workbook import | **SOURCE FIXED; TEST NOT RUN** | `ImportCanonicalWorkbook.php`, test `BillingOutOfScopeTest` | Execute PHPUnit on PR head |
| BG-04 | Schema fails closed for new subscription rows | **SOURCE FIXED; DB TEST NOT RUN** | Follow-up migration changes defaults to `unconfigured/inactive` | Disposable PG17 migration test |
| BG-05 | No payment initiation route/webhook in RC1 | **PARTIAL** | No such route in inspected explicit route files; route guard test added | Execute runtime route inventory and PHPUnit |
| BG-06 | Server-side entitlement authoritative / rejects client claims | **BLOCKED / NOT IMPLEMENTED** | Product API scaffold only exposes health | Central API/authz owner; later release gate |
| BG-07 | Provider signature, idempotency, replay, state reconciliation | **NOT APPLICABLE FOR RC1; NOT IMPLEMENTED** | No selected provider or callback exists | Owner must explicitly bring billing into scope |
| BG-08 | No card data stored; logs safe | **UNSUPPORTED / NOT VERIFIED** | No billing handler/card columns found; generic audit metadata remains | Not certifiable without implementation/log tests |
| BG-09 | UI does not promise an active trial/payment | **DEPENDENCY / NOT ACCEPTED** | “Mulai Trial Gratis” and local-only flow in trial app | UI/release-scope owner |
| BG-10 | Tenant provisioning gated separately from billing | **DEPENDENCY / NOT VERIFIED** | Importer tenant save path and resource-budget requirement | Tenant provisioning owner |
| BG-11 | Exact-head CI for these changes | **NOT RUN at report authoring** | No qualifying PR-head workflow result accessed before report publication | Check PR-bound workflow run/attempt/SHA |
| BG-12 | No Supabase runtime or secret is used for billing | **POLICY VERIFIED; legacy references remain** | Latest ADR prohibits Supabase; no project access occurred | Separate no-Supabase cleanup workstream |

## 9. Commands and execution evidence

| Command / action | Environment | Exit code / result | Evidence/artifact |
|---|---|---|---|
| `php -l /tmp/billing-audit-php-check/database/migrations/central/2026_10_19_000001_fail_closed_subscription_defaults.php` | Local scratch copy of new migration; PHP 8.4.24 CLI | **0 — passed syntax lint** | Container output: “No syntax errors detected”. Scratch file is not a repository checkout. |
| `php -l /tmp/billing-audit-php-check/tests/Feature/BillingOutOfScopeTest.php` | Local scratch copy of new PHPUnit test; PHP 8.4.24 CLI | **0 — passed syntax lint** | Container output: “No syntax errors detected”. |
| `git ls-remote https://github.com/berkah-pos/Berkahtigaputeri.git refs/heads/audit/preprod-billing-boundary-2026-10-18` | Container environment | **128 — blocked** | `fatal: unable to access ... Could not resolve host: github.com`. This prevented a local checkout. |
| `php artisan test --filter=BillingOutOfScopeTest` | Repository checkout with Composer `vendor/` | **NOT RUN** | Checkout/dependencies unavailable to local shell; PHP syntax lint does not prove test behavior. |
| `php artisan route:list` and `php artisan schedule:list` | Laravel runtime | **NOT RUN** | No repository checkout/runtime in local shell. |
| `php artisan migrate --database=central --path=database/migrations/central` | Disposable PostgreSQL 17 | **NOT RUN** | No disposable PG17 database/credential was supplied. No database was contacted or changed. |
| Sandbox payment/webhook tests | Disposable/provider sandbox | **NOT APPLICABLE for proposed RC1 OUT scope / NOT RUN** | No provider selected and no handler exists. No real payment or provider API was called. |
| GitHub Actions exact-head run | PR branch | **NOT RUN / NOT YET OBSERVED in this report** | Must record workflow name, run ID, attempt, tested SHA, status, URL and sanitized artifacts after CI starts. Do not call a later different-SHA run exact-head evidence. |

No production environment, Supabase project, payment provider, secret store, customer data, or payment data was accessed or modified.

## 10. Files changed by this workstream

1. `app/Console/Commands/ImportCanonicalWorkbook.php` — removed the import-time implicit subscription/trial creation and associated model import; added explicit RC1 no-trial comment.
2. `database/migrations/central/2026_10_19_000001_fail_closed_subscription_defaults.php` — new additive migration that sets new subscription defaults to inactive/unconfigured and never restores trial-by-default on rollback.
3. `tests/Feature/BillingOutOfScopeTest.php` — adds route, default-schema and importer regression guards.
4. `docs/reports/preproduction/2026-10-18/07_BILLING_SCOPE_AND_WEBHOOKS.md` — this audit report.

The original central schema migration was restored byte-for-byte and left unchanged; no permanent ADR, platform decision, unrelated UI file, database data, production configuration, or secret was changed.

## 11. Dependencies, residual risk and next step

- **Release-scope/product owner:** decide whether RC1 is explicitly local-only with billing/trials out of scope. The report recommendation is OUT, not a final business decision.
- **UI/release-scope owner:** review “Mulai Trial Gratis” and related copy. This audit did not modify UI sources because that is outside its unique code ownership.
- **Tenant provisioning/security owner:** review whether `config:import-workbook` can create tenant DBs without an activation gate; do not run it on production/shared targets.
- **Laravel central API/auth owner:** when subscription entitlements are approved, implement a single authoritative server-side policy before exposing privileged APIs. Client-supplied plan, expiry, trial/grace, status, or payment results must never grant entitlements.
- **Independent QA/release owner:** run `php artisan test --filter=BillingOutOfScopeTest`, clean central migrations against disposable PostgreSQL 17, runtime route/schedule inventory, and inspect the exact PR head CI run. Retain run ID, attempt, tested SHA, exit/status, URL and sanitized artifacts.
- **Future billing workstream, only after owner approval:** select provider and payment model, document amount/currency/order binding, implement signed webhook authentication, unique event IDs, replay/out-of-order/late event policy, transactional state transitions, refund handling, safe audit logging, and positive/negative sandbox tests. Do not use historical Supabase functions or Midtrans proposal files as authorization to deploy an integration.

**Residual risk:** no end-to-end server-side entitlement system exists to certify. The code changes prevent the observed importer-based trial grant on this branch and change insert defaults for future rows, but the migration and regression tests are unexecuted against the target PostgreSQL environment. Existing subscription rows are not modified by the migration. Do not release billing or describe subscriptions as working.

## 12. Recommendation

**Overall recommendation: BLOCKED (not PASS).**  
**RC1 billing scope recommendation: OUT**, pending written owner approval. Payment gateway/webhooks/subscription activation should not be represented as available in RC1. Do not approve release based on route/source inspection or schema presence alone.


## 13. CI observation after first report publication

- **Workflow:** `Laravel PostgreSQL 17 Baseline`
- **Run ID / URL:** `39180994439` — https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39180994439
- **Attempt:** NOT RETURNED by the available GitHub run wrapper; do not infer an attempt number.
- **Tested SHA:** `81b6b9107ee84ede2bf5689ebd50d0f11e8983ff` (first report head / PR #82 head at the time of observation).
- **Observed status:** `in_progress`; job `Locked PHP 8.4 / Laravel 13 / PostgreSQL 17 baseline` was in progress. The step `Assert manifest, lock, runtime and DB target` completed successfully; `Build PHP 8.4 CI image and install locked dependencies cleanly` was still in progress. No workflow conclusion or later test results had been observed at this snapshot.
- **Exact-head caveat:** this snapshot belongs only to SHA `81b6b9107ee84ede2bf5689ebd50d0f11e8983ff`. The report update itself creates a later commit; re-check the workflow against the latest PR head before accepting any gate.
