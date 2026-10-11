# Merge inventory — uploaded ZIP vs current GitHub repository

**Date:** 2026-10-11  
**Uploaded snapshot:** `Berkahtigaputeri-main (3).zip` (archive root `Berkahtigaputeri-main/`; archive entries timestamped 2026-10-08)  
**Target comparison:** `main` as read from the GitHub repository tree  
**Merge target:** review branch `audit/production-hardening-20261011`

## Results

- Uploaded archive contains **96 files** (excluding directory entries).
- Current GitHub `main` tree contains **97 files**.
- Every file path in the uploaded archive already exists in current `main`.
- `pos-app/README.md` exists in current `main` but is absent from the uploaded archive.
- Therefore **zero source files need to be imported from the uploaded ZIP**. Copying the archive over the repository would risk regressing newer files, particularly workflow fixes added after the archive snapshot.

## Merge strategy applied

1. Preserve current `main` versions of all source and workflow files.
2. Retain the hardening reports under `docs/HARDENING/` on the audit branch for review.
3. Harden root `.gitignore` on the audit branch to exclude generated Flutter/Gradle files, local Android properties, signing material, environment files, Supabase local state, Node dependencies, logs and IDE/OS state. `.env.example` templates remain trackable.
4. No secrets were copied, no database migration was applied, no live configuration was changed, and no source code was overwritten.

## Remaining work, not silently filled in

- Android scaffold is incomplete in the tracked tree: only `pos-app/android/app/build.gradle` was present; manifest, Gradle wrapper and supporting scaffold files need to be generated with the project's pinned Flutter SDK, reviewed, tested, and committed from a real Flutter environment.
- No `supabase/config.toml` was found. Do not invent production database configuration.
- No payment gateway/subscription webhook or AI insight implementation was found in the tracked tree. Implement only after provider/requirements are confirmed, or document that feature as out of scope.
- Flutter tests/builds, Gitleaks, Supabase DB lint/RLS tests, load tests, Play Console checks and physical-device validation must be run in their appropriate environments.

## Acceptance

This branch adds reports and a safe ignore-file baseline, without overwriting newer repository content. It is **not** a declaration that all nine audit subsystems are production-ready. Open/review the PR, run CI, and close remaining controls before release.
