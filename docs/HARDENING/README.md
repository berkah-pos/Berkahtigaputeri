# Production hardening audit — 2026-10-11

**Scope:** repository `new-berkah/Berkahtigaputeri`, `main` snapshot inspected via GitHub API; audit branch `audit/production-hardening-20261011`.

## Verdict

**NOT PRODUCTION-READY / NOT ALL GREEN.** This is a source inventory and evidence-based preliminary audit, not a completed penetration test. The connected GitHub interface can inspect repository files and workflow metadata, but cannot execute commands on the Fedora runner, run Supabase CLI against the project, query live database policies, install the app on a device, or access Play Console/signing credentials. Those checks are explicitly marked unverified rather than reported as passing.

## Inventory

The tracked tree contained 97 files at inspection time. The uploaded 2026-10-08 ZIP contains 96 files; every path in the ZIP is already present on current `main`, and `pos-app/README.md` is present on `main` but absent from the ZIP. See [MERGE_INVENTORY.md](MERGE_INVENTORY.md). Three workflows are present:
- `.github/workflows/build.yml`
- `.github/workflows/pages.yml`
- `.github/workflows/final-pos-sync.yml`

Relevant source files include `pos-app/pubspec.yaml`, `pos-app/android/app/build.gradle`, local SQLite POS/accounting/inventory code and ten Dart test/support files, one Supabase Edge Function (`licence-check`), one migration, and the `btp-admin/` static admin app.

Not found in the tracked tree:
- `pos-app/android/app/src/main/AndroidManifest.xml`
- `supabase/config.toml`
- payment gateway/subscription/webhook function or configuration
- AI insight source/function
- `docs/HARDENING/` before this audit branch

## Existing controls observed

- Android build workflow path filters include `pos-app/**`, and the Pages workflow filters `btp-admin/**` plus its own workflow file.
- Android workflow includes Gitleaks, Java 17, Flutter stable, generated Android scaffold fallback, Gradle `-Xmx2G`, max two workers, Flutter analyze/test, release AAB build and artifact upload.
- The latest inspected POS-only trigger-isolation run and runner build run were reported successful in the project conversation.
- POS checkout source uses integer amount fields and a SQLite transaction boundary, checks stock, fingerprints requests, and returns an already-processed result for a matching transaction ID.
- Journal service validates debit/credit balance and prevents duplicate transaction journal posting.

## Must close before production

1. Implement or formally scope out subscription/payment-gateway billing; no gateway/webhook integration was found.
2. Run actual database RLS/catalog/policy review and `supabase db lint` against the intended project.
3. Add and run adversarial multi-tenant tests against a disposable database.
4. Commit a reviewed Android scaffold/manifest, configure secure release signing, and verify both AAB and split APK outputs.
5. Run complete Flutter tests/analyze, Gitleaks, SQL lint, load tests, Play Console review and physical-device acceptance; attach logs/results.
6. Review CORS, request authentication, rate limiting and abuse controls for `licence-check`.
7. Resolve missing AI subsystem evidence: do not claim AI features are hardened when no AI implementation was found.

The branch also hardens root `.gitignore` to exclude generated Flutter/Gradle output, local signing/configuration files, `.env` files (while allowing `.env.example`), Supabase local state, dependencies and local IDE/OS artifacts. No secrets, database changes, production configuration changes, or application source-code behavior were changed by this audit report branch.