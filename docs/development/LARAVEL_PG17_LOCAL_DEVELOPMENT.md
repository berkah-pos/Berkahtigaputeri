# Laravel + PostgreSQL 17 Local Development

This is the initial backend platform scaffold for Hostinger KVM2 + Coolify. It does not yet implement the complete product API, tenant provisioning privileges, or mobile migration.

## Requirements

- Docker Engine and Docker Compose
- Git

No Supabase project, account, key, endpoint, SDK, or service is needed.

## Start the local development stack

1. Copy `.env.example` to `.env`.
2. For local use only, set distinct values for `POSTGRES_BOOTSTRAP_PASSWORD` and `CENTRAL_DB_PASSWORD`. Keep the bootstrap account name separate from `CENTRAL_DB_USERNAME`. Never reuse these development credentials in staging or production.
3. Start PostgreSQL and the one-shot role bootstrap without starting the application:

   ```sh
   docker compose up --build -d postgres db-bootstrap
   ```

4. Apply central schema migrations through the explicit one-shot migration profile, which alone receives local bootstrap credentials:

   ```sh
   docker compose --profile tools run --rm dev-migrate
   ```

5. Start the app with its restricted runtime credentials and check `http://localhost:8000/api/v1/platform-health`:

   ```sh
   docker compose up --build -d app
   ```

The `app` service uses only the restricted central runtime role. It does not receive the PostgreSQL bootstrap username/password, `PROVISIONER_DB_*` values, or tenant migrator credentials. PostgreSQL port 5432 and application port 8000 bind to loopback only.

The `db-bootstrap` service is a no-ingress, one-shot local helper. It creates/hardens the configured central runtime role and grants only CONNECT, schema USAGE, table DML, and sequence privileges. It refuses to continue if the runtime role is the bootstrap identity or if the existing runtime role has role memberships or owns database/application objects. Resolve such a collision deliberately; do not bypass the failure by granting superuser access to the app.

The opt-in `dev-migrate` profile receives local bootstrap credentials for a single migration command only. It is not part of the ordinary stack and must never be used against staging or production. Normal application code must not run schema migrations through the runtime account.

## Existing local PostgreSQL volumes

The PostgreSQL image applies `POSTGRES_USER` and `POSTGRES_PASSWORD` only when it initializes an empty data directory. Updating a variable does not rotate credentials in an existing volume.

For a volume previously created by the old Compose file, its bootstrap identity was taken from the former `CENTRAL_DB_USERNAME` and `CENTRAL_DB_PASSWORD` settings. Preserve those exact values under `POSTGRES_BOOTSTRAP_USERNAME` and `POSTGRES_BOOTSTRAP_PASSWORD` so the local database remains accessible, then set `CENTRAL_DB_USERNAME=berkahpos_central_runtime` (or another lowercase role name distinct from the bootstrap role) and choose a separate runtime password. Do not delete or recreate the persistent volume to get past an authentication/ownership error.

To explicitly rerun the local role/grant reconciliation after a deliberate local credential change, with PostgreSQL already running:

```sh
docker compose run --rm --no-deps db-bootstrap
```

This helper targets only the configured local central database and fails closed on unexpected ownership or role-membership conflicts. It is not the tenant-provisioning broker and is not an approved way to create or alter production tenant databases.

## Migrations and environments

The CI workflow creates fresh PostgreSQL 17 central and tenant databases and runs each migration family only against those disposable databases. Do not point the CI workflow at a remote or production DB.

Local Compose is not a substitute for the reviewed PostgreSQL tenant broker. It does not provision a real tenant database or certify tenant A/B isolation. Production tenant provisioning must use distinct tenant owner/runtime/migrator roles and the approved isolated broker. The local app role is not proof that the whole production tenant-provisioning gate has passed.

## Known implementation gaps

- Root manifest, lockfile, PHP 8.4 Docker runtime, Laravel 13, Filament 5 and Sanctum are introduced here.
- Central and tenant migration files are smoke-tested on PostgreSQL 17. That is not proof of complete product data parity.
- The effective-configuration business API, identity/enrollment flows, privileged PostgreSQL broker, host middleware, and true tenant A/B denial tests remain separate work.
- Flutter still contains a legacy Supabase client. The product is not compliant with the latest owner decision until that path is replaced with tested Laravel API calls.
- The initial KVM2 host is a modest single-node MVP, not HA. Measure workload before changing connection pools, adding replicas, or splitting PostgreSQL onto another host.
