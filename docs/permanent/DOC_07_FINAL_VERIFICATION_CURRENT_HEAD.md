# HISTORICAL SNAPSHOT — DOC_07 FINAL VERIFICATION (LEGACY FILENAME)

Status: **HISTORICAL — snapshot dated 2026-10-04; not verified against current main**

> The filename's former “CURRENT HEAD” wording is stale. The branch/SHA, run IDs, green matrix, and verification statements below describe the 2026-10-04 snapshot only; they are not evidence of current CI, staging, or production behavior. `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` remains the sole configuration-inheritance authority. The Phase 1 audit is documented separately in `CERTIFICATION_CURRENT_HEAD.md` and is not a full Phase 7 recertification.

Repository: `berkah-ajb-dev/Berkahtigaputeri`  
Branch: `fix/final-pos-canonical-sync`  
Certified implementation HEAD entering Phase 7: `49c39ae3c55cc9a930948defefe69d0a93ff41fc` (`fix: phase 6 atomic versioning rpc`)  
Phase 7 commit: `fix: phase 7 re-certification current head + release docs + PR` (the commit containing this document).

This file is a historical Final Pos verification snapshot, not the active implementation certification. The older a19cb3f / 3-layer snapshot is retained separately as `DOC_07_FINAL_VERIFICATION_HISTORICAL_a19cb3f.md`.

## Final architecture

Canonical effective-config inheritance is:

```text
GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE
```

For one `(tenant_id, device_id, requested_service)` request, only these keys participate:

```text
global
template:<template_id>
tenant:<tenant_id>
tenant:<tenant_id>:service:<requested_service>
device:<device_id>
```

Later layers replace earlier values at the top JSON-object level. POS and Akuntansi are service-specific and are never merged together in one response.

When a service row contains non-empty `inherited_from_template`, service-level MDR aliases (`mdr`, `mdr_pos`, `qris_mdr`, `mdr_%`) are removed before merge so template MDR remains authoritative.

## Workbook authority — 352 keys

Canonical workbook:

`config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`

Sheets:

1. `README_PRODUCTION`
2. `TEMPLATES`
3. `GLOBAL`
4. `TENANTS_MASTER`
5. `DEVICES`
6. `SERVICES`
7. `APP_CONFIG_EXPORT`

Canonical key inventory:

```text
1 global
3 template
100 tenant
140 service
108 device
---------
352 total
```

The workbook is parsed through `openpyxl` by `scripts/sync_excel_to_supabase.py` / the preserved Phase 2 parser, not by cell-by-cell GitHub API inspection.

## Admin ↔ APK ↔ RPC parity

The same five-layer, service-specific contract is implemented by:

- classic Admin: `btp-admin/editor-core.js`;
- APK: `pos-app/lib/core/config/config_service.dart`;
- PostgreSQL: `public.get_effective_config(...)` in `DOC_08_RPC_EFFECTIVE_CONFIG.sql`.

All three include `template:<template_id>`, use the requested service only, use top-level overwrite semantics, and honor the `inherited_from_template` MDR rule.

## RLS / tenant isolation

Final live/repository contract:

- RLS enabled on `tenants`, `devices`, `licences`, `app_config`, and `tenant_services`;
- `anon` direct SELECT is false on `tenants`, `devices`, `app_config`, and `tenant_services` (and also `licences`);
- `anon` EXECUTE on `get_effective_config(text,text,text)` is false;
- `authenticated` may execute the RPC;
- every RPC validates that the requested device belongs to the requested tenant;
- normal authenticated callers must own the device via `devices.user_id = auth.uid()`;
- canonical authenticated super-admin remains explicitly privileged;
- `service_role` remains the trusted server-side workbook sync/verification path;
- `SECURITY DEFINER` RPCs pin `search_path = ''` and perform explicit authorization before protected reads.

Anonymous/publishable-key-only reads are therefore not a supported data-access model.

## Fail-closed CI

Workflow: `.github/workflows/final-pos-sync.yml`  
Name: **Final Pos Sync (fail-closed)**

It runs on push to `main`, pull requests to `main`, and manual dispatch. It fails when:

- `SUPABASE_URL` or `SUPABASE_SERVICE_KEY` is missing;
- workbook sync exits non-zero;
- workbook dry-run does not validate the canonical contract;
- authenticated PostgREST verification cannot determine the row count;
- `public.app_config` count is anything other than **exactly 352**.

There are no `continue-on-error`, `|| true`, or `exit 0` integrity bypasses.

## Atomic version integrity

Canonical write RPC:

```text
public.update_app_config_atomic(
  p_key,
  p_new_value,
  p_expected_version
)
```

The function locks the row with `FOR UPDATE`, compares the current version, stores exactly `expected_version + 1`, and raises SQLSTATE `40001` for stale/concurrent writers. Client-supplied `version` is not authoritative.

Classic Admin, Template Admin, and the canonical workbook sync use this versioned administrative replacement contract. Workbook bootstrap inserts start at version `1`; existing rows always bump monotonically.

## Release surface

Current `pos-app/lib/main.dart` starts `HomeScreen` only. The reachable build is a **Final Pos UAT/configuration viewer** with tenant/device selection, Supabase/config source status, refresh, effective POS MDR, and POS/Akuntansi availability cards.

The current HomeScreen does **not** navigate to cashier checkout, QRIS transaction, or PPN-report flows. Release notes and privacy/data-safety documentation must not advertise those flows as currently reachable UI.

The app must have an authenticated device session before protected cloud config access can succeed under the final RLS model.

## Verification evidence

Final required checks:

```text
python3 scripts/sync_excel_to_supabase.py --dry-run
→ Inventory: 1 global + 3 template + 100 tenant + 140 service + 108 device = 352
→ 352 keys validated

node --check btp-admin/editor-core.js
→ PASS

DEV public.app_config count
→ 352

RPC version conflict tests
→ wrong expected_version: SQLSTATE 40001
→ correct expected_version: success and version N+1
→ stale second writer: SQLSTATE 40001
```

## Historical certification matrix (claims recorded in the 2026-10-04 snapshot)

| Area | Result |
|---|---|
| Documentation | 🟢 GREEN |
| Config architecture | 🟢 GREEN |
| Supabase sync | 🟢 GREEN |
| Admin ↔ APK ↔ RPC parity | 🟢 GREEN |
| Tenant isolation / RLS | 🟢 GREEN |
| Fail-closed CI contract | 🟢 GREEN |
| Version integrity | 🟢 GREEN |
| Release-note accuracy | 🟢 GREEN |

**Historical snapshot conclusion only:** the 2026-10-04 document claimed recertification for the 352-key template architecture. That claim has not been re-executed against current main by this file.
