# 08 — Audit Domain, DNS, Email, TLS, dan Security Headers

**Tanggal pemeriksaan:** initial read-only audit 2026-10-19; retest 2026-10-20 04:10–04:12 WIB (Asia/Jakarta).  
**Status workstream:** **BLOCKED** — bukti DNS/TLS publik, konfigurasi DNS/mail aktual, dan edge runtime tidak dapat diverifikasi dari lingkungan ini.  
**Rekomendasi:** **BLOCKED / NO CUTOVER**. Status ini bukan kesimpulan bahwa domain sedang down atau DNS salah; lookup terhalang dan tidak menghasilkan jawaban DNS yang dapat dipercaya.

## 1. Ringkasan eksekutif

Audit read-only atas repository canonical `berkah-pos/Berkahtigaputeri` dan konektor Hostinger Mail menemukan satu mailbox yang terdaftar pada akun email terhubung (`admin@berkahtigaputeri.co.id`). Source Laravel saat ini hanya menunjukkan scaffold dan health route; konfigurasi Nginx dalam image aplikasi hanya mendengarkan port 80, sementara TLS termination mungkin seharusnya berada di ingress/Coolify. Tidak ditemukan bukti konfigurasi DNS zone, mail sender, SPF/DKIM/DMARC, sertifikat, HTTP→HTTPS redirect, atau security headers edge yang dapat membuktikan konfigurasi aktif.

Probe publik tidak berhasil karena DNS resolver/network dari lingkungan audit tidak bisa menyelesaikan host. Semua status DNS/MX/SPF/DKIM/DMARC/TLS dan respons HTTP publik karena itu tetap **BLOCKED / NOT VERIFIED**, tidak **FAILED**. Tidak ada perubahan registrar, DNS, mailbox, sertifikat produksi, atau kredensial. Tidak ada email uji yang dikirim.

## 2. Identitas revisi dan batasan

- **Repository:** `berkah-pos/Berkahtigaputeri` (canonical repository sesuai root README).
- **Base branch/SHA:** `main` / `371b7fdf0bf672b37ceb1023e647f114221bf797`.
- **Branch audit:** `audit/preprod-domain-email-2026-10-18` (dibuat dari base SHA tersebut).
- **Laporan:** `docs/reports/preproduction/2026-10-18/08_DOMAIN_DNS_EMAIL_TLS.md`.
- **Commit laporan pada saat draft PR dibuka:** `8e4565d0e2c391af39bd1f3eb6bbf24befb4389d`. SHA final setiap pembaruan berikutnya disimpan dalam metadata head PR; sebuah commit tidak dapat memuat SHA-nya sendiri tanpa menghasilkan commit baru.
- **Draft PR:** [#86 — audit: domain DNS email and TLS edge preproduction evidence](https://github.com/berkah-pos/Berkahtigaputeri/pull/86). PR masih draft/open; tidak ada persetujuan merge atau go-live.
- **Scope:** bukti domain/DNS, email delivery posture, HTTP→HTTPS/TLS/canonical host, konfigurasi header di source/edge, runbook cutover dan rollback. Tidak ada perubahan aplikasi/infra di luar file laporan ini.
- **Akses produksi:** tidak digunakan. Semua tes DNS/TLS adalah pemeriksaan read-only; tidak ada database yang disentuh (N/A).

## 3. Dokumen otoritatif dan source yang diperiksa

Dokumen wajib dibaca mengikuti urutan AGENTS.md, termasuk:

1. `AGENTS.md` — aturan kerja, bukti, safety gate, branch/PR, dan larangan Supabase.
2. `docs/permanent/DOC_00_CANONICAL_ARCHITECTURE_DECISION.md` — kontrak konfigurasi 5 lapisan dan workbook 352-entry.
3. `docs/permanent/ADR-2026-10-17-OWNER-KVM2-LARAVEL-POSTGRESQL-NO-SUPABASE.md` — owner authority terbaru: KVM2/Coolify, Laravel, PostgreSQL 17 privat; no Supabase.
4. `docs/permanent/ADR-2026-10-16-OWNER-ARCHITECTURE-DECISION.md` — dibaca sebagai keputusan lebih lama yang tunduk pada ADR 2026-10-17.
5. `docs/permanent/DOC_14_KVM2_ISOLATED_TENANT_ARCHITECTURE.md` — target topologi dan security gates; dinyatakan belum dideploy.
6. `docs/permanent/DOC_00_MASTER_ROADMAP.md` — phase gates dan langkah deployment/release.
7. `docs/permanent/README.md` — peta otoritas dan evidence boundaries.
8. `docs/permanent/DOC_12_SAAS_DATABASE_OFFLINE_ARCHITECTURE_AND_AGENT_PROTOCOL.md` — protokol, keamanan, TLS, dan bukti.
9. `docs/permanent/DOC_13_UNIFIED_POS_APP_INTEGRATION_REPORT.md` — snapshot historis Flutter dan implementasi yang belum selesai.
10. `docs/HARDENING/README.md` — laporan hardening 2026-10-11 yang menunjuk repo lama; diperlakukan sebagai bukti historis, bukan kondisi runtime saat ini.
11. `README.md` root — status baseline Laravel/PostgreSQL dan perbedaan source target vs deployment.

**Source-verified pada base SHA:**

| Path / simbol | Baris | Temuan yang dibuktikan | Batas bukti |
|---|---:|---|---|
| `docker/nginx.conf` — server block | 1–3, 16–18, 27–29 | Container Nginx hanya mendeklarasikan `listen 80 default_server`, `server_name _`, `try_files` dan blokir dotfiles; tidak ada `listen 443`, HTTP redirect atau `add_header` di file ini. | Tidak membuktikan Coolify/edge di luar container tidak melakukan TLS/headers. |
| `Dockerfile` — production stage | source telah diperiksa | Image memasang `docker/nginx.conf`, mengekspos port 80, dan health-check menggunakan HTTP loopback `/up`. | Tidak membuktikan port 80 diekspos langsung ke Internet atau bagaimana konfigurasi ingress aktif. |
| `bootstrap/app.php` — middleware | 7–20; khususnya 14–15 | Closure middleware Laravel kosong; tidak ada middleware custom untuk response security headers di bootstrap ini. | Middleware dari provider/paket lain atau edge dapat menambahkan header; runtime tidak diuji. |
| `routes/web.php` | 5–13 | Route web yang terlihat hanya `/` dengan metadata service/health. | Bukan bukti semua route runtime; tidak ada endpoint deployment terverifikasi. |
| `routes/api.php` | 5–11 | Route API yang terlihat adalah `/v1/platform-health`; tidak ada `/check-status` pada file ini. | Endpoint trial mungkin merupakan layanan lama/terpisah; deployment tidak diverifikasi. |
| `.env.example` | 1–7, 9–30 | Contoh lingkungan lokal memakai `APP_URL=http://localhost:8000`, konfigurasi DB lokal, dan tidak memuat `MAIL_*`. | Ini bukan konfigurasi produksi atau bukti actual environment variables. |
| `berkah-pos-trial/lib/main.dart` | 10–12, 93–94, 275–277 | Trial app memiliki URL untuk `api.../check-status`, apex `/delete-account` dan `/privacy`; permintaan status mengirim email melalui query string GET. | Source string/HTTP call tidak membuktikan host/domain atau endpoint tersedia di publik. Ini juga app trial, bukan bukti API Laravel. |
| `berkah-pos-trial/README.md` | 13 | Menyebut `/check-status` sebagai endpoint yang seharusnya ada dan format respons yang diharapkan. | **CLAIMED/DESIRED**, bukan bukti server berjalan. |
| `berkah-pos-trial/tool/verify_project.py` | 52–69 | Validator lokal memeriksa string URL di source dan marker fitur. | Bukan DNS lookup, TLS handshake, HTTP integration test, ataupun email deliverability test. |
| `pos-app/lib/features/home/home_screen.dart` | 12–13 | Ada link privacy dan delete-account pada app POS modular. | Tidak membuktikan halaman web tersedia atau sesuai kebijakan. |
| `pos-app/pubspec.yaml` | dependency manifest | Masih berisi `supabase_flutter`; dokumen otoritatif melarang penggunaan Supabase. | Konflik platform terpisah; tidak diperbaiki oleh workstream DNS/email ini. Tidak ada koneksi ke Supabase yang dilakukan. |

File `config/mail.php` tidak ditemukan pada base SHA (GitHub API 404). Pencarian source untuk `MAIL_MAILER`, `MAIL_HOST`, `MAIL_FROM_ADDRESS`, SPF/DKIM/DMARC, CAA, sertifikat, HSTS, CSP, dan konfigurasi middleware/header tidak menemukan konfigurasi runtime relevan pada file yang dicari. Pencarian source tidak membuktikan record DNS atau konfigurasi provider tidak ada di luar repository.

## 4. Claimed vs verified

| Area / acceptance gate | Claimed / dokumen atau ekspektasi | Verified langsung | Status dan blocker |
|---|---|---|---|
| Apex `berkahtigaputeri.co.id` | Source memiliki URL HTTPS untuk privacy/delete-account. | Tidak ada jawaban DNS/HTTP/TLS yang dapat diperoleh. | **BLOCKED** — resolver/network audit tidak menyelesaikan host; status publik sebenarnya belum diketahui. |
| `www.berkahtigaputeri.co.id` | Belum ditemukan kontrak canonical/redirect aktif. | Tidak ada jawaban DNS/HTTP/TLS. | **BLOCKED** — belum terbukti ada/tidak ada record maupun redirect ke apex. |
| `app.berkahtigaputeri.co.id` | Ada usulan lama dalam dokumen archive/superseded untuk central UI. | Tidak ada jawaban DNS/HTTP/TLS. | **BLOCKED / DECISION REQUIRED** — jangan menghidupkan subdomain dari dokumen archive saja; tetapkan kebutuhan dan owner. |
| `api.berkahtigaputeri.co.id` | Trial README mendeskripsikan `GET /check-status`; source merujuk endpoint tersebut. | Tidak ada jawaban DNS/HTTP/TLS; Laravel `routes/api.php` pada base hanya memperlihatkan health route. | **BLOCKED** — backend publik dan kontrak API harus diverifikasi oleh owner API/mobile. |
| A/AAAA dan IP publik | ADR memilih KVM2 sebagai target hosting, tetapi tidak menyebut IP publik aktual. | Tidak ada IP address yang berhasil di-resolve atau diverifikasi terhadap panel VPS. | **BLOCKED** — jangan arahkan domain ke IP tebakan, `localhost`, IP private, link-local, loopback, atau CGNAT. |
| NS, DNSSEC, CAA | Tidak ada record-zone terlampir di repo. | Tidak ada record yang dapat dibaca dari resolver eksternal. | **BLOCKED** — zona authoritative dan delegasi belum diketahui. |
| MX dan SPF | Mailbox admin tercatat pada akun Hostinger Mail yang terhubung; tidak ada TXT/MX evidence di source. | API `account_current` berhasil dengan HTTP 200 dan menyebut hanya mailbox terkelola `admin@berkahtigaputeri.co.id`. | Mailbox admin **VERIFIED sebagai terdaftar pada daftar connector**; MX/SPF **BLOCKED**. Kehadiran di daftar tidak membuktikan delivery atau bahwa tidak ada alias di tempat lain. |
| DKIM dan DMARC | Tidak ada selector/key/policy source yang ditemukan. | Lookup TXT eksternal tidak menghasilkan jawaban DNS yang bisa digunakan. | **BLOCKED** — selector/provider dan `p=` aktif belum diverifikasi. Jangan mengubah DMARC. |
| Sender `noreply@`, Reply-To, bounce | Belum ada `MAIL_*` sender config di `.env.example`; `config/mail.php` tak ditemukan pada revisi ini. | Tidak ada sender email aplikasi atau test delivery yang dijalankan. | **BLOCKED** — tentukan service provider, sender identity, Reply-To, envelope-from/return path, bounce mailbox/webhook dan owner. |
| Admin/support/security/privacy email | Daftar mailbox pada connector hanya menunjukkan `admin@...`. | `admin@` **VERIFIED** pada managed-mailbox list; `support@`, `security@`, `privacy@`, dan `noreply@` tidak terdaftar pada daftar yang dikembalikan connector ini. | **BLOCKED / OWNER DECISION** — ketiadaan pada daftar ini bukan bukti alias/mailbox tersebut tidak ada secara global. Jangan membuat mailbox/alias tanpa persetujuan. |
| HTTP→HTTPS & canonical host | Origin image Nginx hanya HTTP port 80; TLS dapat saja diterminasi oleh edge di depan origin. | Probe `curl` tidak dapat menyelesaikan host; redirect chain tidak teruji. | **BLOCKED / P1 release gate** — verifikasi edge actual, chain, redirect, SAN dan origin private boundary. |
| Certificate issuer/chain/SAN/expiry/renewal | Tidak ada sertifikat/TLS configuration teridentifikasi dalam tracked source. | `openssl s_client` tidak berhasil melakukan handshake terverifikasi. | **BLOCKED / P1 release gate** — expiry dan auto-renew tak diketahui, jangan menyatakan sertifikat valid. |
| Security headers | Bootstrap middleware custom kosong; `docker/nginx.conf` tidak memuat header directives. | Tidak ada response headers HTTP(S) publik yang dapat dibaca. | Source-origin gap **VERIFIED**; header effective di edge **BLOCKED**. Jangan menyatakan runtime kekurangan header sebelum proxy diperiksa. |
| Test pengiriman email | Tidak ada test delivery tercatat dalam scope ini. | Tidak ada test message dikirim. | **NOT RUN** — butuh sender yang disetujui, test inbox terkontrol, dan lingkungan terisolasi. |

## 5. Output lookup/commands tersanitasi

### Timestamp dan resolver availability

- Waktu mail-account lookup: `2026-10-19 04:24:39 UTC` (`2026-10-19 11:24:39 WIB`); HTTP 200. Nilai correlation/trace/resource identifiers tidak dipublikasikan.
- Probe DNS/TLS/HTTP: sekitar `2026-10-19 11:24:55 WIB` (command `date -u '+%Y-%m-%dT%H:%M:%SZ'` mengembalikan timestamp `2026-10-19T04:24:55Z`).
- `dig`, `nslookup`, dan `host` tidak terpasang di runner audit. Resolver OS (`getent`) dan `curl` tersedia, tetapi lookup tidak berhasil.

| Probe / perintah tepat | Target | Exit code | Output tersanitasi / hasil |
|---|---|---:|---|
| `getent ahosts berkahtigaputeri.co.id` | A/AAAA apex | 2 | Tidak ada hasil address. |
| `getent ahosts www.berkahtigaputeri.co.id` | A/AAAA `www` | 2 | Tidak ada hasil address. |
| `getent ahosts app.berkahtigaputeri.co.id` | A/AAAA `app` | 2 | Tidak ada hasil address. |
| `getent ahosts api.berkahtigaputeri.co.id` | A/AAAA `api` | 2 | Tidak ada hasil address. |
| `curl -sS -I -L --connect-timeout 4 --max-time 8 -o /dev/null -w 'http_code=%{http_code} final_url=%{url_effective} redirects=%{num_redirects} tls_verify=%{ssl_verify_result}\n' http://berkahtigaputeri.co.id/` | HTTP apex | 6 | `Could not resolve host`; HTTP 000; redirects 0. |
| `curl -sS -I -L --connect-timeout 4 --max-time 8 -o /dev/null -w 'http_code=%{http_code} final_url=%{url_effective} redirects=%{num_redirects} tls_verify=%{ssl_verify_result}\n' https://berkahtigaputeri.co.id/` | HTTPS apex | 6 | `Could not resolve host`; HTTP 000; redirects 0. |
| `curl -sS -I -L --connect-timeout 4 --max-time 8 -o /dev/null -w 'http_code=%{http_code} final_url=%{url_effective} redirects=%{num_redirects} tls_verify=%{ssl_verify_result}\n' https://www.berkahtigaputeri.co.id/` | HTTPS `www` | 6 | `Could not resolve host`; HTTP 000; redirects 0. |
| `curl -sS -I -L --connect-timeout 4 --max-time 8 -o /dev/null -w 'http_code=%{http_code} final_url=%{url_effective} redirects=%{num_redirects} tls_verify=%{ssl_verify_result}\n' https://app.berkahtigaputeri.co.id/` | HTTPS `app` | 6 | `Could not resolve host`; HTTP 000; redirects 0. |
| `curl -sS -I -L --connect-timeout 4 --max-time 8 -o /dev/null -w 'http_code=%{http_code} final_url=%{url_effective} redirects=%{num_redirects} tls_verify=%{ssl_verify_result}\n' https://api.berkahtigaputeri.co.id/check-status` | HTTPS API | 6 | `Could not resolve host`; HTTP 000; redirects 0. |
| `timeout 8 openssl s_client -connect berkahtigaputeri.co.id:443 -servername berkahtigaputeri.co.id -brief -verify_return_error </dev/null` | TLS apex | 1 | Tidak ada handshake terverifikasi; output koneksi tidak menunjukkan bukti sertifikat. |
| `timeout 8 openssl s_client -connect www.berkahtigaputeri.co.id:443 -servername www.berkahtigaputeri.co.id -brief -verify_return_error </dev/null` | TLS `www` | 1 | Tidak ada handshake terverifikasi. |
| `timeout 8 openssl s_client -connect api.berkahtigaputeri.co.id:443 -servername api.berkahtigaputeri.co.id -brief -verify_return_error </dev/null` | TLS API | 1 | Tidak ada handshake terverifikasi. |

Perintah `getent` dijalankan terpisah untuk apex, `www`, `app`, dan `api`; masing-masing exit code 2. Tabel berisi excerpt output yang disanitasi; raw output tidak disimpan sebagai artefak terpisah.

Percobaan baca langsung HTTP(S) lewat web fetch juga tidak memberi salinan halaman yang bisa dianalisis. Ini konsisten dengan kurangnya akses jaringan/resolusi di lingkungan audit, bukan bukti bahwa website tidak beroperasi. Resolver publik `1.1.1.1`/`8.8.8.8` tidak berhasil diuji dari runner ini; belum ada authoritative DNS output untuk dipublikasikan.

### Email account connector

- **Operasi:** read-only `account_current` terhadap dua akun Hostinger Mail yang terhubung.
- **Exit/result:** HTTP 200 pada keduanya; returned managed-mailbox list memuat satu alamat `admin@berkahtigaputeri.co.id`.
- **Output disanitasi:** mailbox `admin@...` ada pada list; tidak ada isi email, resource ID, token, correlation ID atau trace ID yang disimpan dalam laporan.
- **Batas:** ini memeriksa daftar mailbox yang dapat dikelola konektor saja. Tidak memeriksa DNS MX, SMTP submission, inbox usability, authentication/MFA mailbox, message trace, bounce handling, SPF/DKIM/DMARC alignment atau inbox placement. Tidak ada email yang dikirim atau dipindah.

**Artefak/log:** output ringkas di atas tertanam di laporan; tidak ada file raw log terpisah. Tidak ada DB engine dipakai untuk tes ini (N/A). Tidak ada test suite/CI yang dijalankan untuk DNS, TLS atau email.

## 6. Findings

| ID | Severity / confidence | Finding and reproduction/evidence | Impact | Perbaikan yang disarankan / retest |
|---|---|---|---|---|
| F-DNS-01 | **P1 / High** untuk blocker verifikasi; bukan klaim DNS rusak | Pada 2026-10-19 sekitar 11:24 WIB, `getent ahosts` gagal (exit 2) dan `curl -I -L` exit 6 `Could not resolve host` untuk apex/www/app/api. | Tidak ada dasar bukti untuk cutover atau klaim bahwa hostname mengarah ke IP publik yang benar. | Jalankan lookup dari workstation/runner dengan DNS publik berfungsi dan dari authoritative nameserver; simpan A/AAAA/NS/MX/TXT/CAA/DNSSEC secara tersanitasi, time-stamped. Jangan menulis record sebelum pembanding dan approval tersedia. |
| F-EDGE-01 | **P1 / Medium** | `docker/nginx.conf:1-3` hanya mendeklarasikan `listen 80` dan wildcard default server; `Dockerfile` mengekspos 80. TLS termination/redirect mungkin di edge, tetapi tidak ada evidence config/running edge yang dapat diakses. | TLS cert, redirect, canonical host, origin exposure dan proxy trust belum diterima sebagai gate pra-produksi. | Pemilik infra verifikasi konfigurasi ingress/Coolify pada staging terisolasi, sertifikat, chain, SAN, masa berlaku dan renewal; pastikan origin Nginx tidak dapat diakses langsung dari Internet. Retest semua host via curl/openssl setelah DNS dapat diuji. |
| F-HEADERS-01 | **P1 / Medium** | `bootstrap/app.php:14-15` custom middleware closure kosong; `docker/nginx.conf:1-30` tidak mengatur HSTS/CSP/X-Content-Type-Options/Referrer-Policy/Permissions-Policy. Code search tidak menemukan implementation headers di source yang diperiksa. | Jika proxy juga tak memasang header, browser UI berpotensi tidak memiliki proteksi header yang direncanakan; runtime masih belum terbukti. | Pemilik API/infra putuskan satu source of truth (edge atau Laravel middleware). Terapkan dan tes di staging: `X-Content-Type-Options: nosniff`; `Referrer-Policy: strict-origin-when-cross-origin`; CSP yang cocok untuk web/Filament; `Permissions-Policy` least-privilege; HSTS baru setelah HTTPS stabil pada seluruh host yang dicakup. Retest raw response headers. |
| F-MAIL-01 | **P1 / Medium** | `config/mail.php` tidak ada pada base; `.env.example:1-30` tidak mendeklarasikan `MAIL_*`; connector hanya melaporkan mailbox admin. Tidak ditemukan sender configuration atau email delivery test. | Password reset, verification, alerts, receipts atau transactional mail (jika dibutuhkan) belum memiliki bukti pengiriman, alignment, reply path dan bounce tracking. | Pemilik aplikasi pilih sender provider, konfigurasi tersimpan per environment, verifikasi sender domain/DKIM, Return-Path dan Reply-To, rate limit/log privacy, bounce/complaint handling; jalankan test end-to-end pada staging menggunakan recipient yang disetujui. Jangan memasang kredensial ke repo. |
| F-DNS-MAIL-02 | **P1 / Medium** | Tidak tersedia output MX/SPF/DKIM/DMARC/CAA/DNSSEC pada audit; `noreply@`, `support@`, `security@`, `privacy@` tidak terlihat dalam managed mailbox list konektor, sementara `admin@` terverifikasi pada list. | Pengirim tidak tervalidasi dan alamat operasional bisa tidak punya owner/escalation path; reputasi domain dan pemulihan akun tidak dapat dinilai. | Inventarisasikan semua sumber email resmi (provider, aplikasi, ticketing, website forms, billing), semua sender/return-path, DKIM selectors dan policy. Jangan mengubah DMARC dari `p=none` atau status yang ditemukan tanpa review; setelah source inventory, uji report dahulu lalu lakukan p=quarantine/reject bertahap dengan approval. |
| F-API-01 | **P2 / Medium** | `berkah-pos-trial/lib/main.dart:93-94` mengirim email ke `/check-status` melalui GET query string; README baris 13 menyebutnya endpoint yang seharusnya ada. `routes/api.php:5-11` pada base hanya mendefinisikan platform-health. | Jika endpoint lama aktif, alamat email berpotensi masuk ke proxy/access logs, analytics atau caching; endpoint/kontrak juga belum tersambung ke Laravel baseline yang diperiksa. | Routed kepada owner API/mobile; jangan edit pada workstream ini. Jika masih diperlukan, gunakan kontrak authenticated/minimized; hindari identifier personal pada query string jika bisa, disable caching (`Cache-Control: no-store`), redaksi access logs, rate-limit dan cegah user enumeration. Buktikan endpoint live dalam test API terisolasi. |

Severity di atas dipakai sebagai tingkat blocker pra-produksi akibat bukti yang belum ada, bukan pernyataan eksploitasi atau klaim semua finding sudah tereproduksi terhadap production runtime. Tidak ada finding P0; tidak ada perbaikan runtime dilakukan di workstream ini.

## 7. Acceptance gates

| ID | Kriteria | Status | Bukti | Blocker |
|---|---|---|---|---|
| DG-01 | Domain apex dan www resolve dengan konsisten melalui authoritative + setidaknya dua public resolvers; canonical host ditetapkan | **BLOCKED** | Tidak ada output DNS; `getent` exit 2 dan curl exit 6 | Akses resolver eksternal dan authoritative zone snapshot diperlukan. |
| DG-02 | app/api/tenant hostname requirements disetujui, record tepat dan tidak menunjuk ke IP privat | **BLOCKED** | Tidak ada IP yang dapat dibuktikan; app/wildcard pernah muncul di dokumen superseded saja | Owner infra menetapkan kebutuhan hostname dan IP publik aktual dari panel VPS. |
| DG-03 | MX/SPF/DKIM/DMARC/CAA/DNSSEC posture dibuktikan; all senders inventoried | **BLOCKED** | Hanya mailbox admin tercatat pada konektor; tidak ada output DNS records | DNS zone evidence dan provider sender inventory diperlukan. |
| DG-04 | Sender app, Reply-To, Return-Path/bounce handling dan test delivery end-to-end pass | **BLOCKED / NOT RUN** | Tidak ada mail config atau test message | Provider/app owner + test inbox + environment terisolasi. |
| DG-05 | HTTP→HTTPS, cert chain/SAN/expiry/renewal dan `www` canonical redirect teruji | **BLOCKED** | Tidak ada handshake/HTTP response | Akses jaringan berfungsi dan edge staging config diperlukan. |
| DG-06 | HSTS, CSP, X-Content-Type-Options, Referrer-Policy, Permissions-Policy diverifikasi pada public response | **BLOCKED** | Source origin tidak menunjukkan header directives, runtime headers tidak dibaca | Owner edge/app menetapkan implementer dan response-header acceptance test. |
| DG-07 | Hostile/unknown Host dan API/webhook host boundaries gagal secara aman | **NOT RUN / NOT VERIFIED** | Tidak ada endpoint live atau test ingress yang dapat diakses | Dependency ke host/domain isolation dan API/security workstreams. |
| DG-08 | Runbook cutover/rollback disiapkan, DNS/mail tidak diubah | **PARTIAL — runbook proposed below** | Dokumen ini hanya menyediakan langkah perubahan/rollback; tidak ada perubahan dilakukan | Pemilik harus melengkapi zone snapshot/TTL/IP dan menyetujui change window. |

## 8. Ownership dan alamat email yang direkomendasikan

Daftar connector yang tersedia mengonfirmasi `admin@berkahtigaputeri.co.id` sebagai mailbox yang dapat dikelola. Jangan menganggap daftar itu mencakup semua alias/account pada registrar atau provider lain. Dokumentasikan owner manusia/tim, backup owner, MFA, recovery contact, audit akses, retensi, dan metode delegasi sebelum produksi.

| Identitas | Fungsi / kebijakan ownership | Bukti sekarang |
|---|---|---|
| `admin@berkahtigaputeri.co.id` | Admin manusia untuk urusan domain/mailbox/provider; akses least-privilege dan MFA; jangan gunakan sebagai `From` transaksi otomatis. | **VERIFIED** pada daftar mailbox connector, tetapi access-control/MFA tidak diuji. |
| `noreply@berkahtigaputeri.co.id` | Sender aplikasi terpisah; gunakan dedicated service identity atau alias yang disetujui dengan Send As/SMTP/API terdelegasi. Jangan beri akses console/interactive login yang tidak diperlukan. | **NOT VERIFIED**; tidak ditemukan pada daftar mailbox konektor. Tidak dibuat. |
| `support@berkahtigaputeri.co.id` | Reply-To untuk pelanggan, ditangani mailbox/ticket queue dengan owner dan SLA internal. | **NOT VERIFIED**; tidak ditemukan pada daftar konektor. Tidak dibuat. |
| `security@berkahtigaputeri.co.id` | Security incident/report intake, owner on-call dan akses terbatas; jangan kirim rahasia ke autoresponder. | **NOT VERIFIED**; tidak ditemukan pada daftar konektor. Tidak dibuat. |
| `privacy@berkahtigaputeri.co.id` | Permintaan privasi/data-subject dan eskalasi privasi; owner/backup owner dan prosedur response. | **NOT VERIFIED**; tidak ditemukan pada daftar konektor. Tidak dibuat. |
| Return-Path / bounce identity | Menerima delivery status notification, complaint/bounce events dan suppress invalid addresses. Harus sesuai provider yang dipilih dan dipantau. | **NOT VERIFIED**. |

Ini adalah rekomendasi desain, bukan otorisasi membuat mailbox/alias. Pemilik produk/domain harus menyetujui kebutuhan, alamat, biaya/provider, pemegang akses, retensi, dan prosedur eskalasi sebelum perubahan apa pun. Tidak ada mailbox atau kredensial yang dibuat/diubah.

## 9. Rencana cutover dan rollback (belum dieksekusi)

**Prasyarat mutlak:** persetujuan owner untuk change window; akses read-only ke registrar/authoritative zone; ekspor/screenshot tersanitasi dari seluruh record dan TTL saat ini yang disimpan secara privat; public IPv4/IPv6 aktual dari panel VPS; staging endpoint terisolasi; dan bukti backup/rollback target sebelumnya. Karena bukti prasyarat ini tidak tersedia, tidak ada cutover yang diizinkan oleh laporan ini.

### Pre-flight

1. Rekam timestamp dan zona asal; ekspor konfigurasi current zone ke lokasi privat terbatas. Jangan menaruh token/account identifiers atau record internal yang tidak relevan dalam laporan publik.
2. Tentukan authoritative NS, registrant/registrar/DNS host, DNSSEC status, TTL untuk A/AAAA/CNAME/MX/TXT/CAA, serta semua subdomain yang benar-benar dibutuhkan. Simpan old values persis untuk rollback.
3. Dapatkan IP publik aktual dari Hostinger control panel atau konfirmasi owner. Reject private, loopback, link-local, ULA IPv6, CGNAT dan alamat non-global; jangan memakai localhost/dev VPS sebagai public DNS target.
4. Terapkan terlebih dahulu ke staging hostname atau endpoint uji yang disetujui. Pastikan ingress/Coolify routing, app health, Host allowlist, TLS SAN/chain/expiry dan header tests pass sebelum mengubah apex.
5. Inventarisasi semua pengirim email, SPF includes, DKIM selectors, envelope-from/return-path dan DMARC reports sebelum mengirim perubahan email DNS. Jangan ubah MX/SPF/DKIM/DMARC bersamaan dengan perpindahan web.
6. Tentukan canonical policy: apex menjadi web canonical; `www` redirect satu langkah ke HTTPS apex; `api` diarahkan ke Central API hanya setelah route/auth contract dan TLS lulus; `app` dibuat hanya jika benar-benar ada web app owner dan deployment. Tidak ada wildcard tenant route dari usulan archive tanpa ADR/approval yang berlaku.

### Cutover (hanya setelah approval)

1. Jika diperlukan, kurangi TTL record web yang terdampak sebelum change window (misalnya 300 detik) sesuai kontrol registrar dan tunggu periode TTL sebelumnya. Jangan mengubah TTL mail records tanpa kebutuhan dan approval tersendiri.
2. Ubah record web satu per satu (A/AAAA/CNAME sesuai keputusan DNS provider). Jangan meng-import seluruh zone atau menghapus record yang tidak dipahami; ini mencegah gangguan MX/TXT/email.
3. Pastikan cert sudah diterbitkan lewat ACME/Let's Encrypt atau layanan terpilih, pemilik renewal/alert jelas, port 443 teruji, HTTP mengarah ke HTTPS, SAN cocok untuk hostname, dan origin tidak dapat diakses langsung bypass ingress.
4. Verifikasi dari sedikitnya dua jaringan/resolver publik: A/AAAA/NS; MX/TXT SPF; DKIM untuk semua selector; `_dmarc`; CAA; DNSSEC status. Uji HTTP redirect, TLS verify/expiry, host canonical, API health/auth/error response dan semua security headers. Redaksi email/payload/token pada log.
5. Monitor error rate, 4xx/5xx, certificate/ACME events, mail bounce/complaint, support tickets dan DNS propagation sepanjang change window. Pertahankan old route/instance selama rollback window.

### Rollback

1. Jika domain tidak resolve, cert mismatch/expired, API wrong-host, 5xx/error rate meningkat, atau mail delivery regression terjadi, hentikan cutover selanjutnya.
2. Kembalikan hanya record web yang diubah ke nilai A/AAAA/CNAME dari private pre-change snapshot; jangan melakukan perubahan massal pada zone. Jangan mengutak-atik MX/SPF/DKIM/DMARC sebagai bagian rollback web.
3. Pertahankan old service hidup hingga resolver cache dan record TTL mereda; validasi kembali DNS dari dua resolver/jaringan, HTTP redirect, certificate, health/auth, canonical `www`, security headers dan email smoke test bila email ikut terpengaruh.
4. Pulihkan TTL lama setelah stabil dan owner menyetujui. Catat exact timestamp, records yang diubah, before/after dig output tersanitasi, pemeriksaan, keputusan rollback, dan reviewer.
5. Jika origin/certificate/header gate tidak dapat dibuktikan, jangan lanjutkan release. Rollback plan tidak menggantikan approval atau backup configuration.

**Status pelaksanaan:** **NOT RUN** — rencana ini belum mengubah DNS atau provider. Tidak ada nilai DNS pre-change yang tersedia sehingga rollback record aktual belum dapat dijalankan sampai owner mengamankan snapshot tersebut.

## 10. Retest commands dan deliverability acceptance (untuk jaringan/staging yang diizinkan)

Jalankan dari workstation atau runner terotorisasi yang benar-benar bisa mengakses DNS publik; simpan output tersanitasi dengan waktu, sumber resolver, exit code dan revision/deployment identifier.

```bash
date -u '+%Y-%m-%dT%H:%M:%SZ'
dig @1.1.1.1 +noall +answer berkahtigaputeri.co.id A
dig @8.8.8.8 +noall +answer berkahtigaputeri.co.id AAAA
dig +noall +answer berkahtigaputeri.co.id NS
dig +noall +answer berkahtigaputeri.co.id MX
dig +noall +answer berkahtigaputeri.co.id TXT
dig +noall +answer _dmarc.berkahtigaputeri.co.id TXT
dig +noall +answer berkahtigaputeri.co.id CAA
# Query DKIM only after getting selector(s) from the provider; redact public key if policy requires.
dig +noall +answer <selector>._domainkey.berkahtigaputeri.co.id TXT
curl -sS -I -L --connect-timeout 4 --max-time 20 http://berkahtigaputeri.co.id/
curl -sS -I -L --connect-timeout 4 --max-time 20 https://berkahtigaputeri.co.id/
curl -sS -I -L --connect-timeout 4 --max-time 20 https://www.berkahtigaputeri.co.id/
curl -sS -D- --connect-timeout 4 --max-time 20 https://api.berkahtigaputeri.co.id/up
openssl s_client -connect berkahtigaputeri.co.id:443 -servername berkahtigaputeri.co.id -showcerts -verify_return_error </dev/null
```

Do not place the literal `<selector>` in a shell command without replacing it with a selector issued by the provider. DKIM public key and DNS records are not credentials in the same sense as a private key, but the audit report should only preserve the minimum needed evidence.

Email deliverability acceptance requires a **separate explicit test authorization**: send one uniquely tagged message from the application staging environment to a controlled inbox; inspect full headers for SPF, DKIM and DMARC pass/alignment; verify From, Reply-To and envelope-from; monitor bounce/complaint handling and duplicates; confirm secrets are not logged. Mark NOT RUN until that is actually executed. Do not use admin mailbox as app sender merely because it exists.

**DMARC control:** current policy is unknown. Do not write `p=quarantine` or `p=reject` until all authorized senders—including web forms, transactional mail, support/ticketing and third-party systems—are inventoried, SPF/DKIM pass/alignment is measured, aggregate reports are reviewed, and the owner explicitly approves staged enforcement.

## 11. Cross-workstream dependencies and next actions

1. **Infra/SRE owner:** provide a sanitized authoritative-zone snapshot, actual public VPS IP, edge/Coolify routing evidence, certificate renewal ownership and staging hostname; execute HTTP→HTTPS/TLS/header tests without touching production first.
2. **Domain/mail owner:** confirm authoritative registrar/DNS provider, MX/mail provider, all SPF/DKIM send sources/selectors, current DMARC policy, and whether the only verified mailbox `admin@` should remain strictly administrative.
3. **App/API owner:** resolve whether the legacy trial `/check-status?email=...` is still required or will be removed; implement and test the approved Laravel route/contract. This report does not modify trial/mobile/API files.
4. **Security/edge owner:** implement headers in one reviewed layer (edge or application) and prove them from response headers on the exact candidate staging deployment; add a regression test so proxies/config changes cannot remove them.
5. **Release/governance owner:** keep release gate BLOCKED until all applicable rows in Section 7 have direct current evidence, plus independent owner approval. A domain/DNS plan or passing source inspection is not cutover acceptance.

### Final recommendation

**BLOCKED / NO CUTOVER.** Evidence proves the repository’s current origin scaffold has no in-container TLS listener/security-header directives and that the connected Hostinger Mail account lists `admin@berkahtigaputeri.co.id`. It does **not** prove production DNS, TLS, mail authentication or edge headers. Required public resolver outputs, deployed edge configuration, certificate details, DNS email records, application sender and deliverability tests remain BLOCKED/NOT RUN. No DNS/mailbox/production change was performed.

## Appendix A — Evidence boundary and unrelated canonical gates

- Architecture authority is the 2026-10-17 owner ADR: KVM2/Coolify, Laravel and private PostgreSQL 17; no Supabase usage or access, including read-only. No Supabase service or script was called.
- The DOC_00 five-layer contract remains `GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE` with 352 canonical workbook entries. Domain/email work neither changed nor validated the workbook, so detailed workbook execution is **NOT APPLICABLE** to this workstream; the overall release still inherits the global configuration gate.
- No GitHub Actions workflow was manually dispatched or rerun. CI execution for this documentation-only change is **NOT RUN**; a read-only metadata query found no workflow run or combined status for the inspected report commit. Do not run the legacy `scripts/sync_excel_to_supabase.py` workflow path even with a dry-run flag; a repository note indicates an existing docs-triggered workflow may call it.
- No DNS record, MX/TXT value, IP address, certificate, mail credential, message, mailbox, public endpoint, database or production resource was modified.


## 12. Read-only retest — 2026-10-20

Retest performed at **2026-10-20 04:10:38–04:12:13 WIB** (2026-10-19T21:10:38Z–2026-10-19T21:12:13Z) on the audit execution environment. The branch and PR metadata were checked before this report update. All probing was read-only; no DNS, mailbox, certificate, application, database, or production state was changed.

### 12.1 Execution environment and control probes

| Command / target | Exit code | Sanitized result | Interpretation |
|---|---:|---|---|
| date -u '+%Y-%m-%dT%H:%M:%SZ' | 0 | 2026-10-19T21:10:38Z | UTC timestamp for DNS/HTTP batch |
| TZ=Asia/Jakarta date '+%Y-%m-%dT%H:%M:%S%:z' | 0 | 2026-10-20T04:10:38+07:00 | Jakarta local timestamp |
| command -v dig | unavailable | dig not installed | No direct DNS CLI |
| command -v nslookup | unavailable | nslookup not installed | No direct DNS CLI |
| command -v host | unavailable | host not installed | No direct DNS CLI |
| getent ahosts example.com | 2 | no address output | General resolver control failed |
| getent ahosts api.github.com | 2 | no address output | General resolver control failed |
| getent ahosts dns.google | 2 | no address output | General resolver control failed |

Failure of unrelated control hostnames supports an **environment/network blocker**, rather than a justified conclusion that the requested domain records are absent or misconfigured.

### 12.2 Current host lookups and HTTP/TLS attempts

Each command below returned exit code 2 with no address output:
- getent ahosts berkahtigaputeri.co.id
- getent ahosts www.berkahtigaputeri.co.id
- getent ahosts app.berkahtigaputeri.co.id
- getent ahosts api.berkahtigaputeri.co.id

The following curl command was run separately for each listed URL and returned exit code **6** (Could not resolve host), HTTP status 000 and zero redirects:

    curl -sS -I -L --connect-timeout 4 --max-time 8 -o /dev/null -w 'http_code=%{http_code} final_url=%{url_effective} redirects=%{num_redirects} tls_verify=%{ssl_verify_result}\n' URL

Targets:
- http://berkahtigaputeri.co.id/
- https://berkahtigaputeri.co.id/
- https://www.berkahtigaputeri.co.id/
- https://app.berkahtigaputeri.co.id/
- https://api.berkahtigaputeri.co.id/check-status

The printed tls_verify=0 field in failed curl output is **not** evidence of successful TLS validation: no hostname resolution or TLS handshake completed.

For each of berkahtigaputeri.co.id, www.berkahtigaputeri.co.id, and api.berkahtigaputeri.co.id, this TLS probe returned exit code **1** with a name-resolution error and no certificate/handshake information:

    timeout 8 openssl s_client -connect HOST:443 -servername HOST -brief -verify_return_error </dev/null

A second read-only path attempted to bypass the system resolver by pinning DoH hostnames to public resolver IPs. Both attempts returned exit code **7**, HTTP 000, and Could not connect to server:

    curl -sS --connect-timeout 3 --max-time 8 --resolve 'dns.google:443:8.8.8.8' -H 'accept: application/dns-json' 'https://dns.google/resolve?name=example.com&type=A'

    curl -sS --connect-timeout 3 --max-time 8 --resolve 'cloudflare-dns.com:443:1.1.1.1' -H 'accept: application/dns-json' 'https://cloudflare-dns.com/dns-query?name=example.com&type=A'

Consequently, this environment did not successfully reach public recursive DNS-over-HTTPS either. No current A/AAAA/CNAME/NS/MX/TXT/CAA/DNSSEC answer was obtained. Raw network error logs were not retained as separate artifacts; the sanitized command results above are the audit artifact.

### 12.3 Mailbox-list recheck

A read-only current managed-mailbox list lookup was executed for both connected account scopes at approximately 04:10 WIB. Both requests succeeded. Both returned a managed-mailbox list containing admin@berkahtigaputeri.co.id; the report deliberately omits account/resource IDs.

This verifies only that admin@... is shown in those connector-managed mailbox lists at this time. It does **not** verify that the mailbox is usable, that an alias is absent from another provider, that MX records point correctly, or that an address has Send As/SMTP/API permissions. It does not verify MFA, access ownership, inbox placement, SMTP delivery, SPF/DKIM/DMARC alignment, bounces, or complaints. No email was sent and no message was read, moved, or changed.

Current mailbox roles remain:

| Address / identity | Current status | Required control |
|---|---|---|
| admin@berkahtigaputeri.co.id | **VERIFIED** in the current managed-mailbox list only | Human administration; MFA and named primary/backup owner still require independent verification |
| noreply@berkahtigaputeri.co.id | **NOT VERIFIED** | Do not use admin@ as an application sender by default; provision a dedicated sender/alias only after owner approval and provider capability review |
| support@berkahtigaputeri.co.id | **NOT VERIFIED** | Decide whether needed; designate support owner, backup, response SLA and access control |
| security@berkahtigaputeri.co.id | **NOT VERIFIED** | Decide whether needed; designate security incident owner and restricted access |
| privacy@berkahtigaputeri.co.id | **NOT VERIFIED** | Decide whether needed; designate privacy request owner and retention/response procedure |
| Sender envelope / Return-Path and bounce channel | **NOT VERIFIED** | Select provider-supported return path; test bounce/complaint processing before production mail |

These are role recommendations, not authorization to create an address, alias, SMTP/API credential, or mailbox. No mailbox or credential was created or modified.

### 12.4 Source-search refresh and exact code evidence

On the repository default-branch snapshot, repository search returned no matches for Content-Security-Policy, Strict-Transport-Security, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, MAIL_FROM_ADDRESS, MAIL_MAILER, or SPF DKIM DMARC. These search results are source-search evidence only; edge configuration outside Git can still add headers or mail settings.

The following source facts were rechecked at base SHA 371b7fdf0bf672b37ceb1023e647f114221bf797:

| Path and line | VERIFIED source fact | Boundary |
|---|---|---|
| docker/nginx.conf:1-3,16-18,27-29 | Container Nginx declares listen 80 default_server, server_name _, normal try_files, and dotfile denial; no listen 443, explicit HTTP-to-HTTPS redirect, or security-header directives in this 31-line file | Does not prove how Coolify/edge terminates TLS or injects headers |
| Dockerfile:47-50 | Production image copies this Nginx config, exposes port 80, and health-checks http://127.0.0.1/up | Does not establish public origin reachability or current ingress policy |
| bootstrap/app.php:14-15 | Laravel custom middleware registration closure is empty | Does not rule out global/provider middleware or ingress-added headers |
| .env.example:1-31; config/mail.php | Example uses APP_URL=http://localhost:8000, has no MAIL_* settings, and config/mail.php is not present at this base SHA (file fetch returned NOT_FOUND) | Local example/source tree only; does not reveal protected production environment variables or external SMTP settings |
| routes/api.php:5-11 | Visible Laravel API route is /v1/platform-health | Does not prove any separate legacy API is absent outside this deployment; /check-status is not present in this file |
| berkah-pos-trial/lib/main.dart:10-12,91-102 | Trial app references https://api.berkahtigaputeri.co.id/check-status; checkStatus sends supplied email as a GET query parameter at lines 93-94 | Static app source only; endpoint availability/authentication/log treatment not verified |
| berkah-pos-trial/README.md:13 | Documents the desired GET status endpoint and response contract | **CLAIMED/DESIRED**, not endpoint runtime evidence |
| berkah-pos-trial/tool/verify_project.py:52-69 | Local validator checks URL strings and feature markers | Does not test DNS, TLS, HTTP redirects, edge headers, or email delivery |
| pos-app/pubspec.yaml:9-17 | Still declares supabase_flutter at line 16 | Separate platform/runtime conflict; not modified by this DNS/email workstream and no Supabase service was contacted |

### 12.5 Refreshed acceptance and risk decision

| Gate | Current result after retest | Evidence still required |
|---|---|---|
| Apex/www/app/api DNS and public-vs-private target | **BLOCKED / NOT VERIFIED** | Query authoritative NS and at least two independent public resolvers from a working network; verify actual Hostinger public VPS IP and ensure A/AAAA do not resolve to private, loopback, link-local, ULA or CGNAT space |
| MX/SPF/DKIM/DMARC/CAA/DNSSEC | **BLOCKED / NOT VERIFIED** | Authoritative record output plus provider's complete sender/selector inventory; preserve sanitized records and timestamp |
| Sender noreply, Reply-To, envelope-from / Return-Path, bounce | **BLOCKED / NOT VERIFIED** | Approved sender provider/config, least-privilege identity, test inbox and actual message headers |
| SPF/DKIM/DMARC alignment and deliverability | **NOT RUN** | Send a uniquely tagged message only from an approved isolated staging sender to a controlled inbox; verify SPF and DKIM pass, DMARC alignment, Reply-To, bounce/complaint handling, and sanitized logs |
| HTTP-to-HTTPS, canonical www, TLS chain/SAN/expiry/renewal | **BLOCKED / NOT VERIFIED** | Reachable DNS, staging ingress evidence, successful curl redirect checks and openssl verify output, certificate renewal/alert owner |
| HSTS/CSP/X-Content-Type-Options/Referrer-Policy/Permissions-Policy | Origin-source gap **VERIFIED**; effective edge response **BLOCKED** | Infra/API owners decide one enforcement layer; validate actual response headers on the exact staging candidate |
| Hostname allowlist and webhook boundaries | **NOT RUN / NOT VERIFIED** | Coordinate with host/domain isolation and API/security workstreams; exercise hostile Host, central-vs-tenant routing and webhook endpoints in isolated staging |
| Cutover and rollback | **PARTIAL — procedure proposed; execution NOT RUN** | Approved window, current sanitized DNS-zone snapshot, actual public IP, old TTL/record values, staging gates and named approver |

**Updated disposition: BLOCKED / NO CUTOVER.** The present network failures are explicitly **not** a FAILED DNS verdict. DNS state, private/public target correctness, TLS validity and effective security headers all remain unknown. The only new direct operational observation is the managed mailbox list showing admin@...; it is insufficient for an application sender or deliverability claim. The code-origin absence of header directives is verified, but a reverse proxy may implement them; do not modify either layer until infrastructure/API owners choose the authoritative enforcement point.

No workbook/validator, database, application test suite, CI job, staging endpoint, production resource, DNS record, certificate, mailbox or email-delivery test was changed or executed in this refresh. The canonical GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE / 352-entry workbook gate is inherited and **NOT APPLICABLE to this workstream's edits**, but remains a separate required release gate; this report does not claim it was tested.


### 12.6. Exact-head CI metadata check

After the report refresh commit **ffe7b7b85febb96f758c08212c936da5dc0860dd** was created, the following read-only GitHub metadata operations were queried for that exact commit SHA:

| Operation | Result | Conclusion |
|---|---|---|
| Fetch commit workflow runs filtered to pull-request events | Empty list; no run ID, attempt, conclusion, or URL returned | **NOT RUN / NO CI EVIDENCE** for that SHA |
| Fetch combined commit status | Empty list; no status context/state/target URL returned | **NOT RUN / NO CHECK STATUS** for that SHA |

These metadata lookups do not dispatch or execute CI. No workflow was manually dispatched or rerun. The new report-only commit is not treated as tested just because the pre-existing pull request has a green or historic result; CI evidence must be tied to the exact final candidate SHA.
