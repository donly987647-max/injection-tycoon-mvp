#!/usr/bin/env bash
set -euo pipefail
GODOT=/workspace/tools/Godot_v4.7.2-stable_linux.x86_64
exec "$GODOT" --headless --path /workspace/injection-tycoon-mvp res://scenes/smoke.tscn
