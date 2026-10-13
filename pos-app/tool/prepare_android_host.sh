#!/usr/bin/env bash
set -euo pipefail

# Generate missing Android host files without overwriting existing project
# files, app identity, signing configuration, or user-owned native changes.
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required to prepare the Android host." >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
android_dir="$root/android"
temp_dir="$(mktemp -d)"
had_gradle_properties=0
[[ -f "$android_dir/gradle.properties" ]] && had_gradle_properties=1
trap 'rm -rf "$temp_dir"' EXIT

if [[ ! -f "$android_dir/app/build.gradle" ]]; then
  echo "Canonical pos-app/android/app/build.gradle is missing; refusing to invent app identity." >&2
  exit 1
fi

flutter create \
  --platforms=android \
  --project-name berkahpos \
  --org id.co.berkahtigaputeri \
  --overwrite \
  "$temp_dir/seed"

mkdir -p "$android_dir"
# Copy only missing host files. Existing files (including the canonical app
# Gradle config, manifest overrides, and signing setup) are not overwritten.
cp -a -n "$temp_dir/seed/android/." "$android_dir/"
chmod +x "$android_dir/gradlew"

if [[ "$had_gradle_properties" -eq 0 ]]; then
  cat > "$android_dir/gradle.properties" <<'EOF'
# Jetifier transforms Flutter engine artifacts; 2G exhausted the hosted runner heap.
org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=1G -XX:+HeapDumpOnOutOfMemoryError
android.useAndroidX=true
android.enableJetifier=true
org.gradle.workers.max=2
org.gradle.parallel=false
EOF
fi

grep -q 'applicationId = "id.co.berkahtigaputeri.berkahpos"' "$android_dir/app/build.gradle"
grep -q 'namespace = "id.co.berkahtigaputeri.berkahpos"' "$android_dir/app/build.gradle"
test -s "$android_dir/app/src/main/kotlin/id/co/berkahtigaputeri/berkahpos/MainActivity.kt"
test -s "$android_dir/gradlew"
test -s "$android_dir/gradle/wrapper/gradle-wrapper.jar"

echo "Android host is present for id.co.berkahtigaputeri.berkahpos. Existing app Gradle config and app identity were preserved."
