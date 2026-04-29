# Netfox Reference (project-specific cheat sheet)

> **Read this BEFORE editing anything that touches:**
> - `RollbackSynchronizer`, `TickInterpolator`, `RewindableState(Machine)` nodes
> - `state_properties` / `input_properties` arrays in actor `.tscn`
> - `NetworkTime.*` calls or any `_rollback_tick` body
> - Damage / HP sync, authority transfer, input gathering
>
> Skip otherwise — this doc is loaded on demand.

---

## 1. Autoloads

| Autoload | Purpose | Key API |
|---|---|---|
| `NetworkTime` | Owns the tick loop. | `tick` (monotonic int), `ticktime` (sec/tick), `tickrate`, `physics_factor`, `before_tick_loop`, `before_tick`, `on_tick(delta, tick)`, `after_tick`, `after_tick_loop`. `await NetworkTime.start()`, `NetworkTime.stop()`. |
| `NetworkRollback` | Drives the rewind→resimulate→record loop each tick. | Talks to nodes via `_rollback_tick(delta, tick, is_fresh)`. Phases: `before_loop` → `on_prepare_tick` → `on_process_tick` → `on_record_tick` → `after_loop`. |
| `NetworkEvents` | Auto-starts/stops `NetworkTime` on connect/disconnect. | Don't call directly. |

`local_tick` / `remote_tick` on `NetworkTime` are deprecated — just use `tick`.

---

## 2. Tick lifecycle (firing order)

Per network tick, in order:

1. **`NetworkTime.before_tick_loop`** — input gather happens here.
2. `NetworkTime.before_tick`
3. `NetworkRollback.before_loop` — rewind window opens.
4. For each tick in the window:
   - `on_prepare_tick(t)` — RollbackSynchronizer restores recorded state.
   - `on_process_tick(t)` — calls `_rollback_tick(delta, t, is_fresh)` on `root`. State machine ticks the active `RewindableState`.
   - `on_record_tick(t)` — RollbackSynchronizer records new state.
5. `NetworkRollback.after_loop` — `display_enter/exit` callbacks fire; `on_display_state_changed` emits.
6. `NetworkTime.on_tick(delta, tick)` — non-rollback game logic.
7. `NetworkTime.after_tick`, `NetworkTime.after_tick_loop`.

`is_fresh == true` only on the first simulation of a tick. Gate one-shot effects on it.

---

## 3. Core node types

### `RollbackSynchronizer`
Child of an actor. Replicates rollback state.

- **Exports:** `root` (NodePath, almost always `..`), `state_properties: Array[String]`, `input_properties: Array[String]`.
- **Property path syntax:** `":prop"` (root), `"Child:prop"`, `"Child/Sub:prop"`.
- **Drives** `_rollback_tick(delta, tick, is_fresh)` on `root`.
- **Call `process_settings()` after** instantiation if paths under `root` are populated by an inherited scene (see `scenes/actors/player/player_actor.gd:18`).
- **Call `process_authority()` if** authority changes mid-game (Avatar transfer).

### `TickInterpolator`
Sibling of `RollbackSynchronizer`. Smooths visuals between ticks.

- Same `root` + `properties` pattern.
- **List ONLY visual props** (`:transform`, `Model:transform`). Never logical state — interpolating `:hp` would visually lerp damage.
- **`teleport()`** after respawn to avoid lerping across the world.

### `RewindableStateMachine` + `RewindableState`
From `netfox.extras`. Child of the actor; `RewindableState` nodes nested under it.

- Node name = state ID (StringName).
- The `state` property of the machine **must be in the parent `RollbackSynchronizer.state_properties`** so transitions are rewound.
- API: `state_machine.transition(&"Name")`, `state_machine.state` (current StringName).
- Signal: `on_display_state_changed(old, new)` — fires after rollback settles. Use it for animation/audio cues.

`RewindableState` hooks:

| Hook | Purpose | Networked? |
|---|---|---|
| `enter(prev, tick)` | Setup (latch ticks, set vectors) | yes — runs in resim |
| `exit(next, tick)` | Teardown | yes |
| `tick(delta, tick, is_fresh)` | Per-tick logic | yes |
| `can_enter(prev) -> bool` | Transition guard | yes |
| `display_enter(prev)` / `display_exit(next)` | Visuals/SFX only | display-side only |

Modify networked properties only in `enter`/`exit`/`tick`; visuals go in `display_*`.

---

## 4. Project conventions

### Layout: one actor = three children
```
ActorRoot (CharacterBody3D, root of state)
├── RollbackSynchronizer  (root=.. ; state_properties=[":transform",":velocity",":hp",
│                          "Model:transform","RewindableStateMachine:state"])
├── TickInterpolator      (root=.. ; properties=[":transform","Model:transform"])
└── RewindableStateMachine
    └── State1, State2, …  (RewindableState subclasses)
```
Canonical example: `scenes/actors/player/player_actor.tscn:23-31`.

### `process_settings()` after `super()`
Inherited scenes finalize their tree after the synchronizer's `_ready`. Force a re-resolve:
```gdscript
func _ready() -> void:
    super()
    rollback_synchronizer.process_settings()
```
See `scenes/actors/player/player_actor.gd:18`.

### Input gathering
Every input node connects `_gather` to `NetworkTime.before_tick_loop` and disconnects in `_exit_tree`. Gate on **`is_multiplayer_authority()`**, not `multiplayer.is_server()` — the Avatar's authority moves between peers.

```gdscript
func _ready() -> void:
    NetworkTime.before_tick_loop.connect(_gather)

func _gather() -> void:
    if not is_multiplayer_authority() or not input_enabled:
        return
    # populate input properties
```
Examples: `scripts/player_input.gd:12`, `scripts/avatar_input.gd:28`, `scripts/camera_input.gd:30`.

### Movement: always use `physics_move()` from `ActorState`
`scenes/actors/states/actor_state.gd` provides:
```gdscript
func physics_move() -> void:
    actor.velocity *= NetworkTime.physics_factor
    actor.move_and_slide()
    actor.velocity /= NetworkTime.physics_factor
```
Never call `move_and_slide()` directly inside a rollback state — you'll desync from `_physics_process` motion.

### State duration: tick latch, not delta accumulators
```gdscript
var _enter_tick: int = -1

func enter(_prev, _tick) -> void:
    _enter_tick = NetworkTime.tick

func tick(delta, tick, is_fresh) -> void:
    if _enter_tick < 0:
        _enter_tick = NetworkTime.tick  # non-authority bypass — see gotchas
    var elapsed: float = (NetworkTime.tick - _enter_tick) * NetworkTime.ticktime
    if elapsed > DURATION:
        state_machine.transition(&"Idle")
```
Canonical: `scenes/actors/states/stagger_state.gd:14-35`.

Why `NetworkTime.tick` and not the `tick` arg? Because **MinionActor** invokes its state machine outside the rollback loop with hardcoded `tick=0, is_fresh=true` (`scenes/actors/minion/minion_actor.gd:173`) — the arg is meaningless for host-authoritative entities. `NetworkTime.tick` works for both.

### Authority transfer (Avatar)
Avatar's input authority moves between peers via `set_multiplayer_authority(peer_id)` on the input node. See `scripts/avatar_input.gd:60-67`. Authority falls back to peer 1 (server) when dormant.

### Edge-press buffering across rollback
`AvatarInput` stamps presses with `NetworkTime.tick` into a dict; states call `consume_if_buffered(action)` within `BUFFER_WINDOW = 12` ticks (souls-style). See `scripts/avatar_input.gd:25-58`.

---

## 5. Critical gotchas

### Damage sync: `incoming_damage` is NOT in `state_properties`
Rollback would rubberband the value across the resim window. Pattern: **dual-write**.

```gdscript
# host-side write
target.incoming_damage += dmg
# RPC to the controlling peer so their local copy matches
target.apply_incoming_damage.rpc_id(target_peer_id, dmg, source)
```
`Actor._rollback_tick` drains `incoming_damage` once per tick (`scenes/actors/actor.gd:158-160`), then zeroes locally. The zero is *not* synced — that's intentional, hp is synced.

See: `scenes/actors/minion/states/attack_state.gd:91-95`, `scenes/actors/player/avatar/avatar_actor.gd:54-57`.

### Non-authority peers SKIP `enter()` for synced state transitions
They receive the new state via `state_properties` and the machine just sets `state`. Setup code in `enter()` (latch tick, set `_roll_dir`) is not run on non-authority. **`tick()` must be tolerant** — re-latch `_enter_tick` if it's still `-1`.

### Don't time durations with `delta` accumulators in rollback states
The same tick may resim multiple times with `is_fresh=false`. `_elapsed += delta` overcounts. Always use the tick latch pattern above.

### TickInterpolator properties ⊂ visuals only
Including logical state (`:hp`, state name) makes it lerp visually. Strict subset of visual transforms.

### `physics_factor` discipline
Inside rollback states, multiply velocity by `NetworkTime.physics_factor` before `move_and_slide()`, divide after. Use `ActorState.physics_move()`.

### MinionActor opts OUT of the rollback loop
It runs `_state_machine._rollback_tick(delta, 0, true)` from its own `_physics_process` (`scenes/actors/minion/minion_actor.gd:173`). Host-authoritative; clients receive position/state via `MinionManager` RPCs. **Don't add a `RollbackSynchronizer` to a minion** without untangling that path. Minion-vs-minion physical collision is also intentionally OFF — RVO avoidance handles spacing.

### Input authority: `is_multiplayer_authority()`, not `is_server()`
They differ for the Avatar. Get this wrong and the Avatar stops responding for non-host players.

### `NetworkTime.stop()` on disconnect
Without it, the time synchronizer keeps RPC-pinging and floods logs. See `scripts/network/network_manager.gd:59`.

### `NetworkTime.start()` is awaitable
Don't blindly `await` it in autoloads — there may be no MP peer yet. Test harnesses guard with `if NetworkTime.has_method("start")` (e.g. `scripts/test/war_table_test_controller.gd:75`).

---

## 6. Vanilla Godot 4 multiplayer gotchas

These aren't netfox-specific but bite us anyway.

### RPC `call_local` + dict args = shared reference
```gdscript
@rpc("authority", "call_local", "reliable")
func _sync(d: Dictionary) -> void:
    self.cache.clear()
    for k in d:           # BUG: d IS self.cache after clear
        self.cache[k] = d[k]
```
With `call_local`, the local invocation receives the **same dict reference** you passed in. If you pass `self.cache` and clear it, you also clear the source. Fix: `var copy := d.duplicate()` first, or pass a duplicate at the call site.

### RPC modes
| Slot | Options |
|---|---|
| Caller | `"any_peer"` / `"authority"` |
| Local | `"call_local"` / `"call_remote"` |
| Reliability | `"reliable"` / `"unreliable"` / `"unreliable_ordered"` |
| Channel | int (default 0) |

`@rpc("authority", "call_local", "reliable")` is the most common: only host broadcasts, everyone (including host) runs it, guaranteed delivery.

### `multiplayer.get_remote_sender_id()`
Returns the sender's peer id, OR **`0`** if called locally (not via RPC). Defensive pattern:
```gdscript
var sender := multiplayer.get_remote_sender_id()
if sender == 0:
    sender = multiplayer.get_unique_id()  # we ARE the host
```

### Authority for non-replicated nodes
Defaults to peer 1 (server). `@rpc("authority", ...)` on a Control / Node in a regular scene means only the host can call it — exactly what you want for lobby state.

### `preload()` of player/world scenes — two failure modes
`preload()` runs at **parse time** and the result is captured as a script constant for the script's lifetime. Two things go wrong with this for any scene that's substantial (player scenes, world scenes, anything addon-touching):

**A. Export-time parse failure.** If the preloaded scene fails to load in an export (e.g. a GDExtension addon like Terrain3D didn't export cleanly on Windows), the whole script fails to parse → autoload becomes `Nil` → every `NetworkManager.foo()` call errors with `"nonexistent function foo in base Nil"` and the menu looks frozen.

**B. Editor hot-reload staleness.** During a long editing session, scripts get reloaded as you save edits. The class member `var x = preload(path)` captures a `PackedScene` reference at script-init; after subsequent reloads of unrelated dependencies, that captured reference can become stale and `.instantiate()` returns null with a Godot 4 error in the Errors tab. The canonical "fix" is restarting the editor — or just don't cache the preload as a class member.

**Pattern:** for player/world scenes, store the path as a `const String`, call `load(path).instantiate()` inside the function that uses it, and null-check. `network_manager.gd:_load_game_scene` and `multiplayer_manager.gd:_add_player_to_game` are the canonical patterns. Reserve `preload()` for small inert assets (icons, plain UI scenes) that won't be touched by hot-reload.

---

## 7. Files worth reading for examples

| File | Shows |
|---|---|
| `scenes/actors/player/player_actor.tscn:23-31` | RollbackSynchronizer + TickInterpolator + RewindableStateMachine layout |
| `scenes/actors/player/player_actor.gd:18` | `process_settings()` post-`super()` |
| `scenes/actors/actor.gd:157` | `_rollback_tick` body, drain damage, gravity ordering |
| `scenes/actors/states/actor_state.gd` | `physics_move()` helper |
| `scenes/actors/states/stagger_state.gd:14-35` | Tick-latch duration with non-authority fallback |
| `scenes/actors/player/states/roll_state.gd` | Same pattern, rollback-supplied `tick` arg |
| `scripts/avatar_input.gd:25-67` | Input gather + dynamic authority + edge-press buffering |
| `scripts/player_input.gd` | Minimal input gather (fixed authority) |
| `scripts/camera_input.gd` | Non-input node hooked to `before_tick_loop` |
| `scenes/actors/minion/minion_actor.gd:173` | Opt-out of rollback loop pattern |
| `scenes/actors/minion/states/attack_state.gd:80-105` | Dual-write damage pattern |
| `scenes/actors/player/avatar/avatar_actor.gd:49-57` | Receiving end of `apply_incoming_damage` |
| `scripts/network/network_manager.gd:59` | `NetworkTime.stop()` on disconnect |
