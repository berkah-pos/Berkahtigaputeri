# Preproduction Audit — POS Client & Offline Correctness

**Tanggal pemeriksaan:** 20 Oktober 2026 (Asia/Jakarta)  
**Status workstream:** **BLOCKED**  
**Rekomendasi rilis: BLOCKED — bukan PASS.** CI terbaru untuk source/test pada exact SHA `77da4ae145b88ff4cd152e7f518516cc23ad7678` lulus: analyze exit 0, 50 Flutter tests lulus, dan debug Android App Bundle berhasil dibuat. Run 39172242849 (attempt 1) berstatus `success`. Status workstream tetap BLOCKED karena dispatcher/outbox acknowledgement server belum ada dan runtime Supabase masih aktif, bertentangan dengan ADR 2026-10-17. AAB yang dibuat adalah debug-only compile-check, bukan signed release atau bukti uji perangkat.

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

Base SHA dicatat sebelum perubahan. Branch audit dibuat dari SHA tersebut; perubahan source/test hanya di `pos-app/**` dan laporan. Source/test terakhir yang diuji CI adalah SHA `77da4ae145b88ff4cd152e7f518516cc23ad7678`; pembaruan laporan ini dibuat setelah CI selesai dan tidak mengubah aplikasi. PR tetap draft dan belum di-merge.

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
| POS-01 | Sale, items, stok/lots/movements, jurnal dan outbox atomik dalam satu SQLite transaction | **SOURCE-VERIFIED + TEST-EXECUTED** | `pos_database.dart:54–66` memakai transaksi eksklusif; `sqlite_sale_repository.dart:31–80, 230–325`; run 39172242849 pada SHA `77da4ae…` lulus full test suite | Bukti untuk kegagalan insert outbox dan rollback tersedia lewat test regresi; crash device nyata belum disimulasikan |
| POS-02 | Stok tidak cukup tidak memutasi sale, jurnal, stok atau outbox | **TEST-EXECUTED — PASS** | `payment_service_test.dart`; run 39172242849, SHA `77da4ae…`, `flutter test --no-pub` exit 0 | Hanya lingkungan SQLite test; bukan acceptance server inventory |
| POS-03 | Outbox insert failure me-rollback semua perubahan checkout sebelumnya | **TEST-EXECUTED — PASS** | Test fault injection duplicate outbox ID membandingkan stok/lots/cost layers/tabel transaksi ke baseline pra-checkout; run 39172242849 lulus | Test memverifikasi SQLite rollback, bukan power-loss hardware |
| POS-04 | Retry request identik memakai transaction ID/timestamp stabil; perubahan cart/metode membuat intent baru | **TEST-EXECUTED — PASS (in-memory only)** | `StableCheckoutRequestFactory`; dua unit test, run 39172242849 lulus | Key tidak durable lintas force-stop/proses; retry bisnis setelah restart belum aman end-to-end |
| POS-05 | Dua checkout lokal bersamaan tidak menjual unit terakhir dua kali | **TEST-EXECUTED — PASS (satu DB lokal)** | Test `Future.wait` dua checkout atas satu unit; run 39172242849 lulus | Bukan bukti concurrency server atau dua perangkat offline |
| POS-06 | Outbox pending bertahan setelah file DB ditutup/dibuka kembali; local replay tidak menggandakan sale | **TEST-EXECUTED — PASS (file-backed test)** | Test tutup/buka ulang DB lalu replay request sama: satu sale/item/jurnal/outbox; pending tetap; run 39172242849 lulus | Bukan Android force-stop/power-loss test dan bukan remote replay |
| POS-07 | UI tidak mengklaim server accepted/synced tanpa durable ACK | **SOURCE-VERIFIED** | `checkout_screen.dart:195–244`, `reports_screen.dart:156–176`; UI menyatakan transaksi lokal dan cloud sync belum aktif | Tidak ada ACK server karena dispatcher/API belum ada |
| POS-08 | Cancel cart dan double-tap protection | **PARTIAL** | `_cancelCart` memakai dialog konfirmasi; `_processing` guard menonaktifkan kontrol | Widget test khusus cancel, rapid double tap, dan callback-throw belum dibuat/dijalankan |
| POS-09 | Offline dispatcher/reconnect, backoff, acknowledgement, dead-letter, conflict dan ordering | **BLOCKED / NOT IMPLEMENTED** | `outbox_events` hanya menyimpan ID/type/entity/payload/status/retry_count/timestamp; tidak ditemukan dispatcher HTTP aktif | Butuh kontrak backend Laravel dan implementasi client terkoordinasi; jangan mengarang endpoint |
| POS-10 | Flutter runtime bebas Supabase sesuai ADR 17 Oktober | **FAILED — P1 / HIGH confidence** | `pubspec.yaml:16`; `main.dart:2–39`; `config_service.dart`; `login_screen.dart` masih memakai SDK, Auth dan RPC Supabase | Jangan menghapus dependency sampai replacement Laravel auth/config diuji; blocker compliance tetap terbuka |
| POS-11 | Android permissions sesuai kebutuhan yang direview | **SOURCE-VERIFIED** | `AndroidManifest.xml` memuat INTERNET, ACCESS_NETWORK_STATE, CAMERA, BLUETOOTH, BLUETOOTH_CONNECT, BLUETOOTH_SCAN | Merged manifest AAB dan izin final dari artifact tidak dianalisis; source saja tidak membuktikan artifact final |
| POS-12 | Analyze, test suite dan Android compile-check pada exact SHA | **CI-OBSERVED — PASS** | Run 39172242849, attempt 1, tested SHA `77da4ae145b88ff4cd152e7f518516cc23ad7678`: analyze exit 0, 50 tests lulus, debug AAB build dan upload sukses | Hanya debug compile-check; bukan publisher-signed release/device acceptance |
| POS-13 | Token/session/storage/logging aman dan data sensitif tidak bocor | **PARTIAL / BLOCKED** | `AppIdentityStore` menaruh tenant/device IDs di SharedPreferences; Supabase session masih dikelola SDK; belum ada audit secure storage menyeluruh | Lanjutkan bersama auth/API owner; tidak ada nilai secret disalin ke laporan |

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

**Run CI penentu:** workflow `Canonical POS App CI`, run `39172242849`, attempt 1, tested source/test SHA `77da4ae145b88ff4cd152e7f518516cc23ad7678`; exact-SHA conclusion `success`. Analyze exit 0, 50 tests passed (exit 0), debug AAB compile-check exit 0. Hasil ini memperbarui status snapshot yang sebelumnya menandai rerun masih berjalan. Kasus yang tidak memiliki implementasi/tes khusus tetap NOT RUN/BLOCKED di bawah.

| Kasus | Bukti | Status | Hasil/batasan |
|---|---|---|---|
| Stok cukup | PaymentService + SQLite transaction test dan cashier widget test | **CI PASS** | Ada sale, item, jurnal, movement, satu outbox pending; bukan server sync |
| Stok tidak cukup | `payment_service_test.dart` rollback assertion | **CI PASS** | Stok/lots/cost layer dan record checkout tetap di baseline |
| Input invalid | `PaymentRequest.validate()` | **PARTIAL** | Source menolak ID/cart/product kosong, quantity <= 0, diskon negatif, timezone selain Asia/Jakarta; belum ada matriks runtime eksplisit untuk setiap invalid field |
| Cancel cart | Dialog konfirmasi `_cancelCart()` | **NOT RUN** | Belum ada widget regression test khusus yang membuktikan cancel tanpa sale/outbox |
| Retry request identik | `StableCheckoutRequestFactory` unit test | **CI PASS — in-memory** | ID/timestamp sama untuk request shape sama dalam satu stateful widget/factory; tidak durable setelah process death |
| Same transaction ID, fingerprint sama | Existing duplicate transaction test | **CI PASS** | Mengembalikan sale yang sudah tersimpan tanpa menambah sale/jurnal/outbox |
| Same transaction ID, payload berbeda | Existing duplicate transaction test | **CI PASS** | Ditolak dengan `DuplicateTransactionIdException`; data awal tetap |
| Double tap | `_processing` guard dan tombol disabled | **PARTIAL / NOT RUN** | Source mencegah pemanggilan kedua saat processing; rapid double-tap widget test belum ada |
| Timeout / ambiguous server response | Tidak ada client sync transport/API | **BLOCKED** | Belum dapat disimulasikan sebelum endpoint dan durable receipt contract tersedia |
| App ditutup sebelum sync | File-backed SQLite close/reopen test | **CI PASS — simulasi terbatas** | Membuka DB ulang menunjukkan sale/outbox pending tetap; bukan force-stop Android/power loss |
| Replay setelah DB reopen | Test file-backed replay | **CI PASS** | Satu sale/item/jurnal/outbox setelah replay request sama; event tetap pending |
| Exception setelah partial writes | Duplicate outbox ID fault-injection test | **CI PASS** | Rollback stok/lots/cost layers/ledger sampai baseline pra-checkout |
| Dua checkout, satu unit terakhir | `Future.wait` dua operasi pada database SQLite yang sama | **CI PASS — lokal saja** | Tepat satu berhasil; tidak menggantikan server concurrency/dua perangkat |
| Reconnect, retry/backoff, server ACK, dead-letter | Tidak ditemukan dispatcher cloud | **BLOCKED / NOT IMPLEMENTED** | Event lokal tidak memiliki jalur terbukti menuju server |
| Konflik payload dan urutan dependensi | Belum ada sync API contract/dispatcher | **BLOCKED / NOT RUN** | Perlu endpoint Laravel berversi, idempotency dan conflict policy |
| Callback UI throw setelah commit | Pemisahan catch pasca-commit pada checkout UI | **SOURCE-VERIFIED; TEST NOT RUN** | Seharusnya warning refresh, tidak menyebut checkout gagal; widget regression test khusus belum ada |
| UI local/synced distinction | Label checkout dan laporan lokal | **SOURCE-VERIFIED** | Secara eksplisit menyebut penerimaan server belum terjadi dan cloud sync belum aktif |

## 7. Perintah, exit code, artefak dan CI

### Perintah lokal di container audit

| Command | Exit code | Status | Artefak/log tersanitasi |
|---|---:|---|---|
| `flutter --version` | 127 | **NOT RUN / BLOCKED** — executable tidak terpasang | Output shell: `flutter: not installed` |
| `dart --version` | 127 | **NOT RUN / BLOCKED** — executable tidak terpasang | Output shell: `dart: not installed` |
| `git clone --filter=blob:none --no-checkout https://github.com/berkah-pos/Berkahtigaputeri.git /tmp/Berkahtigaputeri-audit` | 128 | **BLOCKED** — container gagal resolve `github.com` (DNS) | Output shell tersanitasi; tidak menggunakan kredensial |
| `flutter pub get` | — | **NOT RUN lokal** | Flutter SDK tidak tersedia |
| `flutter analyze --no-pub` | — | **NOT RUN lokal** | Flutter SDK tidak tersedia |
| `flutter test --no-pub` | — | **NOT RUN lokal** | Flutter SDK tidak tersedia |
| `flutter build appbundle --debug --no-pub` | — | **NOT RUN lokal** | Flutter SDK tidak tersedia |

### GitHub Actions — bukti exact-SHA

**Run penentu terbaru:** [Canonical POS App CI run 39172242849](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39172242849), attempt 1, completed `success`, workflow `.github/workflows/pos-app-ci.yml`, runner `ubuntu-24.04`, job ID `117807563940` ([job log](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39172242849/job/117807563940)). Tested SHA: `77da4ae145b88ff4cd152e7f518516cc23ad7678` — SHA yang sama dengan source/test terbaru saat run tersebut; laporan ini diperbarui setelah run dan commit laporan tidak mengubah aplikasi.

| Command/step | Exit code/conclusion | Bukti |
|---|---|---|
| Flutter distribution/version step | 0 / success | Flutter `3.47.7 stable`, Dart `3.13.5`, DevTools `2.60.0`; workflow memverifikasi checksum archive Flutter `af7455f540df951184c7953fbe3cf884766e7541dacf8571f9f582db03dd6230` |
| `flutter pub get` (Resolve packages) | 0 / success | Step selesai; dependensi berhasil di-resolve |
| `flutter analyze --no-pub` | 0 / success | Log: `No issues found! (ran in 6.3s)` |
| `flutter test --no-pub` | 0 / success | Log: `50 tests passed.` |
| `bash tool/prepare_android_host.sh` | 0 / success | Android host scaffold preparation step sukses |
| Android SDK locate / accept licenses / install compile platforms | 0 / success | Seluruh step setup Android selesai |
| `flutter build appbundle --debug --no-pub` | 0 / success | Log: `Built build/app/outputs/bundle/debug/app-debug.aab` |
| Upload `berkahtigaputeri-pos-debug-aab.zip` | success | Artifact ID `12153067341`; [artifact](https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/39172242849/artifacts/12153067341); SHA-256 ZIP `42035a681f3428ccadcbf5f5ead8619ab7cab9f07c1f0eac3b9dac75cc6a7583`; size 74,762,754 bytes; expires 2026-10-25T22:31:01Z |

Artifact tersebut **debug-only compile-check**, bukan publisher-signed production AAB. Tidak ada pemasangan/uji perangkat Android, pengujian process kill sesungguhnya, uji server sync, atau pengujian produksi yang diklaim.

**Riwayat run awal (tidak dipakai sebagai hasil terbaru):**
- Run 39171703111, attempt 1, tested SHA `16352e9c99a993e45a2212b990d323060aec3f44`: analyze exit 1 (`12 issues found`), maka test/build steps berikutnya dilewati.
- Run 39171950636, attempt 1, tested SHA `07f4d58817f83390f4f16821922e424f0fd1d94d`: analyze exit 0, tests exit 1 (`48 passed, 2 failed`). Dua assertion itu diperbaiki berikutnya: ekspektasi widget mengikuti pesan status lokal yang benar dan rollback test mempertahankan opening inventory movement seed.
- Status “IN PROGRESS” dalam snapshot laporan sebelumnya sudah **usang**. Run 39172242849 di exact SHA `77da4ae…` menuntaskan analyze, 50 test, dan debug compile-check dengan sukses.

Tidak ada operasi database remote, secret rotation, deployment, perubahan DNS, produksi, atau Supabase yang dilakukan.

## 8. Files yang disentuh

| Path | Perubahan |
|---|---|
| pos-app/lib/features/pos/checkout/payment_service.dart | StableCheckoutRequestFactory for same-shape retry |
| pos-app/lib/features/pos/checkout_screen.dart | Cancel cart, stable retry identity, correct local-success status and post-commit callback warning |
| pos-app/lib/features/home/reports_screen.dart | Label/icon status antrean lokal yang tidak menandakan cloud acknowledged |
| pos-app/test/pos/checkout/payment_service_test.dart | Rollback fault injection, local concurrent checkout, file DB reopen/replay; analyzer warnings kemudian dibersihkan |
| pos-app/test/home/cashier_screen_checkout_test.dart | Update success/status text expectations to match the truthful local-only checkout UI |
| pos-app/test/pos/checkout/stable_checkout_request_factory_test.dart | Reuse/rotate/reset key unit tests |
| docs/reports/preproduction/2026-10-18/05_POS_CLIENT_AND_OFFLINE.md | Laporan ini |

Tidak disentuh: backend Laravel/PostgreSQL schema/migrations, workbook/config resolver, pubspec.yaml dan Android permissions, atau workflow YAML. Tidak mengubah ADR permanen.

## 9. Dependency, residual risk, langkah berikutnya

1. **Backend API owner:** definisikan endpoint sale sync dan kontrak versioned: auth, tenant/device authorization server-side, payload/lines, idempotency, receipt durable, duplicate replay, payload conflict, stock conflict, retry classification dan receipt status.
2. **Client sync owner:** implementasikan durable outbox dispatcher dengan lease/claim, backoff+jitter, server ACK setelah commit, conflict queue, dead-letter/recovery, ordering, lifecycle/process-death tests, serta error sanitization. Jangan mengirim token atau data pelanggan ke log.
3. **Auth/config owner:** migrasikan Supabase Auth/RPC ke Laravel Central API dan secure token/session handling secara terkoordinasi; jangan menghapus SDK sebelum replacement diuji.
4. **Quality engineering:** run 39172242849 telah lulus untuk exact source/test SHA; simpan bukti log/versi/exit code di atas. Tambahkan tes widget untuk cancel, rapid double tap, dan callback pasca-commit throw; lengkapi invalid-input matrix dan uji process-death nyata pada perangkat/emulator terisolasi.
5. **Release/security:** periksa Android merged manifest dari build artifact dan secure storage. Uji stock conflict lintas perangkat pada disposable/staging terisolasi. Jangan melakukan deploy, merge, rilis atau approval go-live tanpa owner.

## 10. Rekomendasi status

**BLOCKED.** Atomicity lokal, fingerprint/idempotency pada repository lokal, retry-key in-session, rollback fault injection, satu-DB concurrency, file-backed reopen/replay, seluruh 50 Flutter tests, analyzer, dan debug AAB compile-check lulus pada exact source/test SHA `77da4ae145b88ff4cd152e7f518516cc23ad7678` (CI run 39172242849). Tetapi tidak ada outbox dispatcher/API, durable server receipt/ack, retry/backoff, dead-letter/conflict/ordering atau bukti remote idempotency; key UI masih in-memory dan dapat hilang saat process death; dan runtime Supabase tetap bertentangan dengan ADR no-Supabase. Tidak ada P0 yang terbukti; P1 sync/API dan runtime Supabase cukup untuk memblokir rilis. Jangan menyamakan BLOCKED dengan PASS atau menggunakan laporan ini sebagai persetujuan go-live.
