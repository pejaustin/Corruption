#!/usr/bin/env bash
# One step from Austin's 2 km map to the world sizes. 2 km is the working size (Austin, 2026-10-12): by default only
# 2 km is exported, imported, baked and checked; 400 m and 6 km are kept as they are and regenerated only on request.
#
#   tools/sync_world_sizes.sh                 after editing the map in Blender (ground, markers): everything below, 2 km only
#   tools/sync_world_sizes.sh --all-sizes     the same for 400 m, 2 km and 6 km (also --sizes 400m,2km,6km, any subset)
#   tools/sync_world_sizes.sh --no-export     the .blend is unchanged; you edited art/world/export/world_landscape_2km.tscn
#                                             (something under a marker) or scenes/world/world.tscn (moved places)
#   tools/sync_world_sizes.sh --no-bake       as above, and the ground did not change: skip the navmesh and map-picture bakes
#
# What it does:
#   1. exports every size from art/world/source/world_landscape.blend (tools/blender/export_landscape.py; never saves the .blend),
#      with the forest and water guide outlines (art/world/export/areas_<size>.json), then every POI blockout
#      (art/world/pois/<snake>.blend -> pois/export/<snake>.glb) and the shared props (props.blend -> export/props/*.glb)
#      (tools/blender/export_pois.py; never saves those either)
#   2. re-imports in Godot headless (the .blend importer is switched off in project.godot for the run and restored after)
#   3. bakes each size's map-floor picture (tools/bake_map_illustration.gd) and imports it
#   4. builds the POI scenes (pois/<snake>.tscn, once), the forests and water of each size (export/world_areas_<size>.tscn) and
#      the 400 m and 6 km landscape and world scenes from the 2 km ones (scripts/build/build_world_sizes.gd)
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
SIZES=(2km)
GODOT="${GODOT:-godot}"
DO_EXPORT=1
DO_BAKE=1
while [ $# -gt 0 ]; do
  arg="$1"; shift
  [ "$arg" = "--sizes" ] && { IFS=, read -ra SIZES <<< "${1:?--sizes needs a list}"; shift; continue; }
  case "$arg" in
    --no-export) DO_EXPORT=0 ;;
    --no-bake) DO_BAKE=0; DO_EXPORT=0 ;;
    --all-sizes) SIZES=(400m 2km 6km) ;;
    --sizes=*) IFS=, read -ra SIZES <<< "${arg#--sizes=}" ;;
    -h|--help) sed -n 2,26p "$0"; exit 0 ;;
    *) echo "unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done
# the derived sizes (everything but 2 km) the build step makes from the 2 km scenes
DERIVED=(); for s in "${SIZES[@]}"; do [ "$s" != 2km ] && DERIVED+=("$s"); done
DERIVED_CSV="$(IFS=,; echo "${DERIVED[*]-}")"

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
# The POI marker names (Godot's glb nodes keep Austin's spellings) as snake_case file names: lowercase, apostrophes dropped,
# spaces to underscores. Read from the 2 km ground's nodes via a Blender-free route: the marker list in the glb's JSON chunk.
poi_snakes() {
  python3 - "$ROOT/art/world/export/world_landscape_2km.glb" <<'PY'
import json, struct, sys
d = open(sys.argv[1], 'rb').read()
j = json.loads(d[20:20 + struct.unpack('<I', d[12:16])[0]])
for n in j['nodes']:
    name = n.get('name', '')
    if 'mesh' not in n and not name.endswith('Tower') and 'children' not in n and name:
        print(name.lower().replace("'", '').replace(' ', '_'))
PY
}
# A new glb of the POIs and props needs its .import (the import script puts the curved-world materials on its materials).
ensure_glb_imports() {
  for f in art/world/pois/export/*.glb art/world/export/props/*.glb; do
    [ -f "$f" ] && [ ! -f "$f.import" ] && printf '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\nimport_script/path="res://art/world/pois/poi_post_import.gd"\n' > "$f.import"
  done
  return 0
}
import_assets() { ensure_glb_imports; gd 600 "$GODOT" --headless --path . --import; }

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
  # one POI blockout per marker of his map (snake_case name; tower markers have none), and the shared props
  for snake in $(poi_snakes); do
    [ -f "$ROOT/art/world/pois/$snake.blend" ] || { echo "  no art/world/pois/$snake.blend for a marker; skipped" >&2; continue; }
    run 300 "$BLENDER" -b "$(conv "$ROOT/art/world/pois/$snake.blend")" --python "$(conv "$ROOT/tools/blender/export_pois.py")" -- "$(conv "$ROOT")" >"$LOG" 2>&1 || { cat "$LOG" >&2; echo "Blender export failed for POI $snake" >&2; exit 1; }
    grep -q '^EXPORTED' "$LOG" && echo "  [poi $snake] exported" || { cat "$LOG" >&2; echo "no glb written for POI $snake" >&2; exit 1; }
  done
  run 300 "$BLENDER" -b "$(conv "$ROOT/art/world/props.blend")" --python "$(conv "$ROOT/tools/blender/export_pois.py")" -- "$(conv "$ROOT")" --props >"$LOG" 2>&1 || { cat "$LOG" >&2; echo "Blender export failed for props" >&2; exit 1; }
  grep -cE '^EXPORTED' "$LOG" | sed 's/^/  [props] glbs exported: /'
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
gd 600 SIZES="${DERIVED_CSV:-2km}" "$GODOT" --headless --path . -s res://scripts/build/build_world_sizes.gd

if [ "$DO_BAKE" = 1 ]; then
  step "5/5 navmeshes (then the build again, fitting the towers to them)"
  for size in "${SIZES[@]}"; do gd 1800 WORLD=1 SIZE="$size" "$GODOT" --headless --path . -s res://tools/bake_open_world_navmesh.gd; done
  gd 600 SIZES="${DERIVED_CSV:-2km}" "$GODOT" --headless --path . -s res://scripts/build/build_world_sizes.gd
else
  step "5/5 navmeshes: skipped"
fi

step "done"
git status --short -- art/world/export scenes/world scenes/map | grep -v '\.uid$' || true
echo "Check it: tools/tests/test_world_layout.tscn with WORLD_SIZE=400m, 2km and 6km (README: art/world/README.md, Sizes)."
