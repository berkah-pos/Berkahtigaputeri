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
- Historical host checks for the former Fedora Actions runner are obsolete. The repository CI migration now uses GitHub-hosted Ubuntu 24.04 runners; no runner service, SELinux label, linger, reboot recovery, or workstation availability is required for CI.
- The workflow does not currently build split APKs or use obfuscation/debug-symbol output.
- Need pin all third-party actions to reviewed immutable SHAs according to repository policy; the source mixes a pinned Android setup action with version tags for others.
- Workflow YAML parser validation and actual five-push queue test were not run here.

## Required validation after runner migration

The Fedora systemd-service instructions above have been retired. All four active workflow definitions in `.github/workflows/` are now configured for GitHub-hosted Ubuntu 24.04 runners. Validate through actual Actions run/job records and job logs instead of maintaining an always-on runner machine.

Required gates remain: workflow YAML validation, a real job start, Dart analysis, Flutter tests, Android compile/build, and artifact verification. A run marked `startup_failure` with an empty Jobs API response is an infrastructure/startup blocker, not evidence that code tests passed or failed.