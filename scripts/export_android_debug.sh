#!/usr/bin/env bash
# Rebuild Injection Tycoon MVP Android debug APK (Godot 4.7.2).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/workspace/tools/bin/godot}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export ANDROID_HOME="${ANDROID_HOME:-/workspace/tools/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/35.0.1:$PATH"

OUT="$ROOT/build/InjectionTycoonMVP-debug.apk"
mkdir -p "$ROOT/build"

if [[ ! -x "$GODOT" ]]; then
  echo "Godot binary not found: $GODOT" >&2
  exit 1
fi
if [[ ! -d "$ANDROID_HOME/platforms/android-35" ]]; then
  echo "Android SDK platform 35 missing under $ANDROID_HOME" >&2
  exit 1
fi
if [[ ! -f "$HOME/.local/share/godot/export_templates/4.7.2.stable/android_debug.apk" ]]; then
  echo "Godot 4.7.2 Android export templates missing." >&2
  echo "Install Godot_v4.7.2-stable_export_templates.tpz into ~/.local/share/godot/export_templates/4.7.2.stable/" >&2
  exit 1
fi
if [[ ! -f "$ROOT/android/debug.keystore" ]]; then
  echo "Generating debug keystore..."
  keytool -genkeypair -keystore "$ROOT/android/debug.keystore" \
    -storepass android -alias androiddebugkey -keypass android \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US"
fi

echo "Exporting debug APK -> $OUT"
"$GODOT" --headless --path "$ROOT" --export-debug "Android" "$OUT"
ls -lh "$OUT"
