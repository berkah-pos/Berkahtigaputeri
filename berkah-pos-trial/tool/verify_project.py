#!/usr/bin/env python3
"""Static checks for the requested Android package and permission allowlist."""
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
manifest_path = ROOT / "android/app/src/main/AndroidManifest.xml"
gradle_path = ROOT / "android/app/build.gradle"
pubspec_path = ROOT / "pubspec.yaml"
main_path = ROOT / "lib/main.dart"

ns = {"android": "http://schemas.android.com/apk/res/android"}
errors = []
manifest = ET.parse(manifest_path).getroot()
found = {
    node.attrib[f"{{{ns['android']}}}name"]
    for node in manifest.findall("uses-permission")
}
expected = {
    "android.permission.CAMERA",
    "android.permission.BLUETOOTH",
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.BLUETOOTH_SCAN",
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
}
if found != expected:
    errors.append(f"Permission allowlist mismatch: {sorted(found)}")

gradle = gradle_path.read_text(encoding="utf-8")
pubspec = pubspec_path.read_text(encoding="utf-8")
main = main_path.read_text(encoding="utf-8")

wrapper_path = ROOT / "android/gradle/wrapper/gradle-wrapper.properties"
wrapper = wrapper_path.read_text(encoding="utf-8")

settings_path = ROOT / "android/settings.gradle"
settings = settings_path.read_text(encoding="utf-8")
agp_match = re.search(r'id\s+"com\.android\.application"\s+version\s+"(\d+)\.(\d+)\.(\d+)"', settings)
kotlin_match = re.search(r'id\s+"org\.jetbrains\.kotlin\.android"\s+version\s+"(\d+)\.(\d+)\.(\d+)"', settings)
if not kotlin_match:
    errors.append("Unable to determine Kotlin Gradle Plugin version")
else:
    kotlin_version = tuple(int(part) for part in kotlin_match.groups())
    if kotlin_version < (2, 2, 21):
        errors.append(
            f"Kotlin Gradle Plugin {'.'.join(map(str, kotlin_version))} is below "
            "the version selected for compatibility with AGP 8.11.1 and Gradle 8.14"
        )
if not agp_match:
    errors.append("Unable to determine Android Gradle Plugin version")
else:
    agp_version = tuple(int(part) for part in agp_match.groups())
    if agp_version < (8, 11, 1):
        errors.append(
            f"Android Gradle Plugin {'.'.join(map(str, agp_version))} is below "
            "Flutter stable's supported minimum of 8.11.1"
        )
wrapper_version = re.search(r"distributionUrl=.*gradle-(\d+)\.(\d+)(?:\.(\d+))?-", wrapper)
if not wrapper_version:
    errors.append("Unable to determine Gradle wrapper version")
else:
    gradle_version = tuple(int(part or 0) for part in wrapper_version.groups())
    if gradle_version < (8, 14, 0):
        errors.append(
            f"Gradle wrapper {'.'.join(map(str, gradle_version))} is below "
            "Flutter stable's supported minimum of 8.14.0"
        )
required_settings = {
    "applicationId": r'applicationId\s*=\s*"id\.co\.berkahtigaputeri\.berkahpos"',
    "namespace": r'namespace\s*=\s*"id\.co\.berkahtigaputeri\.berkahpos"',
    "compileSdk": r'compileSdk\s*=\s*35',
    "targetSdk": r'targetSdk\s*=\s*35',
    "minSdk": r'minSdk\s*=\s*24',
    "versionCode": r'versionCode\s*=\s*1',
    "versionName": r'versionName\s*=\s*"1\.0\.0"',
}
for key, pattern in required_settings.items():
    if not re.search(pattern, gradle):
        errors.append(f"Missing or wrong Android setting: {key}")

for dependency in ("sqflite:", "http:", "url_launcher:"):
    if dependency not in pubspec:
        errors.append(f"Missing dependency: {dependency}")

for marker in (
    "https://api.berkahtigaputeri.co.id/check-status",
    "https://berkahtigaputeri.co.id/delete-account",
    "https://berkahtigaputeri.co.id/privacy",
    "Akun Belum Aktif, hubungi tim Berkah POS untuk aktivasi",
    "LaunchMode.externalApplication",
    "CREATE TABLE products",
    "CREATE TABLE sales",
    "CREATE TABLE sale_items",
):
    if marker not in main:
        errors.append(f"Missing feature marker: {marker}")

forbidden = re.compile(r"com\.android\.billingclient|midtrans|xendit|WebView|BILLING|SEND_SMS|READ_CONTACTS|ACCESS_FINE_LOCATION", re.I)
for rel in ("pubspec.yaml", "lib/main.dart", "android/app/build.gradle", "android/app/src/main/AndroidManifest.xml"):
    text = (ROOT / rel).read_text(encoding="utf-8")
    if forbidden.search(text):
        errors.append(f"Forbidden payment SDK, WebView, or permission marker in {rel}")

for required_file in (
    "android/app/src/main/res/values/styles.xml",
    "android/app/src/main/res/values/colors.xml",
    "android/app/src/main/res/drawable/launch_background.xml",
    "android/app/src/main/res/drawable/ic_launcher.xml",
    "android/app/src/main/kotlin/id/co/berkahtigaputeri/berkahpos/MainActivity.kt",
    "android/key.properties.template",
):
    if not (ROOT / required_file).is_file():
        errors.append(f"Missing required scaffold file: {required_file}")

if errors:
    print("FAIL")
    print("\n".join(f"- {e}" for e in errors))
    sys.exit(1)
print("PASS: requested Android settings, source manifest allowlist, forbidden dependency markers, and scaffold files.")
