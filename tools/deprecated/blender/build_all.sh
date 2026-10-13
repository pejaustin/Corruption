#!/usr/bin/env bash
# Regenerate the placeholder world blockout (Blender 4.5, Windows side from WSL; adjust BLENDER for other setups).
# Overwrites art/world/props.blend, pois/*.blend, source/world_landscape.blend, textures/*.png (textures are kept if present).
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
BLENDER="${BLENDER:-/mnt/c/Program Files/Blender Foundation/Blender 4.5/blender.exe}"
conv() { if command -v wslpath >/dev/null; then wslpath -w "$1"; else echo "$1"; fi; }
for s in build_props build_pois build_landscape; do
  "$BLENDER" -b --python "$(conv "$ROOT/tools/blender/$s.py")" -- "$(conv "$ROOT")" | grep -E "saved|trees|Error|Traceback" || true
done
