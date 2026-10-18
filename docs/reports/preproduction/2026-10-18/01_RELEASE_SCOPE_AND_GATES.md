# 01 — Release Scope and Gates

**Status:** DRAFT AUDIT / RECOMMENDATION ONLY — NOT A RELEASE CERTIFICATE  
**Audit date:** 2026-10-19 (Asia/Jakarta)  
**Repository:** berkah-pos/Berkahtigaputeri  
**Audited base:** main at 371b7fdf0bf672b37ceb1023e647f114221bf797  
**Working branch:** audit/preprod-release-scope-2026-10-18  
**Candidate version proposal:** v1.0.0-rc1, only after all applicable P0 gates pass on one integrated exact SHA. No tag was created.  
**Authority:** current source and observed exact-head CI, subject to AGENTS.md and the accepted 2026-10-17 no-Supabase owner ADR.

## 1. Executive recommendation

**Recommendation: NO-GO for a production SaaS release on the audited base.** This is not an owner approval or final go-live decision.

The first release should be a deliberately small **single-business-per-tenant POS MVP**: authenticated Laravel Central API, tenant/device authorization, effective configuration, local-first checkout and outbox, server-accepted idempotent sales, inventory allocation/costing, balanced immutable ledger postings, minimal operational reports, account/device audit, and recovery/rollback controls. Advanced payment/subscription products, AI insight, and hardware integrations should not be release dependencies.

That target is a proposed scope, **not a claim that the backend currently delivers those capabilities**. At main SHA 371b7fdf0bf672b37ceb1023e647f114221bf797, routes/api.php exposes only platform-health; there is no implemented Laravel login, effective-config, sale-sync, inventory-posting, journal-posting, subscription, payment-webhook, AI, or device-integration API in the inspected route inventory. The tenant schema contains starter tables, not proof of a complete business transaction lifecycle.

The only currently defensible launch classification is a **local-only technical beta**, and even that is not a production go decision: the cloud login/config paths still use the Supabase Flutter SDK, which conflicts with the latest owner ADR. Do not market or certify main as a compliant SaaS release.

## 2. Evidence identity and rules

- Current main observed from GitHub during this audit: 371b7fdf0bf672b37ceb1023e647f114221bf797.
- Direct commit status for that SHA reported zero status entries and zero check runs. This is **missing evidence**, not a test failure and not a pass.
- PostgreSQL 17 baseline run 39131351376, attempt 1, passed on separate branch head 6062df7b9a0fd94db17107d654f9b3e16622531b. It ran disposable PG17 role/grant probes, locked dependency/security checks, Laravel route/tests, fresh central and tenant migrations, and production-image smoke. This is branch-scoped evidence, not proof that the same integrated SHA is on main.
- Canonical POS App CI run 39172242849, attempt 1, passed on separate branch head 77da4ae145b88ff4cd152e7f518516cc23ad7678. It ran Dart analysis, Flutter tests, Android host setup, and a **debug-only** Android App Bundle compile check. It is not a signed publisher artifact or backend/SaaS acceptance evidence.
- Recent failed or cancelled runs from intermediate commits are retained as execution history, not silently promoted or treated as tests of the latest candidate.
- AGENTS.md and the current ADR explicitly prohibit any Supabase project access, even read-only, and prohibit running scripts/sync_excel_to_supabase.py. This audit did not connect to Supabase and did not run that script.
- Source/document inspection is not runtime proof. No staging observation, production deployment, backup restore, UAT, concurrency test, rollback drill or final owner sign-off was executed by this audit.

Evidence taxonomy: SOURCE-VERIFIED means the tracked source was inspected at the stated base; CI-OBSERVED refers only to the cited run/attempt/head; STAGING-OBSERVED and PRODUCTION-OBSERVED require direct named-environment observations. All unexecuted checks remain NOT RUN / NOT VERIFIED.

## 3. Feature inventory — proposal vs actual implementation

“Include” below means eligible for the proposed first-release scope, not already release-ready. Cloud feature scope cannot be activated until its corresponding P0 gates pass.

| Feature | Source-verified current state | First-release disposition | Gate / rationale |
|---|---|---|---|
| Login / authentication | Flutter LoginScreen source contains Supabase sign-in and a local-only path; no Laravel login/session route was found in routes/api.php. | **Cloud login: OUT until replaced.** Local-only entry may remain in a non-SaaS beta. | P0. Supabase active runtime is expressly disallowed; Laravel authentication and revocation are not implemented in the inspected routes. |
| Tenant / service / device configuration | Canonical workbook exists with the required 352-entry contract; backend has starter normalized central tables and an importer command. No active Laravel effective-config route/resolver was found. | **NOT PROVEN / blocked for SaaS.** Include only after authenticated API and parity gates pass. | P0. Preserve GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE and resolve one requested service only. |
| POS checkout | Flutter SQLite sale repository source implements one local transaction boundary covering local sale, stock operations, journal and outbox. Tests exist; a separate offline branch’s CI passed. | **Include, limited to locally verified checkout behavior.** | P0 for sale atomicity/idempotency acceptance; no equivalent Laravel sync/acceptance handler was found. |
| Product CRUD | Flutter product model/repository/screens and local database schema are present. | **Include for local operation**, subject to exact integrated candidate test/UAT. | P1; no cloud API parity evidence. |
| Inventory / stock | Flutter has physical-lot FEFO and FIFO financial-cost engines, lot holds/reservations, stock movements, and tests. Backend migration has starter inventory_lots and inventory_movements but no complete stock receipt/checkout service. | **Include only for tested local single-device use.** Cloud stock and cross-device consistency are OUT until implemented. | P0 if cloud sales/inventory are in scope. No global consistency claim while offline multi-device policy is unresolved. |
| Operational reports | Flutter reports screen exists, but current backend API has no tenant reports route. | **Include minimal local reports only after UAT and reconciliation.** Consolidated cloud/tenant reports are OUT for this candidate until server projections are tested. | P1 / accounting sign-off. |
| Journals / COA | Flutter JournalService validates balanced debit/credit, allowed account codes, stable transaction-ID retry, and reversal-shaped entries; tests exist. Backend journal_entries/journal_lines are starter schema with no posted status, closed periods, immutable-posted enforcement, required audit event or database balance trigger at the audited base. | **Cloud-authoritative accounting ledger: NOT PROVEN and release-blocked.** | P0 if the product represents reports as accounting-grade. Local unit tests do not prove backend/DB accounting integrity. |
| Reversal / refund | Generic local journal service can represent a reversal; no end-to-end sale refund API/lifecycle was found. | **OUT / unsupported** unless an explicit tested sale-refund contract is implemented and approved. | Do not confuse a balanced reversal-shaped journal with a complete refund workflow. |
| Offline checkout / outbox | Local SQLite schema contains sales, journals, inventory movements and outbox events; local atomic sale repository is implemented. | **Include offline local checkout** within a single device boundary. | P0: verify crash/restart/retry and no partial transaction on candidate SHA. |
| Cloud sync | Flutter has legacy Supabase configuration/auth/runtime references; current Laravel API route list shows only platform health. Existing sync_receipts is only a table definition in starter schema. | **OUT until replaced by authenticated Laravel Central API** and idempotency/conflict rules pass. | P0. Do not run dual Supabase/Laravel mode. |
| Subscription / entitlement | Central migration has a subscriptions table, but no audited entitlement enforcement, lifecycle route, grace-period rule or reconciliation job was found. | **OUT** unless the owner explicitly changes scope and production controls are implemented. | P0 if any paid entitlement is presented as active; otherwise excluded from v1.0.0-rc1. |
| Payment gateway | A local payment method abstraction exists; no server payment-gateway integration was found in the active backend API. | **OUT.** Local tender recording is not a payment gateway. | Requires separate risk/security review, reconciliation and owner approval. |
| Payment webhook | No active webhook endpoint/controller or signed/idempotent webhook processor was found. | **OUT.** | Do not infer implementation from subscription schema, CTA, or historical notes. |
| AI insight | No active backend AI insight service/API was found in the inspected routes and source inventory. | **OUT.** | Not needed to prove the core POS/accounting painkiller; future scope only. |
| Device / hardware integration | Flutter manifest and UI/source indicate hardware-facing capabilities, but no end-to-end supported printer/scanner test evidence is bound to the candidate. | **OUT for initial release claims.** | Hardware model matrix, permission review and physical-device testing required before future inclusion. |
| Multi-tenant base | Laravel/tenancy dependencies and starter central/tenant migrations are present. A disposable PostgreSQL isolation baseline passed on another branch SHA, but no complete integrated provisioning + auth/API + transaction acceptance at current main was proven. | **Required platform gate for SaaS; not an optional feature.** | P0: real restricted PostgreSQL roles, tenant A/B denial, device/host negatives and worker-context reset on same candidate SHA. |
| Advanced multi-tenancy | Advanced self-service provisioning, organization hierarchies, cross-tenant consolidation, high availability and horizontal-scale claims were not proven. | **OUT.** | Single-node KVM2 target is not HA; capacity claims require load/restore measurements. |
| Existing-business-data migration | Repository contains historical Supabase material, but current ADR prohibits accessing Supabase. No approved offline export was verified as available in this audit. | **NOT VERIFIED / owner-dependent.** Clean-start is the only supported engineering path if no already-available owner-controlled offline export exists. | P0 if continuity of existing records is a release requirement; do not create an export by connecting to Supabase. |

### Proposed minimum in-scope product contract

The first integrated SaaS RC should be limited to: Laravel authentication and authorization; tenant/device enrollment and isolation; a server-resolved five-layer config endpoint; local SQLite product catalog, POS checkout, FEFO physical allocation and FIFO costing; a transactional outbox; authenticated server sync with stable idempotency/conflict handling; an atomic server sale + stock movement + journal + audit-event lifecycle; period locks and immutable balanced posting; minimal product/sales/accounting reports; operational health/observability; recoverable deployment and rollback.

This minimum includes requirements that are **not yet implemented or verified at the audited base**. Release eligibility follows acceptance evidence, not this scope statement.

## 4. Release-excluded feature list

The following are out of scope for the proposed v1.0.0-rc1 unless the owner explicitly approves a scope change and the associated control/test gates are added:

1. Subscription checkout, paid entitlements, renewal/cancellation automation, grace-period enforcement and billing reconciliation.
2. Payment gateway, settlement reconciliation, payment webhook, refund integration and any hosted checkout.
3. AI-generated insights, AI bookkeeping classification or autonomous accounting decisions.
4. Printer/scanner/Bluetooth hardware support as a launch promise.
5. Full sale-refund workflow, partial refunds, and any unverified inventory reversal workflow.
6. Advanced multi-tenant administration, cross-tenant consolidated reporting, public self-service tenant provisioning, multi-region/HA and unmeasured tenant-capacity claims.
7. Existing-data migration from a live Supabase project; only an already-available owner-controlled offline artifact outside Supabase can be considered, otherwise data continuity stays NOT VERIFIED.
8. A signed/publisher Android release artifact, Play Console acceptance, or an update to an existing package identity until the exact certificate/package/version is verified. The observed successful Android job was debug-only compilation.

No CTA, schema/table, package dependency, old checklist, draft report or design document overrides these exclusions.

## 5. Acceptance matrix — fail closed at one exact integrated candidate SHA

Status meanings: **NOT VERIFIED** = evidence absent/inaccessible; **PARTIAL / BRANCH ONLY** = evidence exists but does not match the integrated candidate; **BLOCKED** = a known source/architecture mismatch; **PASS** may only be assigned after required evidence is attached to the exact candidate SHA, run ID and attempt.

| Gate | Priority | Owner | Required evidence | Dependencies | Initial status | Closure criteria |
|---|---|---|---|---|---|---|
| G-01 Scope authority and release version | P0 | Business owner + release manager | Signed/recorded first-release feature scope, explicit exclusions, target deployment channel, package identity, version and support policy | All workstreams’ estimates and constraints | NOT VERIFIED | Owner explicitly accepts scope and versioning policy. v1.0.0-rc1 remains a proposal until then. |
| G-02 Exact integrated candidate CI | P0 | Release engineering / QE | Candidate SHA, source/base/merge SHA, workflow revision, run ID + attempt, every required job, logs/artifacts and approved-stack fingerprint | Scope and all required workstream branches integrated through review | BLOCKED: main SHA has zero direct check-runs/status entries | Every required matrix row has executed_pass evidence on the same tested integrated candidate; no skipped/missing/stale/wrong-stack result. |
| G-03 Remove prohibited active Supabase runtime | P0 | Flutter + backend owner | Source/dependency/environment/workflow scan; functional Laravel auth/config/sync replacement; exact-SHA Flutter analysis/tests and packaged-artifact scan | Laravel auth/config/sync API | BLOCKED: Flutter login/config paths still reference Supabase | No active Supabase SDK/runtime/config; no fallback/dual-run; required functions work against Laravel on candidate SHA. Never connect to Supabase or run the legacy sync script. |
| G-04 Authentication, tenant membership and device authorization | P0 | Backend/security | API tests for unauthenticated, inactive user, wrong membership, wrong device/tenant, revoked device token, expired session and rate limits | G-03, PostgreSQL schema | NOT VERIFIED | Every negative test fails closed; actor/tenant/device are server-derived, not trusted from body IDs. |
| G-05 Five-layer config and workbook parity | P0 | Configuration/backend + QA | Exact 352-entry export/manifest and SHA-256; resolver fixtures for all layers, missing-field inheritance and POS-vs-Akuntansi separation; Flutter/API/Admin parity | G-03, authenticated Central API | BLOCKED: source workbook and tables exist but no active Laravel resolver route was found | Deterministic versioned output/hash; every parity and negative authorization test passes. |
| G-06 PostgreSQL migrations / schema lint | P0 | Backend/database | Fresh central + tenant PostgreSQL 17 migrations, migration-upgrade path, schema/constraint checks, route listing, locked Composer validation/install/platform/audit output | Accepted ADR stack and reviewed migration chain | PARTIAL / BRANCH ONLY: run 39131351376 passed on 6062df7…, not current integrated SHA | Fresh and upgrade tests pass on the exact candidate; no MariaDB acceptance substitution; failure remains fail-closed. |
| G-07 Actual PostgreSQL tenant isolation/provisioning | P0 | Backend/security/DB operations | Actual pg_roles, role attributes, owners, CONNECT/schema/table/sequence/default grants and PUBLIC privileges; tenant A cannot connect/read/write tenant B or central DB; retry, host spoof and worker reset tests | G-06, private provisioning boundary | PARTIAL / BRANCH ONLY: isolation probe passed in run 39131351376 on 6062df7… | Distinct DB and restricted runtime role per tenant proven with real grants on same candidate; normal web/queue has no provisioning privileges. |
| G-08 Atomic sale + stock + journal + audit | P0 | Accounting/inventory backend + QA | Fault injection at every write stage; posted balanced journal; no order/stock/journal/event partial state after failure; no oversell under concurrent last-stock requests | G-06, G-07, API identity, accepted COA/period policy | BLOCKED / NOT VERIFIED: current backend has no complete sale-posting endpoint/service at audited base | One DB transaction; two concurrent sales cannot oversell; all exception points roll back; journal and audit are durable together. |
| G-09 Idempotent server sync and conflict behavior | P0 | Backend/mobile | Same key + same payload replay returns identical receipt without duplicate effects; same key + different payload returns conflict; acknowledgement only after durable commit; parallel replay test | G-03, G-08 | BLOCKED: API route is currently platform-health only | Tests pass with separate PostgreSQL connections and real transaction races on candidate SHA. |
| G-10 Ledger invariants and financial policy | P0 | Accounting + backend + business owner | Balanced/unbalanced DB tests; posted journal/line immutability; reversing entry; locked COA and closed period; audit completeness; IDR integer semantics and rounding policy | G-06, canonical COA, approved tax/rounding policy | BLOCKED / NOT VERIFIED in backend; Flutter-level tests are not backend certification | DB boundary prevents unbalanced/invalid posted journals, changes to posted history, closed-period posting and missing audit event; finance owner signs off. |
| G-11 Secret/security baseline | P0 | Security/release engineering | Redacted secret scan, image/dependency audit, service credential separation, TLS/proxy/host validation, least privilege, no production secrets in mobile/client, alertable auth/audit behavior | Current architecture and deployment config | NOT VERIFIED | Complete review on exact candidate, no open critical/high issue accepted without owner-recorded risk exception. |
| G-12 Backup + restore / data continuity | P0 | Operations/DBA + business owner | Encrypted off-host central + tenant backup manifest, checksums, successful restore of central and selected tenant DBs, isolation after restore, duration/RPO/RTO; offline-export provenance if existing data is required | G-06/G-07, owner data decision | NOT RUN / NOT VERIFIED | A dated disposable restore drill succeeds; single-tenant restore does not overwrite other tenant data; business data continuity decision is explicit. |
| G-13 Isolated staging deploy + health checks | P0 | Operations/release engineering | Staging deployment ID, immutable image digest, TLS/host checks, readiness/health, authenticated smoke journey, migration transcript and redacted logs | G-02–G-12 | NOT RUN / NOT VERIFIED | Deployed artifact matches tested candidate; health/auth/tenant/sale journey passes in isolated staging. |
| G-14 Observability and alerting | P0 | Operations/security | Live evidence of health probes, structured redacted logs, metrics, database/queue saturation signal, backup/restore alert, auth/security alert test and recipient/route verification | G-13, approved thresholds | NOT VERIFIED | Synthetic failure/threshold tests raise and resolve alerts; no sensitive payload/secret leakage. |
| G-15 Rollback / forward recovery | P0 | Operations/release engineering | Disposable deployment rollback drill, immutable prior image, reversible/forward-only migration plan, DB recovery point, smoke tests after rollback | G-12/G-13 | NOT RUN / NOT VERIFIED | Rollback and recovery are executed and results documented on the candidate environment; no unsupported claim of DB downgrade safety. |
| G-16 UAT core journey and accounting sign-off | P0 | Business owner + UAT lead/accounting approver | Signed cases: login/device authorization, config, receive stock, sale, FEFO/FIFO, daily report, balanced journal, offline/retry, period close, failure rollback and tenant boundary | G-03–G-10, G-13 | NOT RUN / NOT VERIFIED | UAT has actor/date/build SHA, pass/fail outcomes and explicit acceptance of known limitations. |
| G-17 Scope/Go decision | P0 | Business owner | Written Go decision naming candidate SHA/version, scope, excluded items, channel, rollout guardrails and accepted residual risks | All P0 gates G-01–G-16 | PENDING OWNER | Owner signs only after release matrix has no open P0; this audit does not approve release. |
| G-18 Local inventory, FEFO/FIFO and local reports | P1 (becomes P0 if marketed as core production accounting) | Mobile + inventory/accounting QA | Exact-head test results for lot/no-lot, expired and held stock, partial lot use, costing precision, report/journal reconciliation, migration/rounding tests | G-02, UAT | PARTIAL: sources/tests exist; offline branch CI pass is not same-SHA SaaS acceptance | Owner accepts device-local scope; supported behavior and unsupported cases are clearly documented. |
| G-19 Android publisher artifact and package continuity | P1 (P0 for Play release) | Mobile release engineer | Signed AAB/APK, package/version, signing certificate fingerprint, Play Console validation and update-key continuity | G-02/G-03/G-17 | PARTIAL: a debug-only AAB compile check passed on another branch SHA | Exact release artifact is publisher-signed and verified; debug artifact is not distributed as a release. |
| G-20 Capacity/performance budget | P1 | Operations/backend | Reproducible workload, p50/p95/p99, errors, CPU/RAM/DB connections/disk, thresholds and headroom | G-06/G-07/G-13 | NOT RUN | Measured against owner-approved thresholds; no tenant capacity/SLA claim without evidence. |
| G-21 Supported device/hardware matrix | P2 / OUT OF SCOPE | Mobile + hardware QA | Physical-device model/OS matrix and repeated printer/scanner tests | Scope change approval | NOT RUN | Only becomes release-required if owner brings hardware integrations into scope. |
| G-22 AI, gateway, subscription and webhook extensions | P2 / OUT OF SCOPE | Product owner + relevant security/finance owners | Separate threat/risk model, reconciliation, consent/policy review, test matrix and exact-SHA acceptance | Explicit scope change | NOT RUN | No launch dependency until owner explicitly approves and its own P0 gates are satisfied. |

P0 means release-blocking. A P1 item becomes P0 when the owner markets or relies on it as a core capability of this release. P2 items above are explicit exclusions, not implied promises.

## 6. Go / No-Go rule

Issue **NO-GO** if any of these is true:

1. Any P0 row is open, missing evidence, stale, skipped, wrong-stack, or not executed on the same integrated candidate SHA.
2. Real PostgreSQL tenant isolation fails or has not been proven; central/tenant migration and database constraints have not passed the applicable clean/upgrade checks.
3. A posted journal can be unbalanced, edited/deleted, posted into a closed period, detached from its required audit event, or duplicated by retry; the order/stock/journal/event transaction can partially commit; a concurrent last-stock test can oversell.
4. Required secrets/access/security baseline is not reviewed; critical alerting is inactive; staging health and auth/smoke journeys do not pass.
5. Encrypted off-host backup plus successful restore, and rollback/forward-recovery rehearsal, are missing.
6. UAT/accounting acceptance is unsigned, or the business owner has not approved scope, channel, version, and known exclusions.
7. Current active Supabase runtime use remains in the product, or the candidate depends on a forbidden Supabase project/service.

A production recommendation can be reconsidered only after the matrix is regenerated against the actual integrated SHA and all P0 evidence is bound to that same revision. The earlier source-level/CI successes remain historical branch-specific evidence until re-run against that candidate.

## 7. Explicit owner decisions still required

1. **Product mode:** approve a compliant SaaS MVP scope vs a strictly local-only beta. Recommendation: do not call the build SaaS until Laravel auth, config and sale sync are active and tested.
2. **Release channel and identity:** Play Store, direct distribution, or both; package/application identity and whether this is a new app or update. Confirm accepted signing certificate before publishing any update.
3. **Commercial model:** confirm that subscription, paid entitlements, payment gateway and webhook are excluded from v1.0.0-rc1. Recommendation: exclude all four initially.
4. **Tenant/stock policy:** confirm whether v1 supports one active device per tenant or multiple concurrent devices. If multiple devices are allowed, approve explicit offline stock conflict semantics; offline devices cannot claim globally consistent stock without a policy.
5. **Accounting policy:** approve locked COA version, posting mappings, tax treatment, rounding, cost precision, period-close and correction/reversal/refund rules.
6. **Existing data:** declare clean-start acceptance or provide an already-available owner-controlled offline export outside Supabase with provenance/checksums. This audit does not create or request a new Supabase export.
7. **Operations targets:** set RPO/RTO, backup retention, restore frequency, security/alert recipients and performance threshold budget for the single-node KVM2 MVP.
8. **Final release decision:** a named business owner must accept the scope, excluded functionality, candidate SHA and residual risks after every P0 gate passes. This report is not that approval.

## 8. Disposition

- Keep this branch/report as an audit recommendation; do not merge, tag, deploy or signal go-live from it.
- Proposed RC label: v1.0.0-rc1 **only after** the P0 matrix is green on one integrated SHA. No tag currently exists or was created by this audit.
- Current recommendation remains **NO-GO**.
