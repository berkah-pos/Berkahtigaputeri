> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> This is a prior source-review report retained as historical evidence, not an active runbook or present-day release certificate. Any Supabase CLI/API/catalog/RLS/test step, legacy identity or “current/green/certified” statement in the original report is retired and cannot authorize current access or count as PostgreSQL 17 acceptance. Never access a Supabase project (including read-only) and never run `scripts/sync_excel_to_supabase.py`, including `--dry-run`.
>
> Current authority: [DOC_00](../permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](../permanent/DOC_00_MASTER_ROADMAP.md), [authority map](../permanent/AUTHORITY_AND_SUPERSESSION_MAP.md). The only cited Laravel/PostgreSQL scaffold smoke pass is scoped to exact commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149). Other target security, API, restore and production gates are NOT VERIFIED.
>
> ---
>
# Release AAB/APK verification record

**Status: PARTIAL — AAB build and artifact upload passed in one reported CI run; release installability/signing not verified.**

## Evidence
The project conversation reports successful workflow run [38092896186](https://github.com/new-berkah/Berkahtigaputeri/actions/runs/38092896186) on commit `4d5f5019feba1df4d5e2ebb0f021f1886d80268e`. The displayed job completed Flutter setup, dependency installation, analysis, tests, release app bundle build and artifact upload successfully. The workflow artifact retention is 14 days.

## Not established
- Artifact downloaded and cryptographically verified.
- Production signing certificate/keystore configured.
- APK split builds (`arm64-v8a`, `x86_64`) produced.
- Obfuscation and split debug info configured.
- Artifact installed on physical Infinix hardware.
- Offline checkout, receipt printing, upgrade from prior version and internal-track install tested.
- AAB size and package metadata checked.

## Required verification on runner
```bash
cd ~/Berkahtigaputeri/pos-app
flutter pub get
flutter analyze
flutter test --coverage
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols
ls -lh build/app/outputs/bundle/release/app-release.aab
find build/app/outputs/flutter-apk -maxdepth 1 -type f -name '*.apk' -print
```

Only run obfuscated production builds once signing configuration and secure symbol retention are confirmed. Do not assert that `app-release.aab` is signed or installable until signature verification and device/internal-track installation pass. The requested artifacts are not attached to this report because this environment cannot execute Flutter builds or retrieve runner-local build outputs.