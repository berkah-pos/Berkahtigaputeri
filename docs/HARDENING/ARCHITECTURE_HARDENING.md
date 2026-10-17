> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.** This dated hardening/audit artifact was written against an earlier source or Supabase-era runtime. Preserve its original findings as history only. Do not follow its Supabase/database commands or interpret its statuses as current platform certification. Current platform authority: [owner ADR](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md); current target/acceptance: [DOC_14](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md); current snapshot: [architecture conflict register](../reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md); full cross-document map: [authority/supersession map](../reports/ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md).

---

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