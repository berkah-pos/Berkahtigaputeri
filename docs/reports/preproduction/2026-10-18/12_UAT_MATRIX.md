# UAT / Cross-Subsystem Acceptance Matrix

**Snapshot:** 2026-10-20 (Asia/Jakarta)  
**Status:** **BLOCKED — do not sign off**  
**Repository:** berkah-pos/Berkahtigaputeri  
**Base SHA inspected:** 371b7fdf0bf672b37ceb1023e647f114221bf797  
**Workstream branch:** audit/preprod-uat-matrix-2026-10-18  
**PR:** [#89 — draft; UAT and compatibility matrix](https://github.com/berkah-pos/Berkahtigaputeri/pull/89)  
**Companion report:** [12_UAT_AND_COMPATIBILITY.md](12_UAT_AND_COMPATIBILITY.md)

## 1. Execution contract and evidence labels

This file is a reusable UAT plan and current status matrix, not a claim that its cases ran. The main source SHA was inspected read-only through GitHub. A local clone attempt failed with exit code 128 because the task container could not resolve github.com; there was no local test runtime, approved isolated staging URL, disposable PostgreSQL endpoint, synthetic test identities, email allowlist, browser automation, or physical test device available. No API request, transaction, account, tenant, email, database row or production resource was created or changed. No Supabase project was accessed.

Use only an isolated, disposable environment explicitly approved by its owner. Freeze and record the integrated candidate SHA, deployment ID, immutable image digest and migration version before testing. The source baseline SHA below is not a selected release candidate. The UAT PR is documentation-only; never infer a tested product build from the PR head. Each evidence package must contain a redacted run log or report and must not contain tokens, cookies, passwords, personal data or secret values.

| Label | Meaning in this matrix |
|---|---|
| **PASS** | Test executed on the exact integrated candidate SHA, expected result met, sanitized evidence linked, and all prerequisites/scope approvals satisfied. None awarded in this snapshot. |
| **FAILED — source gate** | Source inspection directly demonstrates a required source/contract gap. This is not a claim that an HTTP/runtime test was executed and failed. |
| **BLOCKED** | Required approval, API surface, isolated environment, identity or dependency is not available. |
| **NOT RUN** | Executable test has not been launched; no result/exit code is implied. |
| **CLAIMED** | Only asserted in historical documentation; not retested here. |
| **NOT APPLICABLE** | Only after a documented business-owner scope exclusion; no test is marked N/A without approval. |

### Current source / CI evidence inventory

- Exact main SHA: 371b7fdf0bf672b37ceb1023e647f114221bf797.
- Exact-SHA check-run query returned total_count 0; combined status was pending with no individual status entries. Actions query returned two successful dynamic Dependabot jobs (runs [39186055413](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39186055413) and [39184121515](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39184121515)); neither is application UAT or test-suite evidence.
- routes/api.php lines 5–11 only registers GET /api/v1/platform-health; no product journey route was found in that route file.
- pos-app/pubspec.yaml line 16 includes supabase_flutter, and pos-app/lib/main.dart lines 3–35 imports and initializes it. This conflicts with the accepted 2026-10-17 no-Supabase owner ADR.
- .github/workflows/canonical-workbook-validate.yml line 68 invokes scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352. This command/workflow was not run or dispatched. The CI/workflow owner must replace this path with a local no-network validator before allowing the workflow to execute.
- scripts/export_workbook_for_laravel.py contains source logic defining seven expected sheets, count targets 1/3/100/140/108, total 352, uniqueness, keyset MD5 and identifier/mapping validation. The workbook and validator were not executed; actual workbook inventory is NOT RUN / NOT VERIFIED.
- config/ci/required-check-matrix.json says it is “Specification only; not yet wired into CI.” It is not evidence that these tests run automatically.
- Historical run 39005405149 tested the earlier baseline SHA aab154f87342f2a02a1319e1d370ce831dbef522; it is not inherited as evidence for SHA 371b7fdf... or a UAT deployment.

## 2. Preconditions and acceptance gates

| Gate ID | Entry criterion | Required evidence | Current status | Responsible dependency |
|---|---|---|---|---|
| PRE-01 | Signed release scope and versioned acceptance oracle | Owner-approved product scope, features in/out, supported versions and business rules | **BLOCKED** | Business owner / release-governance owner |
| PRE-02 | Isolated staging/disposable environment identified | Environment ID/URL, owner, expiry/cleanup plan, non-production DB/storage proof | **BLOCKED** | SRE/environment owner |
| PRE-03 | Exact candidate identity frozen | Source SHA, successful required CI tied to same SHA, image digest and deployment record | **BLOCKED** | Release engineering |
| PRE-04 | Synthetic accounts and role matrix available | Two or more tenant fixtures, real supported role grants, devices, login access; no superuser substituted for tenant cases | **BLOCKED** | Auth/API + environment owner |
| PRE-05 | Email delivery explicitly authorized | Allowlisted test inboxes/domains and permission to send verification/reset messages | **BLOCKED** | Business/environment owner |
| PRE-06 | Workbook validation can run offline | Approved local validator/workflow, workbook fixture, no network/database writes | **BLOCKED** | CI/workbook owner |
| PRE-07 | Release browser/device scope approved | Browser/OS versions, Android device matrix, viewport thresholds and app update policy | **BLOCKED** | Business owner / QA / release owner |
| PRE-08 | Financial and inventory oracle approved | Expected price, tax, discount, rounding, stock costing, COA, journals, returns/reversals and report formulas | **BLOCKED** | POS/accounting business owner |
| PRE-09 | Offline multi-device stock policy approved | Quota/reservation/restriction/oversell-reconciliation decision; no unqualified global stock-consistency promise | **BLOCKED** | Business owner |
| PRE-10 | Recovery objective agreed | RPO/RTO and backup/file/keys scope | **BLOCKED** | Business owner + SRE |
| PRE-11 | Runtime routes/API exist and are compliant | Authenticated Laravel API, auth/session and tenant/device operations; no Supabase path | **FAILED — source gate** for inspected API route surface and Flutter Supabase source | Laravel API/Auth + Flutter migration owner |
| PRE-12 | UAT matrix is tied to one candidate SHA | Executed logs and evidence artifacts cite same SHA/image; old/stale runs excluded | **BLOCKED** | QA/release coordinator |

## 3. Identity, tenant and configuration journeys

| Test ID | Scenario / steps | Expected result (oracle) | Actual evidence / artifact | Status |
|---|---|---|---|---|
| AUTH-01 | Login with valid and invalid synthetic credentials for each supported role | Valid role gains only authorized session; invalid credentials are rejected without revealing account existence | No product auth endpoint or staging identity verified; no HTTP test executed | **BLOCKED** |
| AUTH-02 | Request password reset for an allowlisted test inbox; use valid, expired and replayed token | Only authorized one-time token works; expired/replayed token denied; no account enumeration; email sent only to allowlist | No reset route/test inbox; no email sent | **BLOCKED** |
| AUTH-03 | Verify email with valid, expired, replayed and tampered token | Valid token succeeds once; all invalid cases denied | Not executed; no route/runtime evidence | **NOT RUN** |
| AUTH-04 | Restore session after restart; logout/revoke; then replay expired/revoked session | Invalid session is denied; local pending sale is preserved | No Laravel session flow executed | **NOT RUN** |
| AUTH-05 | Enumerate roles actually supported by test environment and exercise allowed/forbidden actions | Server authorization matches owner-approved role matrix; unauthorized actions return documented 401/403 | Role set not established; do not invent role names or use superuser as stand-in | **BLOCKED** |
| TEN-01 | Provision tenant A and B with separate synthetic owners/members; concurrently retry creation and interrupt once | Unique immutable tenant identities; safe, idempotent retry; no deletion of pre-existing/unknown DB | No disposable PG17 target or identities; no provisioning test | **BLOCKED** |
| TEN-02 | Assign BASIC, PRO and ENTERPRISE template to synthetic tenants | Assignment/entitlements match owner-approved plan matrix; invalid template denied | Templates are in the written contract, but assignment behavior not executed | **NOT RUN** |
| TEN-03 | Assign POS and Accounting service separately; register devices to correct tenant | Each device/service association is server-validated and audited | No applicable product routes confirmed; no execution | **BLOCKED** |
| TEN-04 | From tenant A and B, attempt cross-tenant product/sale/stock/report/config/device/subscription reads and writes in both directions | Access denied in both directions using actual restricted PG17 runtime roles; no central DB access from tenant role | No real-role/grant execution evidence | **BLOCKED** |
| TEN-05 | Spoof tenant ID, device ID, tenant database name, Host and X-Forwarded-Host | Caller-supplied identifiers are not authority; invalid/mismatched host and context fail closed | No HTTP/runtime test | **NOT RUN** |
| TEN-06 | Disable membership/device/domain and repeat request while cache is warm | Next request follows documented invalidation bound; disabled identity cannot access data | No runtime/cache test | **NOT RUN** |
| TEN-07 | Attempt central-only route from tenant host and tenant route from central host | Cross-boundary route dispatch is rejected; no context bleed | No API/domain environment identified | **NOT RUN** |
| CFG-01 | Run approved no-network XLSX validation on actual workbook | Exact sheets: README_PRODUCTION, TEMPLATES, GLOBAL, TENANTS_MASTER, DEVICES, SERVICES, APP_CONFIG_EXPORT; unique 352 entries counted 1/3/100/140/108; identifiers and keyset hash pass; zero DB/network writes | Validator source exists; XLSX/command were not executed; legacy workflow currently invokes prohibited script | **NOT RUN / BLOCKED pending safe validator path** |
| CFG-02 | Set different sample values at GLOBAL, TEMPLATE, TENANT, SERVICE, DEVICE and omit selected lower-layer fields | Merge order exactly GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE; explicit value overrides one field; absent value inherits | No exact-candidate runtime result | **NOT RUN** |
| CFG-03 | Resolve POS then Accounting for the same synthetic tenant/device | Response contains only requested service-specific row; POS and Accounting are never co-merged | No effective-config API result | **NOT RUN** |
| CFG-04 | Request same tuple/version twice, then apply stale compare-and-swap update | Version/hash deterministic; stale update rejected without partial mutation | No API/database execution | **NOT RUN** |

## 4. POS, stock, reports, journal and audit trail

| Test ID | Scenario / steps | Expected result (oracle) | Actual evidence / artifact | Status |
|---|---|---|---|---|
| POS-01 | Create/edit/deactivate synthetic product; verify offline and API-facing state if in scope | CRUD validation is consistent; identifiers and Rupiah amounts use integer/fixed precision | Product API not observed in routes/api.php; no run | **BLOCKED** |
| STOCK-01 | Receive a lot with cost/expiry; sell across eligible lots; inspect stock movements | Physical allocation follows approved FEFO contract, financial costing follows FIFO where required; no negative/unexplained stock | No stock transaction/DB result | **BLOCKED** |
| POS-02 | Cashier cart → checkout once using synthetic/test mode only | One durable order/lines and local stock/journal/outbox effects in transaction; no real payment | Product checkout API not observed; no run | **BLOCKED** |
| POS-03 | Tap submit twice / concurrent duplicate same transaction ID | Exactly one sale and each required downstream effect; identical replay returns same result | No sync/sale API execution | **NOT RUN** |
| RPT-01 | Compare report totals against immutable source sales/lines, tax, discount and returns | Report totals equal sums from authorized tenant transaction source under approved date/rounding rules | No reports API/result or oracle approved | **BLOCKED** |
| RPT-02 | Compare stock report against movements/lots/reservations | Quantity-on-hand derives consistently from stock ledger and approved reservation policy | No stock/report transaction evidence | **NOT RUN** |
| LED-01 | Post journal generated by a test sale; inspect all journal lines | Every posted journal debit total equals credit total exactly; balances use Rupiah-safe representation | No executed journal posting/query | **NOT RUN** |
| LED-02 | Attempt direct update/delete of posted journal; apply correction/reversal path | Posted journals immutable; correction uses auditable compensating/reversing entry | No running backend journal API proven | **NOT RUN** |
| AUD-01 | Post, reject and reverse a synthetic transaction; inspect audit trail | Actor, timestamp, device ID, app version, action/outcome are present; data isolated by tenant; logs contain no secrets | Audit behavior not executed | **NOT RUN** |
| AUD-02 | Tenant A requests B's reports/audit export using guessed IDs | Denied and safe security event recorded without leaking B's content | No tenant API/role test | **NOT RUN** |

## 5. Offline, reconnect, retry, error handling and recoverability

| Test ID | Failure injection / steps | Expected result (oracle) | Actual evidence / artifact | Status |
|---|---|---|---|---|
| OFF-01 | On disposable on-disk SQLite: checkout, inject failure at each dependent write, reopen app/database | Sale, lines, stock movement, journal and outbox commit atomically or all roll back; no orphan rows | No local runtime/tests executed | **NOT RUN** |
| OFF-02 | Disable network before send; make sale; kill/restart app | Pending sale/outbox survives restart and remains explicitly pending | No device/on-disk test run | **NOT RUN** |
| SYNC-01 | Reconnect and submit event; disconnect after request leaves client uncertain | Server durably commits before ACK; client only marks accepted after receipt; retries bounded with backoff | No sync endpoint visible in inspected route surface; no run | **BLOCKED** |
| SYNC-02 | Send identical idempotency key + canonical payload repeatedly and concurrently | Same durable receipt, one sale, one set of stock/journal effects | No server receipt evidence | **BLOCKED** |
| SYNC-03 | Reuse key with different payload | Explicit deterministic conflict; accepted content not overwritten; conflict/audit state visible | No endpoint execution | **NOT RUN** |
| ERR-01 | Force timeout after simulated server commit but before client receives ACK | Retry returns previously committed receipt; no duplicate stock or journal mutation | No safe disposable API/runtime available | **NOT RUN** |
| ERR-02 | Inject HTTP 429/5xx, malformed body, invalid schema and permanent validation error | Retry only transient errors; permanent error becomes actionable; no hot retry loop or event loss | No HTTP client/runtime results | **NOT RUN** |
| ERR-03 | Expire/revoke session while outbox is pending; reauthenticate and retry | Server denies expired credentials; locally committed sale remains; retry policy follows approved authorization contract | No session runtime result | **NOT RUN** |
| ERR-04 | Disable account/device/domain/subscription while client has cached state | Server enforces current state; stale cache does not grant prohibited access; pending local data remains recoverable | No staging test or approved state policy | **BLOCKED** |
| ERR-05 | Restart Laravel server and queue worker during submission/retry; run tenant A then B in same long-lived worker | Accepted rows durable; no loss/duplication; DB connection, tenant context, cache, filesystem, guard and actor reset between jobs | No server/worker runtime to fault-inject | **NOT RUN** |
| REC-01 | Backup central DB, two tenant DBs, necessary private files and recovery metadata in disposable environment; restore | Checksums/counts/config manifest/journal balances pass; measure duration and compare with owner-approved RPO/RTO | No backup/restore run or artifact | **NOT RUN** |
| REC-02 | Restore one tenant independently while a peer tenant fixture is preserved | Only intended tenant and central mappings change; other tenant's rows and checksum unchanged | No single-tenant restore execution | **NOT RUN** |
| REC-03 | Roll application image backward/forward in disposable staging after approved migration scenario | Deployed image digest and source SHA match; recovery plan succeeds without silently losing accepted transactions | No deployed image/rollback evidence | **NOT RUN** |

## 6. Browser / mobile / compatibility coverage

The following is a proposed minimum coverage set, not an approved support matrix and not tested. Before execution, business/release owner must confirm these targets are in release scope. Record actual OS build, browser/app version, device model, ABI, display/DPI, viewport, orientation, network conditions, tested SHA/image ID and sanitized screenshot/log path for each run. Do not publish auth headers, cookies or tokens in evidence.

| Compatibility ID | Proposed target | Key journeys / fault cases | Current measured compatibility result | Evidence |
|---|---|---|---|---|
| COMP-01 | Desktop Chrome stable; viewport 1366×768 and 1920×1080 | Login, role navigation, config, products, stock, reports, session expiry, tenant boundary | **NOT RUN**; viewport is only proposed | No browser run/screenshot/HAR |
| COMP-02 | Desktop Edge stable; 1366×768 | Key privileged and tenant journeys, keyboard/navigation, error states | **NOT RUN**; not yet approved in support scope | No browser run |
| COMP-03 | Android Chrome stable, mobile viewport near 390×844 | Responsive web/admin journeys if a web client is in release scope; network toggle/reconnect | **NOT RUN**; viewport is only proposed | No Android browser test |
| COMP-04 | Physical Android phone on minimum supported Android version | Install exact candidate, fresh install, offline checkout, restart, reconnect, reports | **NOT RUN**; model/OS build not available | No device transcript, screenshot or logcat |
| COMP-05 | Physical Android phone on current supported Android version | Upgrade from accepted prior build only if package ID/signing cert and release scope are confirmed; repeat key journeys | **NOT RUN**; update certificate path not verified | No AAB/APK or signature comparison |
| COMP-06 | Narrow viewport/orientation and poor-connectivity case on approved device/browser | Layout overflow, reachable checkout controls, loss/recovery of network, duplicate tap | **NOT RUN** | No session artifact |

**Coverage actually executed in this workstream:** no desktop browser, mobile browser, browser automation, physical Android install, emulator, screenshot, video, HAR or device log. Flutter CI workflow source is not proof that an artifact built or ran. A successful Android bundle compile, if observed in a future CI job, still does not prove physical-device compatibility or an accepted upgrade signature.

## 7. Defect register (ordered by severity)

These are test blockers/source acceptance defects, not claims of a production exploit. Source-level “FAILED” is not mislabeled as executed runtime failure. Fix only in the named owner workstream and close with exact-SHA negative/regression evidence.

| Defect ID | Severity / confidence | Finding and source evidence | Expected vs actual | Reproduction / actual result | Routed owner |
|---|---|---|---|---|---|
| UAT-DEF-01 | **P1 / High** | [routes/api.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/routes/api.php#L5-L11), lines 5–11, registers only GET /v1/platform-health. | Expected release journeys need authenticated routes for auth, tenant/device/config, POS/stock, reports/journal and sync. Actual route file has only platform health. | Source inspection reproducible; no staging HTTP request was executed. Acceptance gate **FAILED — source gate**, runtime **NOT RUN**. | Laravel Central API/Auth owner |
| UAT-DEF-02 | **P1 / High** | [pubspec.yaml](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/pubspec.yaml#L16) line 16 and [main.dart](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/pos-app/lib/main.dart#L3-L35) lines 3/11/35 contain Supabase SDK/import/initialization. | Expected no-Supabase Flutter runtime talking to authenticated Laravel APIs. Actual path remains in source, contrary to accepted owner ADR. | Source inspection only; no Supabase connection was made. Compliance gate **FAILED — source gate**. | Flutter migration / Laravel API owner |
| UAT-DEF-03 | **P1 / High** | DOC_14/ADR require actual PG17 role/grant tests and adversarial tenant A↔B denials. No qualifying exact-candidate execution/evidence is available in this workstream; tests/source presence alone is not accepted. | Expected independent DB/runtime roles and proven denial to central/other tenant. Actual security acceptance remains unverified. | No DB access, role query or adversarial test executed; no runtime exploit reproduced. **BLOCKED / NOT RUN**, not a demonstrated runtime privilege bypass. | PostgreSQL provisioning/security + tenancy API owner |
| UAT-DEF-04 | **P1 / High** | [canonical-workbook-validate.yml](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/.github/workflows/canonical-workbook-validate.yml#L58-L68), line 68, invokes prohibited scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352. | Expected local read-only workbook validation with no Supabase usage. Actual workflow source invokes a banned legacy script. | Command/workflow was deliberately not run or dispatched. **FAILED — workflow-policy source gate**. Remediation must be in CI owner PR. | CI/workflow + workbook owner |
| UAT-DEF-05 | **P2 / High** | No identified/approved staging URL, environment ID, synthetic identities, email allowlist, browser automation or physical device evidence was available during this run. | Expected isolated, permissioned UAT environment and safe fixtures. Actual prerequisites absent. | No tests attempted against production/shared services. **BLOCKED**. | SRE/environment + release owner |
| UAT-DEF-06 | **P2 / High** | No exact-candidate end-to-end reconciliation/report, durable sync receipt, recovery/restore or browser/device test artifact exists in this workstream snapshot. | Expected order totals, inventory ledger, debit=credit, audit metadata, idempotency and restore proof. Actual: none executed. | **NOT RUN**; no runtime failure can be inferred from absent evidence. | POS/accounting + sync/API + SRE owners |
| UAT-DEF-07 | **P2 / High** | [required-check-matrix.json](https://github.com/berkah-pos/Berkahtigaputeri/blob/371b7fdf0bf672b37ceb1023e647f114221bf797/config/ci/required-check-matrix.json#L1-L20) line 3 says specification-only/not wired; line 143 references a contract-test file not found in source retrieval. | Expected required fail-closed gate bound to candidate SHA. Actual wiring/path existence not proven. | Source metadata inspected; matrix not executed. **BLOCKED / NOT VERIFIED**. | CI/release coordinator |

No P0 was assigned: no live runtime exploit or production compromise was reproduced in this workstream. P1 classification describes release blockers and prohibited source control behavior, not confirmed exploitation.

## 8. Evidence and command execution ledger

| Command / check | Intended environment | Actual execution | Exit/status | Sanitized artifact |
|---|---|---|---|---|
| git clone --depth 1 --branch main https://github.com/berkah-pos/Berkahtigaputeri.git /tmp/Berkahtigaputeri | Task container setup | Attempted; DNS/network lookup of github.com failed; no checkout | **Exit 128 — FAILED setup** | Error summary only in companion report; no secret data |
| GitHub API GET /repos/berkah-pos/Berkahtigaputeri/commits/main | Read-only source baseline | Executed via connected GitHub repository interface | **Success; returned SHA 371b7fdf…** | Main commit URL in report |
| GitHub API GET /repos/berkah-pos/Berkahtigaputeri/commits/371b7fdf…/check-runs | Exact-SHA CI status | Executed read-only | **Success; total_count 0** | API result summarized in report |
| GitHub API GET /repos/berkah-pos/Berkahtigaputeri/actions/runs?head_sha=371b7fdf…&per_page=100 | Exact-SHA workflow inventory | Executed read-only | **Success; 2 dynamic Dependabot runs only** | Run URLs above; not test logs |
| python3 scripts/export_workbook_for_laravel.py --validate-only | Local checkout with XLSX, no network/DB | **NOT RUN** — local checkout unavailable | **N/A** | None |
| PYTHONPATH=. python -m unittest discover -s scripts/tests -p 'test_*.py' | Local isolated Python environment | **NOT RUN** — local checkout unavailable | **N/A** | None |
| composer validate --strict --no-check-publish and composer audit --locked --no-interaction | Exact candidate, PHP 8.4 | **NOT RUN** locally | **N/A**; historical baseline evidence is other SHA only | None from this workstream |
| php artisan route:list --path=api/v1 and php artisan test | Laravel + disposable PG17 | **NOT RUN** — no local checkout/runtime/PG17 disposable endpoint | **N/A** | None |
| php artisan test --filter=TenantProvisioningPostgresGrantsTest | PG17 with actual restricted synthetic DB roles | **NOT RUN** — test/runtime/grants not available | **N/A** | None |
| flutter analyze --no-pub, flutter test --no-pub --reporter expanded, flutter build appbundle --debug --no-pub | Exact candidate Flutter/Android SDK environment | **NOT RUN** locally | **N/A**; source workflow not execution evidence | None |
| Browser/mobile/API E2E, DB reconciliation, fault injection, backup/restore | Approved isolated staging/disposable | **BLOCKED / NOT RUN** | **N/A** | No screenshot/HAR/network logs/JUnit/DB snapshot/restore artifacts |
| python scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352 or workbook CI dispatch | Prohibited by current owner ADR/AGENTS | **NOT RUN by design** | **NOT APPLICABLE to this audit; do not execute** | None |

**No invented exit codes:** all planned but unlaunched tests have exit status N/A, not zero. The only command above with a concrete failed exit code is the setup clone attempt (128). The two GitHub dynamic workflow runs each report completed/success and attempt 1, but their scope does not include this UAT.

## 9. Business-owner sign-off checklist

These are approval decisions and data oracles, not technical tests. They remain unsigned at this snapshot.

- [ ] Approve RC scope, version/version code, features in/out and known limitations.
- [ ] Confirm supported app roles and approve role/permission matrix for tenant setup, template/service/device assignment, cashier, stock receipt, reporting, journals and admin.
- [ ] Approve BASIC/PRO/ENTERPRISE entitlement matrix, subscription suspend/expiry/offline policy and data-read behavior.
- [ ] Approve sale, price, PPN, discounts, returns/refunds, rounding and report-total formulas using synthetic expected values.
- [ ] Approve chart-of-accounts mappings, journal posting/immutability and reversal/correction behavior; require debit=credit per posting.
- [ ] Approve offline multi-device stock policy; do not promise strong global stock correctness while independent devices are disconnected without reservation/quota/reconciliation rules.
- [ ] Approve reset/verification email recipients and authorize test messages to an explicit allowlist.
- [ ] Approve desktop/mobile browser/OS/device/viewport support matrix and minimum supported versions.
- [ ] Provide/approve isolated environment ID, synthetic identities, owner, test window, data disposal and rollback/cleanup.
- [ ] Approve data-continuity scope. Only an already existing owner-controlled offline export outside Supabase may be used; absent artifact means migration remains NOT VERIFIED.
- [ ] Approve RPO/RTO, backup coverage and restore acceptance criteria.
- [ ] Review all open P1/P2 defects and residual risks. Only accountable owner may issue release Go/No-Go after required technical evidence exists.

## 10. Final disposition

**Recommendation: BLOCKED — no UAT sign-off, release acceptance, merge approval or go-live authorization.** The matrix becomes eligible for execution only after PRE-01 through PRE-10 and PRE-12 have the required evidence and product/API/CI blockers are resolved by their respective owners. Every test must then be rerun on one integrated candidate SHA/image; tests from different PR heads, wrong database engines, or prior baseline builds must not be aggregated into a synthetic green result.

UAT owns the test plan and evidence quality only. Implementation owners own defects; this workstream makes no cross-scope source fixes.
