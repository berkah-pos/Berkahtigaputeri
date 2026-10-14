# DOC_06 — Historical Atomic Versioning Evidence

**Status: HISTORICAL / SUPERSEDED as a runtime certification.**

This file records a former PostgreSQL/Supabase atomic RPC implementation. That RPC is not part of the active Laravel runtime and previous checks do not certify Laravel/MariaDB version integrity.

Current versioning contract:
- each central and tenant configuration record has a positive server-owned version;
- writes compare the expected stored version and reject stale updates;
- an accepted change increments N to N+1 in one transaction/row lock;
- a repeated unchanged workbook import must not reset versions or create a fake change;
- an audit record must identify actor, scope, versions and old/new hashes once the editing API/audit ledger is implemented.

See `DOC_06_AUDIT_VERSIONING.md` and `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`. Until the Laravel concurrent stale-write tests and audit-ledger tests execute successfully, atomic versioning acceptance remains PARTIAL / NOT VERIFIED.
