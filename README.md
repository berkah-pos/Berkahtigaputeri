# Berkahtigaputeri — Berkah POS

Berkah POS is a local-first POS and accounting platform being migrated to Laravel with physically isolated tenant databases.

## Canonical architecture

Read first:
- `AGENTS.md`
- `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md`
- `docs/permanent/DOC_00_MASTER_ROADMAP.md`
- `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md`
- `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md`
- `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md`

Runtime target: Laravel 11 / PHP 8.3 / Filament 3 / Sanctum / stancl/tenancy v3, MariaDB 11, Coolify on Hostinger KVM2. One central database and a physical database per tenant are hosted on one private MariaDB server. The active cloud client API is Laravel; no Supabase SDK/API should be used by runtime mobile, browser or server code.

## Canonical configuration source

Workbook:
`config/FINAL_Production_Excel_A_WebC_Template_100Tenants.xlsx`

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE
1 global + 3 templates + 100 tenants + 140 service rows + 108 devices = 352 keys
keyset MD5: 1fd3d64219ecc7c333453c20da80e295
```

Validate/export workbook records without a hosted data mutation:
```sh
python3 scripts/export_workbook_for_laravel.py --validate-only
python3 scripts/export_workbook_for_laravel.py --output build/central-config-import.json
```

After review and backup, import only into the explicitly selected Laravel environment:
```sh
php artisan config:import-workbook build/central-config-import.json
```

The import command may provision isolated tenant databases. Do not execute it on production until backup, dry-run/reconciliation, resource capacity and approval gates are complete.

## Layout

- `pos-app/`: canonical Flutter mobile client; SQLite local-first storage.
- `app/`, `routes/`, `database/`, `config/`: Laravel Central API and tenant backend.
- `Dockerfile`, `docker-compose.yml`, `docker/`, `.env.example`: local/disposable runtime and Coolify deployment contract.
- `scripts/export_workbook_for_laravel.py`: canonical workbook validator/exporter.
- `app/Console/Commands/ImportCanonicalWorkbook.php`: resumable import into Laravel configuration ownership.
- `btp-admin/`: legacy static admin surface; not the new SaaS central control plane.
- `docs/permanent/`: architecture authority, migration sequence and evidence.

## Local backend

```sh
cp .env.example .env
# Replace every placeholder with a unique local secret before startup.
composer install
php artisan key:generate
docker compose up --build
```

The Docker Compose stack expects a populated `.env` file with distinct strong secrets. Never commit it. The app is intentionally not publicly exposed by Compose; configure the deployment proxy/domain in Coolify.

## Testing

```sh
python3 scripts/check_kvm2_contract.py
python3 scripts/export_workbook_for_laravel.py --validate-only
composer validate --no-check-publish
composer install
php artisan migrate --database=central --path=database/migrations/central --force
php artisan route:list --path=api/v1
cd pos-app && flutter pub get && flutter analyze && flutter test
```

Use feature branches and reviewed PRs. A passing source CI is not proof of live staging/production cutover, isolated tenant A/B behavior, backup restoration or Android release signing.

## Legacy-backend retirement

Supabase code/data are not part of the target runtime. Hosted legacy projects must be exported, reconciled, backed up, and cut over under an approved operational runbook before any hosted resources are deleted. Repository source removal does not delete a hosted project or its data.
