> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> This is a prior source-review report retained as historical evidence, not an active runbook or present-day release certificate. Any Supabase CLI/API/catalog/RLS/test step, legacy identity or “current/green” statement in the original report is retired and cannot authorize current access or count as PostgreSQL 17 acceptance. Never access a Supabase project (including read-only) and never run `scripts/sync_excel_to_supabase.py`, including `--dry-run`.
>
> Current authority: [DOC_00](../permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](../permanent/DOC_00_MASTER_ROADMAP.md), [authority map](../permanent/AUTHORITY_AND_SUPERSESSION_MAP.md). The only cited Laravel/PostgreSQL scaffold smoke pass is scoped to exact commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149). Other target security, API, restore and production gates are NOT VERIFIED.
>
> ---
>
# CI/CD and system architecture hardening

**Status: PARTIAL — workflow source reviewed; host configuration and stress tests unverified.**

## Verified in tracked workflow source
- POS build push path filter: `pos-app/**`, `.github/workflows/build.yml`, and `.gitleaksignore`.
- Pages push path filter: `btp-admin/**` and `.github/workflows/pages.yml`.
- POS workflow runs Gitleaks, selects Java 17, Flutter stable, caps Gradle heap at `-Xmx2G`, sets max workers to 2, disables parallel Gradle, runs analyze/tests, builds an AAB and uploads the artifact for 14 days.
- Pages uses `actions/configure-pages@v6`, `actions/upload-pages-artifact@v5`, and `actions/deploy-pages@v5`.

## Outstanding
- The Android scaffold is generated during CI if missing; the manifest and wrapper are not tracked in the inspected tree. This makes the build dependent on runtime generation rather than a fully reviewed committed Android project.
- `final-pos-sync.yml` performs a dry-run sync only. Confirm that this is the intended behavior; it should not be treated as a production migration/deployment pipeline.
- Historical Fedora runner host checks are retired after CI migration to GitHub-hosted Ubuntu 24.04. No runner systemd unit, SELinux label, linger setting, reboot recovery procedure, or workstation availability is required for repository CI.
- The workflow does not currently build split APKs or use obfuscation/debug-symbol output.
- Need pin all third-party actions to reviewed immutable SHAs according to repository policy; the source mixes a pinned Android setup action with version tags for others.
- Workflow YAML parser validation and actual five-push queue test were not run here.

## Required validation after runner migration

The historical Fedora systemd instructions above are retired. All active workflow definitions use GitHub-hosted Ubuntu 24.04 runners. Validate them through actual GitHub Actions run/job records and logs, not through a long-running workstation service.

Required gates remain: workflow YAML validation, a real job start, Flutter analysis/tests, Android compile/build, and artifact verification. A `startup_failure` run with `jobs: []` is an infrastructure/startup blocker, not a test result.