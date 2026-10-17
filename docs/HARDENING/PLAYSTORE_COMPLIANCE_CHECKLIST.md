> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> This is a prior source-review report retained as historical evidence, not an active runbook or present-day release certificate. Any Supabase CLI/API/catalog/RLS/test step, legacy identity or “current/green/certified” statement in the original report is retired and cannot authorize current access or count as PostgreSQL 17 acceptance. Never access a Supabase project (including read-only) and never run `scripts/sync_excel_to_supabase.py`, including `--dry-run`.
>
> Current authority: [DOC_00](../permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](../permanent/DOC_00_MASTER_ROADMAP.md), [authority map](../permanent/AUTHORITY_AND_SUPERSESSION_MAP.md). The only cited Laravel/PostgreSQL scaffold smoke pass is scoped to exact commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149). Other target security, API, restore and production gates are NOT VERIFIED.
>
> ---
>
# Google Play release compliance checklist

**Status: BLOCKED — release signing, manifest and Play Console evidence missing.**

## Repository findings
- `pos-app/pubspec.yaml` reports version `1.0.0+2`.
- `pos-app/android/app/build.gradle` uses Java 17 and Flutter-provided compile/target SDK values; target SDK cannot be confirmed from this file alone.
- `pos-app/android/app/src/main/AndroidManifest.xml` was not found in the tracked tree.
- The build workflow generates an Android scaffold at runtime when the wrapper/manifest is absent.
- Release build type has no explicit signing configuration in the inspected Gradle file.

## Checklist
- [ ] Commit and review complete Android scaffold, manifest, Gradle wrapper and Gradle properties.
- [ ] Confirm target/compile SDK against the Play Console requirements at submission time.
- [ ] Review all permissions; justify any media, location, contacts, background or broad storage permission.
- [ ] Confirm no cleartext HTTP; test network security config and endpoints.
- [ ] Configure production signing with a protected keystore and GitHub Secrets/secure files; never commit keystore or key.properties.
- [ ] Confirm app bundle signature, package ID, version code increment, 64-bit ABI support and bundle size.
- [ ] Verify Play Billing only if selling digital app features/subscriptions subject to Play policy; distinguish physical POS payments.
- [ ] Complete privacy policy, Data safety form, account deletion disclosures if applicable, data retention/vendor disclosures and SDK inventory.
- [ ] Run Play Console pre-launch report and internal-track install/upgrade tests.

No Play Console access, signing material, device, manifest or final artifact was available to this audit. No item above is marked complete without evidence.