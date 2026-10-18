# Preproduction Audit — POS Client & Offline Correctness

**Tanggal pemeriksaan:** 19 Oktober 2026 (Asia/Jakarta)  
**Status workstream:** **BLOCKED**  
**Rekomendasi rilis:** **BLOCKED — bukan PASS.** Perubahan klien dan regresi test telah ditambahkan. Exact-SHA CI awal gagal pada analisis; setelah perbaikan analyzer, CI untuk commit koreksi masih queued pada saat laporan dibuat. Sinkronisasi cloud, durable server acknowledgement, dan penggantian runtime Supabase tetap blocker.

## 1. Ringkasan eksekutif

### Source yang terbukti

- SQLite sale repository menjalankan operasi checkout dalam transaksi eksklusif melalui PosDatabase.transaction. Ia memeriksa transaction ID: ID dan fingerprint yang sama mengembalikan transaksi yang telah ada; ID sama dengan fingerprint berbeda ditolak dengan DuplicateTransactionIdException.
- Penjualan, sale items, perubahan stok dan lot, stock/inventory movements, jurnal, dan event outbox dibuat di boundary transaksi SQLite yang sama. Foreign keys aktif.
- Source/test yang sudah ada menguji stok tidak cukup, same-request retry, dan request berbeda dengan ID yang sama. Test tambahan telah ditulis untuk error insert outbox, dua checkout pada unit terakhir, serta file database close/reopen + replay.
- UI menampilkan “tersimpan lokal/menunggu antrean lokal”, bukan bukti penerimaan server. Label/icon laporan diubah agar antrean lokal yang kosong tidak tampak sebagai cloud sync sukses.
- **Tidak ditemukan outbox dispatcher / client HTTP sync aktif yang mengirim event, mendapatkan server receipt, dan melakukan acknowledge.** Tabel outbox saja bukan bukti adanya worker. Backend kontrak yang dibutuhkan belum tersedia dalam bukti yang dapat diverifikasi di workstream ini.

### Perbaikan yang dibuat

1. Menambahkan StableCheckoutRequestFactory untuk mempertahankan transaction ID dan timestamp pada retry dengan bentuk request yang sama selama sesi view yang sama; perubahan cart/metode atau cancel memulai intent baru.
2. Menambahkan aksi cancel cart dengan konfirmasi.
3. Memisahkan error pemrosesan checkout lokal dari error callback setelah commit. Jika refresh setelah commit gagal, UI tidak lagi menyebut transaksi gagal; hasil tetap disebut tersimpan lokal.
4. Memperjelas label/ikon status antrean lokal.
5. Menambah regression tests untuk rollback pada kegagalan insert outbox, konkurensi checkout lokal pada stok terakhir, pemulihan outbox setelah file DB dibuka kembali, dan stabilitas key retry.

Perbaikan ini tidak membangun sinkronisasi cloud dan tidak membuat key tetap tersedia setelah proses Android dibunuh karena factory masih in-memory. Oleh sebab itu status keseluruhan tetap BLOCKED.

## 2. Baseline, branch, commit, PR

| Item | Bukti |
|---|---|
| Repository | [berkah-pos/Berkahtigaputeri](https://github.com/berkah-pos/Berkahtigaputeri) |
| Exact base SHA sebelum bekerja | 371b7fdf0bf672b37ceb1023e647f114221bf797 |
| Branch audit | audit/preprod-pos-offline-2026-10-18 |
| Commit implementasi awal | [16352e9c99a993e45a2212b990d323060aec3f44](https://github.com/berkah-pos/Berkahtigaputeri/commit/16352e9c99a993e45a2212b990d323060aec3f44) |
| Commit koreksi analyzer | [07f4d58817f83390f4f16821922e424f0fd1d94d](https://github.com/berkah-pos/Berkahtigaputeri/commit/07f4d58817f83390f4f16821922e424f0fd1d94d) |
| Draft PR | [#81 — POS client and offline correctness](https://github.com/berkah-pos/Berkahtigaputeri/pull/81) |
| Perubahan scope | Hanya pos-app/** dan laporan ini. Tidak ada perubahan backend schema, workbook/resolver, atau workflow YAML. |

Base SHA dicatat sebelum perubahan. Branch audit dibuat dari SHA tersebut; commit kode dan tindak lanjut hanya ditulis ke branch unik. PR tetap draft dan belum di-merge.

## 3. Dokumen otoritatif yang dibaca

Urutan baca dijalankan mengikuti root AGENTS.md dan aturan repo:

1. AGENTS.md (root).
2. docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md.
3. docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md — otoritas owner terbaru; Laravel Central API + PostgreSQL 17 dan tidak menggunakan Supabase.
4. docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md.
5. docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md.
6. docs/permanent/DOC_00_MASTER_ROADMAP.md.
7. docs/permanent/README.md.
8. docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md.
9. docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md.
10. docs/HARDENING/README.md, root README.md, dan pos-app/README.md.
11. Source dan test checkout, SQLite schema, manifest Flutter, AndroidManifest, login/config/storage, laporan lokal, helper test database, serta .github/workflows/pos-app-ci.yml.

Kontrak konfigurasi tetap GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE; target workbook 352 entry = 1 global + 3 template + 100 tenant + 140 service + 108 device. POS dan Akuntansi tidak boleh digabung; satu hasil konfigurasi efektif hanya untuk service yang diminta. Workbook validator tidak dijalankan dalam workstream client. Tidak ada operasi read/write/sync/migration/query ke Supabase; script dan workflow lama yang masih merujuk Supabase diperlakukan sebagai konflik/stale control sesuai ADR terbaru.

## 4. Acceptance gates

| ID | Kriteria | Status | Bukti | Blocker / catatan |
|---|---|---|---|---|
| POS-01 | Sale, items, stok/lots/movements, jurnal dan outbox atomik dalam satu SQLite transaction | **VERIFIED source; runtime pending** | pos_database.dart sekitar baris 54–66; sqlite_sale_repository.dart sekitar baris 31–80 dan 230–325 | Perlu test run sukses pada CI setelah lint fix |
| POS-02 | Stok tidak cukup tidak memutasi sale, jurnal, stok atau outbox | **SOURCE VERIFIED; existing test; runtime pending** | payment_service_test.dart sekitar baris 358; exception stock dan rollback assertions | Exit code test belum tersedia |
| POS-03 | Outbox insert failure me-rollback semua perubahan checkout sebelumnya | **TEST ADDED; runtime not verified** | Test baru sekitar baris 412 menggunakan duplicate outbox primary key sebagai fault injection | Lint run pertama berhenti sebelum test |
| POS-04 | Retry request identik pakai transaction ID/timestamp stabil; request berubah memulai intent baru | **IMPLEMENTED; TEST ADDED; runtime pending** | StableCheckoutRequestFactory dan test unit baru | In-memory only; tidak pulih setelah process death |
| POS-05 | Dua checkout lokal bersamaan tidak dapat menjual dua kali unit terakhir | **TEST ADDED; runtime pending** | Test baru sekitar baris 472 pada satu DB SQLite | Bukan bukti concurrency server multi-device |
| POS-06 | Outbox pending bertahan saat database file ditutup/dibuka kembali; replay tidak menggandakan sale | **TEST ADDED; runtime pending** | Test file-backed baru sekitar baris 517 | Handle reopen bukan simulasi force-stop Android penuh |
| POS-07 | UI tidak mengklaim server accepted/synced tanpa durable ACK | **VERIFIED source after change** | checkout_screen.dart sekitar baris 158–244; reports_screen.dart sekitar baris 160–176 | API acknowledgement memang belum ada |
| POS-08 | Cancel cart tidak membuat sale/outbox; double tap tidak menjalankan dua checkout di widget | **PARTIAL** | Confirmed cancel action dan _processing guard; tombol disabled selama processing | Widget test cancel/double tap belum ditambahkan/dijalankan |
| POS-09 | Offline retry/backoff, acknowledgement, dead-letter, konflik, ordering, reconnect | **BLOCKED / NOT IMPLEMENTED** | Schema outbox sederhana; tak ada dispatcher yang terbukti | Perlu kontrak dan endpoint Laravel |
| POS-10 | Flutter runtime bebas Supabase sesuai ADR 17 Oktober | **FAILED — P1** | pubspec.yaml baris 16; main.dart baris 35–39; config_service.dart dan login_screen.dart memakai Supabase SDK/API | Penggantian auth/config perlu implementasi backend teruji |
| POS-11 | Android permissions sesuai ruang lingkup | **VERIFIED source** | AndroidManifest.xml baris 3–8: INTERNET, ACCESS_NETWORK_STATE, CAMERA, BLUETOOTH, BLUETOOTH_CONNECT, BLUETOOTH_SCAN | Merged manifest dari artifact APK belum diperiksa |
| POS-12 | Flutter analyze, full tests dan Android compile-check pada exact SHA | **FAILED pada commit pertama; pending pada koreksi** | Run 39171703111, attempt 1, SHA 16352e9c… gagal analyze; run 39171950636 pada SHA 07f4d588… queued ketika dicatat | Tidak ada hasil final run koreksi pada waktu pembuatan laporan |
| POS-13 | Token/session/storage/logging aman dan tanpa data sensitif bocor | **PARTIAL / BLOCKED** | AppIdentityStore menyimpan tenant/device identifiers di SharedPreferences; ConfigService menyimpan effective config; Supabase SDK masih aktif | Perlu audit migrasi ke Laravel auth dan secure token storage; tidak ada nilai secret dicatat |

## 5. Temuan, severity dan confidence

### P1 — Outbox tidak mempunyai jalur pengiriman/ack server — OPEN, High

**Bukti:** pos-app/lib/core/database/pos_database.dart sekitar baris 484–499 mendefinisikan outbox_events dengan id, entity_type, entity_id, payload, status, retry_count, dan created_at_utc. sqlite_sale_repository.dart sekitar baris 309–325 menulis event metadata penjualan. Tidak ditemukan service dispatcher HTTP yang memproses outbox, mengunci/claim event, melakukan retry/backoff, mengakui receipt durable, atau menyimpan conflict/dead-letter state.

**Dampak:** event lokal dapat tetap pending selamanya; tidak ada bukti remote transaction diterima, replay remote di-dedupe, konflik payload ditolak, atau stock/accounting disinkronkan. Payload outbox sekarang juga hanya metadata ringkas; kontrak backend perlu menetapkan detail transaksi dan lines yang lengkap.

**Tindak lanjut konkret:** backend owner menetapkan kontrak API Laravel versioned dan terautentikasi, konteks tenant/device dari otoritas server, snapshot sale/lines, idempotency key, receipt durable, replay request sama, konflik key dengan payload berbeda, stock conflict, serta classification retryable/non-retryable. Client kemudian membangun worker durable dengan bounded exponential backoff+jitter, state pending/in-flight/accepted/rejected/conflict, recovery process death dan ACK hanya setelah durable receipt. Jangan menebak URL/payload sebelum kontrak owner tersedia.

### P1 — Supabase runtime masih aktif dan bertentangan dengan ADR terbaru — OPEN, High

**Bukti:** pubspec.yaml baris 16 memiliki supabase_flutter; main.dart menginisialisasi Supabase; ConfigService memakai SupabaseClient dan RPC get_effective_config; LoginScreen menggunakan Supabase Auth. ADR 17 Oktober melarang Supabase dan memilih Laravel Central API + PostgreSQL 17.

**Dampak:** auth dan effective-config path klien tetap terikat platform usang. Menghapus dependency tanpa adapter pengganti berisiko mematahkan login/configuration flow.

**Tindak lanjut:** koordinasikan penggantian login/config API ke Laravel Central API dengan backend, test login/logout/token revocation/tenant authorization dan effective config, lalu hapus SDK/initialization/config lama. Tidak dilakukan dalam commit ini karena contract API pengganti belum terbukti. Tidak ada Supabase project yang diakses.

### P1 — Retry checkout sebelumnya selalu membuat transaction ID baru — MITIGATED in-session; residual setelah process death, High

**Reproduksi source sebelum perubahan:** CheckoutScreen menghasilkan ID berdasarkan microseconds pada tiap invocation. Bila hasil lokal ambigu dan operator mengulang operasi yang sama, key baru melewati duplicate ID check, sehingga pemeriksaan idempotency lokal tak menahan penggandaan yang dimaksud sebagai retry.

**Perbaikan:** StableCheckoutRequestFactory mempertahankan ID dan occurredAtUtc untuk request shape sama, dan reset saat cart/metode berubah, cancel atau checkout lokal berhasil. Test unit baru memeriksa reuse dan rotasi key.

**Residual:** key factory berada di memori. Force-stop sebelum user memulihkan draft tidak memulihkan intent/key dari factory. Sale/outbox yang sudah committed tetap ada di SQLite; perlu UI pencarian/pemulihan transaksi pending dan proses durable checkout draft agar operator tidak membuat penjualan kedua.

### P1 — Exception refresh setelah commit bisa tampil seperti checkout gagal — MITIGATED, High

**Reproduksi source sebelum perubahan:** catch pada _checkout membungkus operasi pasca-commit, sehingga exception callback/refresh dapat memunculkan snackbar gagal sekalipun transaksi SQLite telah berhasil disimpan.

**Perbaikan:** catch sekarang hanya membungkus process lokal. Sesudah commit, UI mengosongkan cart dan menampilkan “Transaksi tersimpan lokal”; exception callback ditampilkan sebagai warning refresh, bukan kegagalan checkout.

**Verifikasi:** source berubah; widget test spesifik callback-throw belum dieksekusi.

### P2 — Stok lokal tidak menjamin konsistensi antarperangkat — OPEN, High

**Bukti:** checkout membandingkan stok produk dan lot SQLite dalam transaksi DB perangkat. Test concurrency baru menguji dua operasi pada satu database lokal.

**Dampak:** dua perangkat offline dapat menjual stok yang sama. Exclusive SQLite transaction tidak memberikan serialisasi lintas perangkat/server.

**Tindak lanjut:** server menerapkan kontrol konflik stok (reservation/version/strict rejection atau kebijakan eksplisit owner) dan mengembalikan state conflict yang dapat ditangani operator. Uji dua tenant/device hanya pada disposable/staging yang disetujui; local stress test bukan substitusi.

### P2 — Schema outbox tidak mempunyai lifecycle state memadai — OPEN, High

**Bukti:** hanya id, entity_type, entity_id, payload, status, retry_count, created_at_utc; tidak terlihat kolom next_attempt_at, attempted_at, acknowledged_at, last_error, lease/claim, dead-letter/conflict. Karena dispatcher belum ada, ini dilaporkan sebagai celah desain untuk sync yang belum diimplementasikan, bukan bug pada worker yang tidak ada.

**Dampak:** retry/backoff, restart saat event sedang dikirim, observability, ordering dependensi dan rekonsiliasi tidak dapat dibuktikan.

### Tidak ada temuan P0 yang terbukti

Tidak ada P0 yang ditetapkan tanpa reproduksi atau bukti dampak yang memenuhi ambang tersebut. P1 sync/API dan runtime Supabase cukup untuk menahan rilis.

## 6. Test matrix checkout/offline/retry/conflict

Status CI-FAILED berarti run awal mencapai test gate tidak—analyze gagal lebih dahulu. CI-PENDING berarti test ditambahkan/ada dalam source, tetapi belum ada hasil akhir yang dapat diverifikasi.

| Kasus | Bukti | Status runtime | Hasil/batasan |
|---|---|---|---|
| Stok cukup | Existing PaymentService + SQLite transaction test | CI-FAILED sebelum tests | Source test ada; belum ada runtime result |
| Stok tidak cukup | Existing rollback test sekitar baris 358 | CI-FAILED sebelum tests | Ekspektasi tidak ada sale/journal/movements/outbox, stok tetap |
| Input invalid | PaymentRequest.validate menolak ID/cart/product kosong, quantity <= 0, discount negatif, timezone salah | PARTIAL / NOT RUN | Matriks eksplisit setiap field belum tersedia |
| Cancel cart | Confirmed cancel action | NOT RUN | Action hanya menghapus cart sebelum penjualan disimpan; widget test belum ada |
| Retry same request | Stable factory + 2 unit tests | CI-PENDING | Stabil dalam satu instance; setelah proses mati belum stabil |
| Same ID, payload berbeda | Existing duplicate transaction ID test | CI-FAILED sebelum tests | Repository menolak fingerprint mismatch |
| Double tap | _processing guard dan disabled control | PARTIAL / NOT RUN | Source guard; widget rapid-tap test belum tersedia |
| Timeout / ambiguous server response | Tidak ada client sync transport/API | BLOCKED | Tidak dapat diuji sebelum endpoint/ACK semantics tersedia |
| App ditutup sebelum sync | File DB close/reopen test baru | CI-PENDING | Bukan force-stop Android / process crash asli |
| Replay setelah database reopen | Test baru dan existing idempotency test | CI-PENDING | Ekspektasi satu sale/item/journal/outbox dan pending tetap |
| Error setelah partial writes | Duplicate outbox ID memicu insert error setelah transaksi mulai menulis | CI-PENDING | Test menegaskan semua write sebelumnya rollback |
| Dua checkout, satu unit terakhir | Future.wait atas dua checkout dalam DB yang sama | CI-PENDING | Hanya satu sale lokal diharapkan; tidak menguji server concurrency |
| Reconnect/retry/backoff/ACK/dead-letter | Tidak ada dispatcher ditemukan | BLOCKED | End-to-end event delivery belum tersedia |
| Konflik payload, urutan dependensi | Tidak ada server sync/response contract ditemukan | BLOCKED | Perlu API contract dan policy |
| UI local/synced distinction | Local labels, no-worker notice | VERIFIED source | Tidak ada kode yang mengklaim ack server |

## 7. Perintah, exit code, artefak dan CI

### Environment lokal

| Command | Exit code | Status | Artefak/log |
|---|---:|---|---|
| flutter --version | 127 | FAILED to launch; flutter command not found di container | Shell output; SDK lokal tidak tersedia |
| dart --version | 127 | FAILED to launch; dart command not found di container | Shell output |
| git ls-remote https://github.com/berkah-pos/Berkahtigaputeri.git refs/heads/main | 128 | BLOCKED; DNS container gagal resolve github.com | Sanitized shell error; tidak menggunakan credentials |
| flutter pub get | — | NOT RUN lokal | SDK tidak tersedia |
| flutter analyze --no-pub | — | NOT RUN lokal | SDK tidak tersedia |
| flutter test --no-pub | — | NOT RUN lokal | SDK tidak tersedia |
| flutter build appbundle --debug --no-pub | — | NOT RUN lokal | SDK tidak tersedia |

### GitHub Actions exact-SHA evidence

**Run pertama (kode sebelum perbaikan lint):**
- Workflow: Canonical POS App CI, .github/workflows/pos-app-ci.yml.
- Run ID 39171703111, attempt 1, [URL](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39171703111).
- Tested SHA: 16352e9c99a993e45a2212b990d323060aec3f44.
- Runner ubuntu-24.04. Flutter 3.47.7 stable, Dart 3.13.5, DevTools 2.60.0. Flutter archive SHA-256 diverifikasi oleh workflow: af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230.
- pub get berhasil. Analyze gagal dengan exit code 1 karena 12 issue: 1 unnecessary import sqflite dan 11 unnecessary non-null assertions di test baru. Test step dan Android compile/build/artifact steps SKIPPED, bukan PASS.
- Sanitized log: job 117805936567; output menyatakan “12 issues found” dan “Process completed with exit code 1”. Tidak ada secret/customer payload dikopi.

**Run koreksi lint:**
- Run ID 39171950636, attempt 1, [URL](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39171950636).
- Tested SHA: 07f4d58817f83390f4f16821922e424f0fd1d94d (commit yang menghapus import tak perlu dan 11 assertion).
- Status pada snapshot audit terakhir: IN PROGRESS. Run 39171950636 menjalankan exact SHA ini; Java dan install Flutter sudah success, sedangkan package resolution, analyze, tests dan Android build masih pending. Belum ada conclusion/test output/artifact yang dapat diklaim. Run duplikat 39171965890 dibatalkan sebelum analyze dan tidak menjadi bukti uji.
- Workflow commands yang ditetapkan: flutter pub get, flutter analyze --no-pub, flutter test --no-pub, bash tool/prepare_android_host.sh, Android SDK install/accept-license step dan flutter build appbundle --debug --no-pub. Exit code tiap langkah untuk run koreksi belum tersedia.

Tidak ada operasi database remote, secret rotation, deployment, perubahan DNS, produksi, atau Supabase yang dilakukan.

## 8. Files yang disentuh

| Path | Perubahan |
|---|---|
| pos-app/lib/features/pos/checkout/payment_service.dart | StableCheckoutRequestFactory for same-shape retry |
| pos-app/lib/features/pos/checkout_screen.dart | Cancel cart, stable retry identity, correct local-success status and post-commit callback warning |
| pos-app/lib/features/home/reports_screen.dart | Label/icon status antrean lokal yang tidak menandakan cloud acknowledged |
| pos-app/test/pos/checkout/payment_service_test.dart | Rollback fault injection, local concurrent checkout, file DB reopen/replay; analyzer warnings kemudian dibersihkan |
| pos-app/test/pos/checkout/stable_checkout_request_factory_test.dart | Reuse/rotate/reset key unit tests |
| docs/reports/preproduction/2026-10-18/05_POS_CLIENT_AND_OFFLINE.md | Laporan ini |

Tidak disentuh: backend Laravel/PostgreSQL schema/migrations, workbook/config resolver, pubspec.yaml dan Android permissions, atau workflow YAML. Tidak mengubah ADR permanen.

## 9. Dependency, residual risk, langkah berikutnya

1. **Backend API owner:** definisikan endpoint sale sync dan kontrak versioned: auth, tenant/device authorization server-side, payload/lines, idempotency, receipt durable, duplicate replay, payload conflict, stock conflict, retry classification dan receipt status.
2. **Client sync owner:** implementasikan durable outbox dispatcher dengan lease/claim, backoff+jitter, server ACK setelah commit, conflict queue, dead-letter/recovery, ordering, lifecycle/process-death tests, serta error sanitization. Jangan mengirim token atau data pelanggan ke log.
3. **Auth/config owner:** migrasikan Supabase Auth/RPC ke Laravel Central API dan secure token/session handling secara terkoordinasi; jangan menghapus SDK sebelum replacement diuji.
4. **Quality engineering:** refresh run 39171950636 sampai selesai; simpan version, exit codes, JUnit/expanded output, artifact checksum, dan exact tested SHA. Pastikan full suite dan Android compile berjalan setelah analyzer bersih. Tambah widget tests untuk cancel, double tap, dan callback throw; lengkapi invalid-input matrix.
5. **Release/security:** periksa Android merged manifest dari build artifact dan secure storage. Uji stock conflict lintas perangkat pada disposable/staging terisolasi. Jangan melakukan deploy, merge, rilis atau approval go-live tanpa owner.

## 10. Rekomendasi status

**BLOCKED.** Source transaction boundary lokal dan guard duplikasi lokal memberi bukti desain yang baik, dan perbaikan idempotency UI menutup sebagian risiko dalam sesi. Namun run pertama gagal analyze dan men-skip test/build; run lint-fix masih queued ketika laporan dibuat. Lebih penting lagi, cloud outbox dispatcher, durable server receipt/idempotency/conflict API belum ada dalam bukti yang diverifikasi, dan Supabase runtime masih bertentangan dengan ADR terbaru. Jangan menganggap BLOCKED setara PASS atau menggunakan laporan ini sebagai persetujuan rilis.
