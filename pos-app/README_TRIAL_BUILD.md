# Berkah POS — Trial Offline Android

Package: `id.co.berkahtigaputeri.berkahpos`  
Version: `1.0.0+1`  
Android: `minSdk 24`, `compileSdk 35`, `targetSdk 35`

## Fitur

- Login berbasis email untuk memeriksa `GET https://api.berkahtigaputeri.co.id/check-status?email=...`.
- Produk CRUD, keranjang kasir, dan transaksi disimpan di SQLite lokal.
- Laporan penjualan lokal.
- Tombol Sales WhatsApp, Hapus Akun, dan Privacy membuka aplikasi/browser eksternal; tidak ada WebView.
- Tidak ada pembayaran, BillingClient, Midtrans, atau Xendit.
- Akun inactive menampilkan pesan aktivasi dan WhatsApp. Mode trial lokal tetap tersedia tanpa pembayaran.

## Siapkan signing

Jalankan dari folder `pos-app`:

```bash
keytool -genkeypair -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias berkahpos
cp android/key.properties.template android/key.properties
```

Edit `android/key.properties` menggunakan password yang dipilih saat membuat keystore. Jangan commit file password atau keystore; simpan backup keystore dan password dengan aman.

## Build AAB

Dengan Flutter SDK terpasang dan Android SDK Platform 35 tersedia:

```bash
flutter pub get
flutter build appbundle --release
```

Flutter akan membuat `build/app/outputs/bundle/release/app-release.aab`. Siapkan signing terlebih dahulu sebelum mengunggah ke Play Console.

## URL Sales WhatsApp

Set nomor/URL WhatsApp resmi perusahaan saat build:

```bash
flutter build appbundle --release --dart-define=SALES_WHATSAPP_URL=https://wa.me/62XXXXXXXXXX
```

Ganti placeholder tersebut dengan URL resmi. Default membuka alur WhatsApp berbagi pesan tanpa penerima yang belum dikonfirmasi.

## Format API

Parser menerima `{"active": true}` atau `{"status": "active"}`; status `inactive`, `expired`, `pending`, atau `suspended` diperlakukan sebagai belum aktif. Jika API tidak terjangkau, layar aktivasi menawarkan trial lokal dan WhatsApp.

## Checklist pra-rilis

Uji CRUD produk, validasi stok, transaksi, laporan, API status, deep links eksternal, halaman privasi/hapus akun, serta perilaku di Android API 24 dan 35. Pastikan listing Play Console, formulir Data safety, kebijakan privasi, deklarasi fitur, dan akun reviewer sesuai perilaku nyata. Persetujuan Google Play tidak dapat dijamin 100%.
