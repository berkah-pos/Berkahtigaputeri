# DOC_05 — Historical Tenant Isolation Evidence

**Status: HISTORICAL / SUPERSEDED for runtime architecture. Do not use as current release certification.**

This file records earlier source and staging checks against the former shared PostgreSQL/Supabase RLS implementation. Those results do not certify the canonical KVM2 architecture and must not be used as evidence that current Laravel tenant databases are isolated.

Current authority:
- `AGENTS.md`
- `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`
- `docs/permanent/DOC_00_MASTER_ROADMAP.md`

Current required evidence is an executed negative Tenant A/B matrix against the Laravel Central API and two distinct MariaDB tenant databases. It must cover configuration, host/domain routing, products, sales, inventory, reports, journals, sync receipts, tenant subscription and authorized admin paths. Source presence or an old RLS query is not a pass.

No production tenant-isolation certification is asserted by this historical file.
