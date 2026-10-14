# FASE 5 — BTP ADMIN, FLUTTER APP AND EFFECTIVE CONFIG ALIGNMENT

**Status: GREEN for the targeted source and disposable contract-test scope. Hosted and physical-device security certification remains incomplete.**

## Configuration contract

Admin, Flutter source and RPC preserve the only canonical order:

GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE.

The effective-config request accepts only pos or akuntansi, fetches only the requested service row, uses top-level overwrite semantics and applies DEVICE last. The Flutter cloud configuration path is authenticated get_effective_config(p_tenant, p_device, p_service); no raw layered SELECT fallback was restored.

## Admin behavior validated

- Runtime Node fixture tests separate POS from Akuntansi and verify exact five-layer keys, precedence, and service-row isolation.
- Tenant saves use the atomic version RPC with the loaded expected version and preserve fields outside the visible UI.
- Feature flags read canonical effective config and save an intentional tenant override in the atomic tenant write.
- Direct tenant-only insert that would bypass the fixed 352-key inventory is disabled until an inventory-safe provisioning design is approved.

## Evidence

- [Canonical POS App CI run 38631854500](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38631854500) passed on the docs/reporting source predecessor and reported no Dart analyzer issues.
- [Canonical Workbook Validation run 38632908922](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38632908922) passed on the current report-bearing commit.
- [Disposable target replay run 38629812613](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629812613) passed 50 baseline and Tenant A/B pgTAP tests and the related structural comparison.
- [Admin parity and workbook dry-run run 38629719283](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38629719283) passed 21 Python tests, the Admin runtime fixture, and the 352-key no-network dry-run.

## Still open

These results do not prove a production-signed APK was installed and tested on physical hardware; they do not test the full REST/storage/subscription/reporting hostile matrix; and they do not authorize the divergent staging-clone ACL state. Production remains blocked pending the wider Tenant A/B matrix and independent release review.
