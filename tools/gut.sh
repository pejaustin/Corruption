#!/bin/sh
# Fast tests (tests/unit, tests/component), headless: tools/gut.sh [test_file.gd]. No argument runs the whole fast tier.
# --fixed-fps: every frame is 1/60 s of game time, run as fast as the CPU allows, so tests that need real
# physics (test_movement) take a fraction of the game time they simulate. Exits non-zero when a test fails. Milestone tests are not GUT: see tests/integration/README.md.
cd "$(dirname "$0")/.."
# $GODOT overrides the Godot binary (Mac: GODOT="arch -arm64 /Applications/Godot.app/Contents/MacOS/Godot").
GODOT=${GODOT:-godot}
if [ -n "$1" ]; then SEL="-gselect=$1"; fi
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
$GODOT --headless --fixed-fps 60 --path . -s addons/gut/gut_cmdln.gd $SEL -glog=1 >"$LOG" 2>&1
CODE=$?
# Filtered: netfox's RollbackSynchronizer waits for a time sync that never comes in a test (no match is
# running), so freeing a Paladin or overlord logs "disconnect a nonexistent connection" errors. They are
# harmless and GUT doesn't count them. Also filtered: the avatar model's stale-UID import warnings.
grep -vE "invalid UID|^ +at: open|nonexistent connection from 'Network(Time|Rollback)" "$LOG"
exit $CODE
