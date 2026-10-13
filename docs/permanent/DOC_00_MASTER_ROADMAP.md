# BERKAH POS - MASTER ROADMAP DOKUMEN PERMANEN

Repository: `berkah-ajb-dev/Berkahtigaputeri`  
Live Admin: https://berkah-ajb-dev.github.io/Berkahtigaputeri/btp-admin/

## Canonical authority

Read `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` first.

The only canonical Final Pos configuration inheritance is:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

The canonical workbook is:

```text
config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx
```

`scripts/sync_excel_to_supabase.py` validates its structure and the exact `APP_CONFIG_EXPORT` inventory:

```text
1 global + 3 templates + 100 tenants + 140 services + 108 devices = 352 keys
```

Supabase configuration rows use:

```text
app_config(key PRIMARY KEY, value JSONB, updated_at)
```

No historical commit is a permanently frozen architecture authority. Current behavior is governed by the canonical architecture decision, tests, reviewed migrations, and the current repository HEAD.

## Product goal

Build a multi-tenant SaaS POS + accounting platform where each tenant can use independently configurable services:

- POS: cashier, barcode, payment, QRIS, printer/drawer, inventory and device behavior.
- Akuntansi: automatic journals, PPN, COA and reporting.

Tenant configuration must remain isolated, service-specific, auditable, versioned, and reproducible from the canonical configuration sources.

## Permanent-document principles

- `/docs/permanent/` contains the durable architecture and verification record.
- Historical documents must be explicitly labelled historical; they must not override current canonical decisions.
- Implementation, SQL/RPC, Admin, Flutter and CI must agree with the same contracts.
- Changes are made through feature/fix branches and pull requests, never by treating an old commit as immutable architecture.

## Canonical correction roadmap

The following phases are executed in order. A later phase must not redefine architecture established by an earlier phase without updating `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`.

### PHASE 1 - Canonical architecture declaration

- Rewrite architecture and agent-instruction documents.
- Remove stale inheritance rules that omit TEMPLATE.
- Establish `GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE` as the sole authority.

Acceptance:
- all agent-facing instructions point to the canonical decision;
- no active architecture instruction preserves a historical frozen-core rule;
- the 352-key workbook contract is documented consistently.

### PHASE 2 - Data-source ownership and synchronization

Decision target: the canonical workbook owns tenant, device, service and feature configuration data.

Acceptance:
- workbook sync updates `app_config` and required relational projections;
- Flutter feature access no longer depends on an unsynchronized `tenants.features` fallback;
- relational projections match workbook-derived configuration after sync.

### PHASE 3 - Admin / APK / RPC parity

Acceptance:
- Admin resolves TEMPLATE exactly like Flutter/RPC;
- effective configuration is service-specific;
- the same tenant/device/service produces identical effective configuration across Admin, APK and RPC.

### PHASE 4 - Fail-closed synchronization CI

Acceptance:
- missing Supabase credentials fail the sync job;
- sync failures fail the job;
- post-sync verification confirms exactly 352 canonical keys and verifies the key manifest/hash.

### PHASE 5 - Tenant isolation and authenticated effective-config access

Acceptance:
- anonymous direct reads of tenant/device/licence/app-config metadata are removed;
- effective-config access authenticates the caller and validates device-to-tenant ownership;
- RLS/auth documentation and APK verification describe the same model.

### PHASE 6 - Atomic configuration versioning

Acceptance:
- all normal configuration writes use an atomic expected-version RPC;
- Admin, Template Admin and sync behavior use documented version semantics;
- SQL seeds cannot silently reset a newer version to version 1.

### PHASE 7 - Re-certification and release documentation

Acceptance:
- historical verification is archived as historical;
- a new current-head verification document certifies the Final Pos architecture;
- APK verification includes TEMPLATE;
- release notes describe only behavior actually reachable from the current application entry UI;
- permanent-document indexes and table counts are correct.

## Protected green contracts

The correction program must not break these already-aligned contracts:

- FEFO physical allocation and FIFO financial costing are intentionally different.
- COA `1-1040` is Inventory and `5-5010` is COGS.
- Flutter version `1.1.0+2` remains aligned with Android `versionName 1.1.0` / `versionCode 2` unless intentionally version-bumped.
- GitHub Pages continues to publish `btp-admin/`.
