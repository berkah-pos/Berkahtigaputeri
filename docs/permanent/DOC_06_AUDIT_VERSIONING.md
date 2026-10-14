# DOC_06 — Configuration Audit and Versioning

**Status:** Active design and acceptance contract for the Laravel runtime; legacy SQL/RPC certification is superseded.

## Version ownership

Every configuration record has a positive integer version owned by the server. A new value is written against an expected version; stale writes must fail instead of overwriting newer configuration. Version numbers are never reset to v1 by a repeat import.

The version applies to each scope record independently:
- global configuration;
- each template;
- tenant base configuration;
- each tenant/service configuration;
- each tenant-local device configuration.

## Write contract

Any future config-editing API or Filament action must execute under a transaction/row lock:
1. authorize active user and scope ownership;
2. read the latest record and verify it exists;
3. compare the supplied expected version;
4. validate data shape and allowed keys;
5. persist and increment to N+1 atomically;
6. append an audit event including actor/scope, old/new hashes, versions and timestamp;
7. return the stored version.

If the expected version differs, return a conflict response and preserve the persisted value. Do not accept a client-supplied new version as authoritative.

## Workbook importer

`php artisan config:import-workbook <manifest.json>` is intended to be resumable. Identical values preserve current versions; changed values increment the version; missing keys should be reconciled explicitly rather than silently deleted. It does not reset versions, drop tenant DBs or replace transaction records.

## Evidence boundary

The migration importer currently preserves/increments versions during source import. That does not yet certify a complete Admin editing API, an append-only audit ledger, concurrent editing behavior or cross-node conflict handling. Those require actual implementation and executed tests. Old PostgreSQL `update_app_config_atomic` SQL/RPC reports are historical only; new APIs must implement the equivalent concurrency guarantee in Laravel/MariaDB.
