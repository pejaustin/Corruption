#!/usr/bin/env bash
# 4-player network smoke test: one listen-server host and three joiners, each a separate headless Godot
# process on localhost. See README.md in this directory. Exit code 0 only if every process passed.
set -u
cd "$(dirname "$0")/../.."
ROOT="$PWD"
GODOT="${GODOT:-godot}"
PLAYERS="${SMOKE_PLAYERS:-4}"
RUN_TIMEOUT="${SMOKE_TIMEOUT:-900}"
LOGDIR="${SMOKE_LOGDIR:-$(mktemp -d "${TMPDIR:-/tmp}/corruption-net-smoke.XXXXXX")}"
mkdir -p "$LOGDIR"
PORT="$(python3 -c 'import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
PIDS=()

cleanup() {
	for pid in "${PIDS[@]:-}"; do
		[ -n "$pid" ] && kill "$pid" 2>/dev/null
	done
	sleep 1
	for pid in "${PIDS[@]:-}"; do
		[ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
	done
	pkill -9 -P $$ 2>/dev/null
}
trap cleanup EXIT INT TERM

launch() { # role name niceness
	nice -n "${3:-0}" timeout -k 10 "$RUN_TIMEOUT" "$GODOT" --headless --max-fps 60 --path "$ROOT" res://tools/net/net_smoke.tscn -- \
		--role="$1" --name="$2" --port="$PORT" --players="$PLAYERS" --world="${SMOKE_WORLD:-400m}" ${SMOKE_ARGS:-} >"$LOGDIR/$2.log" 2>&1 &
	PIDS+=("$!")
}

echo "net smoke: $PLAYERS players, port $PORT, logs in $LOGDIR"
launch host host 0
for _ in $(seq 1 120); do
	grep -q "listening on" "$LOGDIR/host.log" 2>/dev/null && break
	sleep 0.5
done
grep -q "listening on" "$LOGDIR/host.log" || { echo "FAIL host never started listening"; tail -20 "$LOGDIR/host.log"; exit 1; }
for i in $(seq 1 $((PLAYERS - 1))); do
	launch join "join$i" 10
done

status=0
for idx in "${!PIDS[@]}"; do
	wait "${PIDS[$idx]}"
	code=$?
	name=host; [ "$idx" -gt 0 ] && name="join$idx"
	echo "$name exited with $code"
	[ "$code" -ne 0 ] && status=1
done
PIDS=()

echo "---- results ----"
fails=0
for f in host $(seq -f "join%g" 1 $((PLAYERS - 1))); do
	printf '%s: ' "$f"; grep -h "^\[tests\]" "$LOGDIR/$f.log" || { echo "no [tests] summary (crashed or timed out)"; status=1; }
	fails=$((fails + $(grep -c "^  FAIL " "$LOGDIR/$f.log")))
done
echo "-- skipped (cannot be checked headless) --"
grep -h "^  SKIP " "$LOGDIR/host.log" | sed 's/\[host\] //'
if [ "$fails" -gt 0 ]; then echo "-- failures --"; grep -H "^  FAIL " "$LOGDIR"/*.log | sed "s|$LOGDIR/||"; status=1; fi
[ "$status" -eq 0 ] && echo "net smoke: PASS" || echo "net smoke: FAIL (logs in $LOGDIR)"
exit $status
