# 01 — Release Scope and Gates

**Tanggal audit:** 2026-10-20 (Asia/Jakarta)  
**Status workstream:** **BLOCKED — rekomendasi tersedia; kandidat SaaS belum memenuhi syarat RC/UAT**  
**Keputusan rilis:** **NO-GO untuk rilis SaaS publik pada baseline yang diaudit.** Ini rekomendasi, bukan persetujuan go-live.  
**Usulan versi:** **v1.0.0-rc1** sebagai ID kandidat hanya setelah scope owner disahkan dan semua gate wajib ditutup. Versi ini belum layak ditag. Tidak ada tag, merge, deployment, perubahan DNS, atau akses database produksi yang dilakukan.

## 1. Ringkasan eksekutif

Repository kanonis: **berkah-pos/Berkahtigaputeri**. HEAD main yang dicatat sebelum pekerjaan repo: **371b7fdf0bf672b37ceb1023e647f114221bf797**. Branch audit: **audit/release-scope-governance-20261019**. Pekerjaan hanya menambah dokumentasi audit; tidak mengubah source produk, schema, workflow, atau dokumen permanen otoritatif.

Temuan utama:

1. UI dan logika lokal Flutter ada untuk CRUD produk, checkout lokal, penerimaan stok, laporan per perangkat, schema SQLite, event outbox dan jurnal lokal. Source membuktikan keberadaan implementasi, tetapi suite pada HEAD audit dan UAT fisik tidak dijalankan dalam sesi ini.
2. **Cloud SaaS target belum terbukti.** Flutter masih mendeklarasikan/memanggil supabase_flutter; ADR owner 2026-10-17 melarang seluruh penggunaan produk/proyek Supabase. Route Laravel yang terverifikasi pada main hanya health API (GET /api/v1/platform-health), bukan login, effective-config atau penerimaan sync transaksi. Ini blocker rilis multi-tenant.
3. **Tenant isolation PostgreSQL belum VERIFIED.** Kerangka Laravel/PostgreSQL 17 ada. CI baseline yang didokumentasikan berjalan pada SHA **aab154f87342f2a02a1319e1d370ce831dbef522**, bukan HEAD audit; cakupannya hanya baseline/migration smoke. Grant A/B PostgreSQL, broker provisioning, host spoofing, dan reset konteks worker belum lulus bukti exact-SHA.
4. Workbook validator baru ada, tetapi tidak dijalankan langsung pada audit ini. **scripts/export_workbook_for_laravel.py** memvalidasi 7 sheet, 352 key, kategori 1/3/100/140/108 dan keyset MD5. Namun acceptance matrix merujuk **scripts/test_canonical_workbook_contract.py** yang tidak ditemukan pada path itu di main, mensyaratkan manifest SHA-256, dan workflow lama masih memanggil writer Supabase terlarang, meskipun memakai argumen --dry-run. Konflik ini perlu diarahkan ke owner workbook/CI, bukan diselesaikan dengan menjalankan workflow.
5. **Payment gateway, subscription server-enforced, webhook, AI insight dan printer/scanner tidak layak masuk rilis pertama** berdasarkan bukti saat ini. QRIS di checkout adalah metode tender lokal, bukan integrasi gateway. Tombol, model atau dokumen bukan bukti subsistem aktif.
6. Backup/restore, observability/alert, staging deployment, rollback drill, signing certificate/update compatibility dan business UAT belum dibuktikan pada satu kandidat terintegrasi exact-SHA.

**Rekomendasi scope:** kandidat pilot awal paling aman adalah **local-only, satu perangkat**, dan tidak dipromosikan sebagai SaaS sampai build/signing/UAT juga lulus. Bila rilis pertama harus berupa SaaS multi-tenant, tetap **NO-GO** sampai semua gate P0 ditutup pada satu commit kandidat. Owner perlu memilih target produk tersebut secara eksplisit.

## 2. Baseline, branch dan batasan kerja

| Item | Nilai / status |
|---|---|
| Repository | https://github.com/berkah-pos/Berkahtigaputeri |
| Base SHA yang dicatat sebelum mengubah repo | 371b7fdf0bf672b37ceb1023e647f114221bf797 |
| Branch laporan | audit/release-scope-governance-20261019 |
| File laporan | `docs/reports/preproduction/2026-10-18/01_RELEASE_SCOPE_AND_GATES.md` |
| Scope perubahan | Laporan audit saja; tidak ada implementasi produk |
| Database/runtime produksi | Tidak diakses |
| Supabase | Tidak diakses, bahkan read-only; legacy sync script tidak dijalankan |
| Merge/tag/deployment/DNS | Tidak dilakukan |
| Commit pertama yang menambahkan laporan | 62aae89475f9f37334d65fb1a0583cfeacbb1664 (sebelum metadata PR ditambahkan) |
| Draft PR dokumentasi | [#91 — release scope and governance recommendation](https://github.com/berkah-pos/Berkahtigaputeri/pull/91); final branch head SHA dicatat di metadata/description PR setelah konsolidasi akhir |

HEAD `371b7fdf0bf672b37ceb1023e647f114221bf797` terverifikasi sebagai `main` saat audit ulang 2026-10-20. Pada SHA ini, GitHub mengembalikan dua check-run bernama `Dependabot` (run **39186055413** dan **39184121515**, attempt 1, event `dynamic`); keduanya sukses sebagai otomasi Dependabot, bukan required application CI. Commit status API berstatus `pending` dengan `total_count=0`. Run CI aplikasi/workbook/PG17 yang terlihat berasal dari SHA lebih lama atau branch PR terpisah dan **tidak diwariskan** sebagai acceptance bagi HEAD audit atau calon RC baru.

## 3. Dokumen otoritatif yang dibaca sesuai urutan

Semua dokumen berikut dapat diambil dari repo main. DOC_12/DOC_13 dibaca penuh termasuk supersession notice. Dokumen target/plan tidak dianggap bukti runtime.

| Urutan | Dokumen | Fungsi / batas bukti |
|---:|---|---|
| 1 | [AGENTS.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/AGENTS.md) | Dibaca penuh; urutan, batas keamanan, status bukti dan larangan Supabase. |
| 2 | [DOC_00_CANONICAL_ARCHITECTURE_DECISION.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md) | Dibaca penuh; otoritas lima lapis dan inventory 352 entry. |
| 3 | [ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md) | Dibaca penuh; historis/subordinate bila konflik dengan keputusan 17 Oktober. |
| 4 | [DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md) | Dibaca penuh; target PostgreSQL 17, role/grant dan acceptance gates; tidak menyatakan implementasi lengkap. |
| 5 | [DOC_00_MASTER_ROADMAP.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/DOC_00_MASTER_ROADMAP.md) | Dibaca penuh; Phase 0–7 dan urutan release gates. |
| 6 | [docs/permanent/README.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/README.md) | Dibaca penuh; indeks otoritas dan batas evidence. |
| 7 | [DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md) | Dibaca penuh (440 baris); SQLite/outbox, accounting, subscription dan bukti. |
| 8 | [DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md) | Dibaca penuh; snapshot historis Flutter, bukan runtime proof. |
| 9–10 | [DOC_01_3_LAYER_CONFIG.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/DOC_01_3_LAYER_CONFIG.md), [.cursor/rules/berkah-pos.mdc](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/.cursor/rules/berkah-pos.mdc), [.github/muse-instructions.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/.github/muse-instructions.md) | Dibaca; tiga lapis adalah nama lama dan tidak menggantikan kontrak lima lapis. |
| Setelah itu | [docs/HARDENING/README.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/HARDENING/README.md), [README.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/README.md) | Dibaca; pernyataan historis bukan hasil test saat ini. |
| Source terpilih | composer.json, routes/api.php, routes/web.php, Flutter auth/config/screens/repositories/database, exporter workbook, import command, release/workbook workflows, required-check matrix, payment/AI hardening reports | Diperiksa untuk source dan konfigurasi yang aktif; detail di bawah. |

Otoritas platform terbaru adalah [ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md): Laravel Central API + PostgreSQL 17; penggunaan produk/proyek Supabase dilarang, termasuk read-only. DOC_00 tetap satu-satunya otoritas untuk GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE dan 352 entry. Tidak ada dokumen otoritatif diubah.

## 4. Feature inventory: proposed masuk/keluar/belum terbukti/owner

“Source ada” bukan berarti fitur diuji atau layak production. Scope usulan di bawah sengaja ketat.

| Fitur | Bukti source/route | Usulan scope rilis pertama | Status awal / syarat |
|---|---|---|---|
| Login/identity | pos-app/lib/features/auth/login_screen.dart memakai Supabase sign-in; pos-app/lib/main.dart melakukan Supabase.initialize; aplikasi trial lama hanya lookup status via email, bukan autentikasi ownership. | **Keluar dari SaaS release sampai diganti.** Laravel auth masuk hanya setelah diuji. Pilot lokal harus memakai local-only eksplisit. | **FAILED terhadap arsitektur target / belum lulus.** Tidak boleh memakai kredensial Supabase. |
| Tenant/service/device configuration | DOC_00 menentukan lima lapis; exporter dan app/Console/Commands/ImportCanonicalWorkbook.php ada. Route API hanya health. app/Services/EffectiveConfigResolver.php tidak ditemukan pada path yang dicari di main; Flutter ConfigService masih RPC Supabase. | **Keluar dari cloud release** sampai Laravel API, auth, template inheritance dan parity tersedia. | NOT VERIFIED; validasi workbook, precedence, device ownership dan pemisahan POS/Akuntansi wajib dijalankan. |
| POS checkout | checkout_screen.dart, payment_service.dart, sqlite_sale_repository.dart; source menunjukkan sale, lines, stock, journal dan outbox disimpan dalam satu transaksi SQLite. | **Masuk pilot lokal satu perangkat saja**, setelah build/UAT lulus. Keluar dari cloud acceptance sampai server sync ada. | Source-verified; test/UAT pada HEAD audit belum dijalankan. |
| Produk/CRUD | product_screen.dart dan sqlite_product_repository.dart; operasi lokal SQLite. | Masuk pilot local-only. | Source-verified; schema upgrade, CRUD dan negative tests perlu lulus. |
| Stok/lot/FEFO | inventory_screen.dart dan pos_database.dart memuat lot/cost layer/stock movement, operasi lokal. | Masuk pilot satu perangkat dengan rekonsiliasi stok awal yang jelas; stok global lintas perangkat keluar. | Source-verified, belum diuji dalam audit. Owner harus memilih kebijakan jika beberapa perangkat offline menjual stok yang sama. |
| Laporan | reports_screen.dart memakai data lokal dan menampilkan outbox pending; UI menyatakan bukan laporan konsolidasi. | Masuk sebagai laporan lokal perangkat saja; bukan SaaS/real-time report. | Source-verified; jangan klaim laporan cloud. |
| Jurnal/accounting | pos_database.dart menyimpan journals/journal_lines; sale repository memanggil JournalService di transaksi lokal. | Untuk pilot, jurnal lokal hanya sebagai fitur pendukung setelah balance/COA/reversal/UAT lulus; bukan general ledger cloud terverifikasi. | Source-verified; full accounting acceptance tidak dijalankan di audit ini. |
| Offline mode | SQLite, local-only path, outbox, pending status dan laporan lokal terlihat di source. | Masuk untuk local-first single-device. Status synced hanya setelah durable server ACK. | Source-verified; crash/restart/retry/rollback belum dijalankan di audit ini. |
| Cloud sync / server ACK | Outbox ditulis local sale repository; routes/api.php hanya health route. Tidak ada endpoint sync bisnis terverifikasi. | **Keluar dari rilis saat ini; P0 untuk SaaS RC.** | NOT VERIFIED; butuh API Laravel autentik, idempotency, conflict handling dan durable ACK. |
| Subscription/entitlement | `database/migrations/central/2026_10_17_000001_create_central_platform_tables.php` mendefinisikan tabel subscription; `app/Console/Commands/ImportCanonicalWorkbook.php:95-99` membuat row `status=trial` dengan kedaluwarsa 14 hari saat tenant baru diimpor. Route lifecycle/enforcement/reconciliation tidak ditemukan pada API aktif. | **Keluar dari rilis pertama** sampai state machine, enforcement server-side, dan keputusan komersial owner disetujui. | Source-verified: importer memiliki default trial 14 hari; importer tidak dijalankan dan tidak ada bukti entitlement runtime. CTA/model bukan bukti billing aktif. |
| Payment gateway | Metode checkout menunjukkan cash/QRIS/transfer. PAYMENT_HARDENING_REPORT.md menyatakan gateway/webhook tidak ditemukan. | **Keluar.** Metode tender lokal bukan gateway payment collection. | NOT FOUND dalam source yang diperiksa; provider tidak dipilih/diuji. |
| Payment webhook | Handler/route aktif tidak ditemukan; laporan payment menyebut signature, replay protection dan event idempotency tidak ditemukan. | **Keluar.** | NOT FOUND / NOT VERIFIED; perlu owner/provider approval dan test signature/replay/refund. |
| AI insight | AI_HARDENING.md menyatakan fitur belum ditemukan; tidak ada LLM client/AI source terverifikasi dari search scope. | **Keluar.** | NOT FOUND di source yang diperiksa; jangan ada klaim AI di UI/release notes. |
| Printer/scanner/barcode/peripherals | Form/model produk punya field barcode; field itu sendiri bukan scanner integration. Physical printer/scanner adapter dan acceptance tidak terbukti. | **Keluar** sampai ada model perangkat dan test fisik bila owner memerlukannya. | NOT VERIFIED. |
| Tenant admin / SaaS multi-tenant | composer.json memuat Laravel 13, Filament 5, Sanctum, tenancy candidate; starter schema dan health route ada. Real PostgreSQL broker/grants dan tenant A/B tests belum diterima. | **Keluar dari public SaaS saat ini.** | **BLOCKED P0.** Scaffold/package bukan isolation proof. |
| Workbook import | ImportCanonicalWorkbook memvalidasi 352 counts dan keyset MD5 serta menulis central/device config. Import dapat menulis DB; tidak dijalankan. | Ops internal, bukan user feature; jangan apply sebelum target/environment disetujui. | Source-verified; eksekusi/import atomicity/versioning belum diuji. |
| Central Admin/static admin | README menyebut btp-admin/ sebagai jalur static legacy; tujuan owner adalah Admin terautentikasi di Filament. Runtime/policy belum diverifikasi. | Keluar dari klaim rilis sampai diuji. | NOT VERIFIED. |
| Android build/signing | berkah-pos-aab.yml memiliki build/test/AAB steps dan menyebut debug-signed sebagai testing-only; publisher release ditolak bila source Supabase aktif. README menyebut Android scaffold parsial. | Tidak rilis publik sebelum exact-SHA build, certificate match dan physical-device/update test. | NOT RUN / NOT VERIFIED pada audit. Tidak ada AAB yang dibangun di sesi ini. |

### Proposed split

- **Pilot bersyarat:** local-only, satu perangkat; produk, terima stok, checkout, laporan lokal dan jejak jurnal lokal. Harus menyatakan tiada cloud login, sync, consolidated reporting, SaaS entitlement ataupun remote backup guarantee.
- **SaaS RC:** belum ada kandidat terintegrasi yang diterima. Harus melewati Laravel auth, tenant/service/device authorization, config/sync API, PG17 grants/isolation, restore, monitoring dan seluruh P0. Jangan menggabungkan hasil dari SHA/PR berbeda.

## 5. Acceptance matrix lintas workstream

Semua gate perlu bukti pada satu kandidat SHA. NOT RUN, skip, wrong-stack, stale-head, atau bukti tanpa artefak adalah tidak lulus.

| ID / priority | Kriteria & bukti wajib | Owner gate (role) | Dependency | Status awal | Syarat penutupan |
|---|---|---|---|---|---|
| P0-01 | Laravel auth/session/token revocation, device enrollment, server-derived membership; config/business APIs yang perlu; source/dependency scan tanpa Supabase runtime/secret/endpoint. | Laravel Platform + Mobile + Security | API contract, identity/config design | BLOCKED | Auth positive/negative tests lulus exact-SHA; legacy Supabase runtime diganti dan tidak dipakai sebagai fallback. |
| P0-02 | PostgreSQL 17 broker dan real roles/grants; pg_roles/db owner/CONNECT/schema/table/sequence/default grants/PUBLIC; dua arah A/B dan central access denial; provisioning idempotent/recoverable; worker context reset. | PostgreSQL DBA/Security + Laravel | Broker, schema, host/context middleware | NOT RUN / NOT VERIFIED | Redacted catalog outputs dan integration artifacts exact-SHA; A tidak CONNECT/CRUD B atau central, begitu pula sebaliknya. |
| P0-03 | Workbook 7 sheets, 352 key unik, count 1/3/100/140/108; deterministic manifest SHA-256 dua kali; precedence TEMPLATE; POS vs Akuntansi; mismatch denial. | Configuration/Flutter Sync + CI Maintainer | Workbook, exporter/importer/resolver | BLOCKED / NOT RUN | Actual offline validator berjalan exact-SHA, path test stale/missing diselaraskan, hash/manifest dan parity lulus tanpa network/DB writes. |
| P0-04 | Fresh central & tenant migrations/lint di disposable PG17; schema inventory, FK/constraints, ledger/monetary invariants; bukan MariaDB. | Laravel Platform + PostgreSQL DBA | Schema review, PG17 CI | PARTIAL baseline-only | Fresh target migration/lint dan schema regression lulus exact-SHA. |
| P0-05 | Encrypted off-host backups untuk central + semua tenant DB + files/recovery material; restore central, ≥2 tenant dan satu tenant terpisah; checksum, balances, isolation, duration/RPO/RTO. | SRE/Recovery + DBA | Stable schema/storage | NOT RUN / NOT VERIFIED | Dated restore report dengan exact commands, disposable environment, outcome dan artifacts. |
| P0-06 | Secrets/security baseline: least privilege, provisioning creds terisolasi dari web/queue, PostgreSQL/Coolify private, TLS/host-proxy protection, rate limits, secret scan, account/device revocation. | Security + DevOps/SRE + Laravel | Auth/tenant/deployment | NOT RUN / NOT VERIFIED | Adversarial tests, redacted env-name proof, scan/network review pada candidate. |
| P0-07 | Isolated staging deployment dengan immutable image built/tested dari SHA kandidat, migrations/readiness/health, auth/tenant/smoke journeys dan rollback observation. | DevOps/SRE + QA | P0-01..06 | NOT RUN / NOT VERIFIED | Deployment identity/digest, logs, health/tests dan rollback observation. Tidak butuh prod deploy. |
| P0-08 | Observability dan active alerts atas error/latency, sync backlog, DB exhaustion, backup dan security events; synthetic alert diuji. | SRE/Operations | Deployment, telemetry, responder | NOT RUN / NOT VERIFIED | Alert delivery evidence, thresholds, runbook dan responder terdaftar. |
| P0-09 | UAT business/accounting: product→stock receive→checkout→report; tax/rounding, FEFO/FIFO, balanced journal/COA, reversal/period rules, offline restart. | Product Owner + Accounting Owner + QA | Stable build/scope | NOT RUN / NOT VERIFIED | Sign-off yang terikat exact artifact SHA dan test results. |
| P0-10 | Rollback/forward recovery rehearsal; app artifact identity, migration compatibility, backup restore fallback, timed evidence. | DevOps/SRE + DBA | Staging + restore | NOT RUN / NOT VERIFIED | Rehearsal berhasil, recovered service healthy, data/invariants checked. |
| P0-11 | Owner signs release scope/audience, residual risks, rollout and rollback; release approval remains independent from audit. | Business/Product Owner + Release Owner | All P0 and UAT | DECISION REQUIRED | Explicit approval tied to exact candidate SHA. |
| P0-12 | Required workflow matrix, CI run ID + attempt, jobs/artifacts and green conclusions tied to one integrated candidate SHA; no skipped/stale/wrong-SHA result. | Release Engineering / QE + workflow owners | Integration of required source PRs; P0-01–P0-11 | BLOCKED: only Dependabot dynamic checks observed on main HEAD | All mandatory Flutter, Laravel/PG17, workbook, security and release checks complete successfully on the same candidate SHA, with artifacts/log links. |
| P1-01 | SQLite atomicity sale/lines/stock/journal/outbox; crash/restart/retry/migration; transaction-ID replay/conflicting payload. | Mobile Lead + QA | Local DB contract | SOURCE-VERIFIED, TEST NOT RUN HERE | Flutter tests and fault-injection output for exact candidate. |
| P1-02 | Authenticated sync acceptance, atomic server writes, durable receipt, idempotent identical replay, conflict on changed payload, ACK only after commit. | Laravel + Mobile Sync + QA | P0-01/02 + schema | NOT VERIFIED | Disposable PG17 end-to-end tests and replay/timeout/concurrency evidence. |
| P1-03 | Ledger integrity, immutable posted journals/reversals, COA, tax/rounding, period close and sale/inventory/COGS reconciliation. | Accounting Owner + QA + Laravel | Business policy/local/cloud ledger | PARTIAL source-only | Domain tests and signed accounting UAT; cloud acceptance is separate. |
| P1-04 | Exact Android package/version, reviewed manifest/scaffold, publisher-vs-debug signing, SHA-256 cert match and upgrade/install test. | Android Release Lead + Release Owner | Migrated client/signing | NOT RUN / NOT VERIFIED | Exact-SHA artifact build/source scan and physical-device upgrade evidence; no debug artifact publication. |
| P1-05 | Replace legacy workbook workflow; validator path current, SHA-256 manifest, exact count artifacts, offline-only operation and required-check wiring. | Workbook/CI Owner | P0-03 | FAILED control conflict / NOT RUN | Reviewed CI change, no invocation of prohibited writer, test/run logs and manifest hashes. |
| P1-06 | Data continuity: already-existing owner-controlled offline export outside Supabase with provenance/checksum/completeness/privacy OR explicit clean-start approval. | Data Continuity + Business Owner | Owner artifact decision | BLOCKED / NOT VERIFIED | No Supabase export; owner-approved basis and reconciliation evidence. |
| P2-01 | Plans, subscription lifecycle and server-side entitlement | Monetization Owner + Laravel | Product pricing/grace/offline entitlement decision | OUT OF SCOPE | Separate approved scope + server-side state transition tests. |
| P2-02 | Gateway/webhooks/refunds/receipt verification | Payment/Finance Owner + Backend Security | Provider/model decision | OUT OF SCOPE | Provider-approved signature/replay/idempotency/refund/reconciliation tests. |
| P2-03 | AI insight and privacy/spend controls | Product + AI/Privacy/Security | Use case/vendor/data retention decision | OUT OF SCOPE | Server proxy, PII minimization, tenant quotas, output grounding and outage-safe tests. |
| P2-04 | Hardware integrations and advanced scale/HA | Device Integration + Platform/SRE | Models, hardware contract, measured workloads | OUT OF SCOPE | Physical device tests and load/restore measurements; no unmeasured capacity promises. |

### Rule for gate status

Test files, routes, migrations, historical reports, and green runs on other SHAs do not close a gate. Every closure must identify exact candidate SHA, run ID/attempt, workflow/job, command/exit code, environment/database, redacted logs/artifact URL and reviewer/owner role.

## 6. Temuan audit: severity, confidence, remediation

Severity menunjukkan dampak rilis/keamanan, bukan atribusi kesalahan.

### F-01 — Flutter identity/config masih menggunakan Supabase yang dilarang

- **Severity:** P1 release-blocking; **confidence:** High; **status:** SOURCE-VERIFIED.
- **Evidence:** `pos-app/pubspec.yaml:16` mendeklarasikan `supabase_flutter`; `pos-app/lib/main.dart:3,11-40` mengimpor/inisialisasi `Supabase.initialize` dengan build defines Supabase; `pos-app/lib/core/config/config_service.dart:59-103` mensyaratkan sesi Supabase dan memanggil `get_effective_config`. Semua bertentangan dengan ADR 2026-10-17 no-Supabase.
- **Impact:** cloud login/config belum melalui backend yang disetujui; mengaktifkan legacy path melanggar policy. Tenant/device ID lokal bukan identitas yang terautentikasi.
- **Test/reproduction:** source inspection melalui GitHub file interface. flutter analyze --no-pub dan flutter test --no-pub --reporter expanded NOT RUN; exit code N/A.
- **Fix/rekomendasi:** implementasikan Laravel auth/enrollment, membership/device authorization, effective-config API dan Flutter adapter di PR terpisah. Jangan menggunakan fallback Supabase.
- **Negative/regression test:** token missing/expired ditolak; spoof tenant/device ditolak; device disabled ditolak; valid login/config berjalan pada PG17 disposable; scan source/package/build membuktikan tidak ada Supabase runtime path/secret.

### F-02 — Route Laravel hanya health scaffold, bukan product API

- **Severity:** P1; **confidence:** High; **status:** SOURCE-VERIFIED.
- **Evidence:** `routes/api.php:5-11` hanya mendefinisikan `GET /v1/platform-health` (terdaftar sebagai `/api/v1/platform-health`). Business auth/config/sync route tidak ditemukan di file API aktif.
- **Impact:** tidak ada bukti server tenant-scoped login, config delivery ataupun durable sale/outbox acceptance. Event lokal tidak boleh disebut synced ke cloud.
- **Test:** php artisan route:list --path=api/v1 NOT RUN untuk HEAD audit; exit code N/A.
- **Fix:** implement endpoint/policy, enumerate routes dan jalankan positive/negative HTTP tests pada PG17 disposable.
- **Regression test:** route bisnis tidak anonymous; cross-tenant denied; receipt sama pada replay; ACK hanya setelah commit durable.

### F-03 — Tenant isolation / PG17 provisioning belum diterima

- **Severity:** P0 untuk multi-tenant SaaS; **confidence:** High bahwa bukti belum ada (ini bukan klaim telah terjadi exploit); **status:** BLOCKED / NOT VERIFIED.
- **Evidence:** stack/migration starter ada. DOC_14 dan roadmap mengharuskan broker PostgreSQL-specific, katalog/grants nyata dan adversarial A/B. Tidak ada hasil A/B PostgreSQL yang memenuhi acceptance dan terikat HEAD 371b7f... Run 39005405149 memakai SHA aab154f... dan hanya menunjukkan baseline migration smoke.
- **Impact:** belum terbukti tenant tidak dapat connect/read/write tenant lain atau central private data.
- **Tests:** gate command php artisan test --filter=TenantProvisioningPostgresGrantsTest, pg_catalog/grant inspection, Host/membership/device negatives, worker-context reset NOT RUN pada HEAD audit; exit code N/A. Nama test adalah kebutuhan acceptance, bukan klaim file test telah ditemukan/berjalan.
- **Fix:** bangun dan review least-privilege broker; pisahkan tenant DB/runtime/migrator roles; jangan beri privileged provisioning credentials ke web/normal queue. Jalankan dengan user PG17 disposable.
- **Negative test:** A cannot CONNECT/CRUD B atau central; B cannot access A; PUBLIC access revoked as required; runtime lacks CREATEDB/CREATEROLE/owner; worker A→B resets after success/exception/retry; hostile Host dan forged identifiers fail closed.

### F-04 — Workflow workbook menginvokasi Supabase writer terlarang walau dry-run

- **Severity:** P1 governance/CI conflict; **confidence:** High; **status:** SOURCE-VERIFIED; owner action required.
- **Evidence:** `.github/workflows/canonical-workbook-validate.yml:58-68` menjalankan `python -m unittest discover -s scripts/tests -p 'test_*.py'` lalu `scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352`. Script legacy mengandung jalur REST/RPC Supabase; `AGENTS.md` dan ADR terbaru melarang eksekusinya. Walaupun mode dry-run diklaim no-write oleh script, policy tetap melarang menjalankan command ini; audit tidak menjalankannya.
- **Impact:** CI masih coupled ke writer legacy mutation-capable dan kontrol yang tidak lagi authoritative; perubahan argumen di masa depan dapat membuat risiko menjadi nyata. Workflow bisa dipicu perubahan dokumen permanen.
- **Fix:** rujuk ke CI/workbook owner. Ganti dengan offline Laravel workbook validator yang disetujui, keluarkan writer dari active CI execution dan emit SHA-256 manifest/count artifacts. Jangan mengedit authority docs diam-diam atau menjalankan writer.
- **Regression:** workflow static guard menolak invocation writer legacy; validator --validate-only bekerja offline/no DB; hash dan exact count disimpan.

### F-05 — Validator workbook vs acceptance criteria tidak konsisten

- **Severity:** P1; **confidence:** High untuk perbedaan path/criteria; **status:** SOURCE-VERIFIED discrepancy, workbook run NOT RUN.
- **Evidence:** `scripts/export_workbook_for_laravel.py:15-22,72-114,198-219` memvalidasi 7 sheets, 352 key unik, counts 1/3/100/140/108, template IDs, expected keyset MD5 dan menyediakan `--validate-only`. `config/ci/required-check-matrix.json` merujuk `scripts/test_canonical_workbook_contract.py`, tetapi path tersebut tidak ditemukan pada tree `main` yang diaudit. Matrix meminta manifest SHA-256 dan repeat-export, sedangkan tidak ada current-head manifest/hash artifact yang diperoleh.
- **Impact:** prosedur release menunjuk test yang tidak ditemukan dan belum ada evidence SHA-256/repeatability candidate.
- **Commands:** python3 scripts/export_workbook_for_laravel.py --validate-only; python3 -m unittest discover -s scripts/tests -p 'test_*.py'; two-clean-export byte/hash comparison — NOT RUN, exit code N/A karena checkout/runtime lokal tak tersedia.
- **Fix:** owner workbook/CI selaraskan validator aktif dan test paths, validasi workbook XLSX offline, keluarkan source SHA-256, manifest SHA-256, repeat-run comparison, counts.
- **Regression:** dua export clean identik byte-for-byte dan SHA-256; exact sheets/count/hash pass tanpa network/DB.

### F-06 — Release build compliant terhalang legacy Supabase code

- **Severity:** P1; **confidence:** High; **status:** SOURCE-VERIFIED, build NOT RUN.
- **Evidence:** .github/workflows/berkah-pos-aab.yml menolak publisher-signed release bila source mengandung supabase_flutter, Supabase.initialize, SUPABASE_URL atau SUPABASE_PUBLISHABLE_KEY, dan source saat ini cocok dengan pola itu. Debug signing dilabeli testing-only.
- **Impact:** belum ada publisher-signed compliant AAB yang terbukti; debug artifact tidak layak publikasi.
- **Commands:** flutter analyze --no-pub; flutter test --no-pub --reporter expanded; bash tool/prepare_android_host.sh; flutter build appbundle --release; signing certificate comparison NOT RUN, exit code N/A.
- **Fix:** ganti integration Laravel, update build config ke approved API configuration, lalu build/protect release signing dan check cert lineage.
- **Regression:** exact-SHA AAB + digest/SBOM; source scan bersih; physical install/update pass; release signing certificate SHA-256 cocok dengan accepted app lineage. Tidak ada signing secret atau app release dalam audit ini.

### F-07 — Payment/subscription/webhook/AI tidak terbukti diimplementasikan

- **Severity:** P2 bila out-of-scope; P1 bila dijanjikan di release; **confidence:** High di jalur source yang diperiksa; **status:** NOT FOUND / NOT VERIFIED.
- **Evidence:** docs/HARDENING/PAYMENT_HARDENING_REPORT.md mengatakan gateway/webhook tidak ditemukan dan tests tidak dijalankan; docs/HARDENING/AI_HARDENING.md menyatakan AI insight tidak ditemukan; PaymentService hanya menyediakan cash/QRIS/transfer tender.
- **Impact:** QRIS jangan diklaim sebagai gateway; subscription model/CTA bukan enforcement; AI tidak boleh masuk release notes tanpa subsistem dan test.
- **Fix:** pertahankan di luar scope rilis pertama. Owner dapat membuka workstream terpisah setelah memutuskan provider/use case.
- **Regression:** scope dan release notes tidak menjanjikan online billing, webhook, AI, atau entitlement tanpa server-side end-to-end tests dan staging evidence.

### F-08 — Staging, restore, alert, rollback dan business UAT belum dibuktikan

- **Severity:** P0 untuk public SaaS launch; **confidence:** High bahwa bukti tidak terdapat di audit snapshot; **status:** NOT RUN / NOT VERIFIED.
- **Evidence:** DOC_14/matrix mewajibkan bukti. Baseline report menyebut Coolify staging/production, PG grants, backup/restore dan capacity belum verified. Artefak pada exact main HEAD 371b7f... untuk deploy/restore/alert/rollback/UAT tidak ditemukan dalam scope audit.
- **Tests:** staging deploy, health checks, restore runbook, alert test, rollback rehearsal dan UAT NOT RUN; exit code N/A.
- **Fix:** SRE/DBA/QA jalankan gate pada staging terisolasi memakai synthetic data dan immutable image; lampirkan outcome dan owner sign-off. Jangan deploy production sebagai bagian audit.
- **Regression:** DB/files berhasil direstore, balances/tenant boundaries sesuai, synthetic alert diterima responder, rollback/forward recovery lulus, image SHA cocok kandidat.

### F-09 — Import workbook menetapkan trial 14 hari tanpa bukti kebijakan entitlement aktif

- **Severity:** P1 governance/commercial-policy risk bila importer dijalankan; **confidence:** High; **status:** SOURCE-VERIFIED, import NOT RUN.
- **Evidence:** `app/Console/Commands/ImportCanonicalWorkbook.php:95-99` membuat subscription untuk tenant baru dengan `status=trial` dan `expires_at=now()->addDays(14)`. `routes/api.php:5-11` hanya memuat health route, sehingga source yang diperiksa tidak membuktikan enforcement entitlement atau lifecycle subscription.
- **Impact:** import manifest suatu hari dapat menciptakan asumsi trial/masa berlaku komersial yang belum disahkan owner. Ini **bukan** bukti subscription telah aktif pada runtime, bukan bukti billing berjalan, dan importer tidak dijalankan dalam audit.
- **Rekomendasi:** minta owner menyetujui apakah trial 14 hari merupakan kebijakan produk; jika tidak, pisahkan pembuatan tenant dari seeding entitlement dan ubah melalui PR implementasi tersendiri. Jangan mengubah source pada workstream audit ini.
- **Negative/regression test:** pada disposable PostgreSQL 17, import tenant baru tanpa kebijakan komersial yang disetujui tidak boleh memberi akses premium secara implisit; tanpa entitlement valid API harus fail closed; uji status trial/expired dan audit event setelah kebijakan owner disetujui.

## 7. Workbook 352-entry contract: status bukti

Kontrak DOC_00: global 1, templates 3 (BASIC, PRO, ENTERPRISE), tenants 100, services 140, devices 108, total **352**. Urutan wajib GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE; nilai yang tidak di-override tetap diwariskan. Satu request hanya resolve satu service dan tidak boleh menggabungkan POS dengan Akuntansi.

- **SOURCE-VERIFIED:** DOC_00 contract; workbook path ada di main; exporter memuat pemeriksaan sheet/count/key dan expected keyset MD5; Laravel importer memvalidasi count/hash secara source.
- **DOC-ASSERTED:** laporan historis mengklaim workbook CI success pada candidate SHA tertentu.
- **NOT RUN:** validator tidak dijalankan pada audit ini; workbook tidak dibaca melalui runtime Python/openpyxl lokal; tidak ada manifest/hash artefak exact-head.
- **NOT VERIFIED:** workbook→Laravel API→Flutter parity; per-service resolution; version/CAS; mismatch tenant/device denial.

Ini **bukan PASS 352 entry**. Executor berikutnya perlu menjalankan validator no-network/no-database pada candidate checkout, mencatat command/exit code, menghasilkan sumber/manifest SHA-256 serta reproducible hashes, lalu menguji semantik service/template. Writer Supabase dan semua workflow Supabase dikecualikan.

## 8. Test dan CI execution log

Checkout source lokal tidak tersedia. Percobaan aktual `git clone --quiet --depth 1 https://github.com/berkah-pos/Berkahtigaputeri.git /tmp/btp-release-audit` gagal karena container tidak dapat me-resolve `github.com` (exit code 128); tidak ada tes Flutter/PHP/workbook yang diklaim dijalankan.

| Command / CI | Lingkungan | SHA/run | Hasil / exit code | Artifact/log |
|---|---|---|---|---|
| git clone --quiet --depth 1 https://github.com/berkah-pos/Berkahtigaputeri.git /tmp/btp-audit | Container audit; network unavailable | Baseline 371b7fdf... dari repo interface | FAILED karena akses lingkungan, exit code 128 (Could not resolve host: github.com); bukan test aplikasi. | Sanitized command result; checkout tidak tercipta. |
| python3 scripts/export_workbook_for_laravel.py --validate-only | Offline workbook validation | HEAD 371b7f... | NOT RUN; exit code N/A, checkout/runtime tidak tersedia. | None. |
| python3 -m unittest discover -s scripts/tests -p 'test_*.py' | Offline tests | HEAD 371b7f... | NOT RUN; exit code N/A. | None. |
| python3 scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352 | Legacy workflow command yang dilarang | Tidak dijalankan pada SHA mana pun | NOT RUN BY DESIGN; tidak ada exit code. Repo policy melarang eksekusi. | None. |
| flutter analyze --no-pub | Flutter client | HEAD 371b7f... | NOT RUN; exit code N/A. | None. |
| flutter test --no-pub --reporter expanded | Flutter client | HEAD 371b7f... | NOT RUN; exit code N/A. | None. |
| php artisan route:list --path=api/v1 | Laravel + disposable PG17 | HEAD 371b7f... | NOT RUN di audit; exit code N/A. Route source tetap diperiksa. | None. |
| Dependency/install/audit, boot/routes/tests, fresh PG17 central/tenant migrations, production image/health smoke | GitHub Actions; disposable PostgreSQL 17 service | Run **39005405149**, attempt 1, tested SHA **aab154f87342f2a02a1319e1d370ce831dbef522**, job ID **117316738107** | **CI-OBSERVED success untuk SHA itu saja.** Baseline smoke only: locked install, audit, Laravel boot/routes, starter tests, fresh central/tenant migrations, image build dan health/API smoke. Bukan full product acceptance. | [Run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149). Log/artifact link langsung tidak tersedia dari metadata yang diakses. |
| Required CI untuk HEAD `371b7fdf...` | GitHub Actions workflow-runs + check-runs + commit status API | SHA `371b7fdf0bf672b37ceb1023e647f114221bf797`; run 39186055413 + 39184121515, attempt 1 | **BLOCKED / no required app CI evidence.** Dua run dengan event `dynamic`/nama check `Dependabot` selesai `success`; commit status `pending`, `total_count=0`. Ini bukan bukti Flutter, Laravel/PG17, workbook validation, atau Android build. | [Run 39186055413](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39186055413); [run 39184121515](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39184121515).
| Staging, restore, alert, rollback, physical-device UAT | Target terisolasi/hardware diperlukan | Integrated candidate SHA belum dipilih | NOT RUN / NOT VERIFIED. | None. |

Tidak ada secret value, data pelanggan, provider payload atau data database produksi yang disalin ke laporan.

## 9. Go / No-Go decision

### Semua syarat Go wajib dipenuhi

1. Tidak ada gate/finding P0 terbuka.
2. Tenant isolation PostgreSQL 17 lulus dengan role/grant riil dan bidirectional tenant A/B plus central denial.
3. Migration/lint schema applicable lulus pada disposable PostgreSQL 17; workbook 352-entry dan effective-config/service isolation lulus pada kandidat SHA yang sama.
4. Backup mencakup central, setiap tenant DB dan file/recovery material; central restore, multi-tenant restore dan single-tenant restore benar-benar berhasil dan integrity-checked.
5. Security baseline siap: least privilege, protected release signing, service internal private, TLS/host boundary, tak ada backend credential di client, tak ada active Supabase runtime.
6. Isolated staging deployment menggunakan immutable image dari exact candidate SHA; readiness/health dan user journeys lulus.
7. Observability dan alert aktif; synthetic alert terbukti sampai ke responder.
8. UAT ditandatangani product/accounting owner pada artefak rilis yang tepat.
9. Rollback/forward-recovery teruji termasuk kompatibilitas database.
10. Owner bisnis menyetujui scope, risiko tersisa, rollout/rollback dan audiens.
11. Semua evidence terikat SHA/workflow/attempt yang benar; result missing/skip/wrong-stack/stale tetap RED.

### Keputusan saat ini

**NO-GO untuk public SaaS / multi-tenant launch.** P0-01, P0-02, P0-04, P0-05, P0-06, P0-07, P0-08, P0-09, P0-10 dan P0-11 masih BLOCKED/NOT VERIFIED. Jangan membuat RC tag dan jangan deploy produksi berdasarkan laporan ini.

**Pengecualian pilot local-only:** owner dapat mengesahkan pilot satu perangkat terpisah, setelah Android scaffold/build/signing/UAT checkout-stock-tax-journal lulus dan batasannya jelas. Pilot tidak boleh menyatakan cloud login/sync, consolidated reporting, subscription enforcement, atau production recovery. Jika sasaran bisnisnya SaaS berbayar, pengecualian ini tidak memenuhi syarat.

## 10. Out-of-scope eksplisit untuk rilis pertama

- Supabase auth/config/RPC; Supabase sebagai runtime, data source, fallback atau workflow validator.
- SaaS login/membership, tenant/device provisioning dan privileged central admin sebelum Laravel implementation + isolation proof lulus.
- Cloud sales/stock/journal sync, server ACK, multi-device reports dan conflict resolution.
- Subscription purchase/entitlement/renewal/cancellation/refund/offline grace.
- Gateway payment, webhook, receipt verification, refund dan reconciliation. Local tender selection bukan online billing.
- AI insight/LLM bookkeeping/forecast/recommendation.
- Barcode scanner, receipt printer, cash drawer, label printer/hardware model yang belum diuji fisik.
- HA/automatic scale-out/SLA/capacity claims, automatic restore dan backup/DR claims tanpa pengukuran.
- Klaim migrasi data hosted historis: hanya offline export milik owner yang sudah tersedia di luar Supabase dapat dinilai. Selain itu continuity NOT VERIFIED dan perlu keputusan clean-start eksplisit.
- Publishing artifact sebelum certificate/update compatibility dan exact-SHA build diverifikasi.

## 11. Keputusan eksplisit yang masih dibutuhkan dari owner

1. **Tipe produk rilis:** izinkan pilot local-only satu perangkat, atau wajib SaaS login/cloud multi-tenant pada RC1 (pilihan kedua NO-GO sampai semua gate P0).
2. **Daftar fitur dan audiens:** UAT/pilot saja, grup staging terbatas, Play Store terbuka atau SaaS pelanggan umum. Definisikan arti “rilis pertama”.
3. **Continuity data:** apakah ada offline export terkontrol owner di luar Supabase? Bila tidak, setujui/tolak clean-start semantics. Export baru dari Supabase tidak diperbolehkan.
4. **Auth/enrollment:** setujui kontrak Laravel identity/session, membership, device enrollment/revocation dan lifecycle akun support.
5. **Offline stock:** kebijakan ketika beberapa device offline; quota/reservation/reconciliation/oversell workflow.
6. **Accounting UAT:** konfirmasi COA, PPN/rounding/tax snapshot, FEFO/FIFO, journal immutability/reversal, period lock dan returns/refund.
7. **Commercial model:** apakah RC tanpa billing SaaS, trial manual oleh operator, atau subscription server-enforced. Tidak boleh memilih plan/grace/provider berdasarkan asumsi.
8. **Payment:** defer gateway/webhook atau pilih provider/model dan owner untuk signature/replay/idempotency/reconciliation.
9. **AI/hardware:** explicit defer atau tetapkan use case, hardware models dan owner.
10. **Operations/SLO:** pemilik staging, alert recipients, retention, backup frequency, RPO/RTO, incident responder dan rollback authority.
11. **Android app identity:** sumber sertifikat/signing yang authorized serta persetujuan tes certificate/update. Debug AAB tidak untuk publikasi.
12. **Release authority:** siapa yang menandatangani UAT produk/accounting dan siapa yang memutuskan go/no-go final. Audit ini bukan approval tersebut.

## 12. Dependencies, residual risk, next action

**Dependencies:** Mobile/Auth menunggu Laravel contract (Platform Lead); config menunggu workbook validator/resolver/API (Configuration Lead); tenant isolation menunggu broker/grants DBA serta host/membership middleware (DBA + Security); sync menunggu API dan outbox idempotency test (Mobile + API + QA); deployment/observability/restore/rollback menunggu schema/image dan ownership SRE/DBA; business release menunggu scope serta UAT.

**Residual risk:** tidak ada suite lokal dijalankan pada exact HEAD; CI lama sempit dan terikat SHA; aplikasi masih memiliki forbidden legacy platform code; server business transaction API belum verified; PostgreSQL privilege isolation/backup restore/staging ops belum verified; actual workbook validator belum dijalankan; CI workbook workflow menginvokasi writer terlarang. Ini cukup untuk NO-GO tanpa menyimpulkan telah terjadi data breach.

**Urutan langkah berikutnya:**
1. Owner memilih local pilot versus SaaS RC dan menunjuk owner CI/workbook untuk mengganti legacy workflow path tanpa mengubah otoritas permanen diam-diam.
2. Mobile + Platform mengganti Supabase dengan Laravel auth/config/sync dan endpoint tests.
3. DBA + Security membuktikan PostgreSQL 17 grants A/B, central denial, Host spoofing dan worker reset di disposable environment.
4. Workbook owner menjalankan validator offline pada candidate SHA, menghasilkan manifest SHA-256/count dan repeatability proof.
5. QA menjalankan restart/rollback/idempotency/accounting tests; Android owner menjalankan build/signing/physical-device update tests.
6. SRE/DBA menjalankan staging, alert delivery, encrypted backup/restore, rollback dan resource budget evidence.
7. Product/accounting owner menandatangani UAT; release owner menilai ulang seluruh gate pada kandidat SHA yang sama. Hanya sesudah itu release owner memutuskan apakah v1.0.0-rc1 boleh ditag.

---

**Rekomendasi akhir: BLOCKED / NO-GO untuk SaaS RC pada baseline audit ini.** Source mendukung konsep pilot lokal terbatas, tetapi bukan integrated multi-tenant SaaS yang telah diverifikasi. Scope decision owner dan direct test/operations evidence tetap prasyarat; laporan ini bukan persetujuan rilis.
