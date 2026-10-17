# Berkah Tiga Puteri POS

**Canonical repository:** [`berkah-pos/Berkahtigaputeri`](https://github.com/berkah-pos/Berkahtigaputeri)  
**Current owner decision:** [Hostinger KVM2 + Coolify, Laravel, PostgreSQL 17, no Supabase](docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md).  
**Status snapshot:** 2026-10-16, canonical `main` baseline `d7ee23cfaada3405416b01d9e127e32b07fb1a38`

Berkah POS is a local-first POS and accounting application whose configuration contract is defined by the canonical 352-entry workbook. The current owner decision is explicit: Hostinger KVM2 + Coolify, Laravel/PHP 8.4 and private PostgreSQL 17, with a reasonable measured scale-up path. No Supabase product or project access is allowed, including read-only. The accepted target and the currently implemented runtime are different states; do not describe the target as active merely because the ADR or open PRs exist.

## Source of truth and delivery status

| Category | Status | Evidence boundary |
|---|---|---|
| **Implemented on `main`** | Flutter remains Supabase-backed; local-first SQLite flows exist. | `pos-app/pubspec.yaml` includes `supabase_flutter`; `pos-app/lib/main.dart` initializes Supabase; `ConfigService` uses the authenticated Supabase client. The root has no `composer.json` or `composer.lock` at this baseline. |
| **Accepted target design** | Laravel Central API on KVM2/Coolify with PostgreSQL 17, a central DB and a separate DB/restricted runtime role per tenant. | Owner ADR PR [#49](https://github.com/berkah-pos/Berkahtigaputeri/pull/49) is merged. The ADR selects PHP 8.4, Laravel 13, Filament 5, Sanctum and `stancl/tenancy` v3.10.1 as the initial locked candidate. This is a decision, not implementation or deployment proof. |
| **Implementation only on open branches/PRs** | Unmerged proposals and candidates only. | [PR #41](https://github.com/berkah-pos/Berkahtigaputeri/pull/41) is based on the superseded Laravel 11/PHP 8.3/MariaDB direction. [PR #50](https://github.com/berkah-pos/Berkahtigaputeri/pull/50) contains a newer dependency candidate but its tenant tests remain MariaDB-based and fail; PostgreSQL provisioning is not verified. [PR #48](https://github.com/berkah-pos/Berkahtigaputeri/pull/48) and [PR #52](https://github.com/berkah-pos/Berkahtigaputeri/pull/52) contain Flutter migration work that is not on `main`. |
| **Executed CI** | Limited, candidate-specific, and mixed. | At PR #48 head `6e31574ecc04ecae6a535fe409cf415ec18655cc`, workbook validation and the dedicated Flutter checks passed, while Canonical POS CI and KVM2 Laravel Backend CI failed. At PR #50 current head on 2026-10-16 (`29127e8ecc9d2c4253939e26a1aa54a59a07cbff`), Canonical Workbook Validation (#38914169711) passed while Tenant Grant Security (#38914169628), Canonical POS App CI (#38914169548), and KVM2 Laravel Backend CI (#38914169687) failed. Results from its earlier `e108f5629d688ac2376f77ef1ebdc505501b1d60` candidate are historical, not current-head evidence. These results do not establish aggregate acceptance. |
| **Historical source record** | An earlier owner decision designated a Supabase project. | The dated report is historical only. The latest ADR prohibits accessing or using either Supabase project. Existing-data continuity can only use an already available owner-controlled offline export outside Supabase; otherwise it remains NOT VERIFIED. |
| **Production deployment/acceptance** | **NOT RUN / NOT VERIFIED** | No verified KVM2/Coolify production deployment, production cutover, production acceptance or completed migration is claimed. |

For the dated revision-by-revision correction and validation boundaries, see [the source-of-truth correction report](docs/reports/SOURCE_OF_TRUTH_ALIGNMENT_CORRECTION_2026-10-16.md).

## Canonical configuration contract

Read [DOC_00 — Canonical Final POS Configuration Contract](docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md). The only supported effective-configuration inheritance is:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

The canonical workbook is `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`. The exported inventory is exactly 352 entries: 1 global, 3 templates (`BASIC`, `PRO`, `ENTERPRISE`), 100 tenants, 140 services and 108 devices. Resolve one requested service at a time; do not merge POS and Akuntansi service rows into one effective configuration.

The legacy script `scripts/sync_excel_to_supabase.py` is mutation-capable and prohibited: never execute it or provide credentials. Historical SQL/functions/schemas/RLS and past source-designation reports may remain as audit material only; they are not a live source, migration path or permission to connect. Do not erase history or execute archived SQL. The current Flutter client still contains Supabase integration and must be migrated to tested Laravel API calls in a dedicated implementation PR.

## Runtime and documentation authority

- **Platform, engine and stack:** the accepted [owner ADR](docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md).
- **Detailed target topology and acceptance gates:** [DOC_14](docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), subordinate to the ADR.
- **Configuration inheritance and workbook:** [DOC_00](docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md).
- **Platform, hosting and no-Supabase policy:** [Latest owner ADR](docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md).
- **Execution order:** [master roadmap](docs/permanent/DOC_00_MASTER_ROADMAP.md).
- **Document index and evidence rules:** [permanent-document index](docs/permanent/README.md).
- **Flutter app:** `pos-app/`; `main` still contains legacy Supabase client code and is not yet compliant with the latest owner decision. Do not supply Supabase credentials or call its services. Replace it with the Laravel API and validate before a compliant release.

Work on a dedicated branch and submit a reviewed pull request. Keep historical Supabase paths and reports, mark them as historical/current-source inputs accurately, and never rewrite a past report to make it look green. Source presence, target design, a limited green workflow, staging metadata and production acceptance are distinct claims. Unexecuted or stale-head checks remain **NOT RUN / NOT VERIFIED**.
