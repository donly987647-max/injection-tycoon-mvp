#!/usr/bin/env bash
# Rebuild Injection Tycoon MVP HTML5/Web export (Godot 4.7.2).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/workspace/tools/bin/godot}"
# Prefer resolved binary if symlink path fails in some environments
if [[ ! -x "$GODOT" && -x /workspace/tools/Godot_v4.7.2-stable_linux.x86_64 ]]; then
  GODOT=/workspace/tools/Godot_v4.7.2-stable_linux.x86_64
fi

OUT_DIR="$ROOT/build/web"
OUT="$OUT_DIR/index.html"
TEMPLATE_DIR="${HOME}/.local/share/godot/export_templates/4.7.2.stable"

mkdir -p "$OUT_DIR"

if [[ ! -x "$GODOT" ]]; then
  echo "Godot binary not found: $GODOT" >&2
  exit 1
fi
if [[ ! -f "$TEMPLATE_DIR/web_release.zip" ]]; then
  echo "Godot 4.7.2 Web export templates missing under $TEMPLATE_DIR" >&2
  echo "Install Godot_v4.7.2-stable_export_templates.tpz (web_release.zip required)." >&2
  exit 1
fi
if ! grep -q 'name="Web"' "$ROOT/export_presets.cfg" 2>/dev/null; then
  echo "Export preset 'Web' not found in export_presets.cfg" >&2
  exit 1
fi

echo "Exporting Web (HTML5) -> $OUT"
"$GODOT" --headless --path "$ROOT" --export-release "Web" "$OUT"
echo "Export complete:"
ls -lh "$OUT_DIR"
