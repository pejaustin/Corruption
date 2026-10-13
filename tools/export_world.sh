#!/usr/bin/env bash
# Austin's map from Blender to Godot (Austin, 2026-10-13: "take the world geo and the outer boundary blender files, build
# glbs, and reimport them"). Nothing else: markers, towers, POIs, crossings, forests and water are authored in the Godot
# scenes (art/world/export/world_landscape_<size>.tscn) and this script never touches them.
#
#   tools/export_world.sh [2km|400m|all]     (default 2km)
#
#   2km:  art/world/source/world_landscape.blend      -> art/world/export/world_landscape_2km.glb  (geo only)
#         art/world/source/world_backdrop.blend       -> art/world/export/world_backdrop_2km.glb
#   400m: art/world/source/world_landscape_400m.blend -> art/world/export/world_landscape_400m.glb (geo only)
#         art/world/source/world_backdrop_400m.blend  -> art/world/export/world_backdrop_400m.glb  (only if that file exists)
#   The two sizes are separate works. 6 km is legacy (not maintained, not for MVP): not exported.
#
# Then re-imports: if a Godot editor is open on this project it is left alone (focus it and it re-imports); otherwise a
# headless `godot --import` runs, with the .blend importer switched off in project.godot for the run (a headless import
# stops at the first .blend without a Blender path) and project.godot put back afterwards, even on failure.
# Afterwards, if the ground changed: rebuild the water's blockers and walls, rebake the navmesh and the map picture
# (art/world/README.md, "After a ground change").
#
# Environment: GODOT (default godot, else /Applications/Godot.app), BLENDER (default /Applications/Blender.app on a Mac,
# the Windows install under WSL, else blender).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
case "${1:-2km}" in
  2km) SIZES=(2km) ;;
  400m) SIZES=(400m) ;;
  all) SIZES=(2km 400m) ;;
  -h|--help) sed -n 2,22p "$0"; exit 0 ;;
  *) echo "usage: tools/export_world.sh [2km|400m|all]" >&2; exit 2 ;;
esac

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1 && [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
  GODOT=/Applications/Godot.app/Contents/MacOS/Godot
fi
if [ -z "${BLENDER:-}" ]; then
  if [ -x /Applications/Blender.app/Contents/MacOS/Blender ]; then BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
  elif grep -qi microsoft /proc/version 2>/dev/null; then BLENDER="/mnt/c/Program Files/Blender Foundation/Blender 4.5/blender.exe"
  else BLENDER=blender; fi
fi
conv() { if [[ "$BLENDER" == *.exe ]] && command -v wslpath >/dev/null; then wslpath -w "$1"; else echo "$1"; fi; }
LOG="$(mktemp)"
PROJECT_BACKUP=""
restore_project() {
  if [ -n "$PROJECT_BACKUP" ] && [ -f "$PROJECT_BACKUP" ]; then cp "$PROJECT_BACKUP" project.godot; rm -f "$PROJECT_BACKUP"; PROJECT_BACKUP=""; fi
}
trap 'rm -f "$LOG"; restore_project' EXIT

# blender <file.blend> <script.py> <args...>: runs a background Blender, prints its EXPORTED / checksum lines.
blender() {
  local blend="$1" script="$2"; shift 2
  "$BLENDER" -b "$(conv "$ROOT/$blend")" --python "$(conv "$ROOT/$script")" -- "$(conv "$ROOT")" "$@" >"$LOG" 2>&1 \
    || { cat "$LOG" >&2; echo "Blender failed on $blend" >&2; exit 1; }
  grep -E '^EXPORTED|GEOMETRY_AND_NAMES_UNCHANGED|^WARNING' "$LOG" | sed "s|^|  [$blend] |"
  if grep -q 'GEOMETRY_AND_NAMES_UNCHANGED' "$LOG" && ! grep -q 'GEOMETRY_AND_NAMES_UNCHANGED True' "$LOG"; then
    echo "the export changed $blend in memory; stop" >&2; exit 1
  fi
}

for size in "${SIZES[@]}"; do
  if [ "$size" = 2km ]; then land=art/world/source/world_landscape.blend; back=art/world/source/world_backdrop.blend
  else land=art/world/source/world_landscape_$size.blend; back=art/world/source/world_backdrop_$size.blend; fi
  echo "== $size"
  blender "$land" tools/blender/export_landscape.py "$size"
  if [ -f "$back" ]; then blender "$back" tools/blender/export_backdrop.py "$size"; else echo "  no $back: no backdrop at $size"; fi
done

# An editor open on this project re-imports by itself when focused; a second Godot importing alongside it would fight it.
editor_open() {
  ps -axo command 2>/dev/null | grep -i godot | grep -v grep | grep -F -- "$ROOT" | grep -Eq -- '(--editor|(^| )-e( |$))'
}
if editor_open; then
  echo "A Godot editor is open on this project: focus the Godot editor to reimport."
  exit 0
fi
echo "== re-import (headless)"
if ! grep -q 'import/blender/enabled' project.godot; then
  PROJECT_BACKUP="$(mktemp)"
  cp project.godot "$PROJECT_BACKUP"
  printf '\n[filesystem]\n\nimport/blender/enabled=false\n' >> project.godot
fi
status=0
"$GODOT" --headless --path . --import >"$LOG" 2>&1 || status=$?
restore_project
if [ "$status" -ne 0 ]; then tail -20 "$LOG" >&2; echo "Godot import failed (exit $status)" >&2; exit "$status"; fi
echo "  done"
