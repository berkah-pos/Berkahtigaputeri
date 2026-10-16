# Berkah Tiga Puteri POS

**Canonical repository:** [`berkah-pos/Berkahtigaputeri`](https://github.com/berkah-pos/Berkahtigaputeri)  
**Architecture decision:** [Owner ADR — Laravel Central API + PostgreSQL 17](docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md)  
**Status snapshot:** 2026-10-16, canonical `main` baseline `d7ee23cfaada3405416b01d9e127e32b07fb1a38`

Berkah POS is a local-first POS and accounting application whose configuration contract is defined by the canonical 352-entry workbook. The accepted target architecture and the currently implemented runtime are different states; do not describe the target as active merely because the ADR or open PRs exist.

## Source of truth and delivery status

| Category | Status | Evidence boundary |
|---|---|---|
| **Implemented on `main`** | Flutter remains Supabase-backed; local-first SQLite flows exist. | `pos-app/pubspec.yaml` includes `supabase_flutter`; `pos-app/lib/main.dart` initializes Supabase; `ConfigService` uses the authenticated Supabase client. The root has no `composer.json` or `composer.lock` at this baseline. |
| **Accepted target design** | Laravel Central API on KVM2/Coolify with PostgreSQL 17, a central DB and a separate DB/restricted runtime role per tenant. | Owner ADR PR [#49](https://github.com/berkah-pos/Berkahtigaputeri/pull/49) is merged. The ADR selects PHP 8.4, Laravel 13, Filament 5, Sanctum and `stancl/tenancy` v3.10.1 as the initial locked candidate. This is a decision, not implementation or deployment proof. |
| **Implementation only on open branches/PRs** | Unmerged proposals and candidates only. | [PR #41](https://github.com/berkah-pos/Berkahtigaputeri/pull/41) is based on the superseded Laravel 11/PHP 8.3/MariaDB direction. [PR #50](https://github.com/berkah-pos/Berkahtigaputeri/pull/50) contains a newer dependency candidate but its tenant tests remain MariaDB-based and fail; PostgreSQL provisioning is not verified. [PR #48](https://github.com/berkah-pos/Berkahtigaputeri/pull/48) and [PR #52](https://github.com/berkah-pos/Berkahtigaputeri/pull/52) contain Flutter migration work that is not on `main`. |
| **Executed CI** | Limited, candidate-specific, and mixed. | At PR #48 head `6e31574ecc04ecae6a535fe409cf415ec18655cc`, workbook validation and the dedicated Flutter checks passed, while Canonical POS CI and KVM2 Laravel Backend CI failed. At PR #50 head `e108f5629d688ac2376f77ef1ebdc505501b1d60`, workbook validation passed while tenant-grant, POS and backend checks failed. These results do not establish aggregate acceptance. |
| **Staging observations** | Supabase staging-labelled resources were observed; authoritative source is unresolved. | The ADR records materially different migration/catalog footprints across the accessible staging and staging-clone projects. Neither has been confirmed as production/source of record. This is observation, not approval to migrate or mutate either resource. |
| **Production deployment/acceptance** | **NOT RUN / NOT VERIFIED** | No verified KVM2/Coolify production deployment, production cutover, production acceptance or completed migration is claimed. |

For the dated revision-by-revision correction and validation boundaries, see [the source-of-truth correction report](docs/reports/SOURCE_OF_TRUTH_ALIGNMENT_CORRECTION_2026-10-16.md).

## Canonical configuration contract

Read [DOC_00 — Canonical Final POS Configuration Contract](docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md). The only supported effective-configuration inheritance is:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

The canonical workbook is `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`. The exported inventory is exactly 352 entries: 1 global, 3 templates (`BASIC`, `PRO`, `ENTERPRISE`), 100 tenants, 140 services and 108 devices. Resolve one requested service at a time; do not merge POS and Akuntansi service rows into one effective configuration.

The legacy script `scripts/sync_excel_to_supabase.py` currently contains a Supabase REST/RPC write path when invoked with cloud credentials. Treat it as a legacy main-branch write path, **not** as a read-only validator or the target Laravel importer; do not run it against an unknown/shared source as part of this work. Retain it, related SQL/functions/schemas/RLS and available project data as implementation/migration evidence until the source is identified and an approved replacement, verified export/backup, parity, rollback and explicit retirement decision exist. Do not erase or blindly execute historical migration inputs.

## Runtime and documentation authority

- **Platform, engine and stack:** the accepted [owner ADR](docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md).
- **Detailed target topology and acceptance gates:** [DOC_14](docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), subordinate to the ADR.
- **Configuration inheritance and workbook:** [DOC_00](docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md).
- **Execution order:** [master roadmap](docs/permanent/DOC_00_MASTER_ROADMAP.md).
- **Document index and evidence rules:** [permanent-document index](docs/permanent/README.md).
- **Flutter app:** `pos-app/`; its current `main` runtime remains Supabase-backed until a reviewed migration actually merges.

Work on a dedicated branch and submit a reviewed pull request. Keep historical Supabase paths and reports, mark them as historical/current-source inputs accurately, and never rewrite a past report to make it look green. Source presence, target design, a limited green workflow, staging metadata and production acceptance are distinct claims. Unexecuted or stale-head checks remain **NOT RUN / NOT VERIFIED**.
