> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.** This retained document records a legacy Supabase-era workflow, retired implementation contract, or dated verification snapshot. Its commands, SQL, project identifiers, identity claims and “green/certified/current” labels are historical evidence only. Do not follow them against any hosted environment or connect to a Supabase project. Current platform authority: [ADR-2026-10-17 no-Supabase decision](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md). Current target and acceptance: [DOC_14](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md). Current configuration semantics only: [DOC_00](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md). See the [authority/supersession map](../reports/ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md) and [dated audit snapshot](../reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md).

---

# HISTORICAL - certified old 3-layer a19cb3f, NOT current Final Pos

# DOC_07 - FINAL VERIFICATION P1-P5

Status: **FINAL GREEN / main / 2026-10-04**

Repo: `berkah-ajb-dev/Berkahtigaputeri`

## Canonical Admin URLs

- Root Pages: `https://berkah-ajb-dev.github.io/Berkahtigaputeri/`
- Root Admin: `https://berkah-ajb-dev.github.io/Berkahtigaputeri/btp-admin/`
- Login: `https://berkah-ajb-dev.github.io/Berkahtigaputeri/btp-admin/login.html`
- Clients: `https://berkah-ajb-dev.github.io/Berkahtigaputeri/btp-admin/clients.html`
- Edit pilot: `https://berkah-ajb-dev.github.io/Berkahtigaputeri/btp-admin/edit.html?tenant=berkah_sumber`
- History pilot: `https://berkah-ajb-dev.github.io/Berkahtigaputeri/btp-admin/history.html?key=tenant%3Aberkah_sumber`

## Deployment proof

Workflow existing `.github/workflows/pages.yml` sekarang membuat layout:

```text
_site/
  index.html            -> redirect ke btp-admin/
  btp-admin/
    index.html          -> clients.html jika authenticated, login jika belum
    login.html
    clients.html
    edit.html
    history.html
    auth.js
    admin-fields.js
    editor-core.js
    feature-flags.js
```

Stable-path deployment:

- commit `3a14edb521fcc3cc726edf6e2261ab4d801e139a`
- Pages run **#48**
- result: **SUCCESS**
- artifact `github-pages` id `11290014521`
- artifact digest `sha256:491c77f9b58651f13dbd3138a2979273ad2f6c0388d1a63a956a506ac89c7f7b`
- artifact contents were inspected and contain `index.html`, `btp-admin/index.html`, `btp-admin/clients.html`, `btp-admin/edit.html`, `btp-admin/history.html`, and `btp-admin/login.html`.

Direct HTTP probing from the execution environment could not resolve/fetch the `github.io` host, so final verification does **not** claim an independent browser HTTP check. Deployment success and the exact deployed artifact layout are verified.

## P1 - 3 Layer Foundation

Commit:

`4bfa744a95f25cb958f6bc73c921d201bd12da91`

Message:

`feat: admin 3 layer GLOBAL TENANT DEVICE + 2 services`

Pages run **#42: SUCCESS**.

Supabase LIVE has exactly the five required pilot keys:

```text
global                                      version 1
tenant:berkah_sumber                        version 2
tenant:berkah_sumber:service:pos            version 1
tenant:berkah_sumber:service:akuntansi     version 1
device:infinix_xos_123                      version 1
```

Inheritance contract:

```text
GLOBAL -> TENANT -> SERVICE -> DEVICE
```

Device is the highest override layer. Pilot device `infinix_xos_123` exists in the relational device data and in `app_config`.

## P2 - RLS + Super Admin Auth

Commit:

`31f7e6cd6ff16089189efe57cb3966b5cbc48568`

Message:

`feat: RLS + super admin auth`

Pages run **#43: SUCCESS**.

RLS is enabled on:

```text
tenants
devices
licences
app_config
config_history
```

Acceptance evidence:

- simulated `anon` write to `app_config` -> rejected with permission denied;
- simulated authenticated JWT for `satria@berkahtigaputeri.com` -> write affected 1 row;
- browser admin uses only Supabase Publishable/Anon credentials; no service-role credential is embedded in the admin files.

`DOC_03_RLS_AUTH.sql` is synchronized with the LIVE policy contract. Manual SQL copy/paste is only needed when rebuilding another Supabase environment; the staging project was migrated directly during this verification.

## P3 - Super Admin Clients + Edit

Final P3 commit:

`4eddbf9636f4e3b5113ae3413ea59f4222ef5716`

Message:

`feat: super admin clients list + edit per tenant`

Pages run **#45: SUCCESS**.

Verified implementation:

- `clients.html` provides search, package filter, blocked filter, expiry warning, Add Tenant, and Edit action;
- `edit.html?tenant=berkah_sumber` renders the canonical 43 fields;
- editor loads GLOBAL, TENANT, POS service, AKUNTANSI service, then DEVICE;
- tenant `berkah_sumber` prioritizes canonical device `infinix_xos_123`;
- root `btp-admin/index.html` routes authenticated admin to `clients.html` and unauthenticated visitors to login.

Before P4 seed, P3 database snapshot contained one canonical tenant: `berkah_sumber`.

## P4 - Feature Flags POS + AKUNTANSI

Commit:

`86016e45145bed1d9ffbe32a29b4471a6e55eb78`

Message:

`feat: feature flag POS + AKUNTANSI`

Pages run **#46: SUCCESS**.

LIVE UAT tenants:

```text
berkah_sumber -> POS=true, AKUNTANSI=true
clientA       -> POS=true, AKUNTANSI=false, POS MDR=0.5%
clientB       -> POS=true, AKUNTANSI=true,  POS MDR=0.7%
```

Service keys are tenant-scoped, therefore Client A and Client B do not collide:

```text
tenant:clientA:service:pos
tenant:clientB:service:pos
tenant:clientB:service:akuntansi
```

When AKUNTANSI is OFF, scope `akuntansi` is disabled in the editor, explicitly including `ppnAccount` / account `2-2010`.

## P5 - Audit + Anti-Collision

Commit:

`88d8b70633ba216de1b19d1b998a34a826d6d034`

Message:

`feat: audit log + anti-tabrakan`

Pages run **#47: SUCCESS**.

Audit trigger LIVE:

```text
trg_app_config_audit -> log_config_change()
```

Acceptance SAVE verification:

```text
key          = tenant:berkah_sumber
old version  = 1
new version  = 2
changed_by   = satria@berkahtigaputeri.com
```

A matching `config_history` row was created automatically at the same save timestamp.

Optimistic concurrency in `editor-core.js` compares `loadedVersion` against the database version immediately before save. If they differ, save is cancelled and UI displays:

`Config sudah diupdate orang lain, reload?`

History UI:

`/btp-admin/history.html?key=tenant:berkah_sumber`

reads `config_history` through the authenticated Supabase client and shows version, changed time, changed by, old value, and new value.

## Security advisor snapshot

No security-advisor finding was reported for the P1-P5 tables above. Remaining project-level notices are outside this P1-P5 scope:

- `subscriptions` and `subscription_events` already have RLS enabled but currently have no policies;
- Supabase Auth leaked-password protection is disabled.

These should be handled as a separate security-hardening task and do not alter the verified P1-P5 admin/RLS contract.

## Final acceptance matrix

| Priority | Acceptance | Result |
|---|---|---|
| P1 | 5 canonical app_config rows + 3-layer/service inheritance | PASS |
| P2 | anon write denied; authenticated super-admin write allowed | PASS |
| P3 | clients list + 43-field tenant editor + canonical device | PASS |
| P4 | Client A POS-only; Client B POS+Akuntansi; MDR isolated | PASS |
| P5 | save creates config_history + stale-version guard | PASS |
| Pages | stable `_site/btp-admin/` artifact deployed from `main` | PASS |

All implementation changes were made directly on `main`; no new feature branch was created for this execution.
