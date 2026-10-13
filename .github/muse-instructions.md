# Copilot Instructions - Berkah POS Final Pos

Before any code change, read `AGENTS.md` and follow this repository-mandated order:

1. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — sole configuration-inheritance authority.
2. `docs/permanent/DOC_00_MASTER_ROADMAP.md` — phase gates in sequence.
3. `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md` — scoped work and evidence-reporting rules.
4. `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` — current integration evidence and unresolved gates.
5. `docs/permanent/DOC_01_3_LAYER_CONFIG.md` — legacy filename; Final Pos contract.
6. `docs/permanent/DOC_02_SUPABASE_SCHEMA_V1.sql`.
7. `docs/permanent/DOC_03_RLS_AUTH.sql`.
8. `docs/permanent/DOC_04_ADMIN_ARCHITECTURE.md`.
9. `scripts/sync_excel_to_supabase.py` — canonical workbook validator and 352-key inventory; do not inspect the binary workbook through GitHub's text API.

## Canonical architecture

The only supported effective-config inheritance is:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
```

Canonical key forms:

```text
global
template:<TEMPLATE_ID>
tenant:<tenant_id>
tenant:<tenant_id>:service:<service>
device:<device_id>
```

Schema:

```text
app_config(key PRIMARY KEY, value JSONB, updated_at)
```

The canonical workbook is `config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`; its validator requires exactly 352 exported keys: 1 global + 3 templates + 100 tenants + 140 services + 108 devices.

## Rules

- Do not implement an inheritance path that omits TEMPLATE.
- Resolve only the requested service; never merge POS and Akuntansi service rows into one effective configuration.
- Do not restore the legacy `app_config(device_id, key, value)` schema.
- Use a branch + PR for changes; do not push implementation changes directly to `main`.
- Official Admin code stays under `btp-admin/`; do not create a duplicate root `complete-settings.html` implementation.
- Historical verification does not override `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`.
- Follow correction phases in `DOC_00_MASTER_ROADMAP.md` in order.
- Preserve GitHub Pages publication of `btp-admin/`.

Live Admin: https://berkah-ajb-dev.github.io/Berkahtigaputeri/btp-admin/
