# Source-of-truth alignment correction — 2026-10-16

**Report date:** 2026-10-16  
**Inspected baseline:** `main` at `d7ee23cfaada3405416b01d9e127e32b07fb1a38`  
**Accepted decision:** [ADR-2026-10-16 owner architecture decision](../permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md), accepted by merged [PR #49](https://github.com/berkah-pos/Berkahtigaputeri/pull/49)  
**Purpose:** Correct contradictory/current-state documentation without rewriting historical reports or implying implementation, CI, staging or production acceptance that has not occurred.

## 1. Status taxonomy and findings

| Required status category | Finding at the inspected baseline / candidate revisions | Correct wording |
|---|---|---|
| **(1) Implemented on `main`** | Source inspection of [`pos-app/pubspec.yaml`](https://github.com/berkah-pos/Berkahtigaputeri/blob/d7ee23cfaada3405416b01d9e127e32b07fb1a38/pos-app/pubspec.yaml), [`pos-app/lib/main.dart`](https://github.com/berkah-pos/Berkahtigaputeri/blob/d7ee23cfaada3405416b01d9e127e32b07fb1a38/pos-app/lib/main.dart) and [`config_service.dart`](https://github.com/berkah-pos/Berkahtigaputeri/blob/d7ee23cfaada3405416b01d9e127e32b07fb1a38/pos-app/lib/core/config/config_service.dart) shows `supabase_flutter`, `Supabase.initialize`, Supabase email/password session handling and the Supabase-backed effective-config client. The repository root has no `composer.json` or `composer.lock` at this SHA. The main-branch app has local-first SQLite behavior, but this is not Laravel cloud-sync acceptance. | Flutter on `main` remains Supabase-backed. The Laravel runtime is not implemented on `main`; no root Composer application baseline is present at this commit. |
| **(2) Target design accepted in an ADR** | Owner ADR PR [#49](https://github.com/berkah-pos/Berkahtigaputeri/pull/49) merged on 2026-10-16. It selects Laravel Central API on KVM2/Coolify, PostgreSQL 17, a central database plus tenant databases/restricted roles, PHP 8.4, Laravel 13, Filament 5, Sanctum and `stancl/tenancy` v3.10.1 as the initial candidate. | **Accepted target design**, not a statement of implemented or deployed runtime. |
| **(3) Implementation only on an open branch/PR** | [#41](https://github.com/berkah-pos/Berkahtigaputeri/pull/41) is an unmerged pre-ADR Laravel 11/PHP 8.3/MariaDB proposal. [#50](https://github.com/berkah-pos/Berkahtigaputeri/pull/50) is an unmerged PHP 8.4/Laravel 13 dependency candidate, but its tenant-grant implementation/tests remain MariaDB-specific and PostgreSQL 17 provisioning is not verified. [#47](https://github.com/berkah-pos/Berkahtigaputeri/pull/47) is a RED isolation candidate; [#48](https://github.com/berkah-pos/Berkahtigaputeri/pull/48) and [#52](https://github.com/berkah-pos/Berkahtigaputeri/pull/52) contain Flutter transition changes but are not on `main`. [#53](https://github.com/berkah-pos/Berkahtigaputeri/pull/53) is a draft acceptance-evidence matrix; [#54](https://github.com/berkah-pos/Berkahtigaputeri/pull/54) is draft operational planning/runbooks. | Treat every change on these branches as an unmerged candidate. Do not describe open-PR source as the current implementation or approved runtime. |
| **(4) Executed CI evidence** | Current candidate evidence is mixed and bound to the inspected candidate revisions. Details and direct run links are in §2 below. Workbook or dedicated Flutter successes coexist with failures in broader POS/backend or tenant-grant checks. | Report each workflow/job result and tested SHA. Do not infer an aggregate green result, backend readiness, target-engine parity or deployment acceptance from a partial pass. |
| **(5) Staging observations** | The ADR records two accessible Supabase projects labelled staging and staging-clone. Their migration/catalog metadata differ materially (139 versus 12 migration-history records, with different relation/routine/trigger/extension counts). Neither project has been identified as the authoritative source of record or confirmed as production. No live migration or corrective resource mutation was part of this work. | These are **staging observations** and unresolved source-identification evidence, not production proof or authority to mutate either project. Source-of-truth identification and a sanitized, verified inventory/export remain blockers. |
| **(6) Production deployment/acceptance** | No direct evidence establishes a deployed Laravel/PostgreSQL runtime on KVM2/Coolify, completed data migration, production cutover, production tenant isolation, successful restore or release acceptance. | **NOT RUN / NOT VERIFIED.** No production-readiness or launch claim is made. |

## 2. Exact candidate CI snapshot

The following run results were retrieved by querying GitHub Actions runs associated with the listed commit. They are evidence about those candidate revisions only.

| Candidate head SHA | Workflow/run | Result |
|---|---|---|
| PR #48 — `6e31574ecc04ecae6a535fe409cf415ec18655cc` | [Canonical Workbook Validation #38856048876](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048876) | **PASS** |
| PR #48 — same SHA | [Phase 5 Flutter Transition Checks #38856048883](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048883) | **PASS**, dedicated Flutter scope only |
| PR #48 — same SHA | [KVM2 Laravel Backend CI #38856048750](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048750) | **FAIL** |
| PR #48 — same SHA | [Canonical POS App CI #38856048817](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38856048817) | **FAIL** |
| PR #50 — `e108f5629d688ac2376f77ef1ebdc505501b1d60` | [Canonical Workbook Validation #38886111750](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38886111750) | **PASS** |
| PR #50 — same SHA | [Phase 2 Tenant Grant Security CI #38886111736](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38886111736) | **FAIL** |
| PR #50 — same SHA | [Canonical POS App CI #38886111728](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38886111728) | **FAIL** |
| PR #50 — same SHA | [KVM2 Laravel Backend CI #38886111739](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38886111739) | **FAIL** |
| PR #52 — `ef3a71894db8461a596db5cd51b6bdf764c8f039` | [Phase 5 Flutter Transition Checks #38900260816](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38900260816) | **PASS**, dedicated Flutter scope only |
| PR #52 — same SHA | [Canonical POS App CI #38900260866](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38900260866) | **FAIL** |
| PR #52 — same SHA | [KVM2 Laravel Backend CI #38900260758](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38900260758) | **FAIL** |
| PR #53 — `091594a18a0e648d557874066127fd5d24c83a42` | [Canonical Workbook Validation #38906173717](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38906173717) | **PASS**; not aggregate application acceptance |
| PR #54 — `94e0f3c0eb170f41149aa8b456b67e2fbeb096c5` | No workflow run returned for this revision in the inspected result | Planning-only documentation; no staging execution claimed |

PR #50's own evidence describes failed MariaDB tenant-grant tests and explicitly leaves PostgreSQL provisioning, grants and tenant A→B denial **NOT VERIFIED**. Do not treat a successful package install/image smoke or a workbook/Flutter job as a substitute for those gates.

## 3. Roadmap numbering reconciliation

The master roadmap's **Phase 0–Phase 7** numbering is canonical. Historical labels in stacked PR titles are retained without rewriting them; they refer to an earlier branch sequence and do not override the accepted ADR or roadmap. The master roadmap now includes a crosswalk for PRs #41, #45–#54, including the MariaDB-to-PostgreSQL mismatch.

## 4. Malformed duplicate preservation

The malformed duplicate's current-main reference search found one in-repository path reference: `docs/permanent/README.md`. That reference was changed to the archive location. The file was moved, not discarded, to `docs/archive/superseded/DOC_14_MALFORMED_DUPLICATE_PROPOSAL_2026-10-15.md`; its original proposal date and body are retained with an archive note. The canonical document remains `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`.

No historical CI/evidence report or accepted ADR was rewritten to manufacture a pass. The correction updates source-of-truth guidance and adds this dated correction report; no staging or production resources were changed.

## 5. Validation record

This report is the record for the documentation alignment PR. The implementation and PR statuses above are source/metadata observations, not fresh application test execution. Application/PHPUnit/Flutter integration suites were not rerun as part of this documentation-only change. Relative-link checks, documentation contract assertions and post-edit source/reference searches are to be recorded against the completed PR head; a missing result remains **NOT RUN / NOT VERIFIED**.
