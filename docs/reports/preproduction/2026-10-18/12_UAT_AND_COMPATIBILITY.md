# UAT & Cross-Subsystem Compatibility — Pre-production Hardening

**Status keseluruhan: BLOCKED — belum layak untuk UAT sign-off.**  
**Tanggal audit:** 2026-10-19 (Asia/Jakarta)  
**Repository:** [berkah-pos/Berkahtigaputeri](https://github.com/berkah-pos/Berkahtigaputeri)  
**Base SHA sebelum perubahan:** 371b7fdf0bf672b37ceb1023e647f114221bf797  
**Branch:** audit/preprod-uat-matrix-2026-10-18  
**Laporan:** docs/reports/preproduction/2026-10-18/12_UAT_AND_COMPATIBILITY.md  
**PR:** belum dibuat saat konten ditulis; akan dipublikasikan sebagai draft.  
**Perubahan source produk:** tidak ada. Hanya laporan UAT ini yang ditambahkan.  
**Keputusan rilis:** tidak ada PASS atau persetujuan go-live yang dikeluarkan.

> **Batas bukti penting:** pemeriksaan dilakukan melalui GitHub repository interface. Tidak ada checkout/repository filesystem, URL staging yang disetujui, akun/device sintetis, allowlist email, browser automation, atau akses ke disposable runtime yang tersedia. Karena itu tidak ada test end-to-end, browser/device test, migrasi, transaksi, atau query database yang diklaim telah dijalankan. Source presence bukan runtime verification. Tidak ada koneksi ke Supabase dan tidak dijalankan skrip sinkronisasi Supabase.

## 1. Ringkasan eksekutif

Pekerjaan ini mempersiapkan UAT lintas subsistem dengan status fail-closed. Berdasarkan source dan dokumen otoritatif:

1. **API produk belum tersedia pada route inventory yang diperiksa.** File [routes/api.php](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/routes/api.php) hanya mendaftarkan GET /api/v1/platform-health (source file baris 1–9). File routes/web.php hanya mengembalikan status layanan dari root. Tidak ada route produk yang tampak untuk login/reset password/email verification, tenant/template/device setup, checkout, stock mutation, reports, journal, atau sync. Ini blocker penerimaan produk, bukan bukti ada runtime exploit.
2. **Flutter masih mempunyai jalur Supabase yang bertentangan dengan ADR pemilik terbaru.** pos-app/pubspec.yaml masih bergantung pada supabase_flutter; pos-app/lib/main.dart mengimpor dan menjalankan Supabase.initialize. Kebijakan terbaru melarang penggunaan semua Supabase product, bahkan read-only. Alur cloud Flutter belum compliant dan belum tervalidasi terhadap Laravel Central API.
3. **Isolasi tenant nyata belum dibuktikan.** Tidak ada hasil test pada candidate SHA ini untuk PostgreSQL role/grants, tenant A↔B, Host spoofing, context reset pada worker, device membership, atau akses ke central DB. Package tenancy maupun migration smoke tidak cukup sebagai bukti isolasi.
4. **Workbook contract memiliki validator source, tetapi workbook aktual tidak dieksekusi pada audit ini.** scripts/export_workbook_for_laravel.py mendefinisikan validasi sheets, key uniqueness/types/counts, template, mapping service/device, dan expected keyset MD5. Angka 352 adalah kontrak target; aktual workbook belum TEST-EXECUTED pada workstream ini.
5. **Workflow workbook masih memuat command legacy yang dilarang.** .github/workflows/canonical-workbook-validate.yml memanggil python scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352. Command ini tidak dijalankan. Konflik ditugaskan ke pemilik CI/workflow; laporan QA ini tidak mengubah workflow.
6. **Compatibility dan error recovery belum memiliki bukti eksekusi.** Tidak ada bukti pada SHA ini untuk desktop/browser, Android physical device/OS, network drop, duplicate submission, session expiry, disabled domain/device, restart server/worker, restore, atau rollback.

Hasil yang sah adalah **BLOCKED**. Ini berbeda dari menyatakan semua tes runtime FAIL: mayoritas tes **NOT RUN** karena environment dan prasyarat produk belum tersedia/teridentifikasi. Defect source/API yang teramati dicatat sebagai FAILED acceptance gate dan dirutekan ke owner; implementasinya tidak diperbaiki di workstream UAT.

## 2. Otoritas yang dibaca sesuai urutan wajib

| Urutan | Dokumen | Status / relevansi |
|---|---|---|
| 1 | Root AGENTS.md | Dibaca. Menetapkan urutan otoritas, kontrak evidence, larangan Supabase, workbook 352, no direct push to main, serta release gates. |
| 2 | docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md | Dibaca. Otoritas konfigurasi: GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE, workbook 352, POS dan Accounting harus di-resolve terpisah. |
| 3 | docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md | Dibaca lengkap. Historis/subordinate bila bertentangan dengan ADR 2026-10-17. |
| 4a | docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md | Dibaca karena root AGENTS mewajibkannya dan ini otoritas pemilik terbaru: KVM2/Coolify, Laravel/PHP 8.4, PostgreSQL 17, tanpa Supabase. |
| 4b | docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md | Dibaca. Target arsitektur, provisioning/privilege gates, API, Flutter, recovery dan release acceptance; bukan bukti implementasi. |
| 5 | docs/permanent/DOC_00_MASTER_ROADMAP.md | Dibaca. Fase 0–7; Phase 4 API/auth, Phase 5 config/Flutter/offline sync, Phase 6 security/recovery/load, Phase 7 staging release. |
| 6 | docs/permanent/README.md | Dibaca. Peta otoritas dan batas evidence. |
| 7 | docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md | Dibaca lengkap. SQLite atomic sale/outbox, idempotency/acknowledgement, stock-conflict policy, audit. |
| 8 | docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md | Dibaca lengkap. Snapshot historis, bukan bukti runtime terkini; cloud sync, tenant A/B, device dan restore belum tersertifikasi. |
| 9 | docs/HARDENING/README.md | Dibaca. Snapshot audit lama, bukan bukti current-head atau izin untuk mengakses Supabase. |
| 10 | Root README.md | Dibaca. Mengonfirmasi baseline dan menyebut sisa Supabase Flutter client serta missing production readiness. |
| 11 | .cursor/rules/berkah-pos.mdc dan .github/muse-instructions.md | Dibaca sesuai AGENTS. |

### Source/test/workflow khusus UAT yang diperiksa

- routes/api.php dan routes/web.php
- composer.json
- pos-app/pubspec.yaml dan pos-app/lib/main.dart
- scripts/export_workbook_for_laravel.py
- app/Console/Commands/ImportCanonicalWorkbook.php
- .github/workflows/canonical-workbook-validate.yml
- .github/workflows/pos-app-ci.yml
- .github/workflows/laravel-pg17-baseline.yml
- .github/workflows/berkah-pos-aab.yml
- .github/workflows/berkah-pos-trial-ci.yml
- config/ci/required-check-matrix.json
- docs/reports/ACCEPTANCE_MATRIX_CI_EVIDENCE_2026-10-16.md
- docs/reports/LARAVEL_PG17_BASELINE_ACCEPTANCE_2026-10-17.md
- docs/permanent/BACKEND_SYNC_AUDIT.md

Tidak ada akses live ke Supabase, mutasi data, maupun tes dengan customer nyata.

## 3. Revision, branch dan files

| Item | Nilai |
|---|---|
| Repository | berkah-pos/Berkahtigaputeri |
| Base SHA sebelum bekerja | 371b7fdf0bf672b37ceb1023e647f114221bf797 |
| SHA baseline scaffold pembanding | aab154f87342f2a02a1319e1d370ce831dbef522 |
| Branch | audit/preprod-uat-matrix-2026-10-18 |
| File yang ditambahkan | docs/reports/preproduction/2026-10-18/12_UAT_AND_COMPATIBILITY.md |
| Source/ADR/workflow lain | Tidak disentuh |
| Commit hasil laporan / PR | Akan ditautkan saat publikasi |
| Local clone dirty state | Tidak dapat ditentukan karena clone lokal tidak tersedia |
| Local test runtime/browser automation | Tidak tersedia |

Base 371b7fdf… terverifikasi empat commit di atas baseline aab154f… (ahead 4, behind 0). Historical baseline run 39005405149 menguji SHA aab154f…, **bukan** SHA 371b7fdf…. Hasil baseline itu tidak dianggap evidence exact-SHA untuk kandidat laporan ini.

## 4. Ruang lingkup dan asumsi UAT

Release scope belum ditemukan sebagai keputusan bisnis yang disetujui. Matrix ini adalah rencana penerimaan berdasarkan prompt workstream dan kontrak yang tersedia; bukan klaim bahwa scope sudah ditandatangani.

Asumsi:
- Environment harus berupa staging/disposable yang terpisah dari produksi; source SHA dan deployed image identity dapat diverifikasi.
- Tenant, user, device, produk, stok, sale dan journal untuk test harus sintetis.
- Login/reset/email hanya dikirim ke alamat test yang secara eksplisit di-allowlist pemilik environment.
- Role yang diuji harus diambil dari role/membership yang benar-benar tersedia. Jangan mengarang daftar role dari nama fitur.
- Tidak ada pembayaran nyata, customer produksi, perubahan DNS, atau akses Supabase.
- Browser/device coverage belum disetujui. Chrome desktop dan mobile Chromium/Android di bawah hanya usulan minimum.
- Harga/PPN, pembulatan, offline stock policy, permissions, dan reporting rules memerlukan oracle yang disetujui pemilik bisnis.

## 5. Acceptance gate lintas subsistem

BLOCKED berarti prerequisite/environment/keputusan tidak tersedia. NOT RUN berarti test belum dijalankan. FAILED hanya untuk kriteria yang gagal berdasarkan source/evidence langsung; tidak mengarang hasil runtime.

| Gate ID | Kriteria | Status | Evidence | Blocker / next owner |
|---|---|---|---|---|
| G-01 | Scope rilis dan acceptance oracle disetujui bisnis | BLOCKED | Tidak ditemukan release-scope sign-off yang berlaku di sumber yang diperiksa | Business owner / release coordinator |
| G-02 | Environment ID/URL dan isolated DB diketahui | BLOCKED | Tidak ada staging runtime identity di sesi ini | SRE / environment owner |
| G-03 | Candidate SHA dan deployed image digest sama | BLOCKED | Base SHA diketahui, tetapi deployment/image tidak terverifikasi | Release engineering |
| G-04 | Synthetic identities, role matrix, test devices, email allowlist | BLOCKED | Belum tersedia; superuser tidak akan menggantikan role tenant | Identity/API + environment owner |
| G-05 | Product API meliputi journey rilis | FAILED — source gate | routes/api.php hanya GET /api/v1/platform-health | Laravel Central API owner |
| G-06 | Flutter remote path memenuhi no-Supabase ADR | FAILED — source-compliance gate | Supabase dependency + initializer masih source-verified | Flutter/API migration owner |
| G-07 | Auth/session/reset/verification/authorization teruji | NOT RUN | Product auth routes/runtime tidak terbukti | Laravel Auth/API owner |
| G-08 | PostgreSQL tenant A/B dengan real role/grants | NOT RUN | Tidak ada hasil real-role/current-candidate test | PostgreSQL provisioning/security owner |
| G-09 | Actual workbook 352 inventory terverifikasi | NOT RUN | Validator source ada, workbook tidak dieksekusi pada audit ini | Config/workbook owner + QA |
| G-10 | Five-layer parity dan POS/Accounting isolation | NOT RUN | Kontrak tertulis; tidak ada current-head run | Config/API/Flutter owner |
| G-11 | Checkout, stock, journal, reports reconcile | BLOCKED | Route inventory tidak menunjukkan API produk yang diperlukan | POS/accounting + API owner |
| G-12 | Offline/reconnect/retry/durable ACK/idempotency | NOT RUN | Tidak ada E2E sync run; sync API tidak terlihat pada route inventory | Flutter sync/API owner |
| G-13 | Error path/restart/recoverability | NOT RUN | Tidak ada disposable runtime untuk fault injection | SRE + API/worker owner |
| G-14 | Browser dan mobile compatibility dibuktikan | NOT RUN | Tidak ada test browser/device | QA/release owner |
| G-15 | Backup/restore central + tenant DB | NOT RUN | Tidak ada restore artifact/run | Recovery owner |
| G-16 | Audit actor/time/device/app version dan tenant boundaries | BLOCKED | Audit API/runtime behavior tidak diperlihatkan atau dieksekusi | API/accounting/security owner |
| G-17 | Exact-SHA CI/UAT evidence lengkap | BLOCKED | Untuk SHA 371b7fdf, query tool mengembalikan statuses kosong dan tidak ada PR-workflow run record; baseline CI adalah SHA lain | CI/release coordinator |
| G-18 | Business owner sign-off dan go/no-go | BLOCKED | Belum ada sign-off yang ditemukan | Accountable release owner |

## 6. UAT matrix — fungsi, tenant, konfigurasi, POS, accounting

Seluruh journey di bagian ini BLOCKED atau NOT RUN; tidak ada PASS hanya berdasarkan source/test-file presence. Saat dieksekusi, setiap row harus membawa test ID, candidate SHA, deployed image, role asli, synthetic fixture, expected/actual, result/exit code dan sanitized artifact.

| Test ID | Skenario / langkah | Expected result / oracle | Actual evidence pada audit ini | Status |
|---|---|---|---|---|
| AUTH-01 | Login benar/salah pada role test | Session/token scoped; salah kredensial ditolak tanpa bocor apakah akun ada | Login API tidak terlihat; tidak dijalankan | BLOCKED |
| AUTH-02 | Reset password ke alamat email allowlisted | Token sekali pakai dan expired; tidak mengungkap akun; email terkirim ke test inbox yang diizinkan | Tidak ada endpoint/allowlist test terverifikasi; email tidak dikirim | BLOCKED |
| AUTH-03 | Email verification valid, expired, replay, signature salah | Hanya token valid diterima; expired/replay ditolak | Tidak dieksekusi | NOT RUN |
| AUTH-04 | Session restore, logout/revoke dan expired session | Token revoked/expired ditolak; transaksi lokal tidak hilang | Laravel auth path tidak terbukti | BLOCKED |
| AUTH-05 | Semua role yang didukung pada environment | Least privilege; forbidden actions mendapat 401/403 sesuai kontrak | Role actual belum diketahui | BLOCKED |
| TEN-01 | Setup tenant/domain valid, duplicate dan invalid | Tenant ID dibuat server-side; domain invalid/duplicate ditolak | Endpoint/env tak tersedia | BLOCKED |
| TEN-02 | Assign BASIC/PRO/ENTERPRISE | Template assignment dan entitlements cocok dengan keputusan bisnis | Tiga template ada dalam kontrak; runtime belum dites | NOT RUN |
| TEN-03 | Provision tenant A dan B bersamaan | Database/login terpisah per tenant; retry/concurrent provisioning idempotent | Tidak ada real PG role/provisioning evidence | NOT RUN |
| TEN-04 | A mencoba CRUD/report/export data B dan sebaliknya | Cross-tenant requests dan SQL CONNECT/SELECT/INSERT/UPDATE/DELETE ditolak | Tidak ada API/DB fixture untuk test | BLOCKED |
| TEN-05 | Spoof tenant_id/device_id/Host/X-Forwarded-Host | Auth server-side; hostile/ambiguous hosts fail-closed | Tidak dieksekusi | NOT RUN |
| TEN-06 | Disabled device/domain/membership dengan cache hangat | Request berikut ditolak sesuai invalidation contract | Tidak dieksekusi | NOT RUN |
| CFG-01 | Jalankan validator workbook read-only | Tujuh sheet, 352 keys unik, counts 1/3/100/140/108, mapping/hash cocok; zero DB writes | scripts/export_workbook_for_laravel.py tersedia; tidak dijalankan | NOT RUN |
| CFG-02 | Test precedence dan inherited/missing fields | GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE; hanya field eksplisit ditimpa | Tidak ada current-head test execution | NOT RUN |
| CFG-03 | Resolve POS lalu Akuntansi | Setiap response hanya berisi konfigurasi service yang diminta | Tidak dieksekusi | NOT RUN |
| CFG-04 | Device wrong-tenant/inactive, version/hash | Device invalid ditolak; config hash deterministik untuk tuple/version sama | Tidak dieksekusi | NOT RUN |
| POS-01 | Produk sintetis → cart → checkout cash/test mode | Sale satu kali dengan integer rupiah/fixed precision; pembayaran nyata tidak dilakukan | Checkout API tidak terlihat | BLOCKED |
| POS-02 | Receive lot → checkout item expiry/cost layer | Stock movements konsisten; FEFO fisik dan FIFO financial costing sesuai kontrak | E2E tidak dieksekusi | BLOCKED |
| POS-03 | Sale menghasilkan journal | Debit=credit; reversal/correction diaudit, posted journal tidak diedit diam-diam | Backend journal journey tidak tersedia untuk test | BLOCKED |
| POS-04 | Reconcile order totals dengan report | Sale lines/tax/discount/COGS/stock/journal selaras dengan oracle yang disetujui | Tidak ada report-source DB test | BLOCKED |
| POS-05 | Duplicate checkout request/transaction ID | Satu sale, stock movement dan journal; replay identical idempotent | Tidak dieksekusi | NOT RUN |
| AUD-01 | Posting/correction/reversal dan audit metadata | Actor, timestamp, device ID, app version tercatat; logs tak memuat secrets | Tidak dieksekusi | BLOCKED |
| AUD-02 | A meminta report/export B | Ditolak dan audit security event tersanitasi | Tidak dieksekusi | NOT RUN |

## 7. UAT matrix — offline, reconnect, failures, recovery

| Test ID | Skenario / langkah | Expected result / oracle | Actual evidence pada audit ini | Status |
|---|---|---|---|---|
| OFF-01 | Airplane mode: checkout lokal lalu restart app | Sale/lines/stock/journal/outbox commit atomik dan pending state bertahan | Belum dijalankan di SQLite on-disk/device exact candidate | NOT RUN |
| OFF-02 | Network drop sebelum sync send | Sale tak hilang; outbox pending/retryable; retry bounded/backoff | Tidak ada app/runtime execution | NOT RUN |
| OFF-03 | Server commit tapi response timeout sebelum ACK | Retry key+payload sama mengembalikan receipt sama; efek tak ganda | API sync belum terbukti; tidak dijalankan | BLOCKED |
| OFF-04 | Idempotency key sama, payload berbeda | Konflik eksplisit dan audit; existing sale tak overwrite | Tidak dieksekusi | NOT RUN |
| OFF-05 | Reconnect setelah transaksi offline | ACK hanya setelah commit durable; status Pending/Syncing/Accepted/Conflict akurat | Tidak ada cloud sync run | BLOCKED |
| OFF-06 | Double tap / duplicate concurrent submission | Satu event bisnis, tanpa duplikasi sale/stock/journal | Tidak ada API transaction endpoint/test | BLOCKED |
| OFF-07 | Restart server/worker saat request atau retry job | Data durable; tidak ada loss/duplication; context worker di-reset | Tak ada disposable server/worker | NOT RUN |
| OFF-08 | Multi-device offline menjual stok terakhir yang sama | Kebijakan quota/reservation/restrict/reconcile ditetapkan bisnis dan discrepancy diaudit | DOC_12 meminta policy decision; sign-off belum ditemukan | BLOCKED |
| ERR-01 | Expired/revoked session dengan outbox pending | API menolak auth; pending local sale aman; re-auth melanjutkan bila diizinkan | Tidak dieksekusi | NOT RUN |
| ERR-02 | Account/device/domain suspended | Server menolak request berikutnya sesuai SLA invalidation | Tidak dieksekusi | NOT RUN |
| ERR-03 | Local DB exception/failure transaksi | Rollback semua row terkait; tidak ada sale tanpa outbox/lines | Tidak dieksekusi | NOT RUN |
| ERR-04 | HTTP 5xx/429, malformed body, payload invalid | Retry hanya untuk error retryable; permanent failure terlihat dan aman | Tidak dieksekusi | NOT RUN |
| ERR-05 | Worker crash / queued retry | Transaksi durable, context tenant bersih pada job berikutnya | Tidak dieksekusi | NOT RUN |
| REC-01 | Backup central + 2 tenant DB + required files lalu restore | Checksum, counts, journal balances, config hash dan tenant boundary valid; durasi direkam | Tidak ada restore run/artifact | NOT RUN |
| REC-02 | Restore tenant tunggal tanpa mengubah tenant lain | Hanya tenant target berubah; central mappings dan peer tenant tetap valid | Tidak dieksekusi | NOT RUN |
| REC-03 | Deploy dan rollback immutable image pada staging | Deployed SHA/digest cocok; rollback/forward recovery dites | Tidak ada staging/image evidence | NOT RUN |

## 8. Compatibility coverage

Browser/OS/device/build/viewport/screenshot/log tidak dapat disebut tested tanpa eksekusi. Baris 390×844 dan 1366×768 adalah usulan viewport, bukan coverage yang telah dilakukan.

| ID | Target / viewport | Data yang harus direkam saat run | Hasil audit | Evidence |
|---|---|---|---|---|
| COMP-01 | Android phone, aplikasi POS | Model, Android version/build, ABI, app version/commit, density/resolution, network state | NOT RUN | Tidak ada install/device transcript |
| COMP-02 | Android Chrome, viewport usulan 390×844 CSS px | Chrome version, Android build, app/browser build, auth/checkout/report responsive | NOT RUN | Tidak ada browser execution/screenshot |
| COMP-03 | Desktop Chrome, viewport usulan 1366×768 CSS px | OS/build, Chrome version, login/admin/report, keyboard and session | NOT RUN | Tidak ada browser execution |
| COMP-04 | Desktop Microsoft Edge | OS/build, browser version, auth, route and reports | NOT RUN | Belum disahkan dan tidak dieksekusi |
| COMP-05 | Desktop Firefox | OS/build, browser version, auth, responsive UI, exports | NOT RUN | Belum disahkan dan tidak dieksekusi |
| COMP-06 | Tablet/wide mobile jika termasuk release scope | Model, OS/browser build, orientation, viewport | BLOCKED | Business owner belum menentukan support matrix |

**Coverage yang benar-benar diuji:** tidak ada browser/device runtime execution. pos-app-ci.yml mendefinisikan Flutter analysis/tests dan debug AAB compile-check pada runner jika workflow terpicu; itu bukan pemasangan aplikasi di perangkat fisik. berkah-pos-aab.yml memiliki guard untuk menolak publisher-signed release saat path Supabase masih ada; keberadaan workflow bukan hasil run. Tidak ada screenshot, HAR, network log, ataupun device log yang dibuat.

## 9. Defect register

Severity menunjukkan dampak terhadap acceptance target, bukan klaim telah terjadi eksploitasi. Confidence menunjuk kepastian source evidence.

| ID | Severity / confidence | Finding dan evidence | Expected vs actual | Reproduksi/status | Owner |
|---|---|---|---|---|---|
| UAT-DEF-01 | **P1 / High** | routes/api.php mendefinisikan hanya GET /v1/platform-health (Laravel prefix menghasilkan /api). routes/web.php hanya root status JSON. Baseline CI terdahulu hanya smoke health/route/migration. | Expected: API routes+tests untuk auth, tenant/device, checkout, stock, reports, journal, sync dan audit mengikuti release scope. Actual: route inventory source hanya health endpoint; E2E tak dapat dijalankan. | SOURCE-VERIFIED; gate FAILED; runtime NOT RUN. Source check: buka routes/api.php. HTTP reproduction tidak dilakukan karena staging/test identities tidak tersedia. | Laravel Central API/Auth owner |
| UAT-DEF-02 | **P1 / High** | pos-app/pubspec.yaml masih membutuhkan supabase_flutter; pos-app/lib/main.dart mengimpor package dan memanggil Supabase.initialize. ADR 2026-10-17 melarang seluruh Supabase use/access. | Expected: remote auth/config/sync melalui authenticated Laravel Central API tanpa Supabase SDK/URL/fallback. Actual: legacy path masih ada. | SOURCE-VERIFIED; compliance gate FAILED; tidak ada request ke Supabase dan cloud runtime test NOT RUN. | Flutter migration / API owner |
| UAT-DEF-03 | **P1 / High** | Tenant isolation belum dibuktikan dengan PG roles/grants nyata. Search atas TenantProvisioningPostgresGrantsTest pada current main hanya menemukan referensi di matrix, bukan implementasi test. | Expected: A hanya akses A, B hanya akses B, no central DB access dari runtime tenant, no elevated global DDL. Actual: tidak ada qualifying evidence. | NOT RUN; tidak ada exploit yang direproduksi karena DB/runtime unavailable. | PostgreSQL provisioning/security + API tenancy owner |
| UAT-DEF-04 | **P2 / High** | .github/workflows/canonical-workbook-validate.yml menjalankan python scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352, bertentangan ADR terbaru. config/ci/required-check-matrix.json berkata specification-only/not wired dan merujuk scripts/test_canonical_workbook_contract.py yang tidak ditemukan (GitHub fetch 404; search tak menemukan). | Expected: validator offline/read-only, non-Supabase, wired ke required checks; no legacy sync invocation. Actual: workflow masih refer ke command yang dilarang; matrix tidak wired; referenced path tidak terbukti ada. | SOURCE-VERIFIED; command terlarang sengaja NOT RUN. Tidak mengklaim workflow dijalankan untuk source ini. | CI/workflow + config owner |
| UAT-DEF-05 | **P2 / High** | Tidak ada staging URL/environment ID, deployed SHA/image digest, synthetic identities, email allowlist atau browser/device matrix dalam evidence yang dapat diakses. | Expected: semua UAT dibatasi ke isolated env dan exact SHA. Actual: prasyarat tak tersedia. | BLOCKED sebelum setup; tidak menebak endpoint/kredensial. | SRE/environment + release owner |
| UAT-DEF-06 | **P2 / High** | Tidak ada direct E2E reconciliation, durable sync receipt, backup restore, atau browser/device results pada candidate yang diperiksa. | Expected: order totals, inventory moves, debit=credit, audit trail dan outbox receipt konsisten; restore memulihkan data dan batas tenant. Actual: none executed in this workstream. | NOT RUN; tidak ada test pada production/shared DB. | POS/accounting + sync/API + SRE owners |
| UAT-DEF-07 | **P2 / Medium** | Acceptance matrix adalah specification-only/not wired to CI; historical PR results berdasar SHA berbeda dan beberapa MariaDB target yang ditolak. | Expected: mandatory checks fail-closed pada exact candidate SHA. Actual: current SHA query mengembalikan status kosong dan tidak ada PR-run entries dari connector query. | Source/report evidence; bukan klaim tak ada semua workflow di GitHub. | CI/release coordinator |

Tidak ada P0 ditetapkan karena tidak ditemukan reproduksi eksploitasi/runtime compromise pada audit. Defect tidak diperbaiki di branch QA; setiap fix memerlukan PR owner masing-masing dan test negatif/regresi.

## 10. Exact-SHA evidence dan command log

### 10.1 Query/current-head observations

| Operasi / source | Revision | Hasil | Classification |
|---|---|---|---|
| Compare aab154f… → 371b7fdf… | Base aab154f…, head 371b7fdf… | Ahead 4, behind 0 | Revision check, bukan UAT |
| GitHub get_commit_combined_status | SHA 371b7fdf0bf672b37ceb1023e647f114221bf797 | statuses: [] | Connector tidak mengembalikan status records; bukan pass/fail CI |
| GitHub fetch_commit_workflow_runs | SHA 371b7fdf0bf672b37ceb1023e647f114221bf797 | workflow_runs: []; wrapper hanya memfilter PR-triggered runs/first page | Tidak ada PR-run records yang dikembalikan; bukan bukti semua workflow tidak ada |
| Fetch routes/api.php | Current main source | Hanya route platform-health | SOURCE-VERIFIED |
| Fetch pos-app/pubspec.yaml + main.dart | Current main source | Supabase dependency/import/initialize masih ada | SOURCE-VERIFIED |
| Fetch workbook validator | Current main source | Validator memeriksa sheet/key/count/hash ketika dijalankan | SOURCE-VERIFIED; actual workbook NOT RUN |
| Fetch workbook workflow | Current main source | Legacy Supabase command terlihat | SOURCE-VERIFIED; command NOT RUN |
| Fetch required-check matrix | Current main source | Matrix menyatakan specification-only/not wired dan merujuk test path yang tidak ditemukan | SOURCE-VERIFIED |
| Historical CI [run 39005405149](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39005405149) | SHA aab154f87342f2a02a1319e1d370ce831dbef522; workflow Laravel PostgreSQL 17 Baseline; attempt tidak dinyatakan dalam report yang dibaca | Report mengklaim composer validate/locked install/platform check/audit, Laravel boot/routes, disposable PG17 migration, production image health/API smoke sukses | CLAIMED oleh report exact-SHA; baseline smoke, bukan current SHA atau UAT |
| Historical acceptance matrix [report](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/reports/ACCEPTANCE_MATRIX_CI_EVIDENCE_2026-10-16.md) | PR #48/#52/#50, SHA berbeda | Partial passes, preflight/test failures dan MariaDB candidate yang ditolak | Historical only; bukan current-head sign-off |

### 10.2 Commands considered — no tests executed

Tidak ada local checkout atau disposable runtime di lingkungan ini. Karena itu semua shell command berikut **NOT RUN**; exit code **N/A**, bukan 0.

| Exact command | Intended environment | Exit/result | Sanitized artifact |
|---|---|---|---|
| python3 scripts/export_workbook_for_laravel.py --validate-only | Local clone, canonical XLSX, read-only, no DB | N/A — NOT RUN; filesystem/XLSX tidak tersedia di runtime | Tidak ada manifest |
| PYTHONPATH=. python -m unittest discover -s scripts/tests -p 'test_*.py' | Local clone/isolated Python environment | N/A — NOT RUN; filesystem unavailable | Tidak ada test log |
| python scripts/test_canonical_workbook_contract.py | Local clone/isolated Python; path direferensikan acceptance matrix | N/A — NOT RUN; GitHub file fetch mengembalikan 404 dan search tidak menemukan file | Path-missing observation saja |
| composer validate --strict --no-check-publish | PHP 8.4 candidate workspace | N/A — NOT RUN locally; historical baseline claim pada aab154f… | Historical URL; tidak mengambil log baru |
| composer check-platform-reqs | PHP 8.4 candidate workspace | N/A — NOT RUN locally | Tidak ada artifact lokal |
| composer audit --locked --no-interaction | Exact candidate dan committed lock | N/A — NOT RUN locally | Tidak ada artifact lokal |
| php artisan route:list --path=api/v1 | Disposable Laravel candidate | N/A — NOT RUN locally; route source dibaca saja | Tidak ada route-list artifact baru |
| php artisan test | Laravel + disposable PostgreSQL 17 | N/A — NOT RUN; tidak ada composer vendor/runtime lokal | Tidak ada PHPUnit XML/log |
| php artisan test --filter=TenantProvisioningPostgresGrantsTest | Disposable PG17 dengan role sintetis nyata | N/A — NOT RUN; implementasi test/runtime tidak diverifikasi | Tidak ada grants artifact |
| php artisan test --filter=EffectiveConfigResolverTest | PG17 + synthetic config fixtures | N/A — NOT RUN; search current main tidak menemukan implementation test | Tidak ada resolver artifact |
| flutter analyze --no-pub | pos-app/, exact candidate, Flutter SDK | N/A — NOT RUN locally; repo/SDK tidak mounted | Tidak ada analyzer log |
| flutter test --no-pub --reporter expanded | pos-app/, exact candidate SHA | N/A — NOT RUN locally; historical PR #48/#52 SHA berbeda dan client-only | Tidak ada test report |
| flutter build appbundle --debug --no-pub | Runner + Android SDK, exact SHA | N/A — NOT RUN pada sesi ini; workflow definition bukan artifact | Tidak ada AAB |
| Staging/browser/device E2E | Approved isolated target dan synthetic roles | N/A — BLOCKED, environment/tools/credentials tidak tersedia | Tidak ada screenshot/network logs |
| Authenticated sync/replay | Isolated Laravel + disposable PG17, synthetic idempotency IDs | N/A — BLOCKED; sync endpoint tak terlihat di route inventory | Tidak ada receipt/row evidence |
| Backup + central/tenant restore | Disposable PG17 and isolated storage target | N/A — NOT RUN; no restore target or artifacts | Tidak ada checksum/restore log |
| python scripts/sync_excel_to_supabase.py --dry-run --expect-keys 352 | Dilarang oleh ADR terbaru | NOT RUN by design; jangan jalankan meskipun workflow lama memuatnya | Tidak ada artifact |

### 10.3 Evidence artifacts

Dihasilkan:
- Markdown report ini.
- GitHub source/document URLs.
- Ringkasan read-only source dan connector query yang ditulis di atas.

Tidak dihasilkan: workbook manifest/checksum; PHPUnit/Flutter outputs; request/response transcripts; PostgreSQL role/grant snapshots; browser/device screenshots, video, HAR atau crash logs; backup/restore checksum/timing; deployment digest/rollback report.

Tidak ada credentials, keys, tokens, customer data, atau payload sensitif yang disalin ke report.

## 11. Protocol eksekusi UAT setelah prerequisite tersedia

1. **Freeze candidate:** catat repository SHA, CI-tested SHA, deployed image digest dan staging release ID; stop bila identitas berbeda.
2. **Prove isolation:** pemilik environment mengonfirmasi host non-production, disposable PG17 dan isolated storage. Hostname saja bukan bukti cukup.
3. **Seed synthetic fixtures:** dua tenant dan identities/devices terpisah, role nyata, templates, service assignment, subscription, products, lots, dan expected price/tax. Fixture IDs di-sanitasi.
4. **Jalankan berurutan:** auth/session → tenant/role/domain → workbook/config → product/stock/checkout → journal/reports → offline/outbox/reconnect/idempotency → failures/restart → tenant isolation negatives → compatibility → restore.
5. **Rekonsiliasi source transaksi:** order+lines+tax/discount ke report totals; stock movement ledger ke quantity; physical allocation FEFO dan financial costing FIFO; total debit = credit; outbox receipt ke tepat satu accepted sale; audit record ke actor/time/device/app version.
6. **Adversarial dengan real identities:** tenant A lalu B di worker yang sama; tes dua arah pada product/sale/stock/report/config/device/domain/subscription/sync. Jangan gunakan superuser untuk kasus ordinary user.
7. **Fault path:** drop network sebelum send, timeout setelah simulated commit, duplicate replay, same-key/different-payload, expired/revoked session, disabled account/device/domain, worker/server restart. Buktikan local durability serta final cloud row counts.
8. **Compatibility:** rekam model/OS/build, browser/version, app version/build/SHA, viewport, DPI/orientation, network state; redaksi cookies/authorization headers.
9. **Evidence package:** test ID, candidate SHA, exact command, environment ID, start/end, exit code, JUnit/log paths, expected/actual, sanitized hashes dan URL artifact. Pisahkan test result dari orchestration status.
10. **Independent sign-off:** defects hanya ditutup setelah owner PR dan exact-head regression; business owner menyetujui behavior dan release scope; hanya accountable owner mengambil keputusan Go/No-Go.

## 12. Sign-off pemilik bisnis yang masih diperlukan

Item berikut outstanding, bukan bukti telah disetujui.

- [ ] Menyetujui release scope dan pengecualian fitur.
- [ ] Menyetujui role/permission matrix berdasarkan role nyata: setup tenant, template, service/device, cashier, stock receiving, reports, journals.
- [ ] Menyetujui BASIC/PRO/ENTERPRISE entitlements dan ekspektasi status subscription.
- [ ] Menyetujui expected totals untuk harga, PPN, discount, refund/return, rounding dan reports.
- [ ] Menyetujui COA/journal oracle dan reversal/correction policy; debit=credit untuk setiap posted journal.
- [ ] Memilih kebijakan konflik stock multi-device offline (quota/reservation/restrict/oversell reconciliation); tanpa keputusan ini tidak boleh menjanjikan global stock consistency.
- [ ] Mengonfirmasi email/domain test dan izin mengirim reset/verification message; tidak ada email yang dikirim oleh workstream ini.
- [ ] Menyetujui browser/OS/device/viewport matrix dan minimum supported versions.
- [ ] Menyediakan staging/disposable environment ID, owner/contact, expiry/cleanup plan, synthetic credentials dan deployed image identity.
- [ ] Memutuskan scope migrasi data. ADR terbaru hanya mengizinkan existing owner-controlled offline export di luar Supabase; jika tidak ada, continuity tetap NOT VERIFIED.
- [ ] Menyetujui RPO/RTO dan cakupan restore.
- [ ] Mereview residual defects dan mengambil keputusan go/no-go hanya setelah mandatory technical gates punya evidence.

## 13. Rekomendasi acceptance dan tindak lanjut

**Rekomendasi: BLOCKED. Jangan menyatakan UAT PASS dan jangan menyetujui release/go-live.**

Langkah berikut:
1. Route UAT-DEF-01/UAT-DEF-02 ke Laravel API/Auth dan Flutter migration owners; UAT-DEF-03 ke PostgreSQL provisioning/security owner.
2. Route UAT-DEF-04 ke CI/workflow owner. Ganti legacy workbook path dengan validator offline/non-Supabase dan wiring required-checks hanya setelah tervalidasi di exact candidate SHA. Laporan QA ini tidak mengubah workflow.
3. Minta environment owner dan business owner menyediakan isolated staging, dua tenant identities/role assignments, email allowlist, approved scope, expected financial values dan compatibility matrix.
4. Jalankan matrix pada satu integrated candidate SHA, menggunakan PG17 real roles/grants dan API E2E. Jangan gabungkan historical results dari branch/SHA lain.
5. Tinjau ulang setelah exact-SHA E2E, compatibility, restore, dan business sign-off selesai. Hanya accountable owner yang menetapkan keputusan release.

## Appendix A — Kosa kata status

- **SOURCE-VERIFIED:** isi file diperiksa langsung dari repository.
- **CLAIMED:** hasil hanya dinyatakan dalam laporan terdahulu, belum diulang dalam workstream ini.
- **FAILED:** acceptance criterion bertentangan/tidak tersedia pada source evidence langsung; bukan klaim test runtime gagal.
- **BLOCKED:** environment, decision, API, credential provisioning atau ownership prerequisite tidak tersedia.
- **NOT RUN:** test/command tidak dijalankan.
- **NOT APPLICABLE:** hanya untuk scope exclusion yang disetujui; tidak ada major journey yang ditandai N/A tanpa approval.
- **PASS:** hanya setelah test dijalankan pada exact accepted candidate SHA dengan expected result dan evidence link.

## Appendix B — Source references

- [Root AGENTS.md](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/AGENTS.md)
- [Canonical configuration contract](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md)
- [Owner ADR — no Supabase](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md)
- [DOC_14 tenant architecture](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md)
- [Master roadmap](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/DOC_00_MASTER_ROADMAP.md)
- [DOC_12 offline-first protocol](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md)
- [DOC_13 integration snapshot](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md)
- [Workbook validator source](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/scripts/export_workbook_for_laravel.py)
- [Laravel API routes](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/routes/api.php)
- [Flutter pubspec](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/pos-app/pubspec.yaml)
- [Flutter main initializer](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/pos-app/lib/main.dart)
- [Legacy workbook workflow to route to CI owner](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/.github/workflows/canonical-workbook-validate.yml)
- [Fail-closed check-matrix specification](https://github.com/berkah-pos/Berkahtigaputeri/blob/main/config/ci/required-check-matrix.json)
