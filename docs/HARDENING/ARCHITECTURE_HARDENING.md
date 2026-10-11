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