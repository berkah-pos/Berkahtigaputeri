# GitHub Actions workflow reset — Berkah POS

**Reset intent:** start from a minimal, auditable automation baseline after duplicate triggers and persistently queued runs.

## Reset scope on this branch

All GitHub Actions workflow definitions were removed from the active tree:

- `.github/workflows/berkah-pos-standalone-ci.yml`
- `.github/workflows/final-pos-sync.yml`
- `.github/workflows/pages.yml`
- `standalone-berkah-pos/.github/workflows/flutter-ci.yml`
- `.github/workflows/build.yml` (the legacy UAT workflow, removed with the retired `pos-app/` tree)

The active Flutter candidate remains `standalone-berkah-pos/`, package `id.co.berkahtigaputeri.berkahpos`.

## Effects and limits

- At the reset checkpoint, there are no workflow definition files in this branch.
- Deleting workflow YAML does **not** automatically cancel workflow runs already created by GitHub. Previously queued runs may remain visible and should be cancelled in Actions UI if they have not been stopped.
- This reset does not delete commit history, repository/organization secrets, already-published GitHub Pages content, or the Supabase backend.
- The old workbook-to-Supabase sync automation has been removed from this branch. Until explicitly rebuilt and re-enabled, that sync is not run by GitHub Actions.
- The old GitHub Pages deployment automation has been removed from this branch. Existing published Pages content may remain hosted until changed separately.
- The GitHub repository's base branch does not receive these changes until the pull request is merged.

## Restart principles

1. Keep one canonical Flutter app: `standalone-berkah-pos/`.
2. Reintroduce a single purpose-specific Android CI workflow first; do not silently restore UAT, Pages, or Supabase-sync workflows.
3. Scope triggers to the standalone app and its own workflow file.
4. Validate Dart formatting, dependency resolution, static analysis, unit tests, and unsigned Android APK/AAB compilation.
5. Treat queued, pending, cancelled, skipped, or artifact-free runs as non-passing.
6. Only produce a release claim after CI succeeds and a separately signed AAB passes physical-device and Play Console checks.
