#!/usr/bin/env bash
# One step from Austin's 2 km map to all three world sizes (400 m, 2 km, 6 km).
#
#   tools/sync_world_sizes.sh                 after editing the map in Blender (ground, markers): everything below
#   tools/sync_world_sizes.sh --no-export     the .blend is unchanged; you edited art/world/export/world_landscape_2km.tscn
#                                             (something under a marker) or scenes/world/world.tscn (moved places)
#   tools/sync_world_sizes.sh --no-bake       as above, and the ground did not change: skip the navmesh and map-picture bakes
#
# What it does:
#   1. exports every size from art/world/source/world_landscape.blend (tools/blender/export_landscape.py; never saves the .blend)
#   2. re-imports in Godot headless (the .blend importer is switched off in project.godot for the run and restored after)
#   3. bakes each size's map-floor picture (tools/bake_map_illustration.gd) and imports it
#   4. builds the 400 m and 6 km landscape and world scenes from the 2 km ones (scripts/build/build_world_sizes.gd)
#   5. bakes each size's navmesh (tools/bake_open_world_navmesh.gd, WORLD=1), then builds again so the towers
#      are fitted against the fresh meshes
#
# Environment:
#   GODOT    Godot 4.6 binary (default: godot).
#   BLENDER  Blender 4.5 binary. Default: the Windows one under WSL, /Applications/Blender.app on a Mac, else `blender`.
#   VERBOSE=1 shows all engine output instead of the lines that matter.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
SIZES=(400m 2km 6km)
GODOT="${GODOT:-godot}"
DO_EXPORT=1
DO_BAKE=1
for arg in "$@"; do
  case "$arg" in
    --no-export) DO_EXPORT=0 ;;
    --no-bake) DO_BAKE=0; DO_EXPORT=0 ;;
    -h|--help) sed -n 2,22p "$0"; exit 0 ;;
    *) echo "unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done

# --- helpers ---

if command -v timeout >/dev/null; then TIMEOUT=timeout; elif command -v gtimeout >/dev/null; then TIMEOUT=gtimeout; else TIMEOUT=""; fi
# run <seconds> <command...>: with a time limit when the platform has `timeout`.
run() { local secs="$1"; shift; if [ -n "$TIMEOUT" ]; then "$TIMEOUT" "$secs" "$@"; else "$@"; fi; }
step() { printf '\n== %s\n' "$*"; }
LOG="$(mktemp)"

# gd <seconds> <env assignments and godot arguments...>: runs Godot, shows the lines that matter, fails on a non-zero exit.
gd() {
  local secs="$1"; shift
  local status=0
  run "$secs" env "$@" >"$LOG" 2>&1 || status=$?
  if [ -n "${VERBOSE:-}" ]; then cat "$LOG"; else grep -E '^\[(build|bake|illustration)\]|SCRIPT ERROR|^ERROR: (bake|could not)|no yaw|is missing' "$LOG" | grep -v "Nonexistent function '_process'" || true; fi
  if [ "$status" -ne 0 ]; then echo "FAILED (exit $status): $*" >&2; tail -20 "$LOG" >&2; exit "$status"; fi
}

# Godot 4.6 stops a headless import at the first .blend when it has no Blender path; the importer is switched off for
# the run (a [filesystem] entry in project.godot) and project.godot is put back afterwards.
PROJECT_BACKUP=""
disable_blender_import() {
  if grep -q 'import/blender/enabled' project.godot; then return; fi
  PROJECT_BACKUP="$(mktemp)"
  cp project.godot "$PROJECT_BACKUP"
  printf '\n[filesystem]\n\nimport/blender/enabled=false\n' >> project.godot
}
restore_project() {
  if [ -n "$PROJECT_BACKUP" ] && [ -f "$PROJECT_BACKUP" ]; then cp "$PROJECT_BACKUP" project.godot; rm -f "$PROJECT_BACKUP"; PROJECT_BACKUP=""; fi
}
import_assets() { gd 600 "$GODOT" --headless --path . --import; }

trap 'rm -f "$LOG"; restore_project' EXIT

# --- checks ---

if ! "$GODOT" --version 2>/dev/null | grep -q '^4\.6'; then
  echo "GODOT must be Godot 4.6 (got: $("$GODOT" --version 2>&1 | head -1)); set GODOT=/path/to/godot" >&2
  exit 1
fi

# --- 1. export from Blender ---

if [ "$DO_EXPORT" = 1 ]; then
  if [ -z "${BLENDER:-}" ]; then
    if grep -qi microsoft /proc/version 2>/dev/null; then BLENDER="/mnt/c/Program Files/Blender Foundation/Blender 4.5/blender.exe"
    elif [ -x /Applications/Blender.app/Contents/MacOS/Blender ]; then BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
    else BLENDER=blender; fi
  fi
  conv() { if [[ "$BLENDER" == *.exe ]] && command -v wslpath >/dev/null; then wslpath -w "$1"; else echo "$1"; fi; }
  step "1/5 export from Blender ($BLENDER)"
  for size in "${SIZES[@]}"; do
    run 300 "$BLENDER" -b "$(conv "$ROOT/art/world/source/world_landscape.blend")" --python "$(conv "$ROOT/tools/blender/export_landscape.py")" -- "$(conv "$ROOT")" "$size" >"$LOG" 2>&1 || { cat "$LOG" >&2; echo "Blender export failed for $size" >&2; exit 1; }
    grep -E '^EXPORTED|GEOMETRY_AND_NAMES_UNCHANGED' "$LOG" | sed "s/^/  [$size] /"
    grep -q 'GEOMETRY_AND_NAMES_UNCHANGED True' "$LOG" || { echo "the export changed the scene in memory ($size); stop" >&2; exit 1; }
  done
else
  step "1/5 export from Blender: skipped"
fi

# --- 2-5. Godot ---

disable_blender_import
step "2/5 import in Godot"
import_assets

if [ "$DO_BAKE" = 1 ]; then
  step "3/5 map-floor pictures"
  for size in "${SIZES[@]}"; do gd 300 SIZE="$size" "$GODOT" --headless --path . -s res://tools/bake_map_illustration.gd; done
  import_assets
else
  step "3/5 map-floor pictures: skipped"
fi

step "4/5 build the 400 m and 6 km scenes from the 2 km ones"
gd 600 "$GODOT" --headless --path . -s res://scripts/build/build_world_sizes.gd

if [ "$DO_BAKE" = 1 ]; then
  step "5/5 navmeshes (then the build again, fitting the towers to them)"
  for size in "${SIZES[@]}"; do gd 1800 WORLD=1 SIZE="$size" "$GODOT" --headless --path . -s res://tools/bake_open_world_navmesh.gd; done
  gd 600 "$GODOT" --headless --path . -s res://scripts/build/build_world_sizes.gd
else
  step "5/5 navmeshes: skipped"
fi

step "done"
git status --short -- art/world/export scenes/world scenes/map | grep -v '\.uid$' || true
echo "Check it: tools/tests/test_world_layout.tscn with WORLD_SIZE=400m, 2km and 6km (README: art/world/README.md, Sizes)."
