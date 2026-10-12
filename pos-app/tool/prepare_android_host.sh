#!/usr/bin/env bash
set -euo pipefail

# Fill missing Android host files for the new app identity without overwriting
# the canonical Gradle app file or signing configuration. CI uses a disposable checkout.
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required to prepare the Android host." >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
android_dir="$root/android"
had_app_build_gradle_kts=0
[[ -f "$android_dir/app/build.gradle.kts" ]] && had_app_build_gradle_kts=1
temp_dir="$(mktemp -d)"
had_gradle_properties=0
[[ -f "$android_dir/gradle.properties" ]] && had_gradle_properties=1
trap 'rm -rf "$temp_dir"' EXIT

if [[ ! -f "$android_dir/app/build.gradle" ]]; then
  echo "Canonical pos-app/android/app/build.gradle is missing; refusing to invent app identity." >&2
  exit 1
fi
if [[ "$had_app_build_gradle_kts" -eq 1 ]]; then
  echo "Both app/build.gradle and app/build.gradle.kts exist. Resolve this native-build conflict manually; refusing to choose one automatically." >&2
  exit 1
fi

flutter create \
  --platforms=android \
  --project-name pos \
  --org com.berkahtigaputeri \
  --overwrite \
  "$temp_dir/seed"

mkdir -p "$android_dir"
# Copy only missing host files. Existing files (including the canonical app
# Gradle config, manifest overrides, and signing setup) are not overwritten.
cp -a -n "$temp_dir/seed/android/." "$android_dir/"

# Flutter 3.29+ creates Kotlin-DSL app scripts by default. This project
# intentionally keeps a reviewed Groovy app/build.gradle (signing guard and
# package identity). Do not let a generated app/build.gradle.kts shadow it.
if [[ -f "$android_dir/app/build.gradle.kts" ]]; then
  rm -f "$android_dir/app/build.gradle.kts"
fi

chmod +x "$android_dir/gradlew"

if [[ "$had_gradle_properties" -eq 0 ]]; then
  cat > "$android_dir/gradle.properties" <<'EOF'
org.gradle.jvmargs=-Xmx2G -XX:MaxMetaspaceSize=1G -XX:+HeapDumpOnOutOfMemoryError
android.useAndroidX=true
android.enableJetifier=true
org.gradle.workers.max=2
org.gradle.parallel=false
# Keep the reviewed Groovy/KGP app build compatible with newer Flutter/AGP templates.
android.builtInKotlin=false
android.newDsl=false
EOF
fi

grep -q 'applicationId = "com.berkahtigaputeri.pos"' "$android_dir/app/build.gradle"
grep -q 'namespace = "com.berkahtigaputeri.pos"' "$android_dir/app/build.gradle"
test -s "$android_dir/app/src/main/kotlin/com/berkahtigaputeri/pos/MainActivity.kt"
test -s "$android_dir/gradlew"
test -s "$android_dir/gradle/wrapper/gradle-wrapper.jar"

echo "Android host is present for com.berkahtigaputeri.pos. Existing app Gradle config and app identity were preserved."
