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
## Static Pages CSP follow-up (2026-10-11)

A transitional meta CSP was added to each current `btp-admin/*.html` page. It restricts script execution sources to same-origin and the Supabase SDK CDN, constrains connections to same-origin/Supabase domains, disallows plugin objects, restricts the document base URI, and upgrades mixed content. The legacy template page additionally depends on Google Fonts; the shared policy allows `fonts.googleapis.com` for styles and `fonts.gstatic.com` for font data.

**Residual risk:** existing inline scripts and inline CSS require `'unsafe-inline'` in this transitional policy. Move inline code to reviewed external assets and then tighten `script-src` using nonces/hashes. CSP meta tags cannot supply every response-header directive (for example, `frame-ancestors`); stronger framing controls require response headers from the hosting layer or a compatible reverse proxy. Validate every admin page and authentication recovery flow in a browser preview before promoting.
