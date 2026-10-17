# Laravel + PostgreSQL 17 Local Development

This is the initial backend platform scaffold for Hostinger KVM2 + Coolify. It does not yet implement the complete product API, tenant provisioning privileges, or mobile migration.

## Requirements

- Docker Engine and Docker Compose
- Git

No Supabase project, account, key, endpoint, SDK, or service is needed.

## Start the local development stack

1. Copy `.env.example` to `.env`.
2. Keep the local PostgreSQL values local-only; never reuse them in staging or production.
3. Build and start the local app and PostgreSQL 17 service:

   ```sh
   docker compose up --build -d
   ```

4. Check `http://localhost:8000/api/v1/platform-health`.

The Compose file binds both application and database ports to loopback only. Its PostgreSQL volume is local development data, not production data and not the disposable CI database.

## Migrations and environments

The CI workflow creates fresh PostgreSQL 17 central and tenant databases and runs each migration family only against those disposable databases. Do not point the CI workflow at a remote or production DB.

This baseline does not yet provision tenant databases or prove restricted tenant grants. The local sample uses a privileged developer role only for disposable testing; production must use a reviewed tenant broker and distinct least-privilege runtime roles.

## Known implementation gaps

- Root manifest, lockfile, PHP 8.4 Docker runtime, Laravel 13, Filament 5 and Sanctum are introduced here.
- Central and tenant migration files are smoke-tested on PostgreSQL 17. That is not proof of tenant privilege isolation or complete product data parity.
- The effective-configuration business API, identity/enrollment flows, privileged PostgreSQL broker, host middleware, and true tenant A/B denial tests remain separate work.
- At the audit base SHA `371b7fdf0bf672b37ceb1023e647f114221bf797`, Flutter source contained a legacy Supabase client. This is a dated source observation, not a dynamic `main` pointer; resolve the live branch and inspect the client before relying on status. The owner ADR prohibits Supabase use, and the signed AAB workflow must remain blocked until the legacy path is replaced with tested Laravel API calls.
- The initial KVM2 host is a modest single-node MVP, not HA. Measure workload before changing connection pools, adding replicas, or splitting PostgreSQL onto another host.
