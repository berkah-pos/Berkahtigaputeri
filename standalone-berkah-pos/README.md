# Berkah POS — PT Berkah Tiga Puteri

Repositori Flutter mandiri untuk Berkah POS. Source ini diimpor dari paket proyek yang disediakan dan ditempatkan terpisah dari aplikasi POS multi-tenant yang sudah ada.

## Konfigurasi Android

Package: `id.co.berkahtigaputeri.berkahpos`  
minSdk: 24  
versionCode: 1  
versionName: 1.0.0

Konfigurasi Android default menggunakan compileSdk/targetSdk 36 untuk mengikuti persyaratan target API Google Play yang berlaku pada tanggal pengajuan. Untuk pengujian kompatibilitas API 35, build dapat dioverride, tetapi verifikasi persyaratan Play Console sebelum rilis.

## Build & test

Prasyarat: Flutter stable, Android SDK, JDK 17.

```bash
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

AAB berada di `build/app/outputs/bundle/release/app-release.aab`. Build rilis memerlukan signing key milik organisasi. Salin `android/key.properties.template` ke `android/key.properties` dan isi konfigurasi signing; jangan commit keystore atau password.

## Sebelum rilis

Tidak ada jaminan bahwa aplikasi akan lolos review Google Play. Pastikan endpoint API dan URL kebijakan privasi/hapus akun benar-benar aktif dan dimiliki organisasi; periksa Data safety, listing, serta semua alur pada perangkat nyata. Status trial lokal hanya fallback demonstrasi, bukan entitlement backend yang aman.
