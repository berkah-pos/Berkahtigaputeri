> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.** This retained document records a legacy Supabase-era workflow, retired implementation contract, or dated verification snapshot. Its commands, SQL, project identifiers, identity claims and “green/certified/current” labels are historical evidence only. Do not follow them against any hosted environment or connect to a Supabase project. Current platform authority: [ADR-2026-10-17 no-Supabase decision](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md). Current target and acceptance: [DOC_14](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md). Current configuration semantics only: [DOC_00](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md). See the [authority/supersession map](../reports/ARCHITECTURE_AUTHORITY_SUPERSESSION_MAP_2026-10-17.md) and [dated audit snapshot](../reports/ARCHITECTURE_CONFLICT_REGISTER_2026-10-17.md).

---

> **Do not execute the checklist below against the current Final Pos system.** It describes a historical five-row pilot, the retired three-layer model, and obsolete UI instructions. The active contract is `DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` for workbook/inheritance semantics and `ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` plus `DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` for the Laravel/PostgreSQL 17 target. The old Supabase schema/RLS files are archive-only; do not execute their contents. The canonical workbook inventory remains 352 entries.

---

# HISTORICAL / SUPERSEDED — DOC_02 VERIFICATION (RETIRED 3-LAYER PILOT)

## Tujuan
Memverifikasi fondasi 3 layer + 2 layanan pada tabel LIVE `app_config(key PRIMARY KEY, value JSONB, updated_at)`.

## 1. Verifikasi schema dan 5 row minimum
Copy paste query berikut di **Supabase SQL Editor**:

```sql
select key, value->>'version' as version, updated_at
from app_config
where key in (
  'global',
  'tenant:berkah_sumber',
  'tenant:berkah_sumber:service:pos',
  'tenant:berkah_sumber:service:akuntansi',
  'device:infinix_xos_123'
)
order by key;
```

Expected: tepat 5 key pilot berikut tersedia:

- `global`
- `tenant:berkah_sumber`
- `tenant:berkah_sumber:service:pos`
- `tenant:berkah_sumber:service:akuntansi`
- `device:infinix_xos_123`

Jika row belum ada, jalankan `DOC_02_SUPABASE_SCHEMA_V1.sql` di Supabase SQL Editor terlebih dahulu.

## 2. Verifikasi UI LIVE
Buka:

`https://berkah-ajb-dev.github.io/Berkahtigaputeri/btp-admin/`

Default target:
- tenant: `berkah_sumber`
- device: `infinix_xos_123`

Isi Supabase URL + Anon/Publishable Key, lalu klik **LOAD 5 LAYER**.

UI harus menampilkan:

`Efektif config: GLOBAL + TENANT(berkah_sumber) + DEVICE(infinix) + 2 layanan`

Status load harus menunjukkan kelima key dan precedence:

`GLOBAL < TENANT < SERVICE POS/AKUNTANSI < DEVICE`

DEVICE adalah override tertinggi.

## 3. Verifikasi save + version increment
Lakukan test berurutan:

1. Klik `SAVE GLOBAL` -> row `key='global'` harus berubah dan `value.version` naik 1.
2. Klik `SAVE DEVICE` -> row `key='device:infinix_xos_123'` harus berubah dan `value.version` naik 1.
3. Klik `SAVE TENANT` -> `key='tenant:berkah_sumber'`.
4. Klik `SAVE SERVICE POS` -> `key='tenant:berkah_sumber:service:pos'`.
5. Klik `SAVE SERVICE AKUNTANSI` -> `key='tenant:berkah_sumber:service:akuntansi'`.

Verifikasi ulang di SQL Editor:

```sql
select key, value->>'version' as version, updated_at
from app_config
order by key;
```

## Acceptance P1
- Admin membaca 5 key, bukan hanya global+device.
- Semua tombol SAVE menulis ke key yang benar.
- `version` increment setiap save.
- Tidak menggunakan schema lama `(device_id, key, value)`.
