# Permanent Documentation — KVM2 Canonical Authority

This directory contains durable architecture, security, migration and verification records. Historical evidence never certifies current deployment or production readiness.

## Mandatory read order

1. Root `AGENTS.md` — mandatory preflight, branch/PR discipline and evidence contract.
2. `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — logical config contract and canonical 352-key workbook inventory.
3. `DOC_00_MASTER_ROADMAP.md` — ordered KVM2/Laravel migration and acceptance gates.
4. `DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md` — local-first, transaction, tenant boundary and evidence rules.
5. `DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` — current app/backend implementation status.
6. `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` — runtime architecture, deployment, tenant DB isolation and legacy backend retirement.
7. `DOC_01_3_LAYER_CONFIG.md` — retained compatibility name for the five-layer config contract.
8. `scripts/export_workbook_for_laravel.py` — executable source-workbook validator/export contract.
9. Relevant source, migrations, tests, security reports and runbooks scoped to the task.

DOC_14 must exist under the exact canonical filename above. DOC_00 remains authoritative for logical precedence only; AGENTS.md and DOC_14 govern runtime database/auth/deployment choices.

## Canonical logical model

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

Workbook: `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`.

```text
1 global + 3 templates + 100 tenants + 140 service rows + 108 devices = 352 keys
```

Sorted keyset MD5: `1fd3d64219ecc7c333453c20da80e295`.
Canonical template IDs: `BASIC`, `PRO`, `ENTERPRISE`.

## Runtime architecture

- Laravel 11 / PHP 8.3 / Filament 3 / Sanctum / stancl/tenancy v3.
- MariaDB 11 on one private server, with `berkahpos_central` and a distinct `berkahpos_tenant_{id}` DB per tenant.
- Mobile client remains local-first with SQLite; active cloud runtime uses authenticated Laravel APIs.
- Effective config endpoint: `GET /api/v1/effective-config?tenant_id=&device_id=&service=`.
- Deployment target: Hostinger KVM2 + Coolify; app health check `GET /up`.
- Active GitHub Actions use hosted `ubuntu-24.04`, never a workstation/self-hosted runner.
- Legacy `btp-admin/` is not the new control plane; the Central Admin is `/central/admin`.

## Retired legacy material

Supabase RLS/schema/RPC SQL, Supabase migrations/functions, and Supabase-authenticated static admin pages are superseded as active runtime. Keep only documentation necessary to explain source-history, audit provenance, or a verified migration mapping. Any retained legacy file must visibly state `HISTORICAL / SUPERSEDED — NOT ACTIVE RUNTIME`. Do not wire historical files into deploy/CI/runtime.

## Security and evidence boundary

Anonymous or client-authorized cross-tenant access is prohibited. Database identity, domain, subscription and device membership must be resolved server-side before a tenant DB connection is initialized. No tenant isolation, config import, deploy, backup/restore, transaction sync, release signing or production cutover is certified by source presence alone.

Live Admin legacy URL: https://berkah-ajb-dev.github.io/Berkahtigaputeri/btp-admin/
New Central Admin target: https://app.berkahtigaputeri.co.id/central/admin (not to be described as live until deployment evidence exists).
