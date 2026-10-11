# Vercel deployment audit — 2026-10-11

**Status: NO VERIFIED VERCEL PROJECT LINK FOR `new-berkah/Berkahtigaputeri`; NO VERCEL WRITES PERFORMED.**

## Read-only account findings

The connected Vercel context reports team `berkahtigaputeri-9409` on Hobby plan with **zero linked Git projects**. Project search for “berkah” returned none. The full visible project list contains:
- `umkm-staging-2`
- `umkm-staging`
- `supabase_umkm`

These names do not prove they are this repository or its production app. Recent `umkm-staging-2` deployments include READY production deployments, and some deployment metadata identifies the GitHub repo as `Andisatriawan/umkm`, not `new-berkah/Berkahtigaputeri`.

## Decision

- Did not create or alter a Vercel project, Git connection, environment variable, domain, deployment, alias, or route.
- The current repository's admin is deployed via GitHub Pages in `.github/workflows/pages.yml`; Vercel is not shown as an active deployment integration for this repo.
- Do not reuse/modify the `umkm-staging-2` project just because the team name looks similar. That could deploy the wrong application or change unrelated infrastructure.

## Required if Vercel hosting is desired

1. Confirm whether Vercel should host `btp-admin`, an API/frontend package, or a different app. This repository is primarily a Flutter app, which Vercel does not build into native Android APK/AAB artifacts.
2. Create/link the exact repository/project in the intended Vercel team via a reviewed PR or approved UI flow; configure the root directory and build/output settings intentionally.
3. Audit Production/Preview environment variable *names and presence* without printing decrypted secret values.
4. Use preview deployments first; verify domain, access controls, build logs and rollback before any promotion to production.

No Vercel configuration changes were necessary or safe based on the evidence available.
