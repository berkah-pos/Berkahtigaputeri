# GitHub Actions workflow reset — Berkah POS

**Reset intent:** start from a minimal, auditable automation baseline after duplicate triggers and persistently queued runs.

## Reset scope on this branch

All previous GitHub Actions workflow definitions were removed from the active tree at the reset checkpoint:

- `.github/workflows/berkah-pos-standalone-ci.yml`
- `.github/workflows/final-pos-sync.yml`
- `.github/workflows/pages.yml`
- `standalone-berkah-pos/.github/workflows/flutter-ci.yml`
- `.github/workflows/build.yml` (the legacy UAT workflow, removed with the retired `pos-app/` tree)

The active Flutter candidate remains `standalone-berkah-pos/`, package `id.co.berkahtigaputeri.berkahpos`.

## Effects and limits

- The reset checkpoint commit contained no workflow definition files.
- Deleting workflow YAML does **not** automatically cancel workflow runs already created by GitHub. Previously queued runs may remain visible and should be cancelled in Actions UI if they have not been stopped.
- This reset does not delete commit history, repository/organization secrets, already-published GitHub Pages content, or the Supabase backend.
- The old workbook-to-Supabase sync automation has been removed from this branch. Until explicitly rebuilt and re-enabled, that sync is not run by GitHub Actions.
- The old GitHub Pages deployment automation has been removed from this branch. Existing published Pages content may remain hosted until changed separately.
- The GitHub repository's base branch does not receive these changes until the pull request is merged.

## Restart status

The reset has been followed by one clean workflow only:

- `.github/workflows/berkah-pos-android-ci.yml`

No legacy UAT, GitHub Pages deployment, or workbook-to-Supabase synchronization workflow has been restored. The clean workflow is scoped to `standalone-berkah-pos/**` and its own definition, and validates formatting, dependencies, analysis, tests, and unsigned APK/AAB builds.

## Release gate

1. Observe the first clean CI run and inspect its logs/artifacts.
2. Treat queued, pending, cancelled, skipped, or artifact-free runs as non-passing.
3. Only produce a release claim after CI succeeds and a separately signed AAB passes physical-device and Play Console checks.
