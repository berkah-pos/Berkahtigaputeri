> **HISTORICAL / SUPERSEDED — DO NOT EXECUTE — NOT CURRENT ACCEPTANCE.**
>
> This Supabase-era guide or result is retained as historical evidence only. Its commands, identities, “current/live/GREEN/CERTIFIED” wording and outcomes do not authorize present-day work and do not satisfy PostgreSQL 17 acceptance. Do not access any Supabase project, including read-only access, and never run `scripts/sync_excel_to_supabase.py`, including `--dry-run`.
>
> Current authority: [DOC_00](DOC_00_CANONICAL_ARCHITECTURE_DECISION.md), [ADR-2026-10-17](ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md), [DOC_14](DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md), [roadmap](DOC_00_MASTER_ROADMAP.md), [authority map](AUTHORITY_AND_SUPERSESSION_MAP.md). The initial backend smoke pass belongs only to commit `aab154f87342f2a02a1319e1d370ce831dbef522` / run [39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149); full product and release gates remain NOT VERIFIED.
>
> ---
>
# DOC_04 - ARSITEKTUR ADMIN SAAS (PERMANEN)

## Struktur Folder di Repo (Akumulasi Permanen)
```
/docs/permanent/
  DOC_00_MASTER_ROADMAP.md
  DOC_01_3_LAYER_CONFIG.md
  DOC_02_SUPABASE_SCHEMA_V1.sql
  DOC_03_RLS_AUTH.sql
  DOC_04_ADMIN_ARCHITECTURE.md
  DOC_05_FEATURE_FLAGS.md
  DOC_06_AUDIT_VERSIONING.md

/btp-admin/
  index.html (redirect ke clients.html)
  clients.html (Super Admin List - Prioritas 3)
  edit.html (Form 43 fields dengan Final Pos effective config)
  login.html (Supabase Auth - Prioritas 2)
```

## Flow Banyak Clients Submit Beda 2 Layanan

### Skenario: 10 Clients Submit Bersamaan
1. Client A (Toko A) submit: service_pos.mdr=0.5% (paket pro)
   -> Write key='tenant:clientA:service:pos' saja, tidak ganggu global
2. Client B (Toko B) submit: service_pos.mdr=0.7% (paket basic)
   -> Write key='tenant:clientB:service:pos' saja
3. Tidak ada tabrakan karena key beda

### Skenario: 2 Layanan Beda di 1 Client
Tenant berkah_sumber:
- butuh POS dengan QRIS ON, Transfer OFF
- butuh Akuntansi dengan auto jurnal ON
-> 2 rows:
  tenant:berkah_sumber:service:pos {qris_enabled:true, transfer_enabled:false}
  tenant:berkah_sumber:service:akuntansi {auto_jurnal:true}

Canonical effective-config runtime tidak menggabungkan kedua service tersebut. Satu request hanya memakai service yang diminta:

```text
GLOBAL -> TEMPLATE -> TENANT -> SERVICE(requested) -> DEVICE
```

## Prioritas Eksekusi / Tabel Inti

Verifikasi **6 tabel** Final Pos/config utama ada:

```text
tenants
devices
licences
app_config
config_history
tenant_services
```

`app_config` canonical workbook-owned mempunyai tepat 352 key:

```text
1 global + 3 template + 100 tenant + 140 service + 108 device
```

Admin normal config replacement menggunakan `update_app_config_atomic(key, new_value, expected_version)` agar version increment bersifat atomic.

## Catatan Permanen

- Jangan hapus dokumen permanen; verification lama harus dipindah/ditandai historical.
- Semua SQL rerunnable tidak boleh menurunkan version config yang lebih baru.
- Version JSONB dikelola oleh atomic RPC untuk normal replacement.
- TEMPLATE adalah layer canonical dan tidak boleh dihilangkan dari effective config.
