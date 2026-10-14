# Kebijakan Privasi — Berkah Tiga Puteri POS

**Status: Draf migrasi. Kebijakan final harus diverifikasi dengan AAB yang akan dirilis, backend yang telah dideploy, kanal kontak resmi, dan persyaratan hukum yang berlaku.**

## Arsitektur dan pemrosesan data

Berkah POS ditujukan sebagai aplikasi POS dan akuntansi local-first. Data transaksi lokal disimpan pada SQLite perangkat. Backend cloud target adalah Laravel Central API dengan autentikasi Laravel/Sanctum dan MariaDB yang memisahkan database setiap tenant. Implementasi fitur atau rancangan arsitektur tidak dengan sendirinya membuktikan bahwa layanan cloud telah aktif.

Tergantung fitur yang benar-benar diaktifkan pada build dan backend, data yang dapat diproses meliputi:
- email/identitas akun dan token sesi yang diperlukan untuk masuk;
- identitas tenant/perangkat untuk pemeriksaan hak akses;
- konfigurasi efektif dan status layanan;
- data produk, stok, transaksi, detail penjualan dan jurnal akuntansi yang dibuat tenant;
- status outbox/sinkronisasi ketika API sync benar-benar diaktifkan;
- informasi teknis minimum untuk keamanan dan pemecahan masalah.

## Pengamanan

API cloud target memakai HTTPS/TLS dan memeriksa identitas akun, membership tenant, perangkat terdaftar serta status langganan di sisi server. Setiap tenant mempunyai database terpisah di server MariaDB yang sama. ID tenant atau perangkat yang tersimpan di ponsel bukan bukti izin akses. Kesiapan kontrol ini harus dibuktikan melalui pengujian sebelum dinyatakan tersertifikasi untuk produksi.

Aplikasi tidak boleh menyertakan kata sandi database, application key Laravel, kredensial Redis, payment secret atau kredensial administrator di APK.

## Penggunaan dan pembagian data

Tujuan penggunaan data adalah menjalankan fungsi POS/akuntansi yang diminta tenant, menjaga konsistensi transaksi, mengamankan akun, dan menyediakan dukungan operasional. Kebijakan produk adalah tidak menjual data dan tidak menggunakannya untuk iklan pihak ketiga. Pemroses layanan yang diperlukan untuk operasi harus diungkapkan sesuai konfigurasi produksi yang sesungguhnya.

## Penyimpanan, retensi, koreksi dan penghapusan

Data lokal tersimpan di perangkat sampai dihapus sesuai fungsi aplikasi atau data perangkat dikelola pemiliknya. Retensi data cloud, pencadangan, koreksi serta permintaan penghapusan wajib ditentukan dan diterapkan oleh pengelola backend sebelum rilis SaaS. Data akuntansi/transaksi yang wajib disimpan tidak boleh dihapus secara otomatis tanpa dasar hukum dan prosedur resmi.

Sebelum menerbitkan kebijakan final, pengelola harus mengisi kanal kontak resmi yang aktif untuk permintaan privasi, koreksi dan penghapusan data. Jangan menerbitkan draf ini sebagai komitmen operasional final sebelum langkah tersebut diverifikasi.

## Perubahan kebijakan

Perbarui kebijakan sebelum mengaktifkan alur cloud baru atau mengubah cara data transaksi, billing, payment, analitik, crash reporting maupun SDK pihak ketiga diproses.
