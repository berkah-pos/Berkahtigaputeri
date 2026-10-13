#!/usr/bin/env bash
set -euo pipefail

# Generate only Gradle wrapper support files from a temporary Flutter scaffold.
# Existing applicationId, SDK levels, manifest, and app Gradle config are untouched.
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required to prepare the Gradle wrapper." >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

flutter create --platforms=android --project-name berkah_wrapper_seed --org id.co.berkahtigaputeri --overwrite "$tmp/seed" >/dev/null
mkdir -p "$root/android/gradle/wrapper"
cp "$tmp/seed/android/gradlew" "$root/android/gradlew"
cp "$tmp/seed/android/gradlew.bat" "$root/android/gradlew.bat"
cp "$tmp/seed/android/gradle/wrapper/gradle-wrapper.jar" "$root/android/gradle/wrapper/gradle-wrapper.jar"
cp "$tmp/seed/android/gradle/wrapper/gradle-wrapper.properties" "$root/android/gradle/wrapper/gradle-wrapper.properties"
chmod +x "$root/android/gradlew"

echo "Gradle wrapper files and version properties prepared from the current Flutter scaffold."
