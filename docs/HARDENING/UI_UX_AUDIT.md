> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> This is a prior source-review report retained as historical evidence, not an active runbook or present-day release certificate. Any Supabase CLI/API/catalog/RLS/test step, legacy identity or “current/green/certified” statement in the original report is retired and cannot authorize current access or count as PostgreSQL 17 acceptance. Never access a Supabase project (including read-only) and never run `scripts/sync_excel_to_supabase.py`, including `--dry-run`.
>
> Current authority: [DOC_00](../permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](../permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](../permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](../permanent/DOC_00_MASTER_ROADMAP.md), [authority map](../permanent/AUTHORITY_AND_SUPERSESSION_MAP.md). The only cited Laravel/PostgreSQL scaffold smoke pass is scoped to exact commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149). Other target security, API, restore and production gates are NOT VERIFIED.
>
> ---
>
# UI/UX and GitHub Pages admin audit

**Status: INCOMPLETE — no browser/device automation or Lighthouse run.**

## Evidence
- Static admin files exist under `btp-admin/`.
- `btp-admin/auth.js` uses a Supabase publishable key and stores configurable URL/key in localStorage. A publishable/anon key is not a secret; authorization must come from Auth and RLS.
- The login UI restricts an email address client-side. This is not a substitute for server-side role authorization.
- The licence-check Edge Function uses wildcard CORS.
- Pages workflow copies `btp-admin` into `_site/btp-admin` and creates a redirect index. GitHub Pages does not provide arbitrary server response-header configuration through this workflow alone.

## Required actions
- Review all HTML insertion sites for DOM XSS; use textContent for untrusted text and context-appropriate escaping/sanitization for rich HTML.
- Enforce admin privileges in database RLS/RPCs, not only email checks in JavaScript.
- Define a restrictive CSP compatible with required CDN scripts; prefer self-hosted/pinned assets and avoid unsafe-inline where practical. If using meta CSP, document its limitations and test it.
- Add explicit loading, offline, retry and error states to critical admin/POS flows.
- Test responsive layout on the target 8-inch Infinix device and actual receipt printer.
- Add widget tests for login → sale → print and network/offline transitions.

## Not run
Lighthouse >90, XSS payload suite, mobile viewport/device testing, keyboard/accessibility checks, printer tests and Flutter widget tests. Do not claim compliance or a Lighthouse score without reports.