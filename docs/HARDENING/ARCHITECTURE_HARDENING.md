# CI/CD and system architecture hardening

**Status: PARTIAL — workflow source reviewed; host configuration and stress tests unverified.**

## Verified in tracked workflow source
- POS build push path filter: `pos-app/**`, `.github/workflows/build.yml`, and `.gitleaksignore`.
- Pages push path filter: `btp-admin/**` and `.github/workflows/pages.yml`.
- POS workflow runs Gitleaks, selects Java 17, Flutter stable, caps Gradle heap at `-Xmx2G`, sets max workers to 2, disables parallel Gradle, runs analyze/tests, builds an AAB and uploads the artifact for 14 days.
- Pages uses `actions/configure-pages@v6`, `actions/upload-pages-artifact@v5`, and `actions/deploy-pages@v5`.

## Outstanding
- The Android scaffold is generated during CI if missing; the manifest and wrapper are not tracked in the inspected tree. This makes the build dependent on runtime generation rather than a fully reviewed committed Android project.
- Added `.github/workflows/supabase-functions.yml` on the follow-up branch to run Gitleaks, Deno lint/type checks, and provider-state/webhook unit tests on `supabase/**` changes. It runs on GitHub-hosted Ubuntu because these tests do not require Fedora hardware and should not be blocked by a stalled Android toolchain on the single self-hosted runner. Do not merge until CI is green.
- Supabase deployed functions had drifted from the checked-in tree; the follow-up branch snapshots the active staging sources and adds `supabase/config.toml`, without deploying them.
- `final-pos-sync.yml` performs a dry-run sync only. Confirm that this is the intended behavior; it should not be treated as a production migration/deployment pipeline.
- Host checks not possible here: systemd unit enabled/active, Restart=always, runner ownership, SELinux labels, linger, reboot recovery, disk/RAM/swap, runner version and labels.
- The workflow does not currently build split APKs or use obfuscation/debug-symbol output.
- Need pin all third-party actions to reviewed immutable SHAs according to repository policy; the source mixes a pinned Android setup action with version tags for others.
- Workflow YAML parser validation and actual five-push queue test were not run here.

## Required commands on Fedora
```bash
sudo systemctl is-enabled actions.runner.new-berkah.btp-fedora44-01.service
sudo systemctl is-active actions.runner.new-berkah.btp-fedora44-01.service
systemctl show actions.runner.new-berkah.btp-fedora44-01.service -p Restart -p User
gh api repos/new-berkah/Berkahtigaputeri/actions/runners --jq '.runners[] | {name,status,busy}'
```
Then run YAML validation, controlled push concurrency test, reboot recovery and log-secret review. Do not report host configuration as verified from GitHub workflow source alone.