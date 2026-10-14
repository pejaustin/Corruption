# CLAUDE.md — Godot 4 Project Guide

This file gives Claude Code the context it needs to make informed changes to a Godot 4 project. Read it before writing or editing any `.gd`, `.tscn`, or `.tres` file.

> **Engine version:** Godot 4.x. This project does **not** use Godot 3 — many APIs were renamed in 4.0 and the old names will silently fail or look right but be wrong. See "Godot 3 → 4 gotchas" below.

---

## 1. Project at a glance

- **Game type:** 4-player PvP Dark Lord simulator — 3D third-person (Avatar) + 3D first-person (Overlords)
- **Scripting language:** GDScript only
- **Target platforms:** Desktop
- **Entry scene:** `scenes/world/world.tscn`, the 2 km world; the host picks 400 m / 2 km / 6 km in the lobby (`GameState.world_size`, `MatchConfig.WORLD_SCENES`). 400 m and 2 km are separate works (each its own Blender map and Godot scenes); 6 km is legacy (not maintained, not for MVP). See `art/world/README.md` "Sizes". Project main scene is `scenes/menus/main_menu.tscn`
- **Key autoloads:** `NetworkManager`, `DebugManager`, plus netfox autoloads (`NetworkTime`, `NetworkRollback`, etc.)
- **Game constants:** `scripts/game_constants.gd` — Factions enum, MAX_PLAYERS, GOOD_SIDE, seat colours; match pace in `scripts/match_config.gd`
- **Full overview:** `docs/one-pager.md`

---

## 2. How to run, lint, and validate

- **Run:** open `project.godot` in Godot 4.6 and press F5 (main menu → host → lobby → start).
- **Sandbox:** `tools/sandbox/sandbox_400m.tscn` opens the 400 m world on its own as an offline host (you are player 1, no
  lobby): open it and press F6, or `godot --path . res://tools/sandbox/sandbox_400m.tscn`. Esc → Debug panel to spawn units.
- **Combat test arena** (`tools/arena/`, #640): fight as the Paladin (any control level) or a boss form (any of
  `data/bosses/` attacks) against an AI, any minion type, or a second player, on a flat floor with no match: open
  `tools/arena/arena.tscn` and press F6, or `godot --path . res://tools/arena/arena.tscn -- --offline --fight`. Esc = setup
  panel (Offline / Host / Join, then Fight). Two players: one runs `-- --host --fight --opponent=player`, the other
  `-- --join=<ip>` and plays the other role. Presets: `tools/arena/presets/*.tres` (`--arena-preset=<path>`); flags in
  `ArenaConfig.apply_args`. Hooks it relies on: `AvatarActor.control_level_override`, `restore_full_hp`.
- **Tests (Austin, 2026-10-13):** most tests take milliseconds and check one thing. Tests compound: drive the
  subject directly and trust what other tests cover (kill a boss with `notify_minion_died`, not by fighting it; set a
  site's `present_strength`, don't walk units in). Inject or split code only where a test needs it.
  - **Fast tier (GUT), every change:** `tests/unit/` (no scene tree) and `tests/component/` (one node or scene on a
    bare stage, `tests/support/stage_test.gd`: MinionManager + GroupManager as `current_scene`, no world).
    `tools/gut.sh test_paladin.gd` runs one file; run only the touched system's file, `tools/gut.sh` for all (about 2 s).
    Physics tests (`test_movement`) use a small baked navmesh (`add_ground`) and `--fixed-fps`.
  - **Milestone tier, only before a version or when asked:** `tests/integration/` (load the real world, e.g.
    `godot --headless --path . res://tests/integration/test_orders.tscn`; a fresh clone needs one
    `godot --headless --import` first), the net smoke and the input playtests below. See `tests/integration/README.md`.
- **4-player network smoke** (`tools/net/`): `tools/net/smoke.sh` starts a listen-server host and three joiners as separate
  headless processes on localhost (free UDP port, `timeout`, trap-killed) and drives lobby -> Start -> seats/towers -> orders
  and couriers -> site changes -> Paladin (defeat, possess, Palantir viewers, recall) -> mirror calls -> gauntlet, win and
  draw, checking on every peer; it exits non-zero on any FAIL or missing summary. Logs: `$SMOKE_LOGDIR` (default a temp dir).
  Env: `SMOKE_WORLD=400m|2km|6km` (default 400m), `SMOKE_PLAYERS`, `SMOKE_ARGS="--stop-after=<phase>"`. Takes ~4-8 min.
  Not covered (printed as SKIP): audio capture/playback, mic, a moving player's pose, real network latency/NAT. The host
  freezes the 23 neutral townsfolk and the processes run physics at 30 Hz so four worlds fit on 4 cores. netfox's
  "Trying to run rollback ... past the history limit" / "Received data for N, rejecting because older than 64 frames"
  warnings (thousands per joiner) mean the host's tick count fell behind its clock under CPU load.
- **Input playtests** (`tools/playtest/`): play the game like a person, not by calling its functions.
  `input_driver.gd` pushes real `InputEvent`s through `Input.parse_input_event()` (actions, keys, mouse look, the
  interaction raycast) and has `walk_to`, `aim_at`, `press_action`, `key`, `look`, `click` and `screenshot`, logging
  the on-screen prompt at each step. `playtest_order.tscn` plays the order loop: select your group's piece on the map
  floor (E), look at the Chapel (the way there, by the East road point, lights up), E on it, hand the scroll to the advisor, pick "Corrupt the site" with
  the 1-9 key, wait for the courier's report. It prints `ok`/`FAIL` per step and `[playtest] N steps, M failed`, and
  exits with the failure count. Run it windowed (needs a display and GPU; screenshots go to `$PLAYTEST_DIR`, default
  `/tmp/claude-1000/playtest`): `godot --path . --resolution 1280x720 res://tools/playtest/playtest_order.tscn`.
  Without Vulkan add `--rendering-driver opengl3 --rendering-method gl_compatibility`. Stand about 1.9 m back from
  floor markers: the overlord's camera is 2.3 m up and cannot look down past 70 degrees.
- **World ground and navmesh:** the game world is Austin's 2 km map (`art/world/export/world_landscape_2km.tscn`, under
  `World/Nav` in `world.tscn`); the old Terrain3D ground is gone (the addon stays installed). The navmesh is baked and
  saved as `scenes/world/world_navmesh.res`, not at runtime: re-bake after any ground, tower, bridge, ford or water change:
  bake it in the editor: open `world.tscn` (or `world_400m.tscn`), select `World/Nav`, **Bake NavigationMesh** (Austin, 2026-10-13; the bake settings are on that region's NavigationMesh resource). The old custom bake tool is in `tools/deprecated/`. The map floor's picture is `tools/bake_map_illustration.gd`'s.
  **From Blender:** `tools/export_world.sh [2km|400m|all]` exports only the ground (`geo`) and the backdrop to glb and reimports
  (Austin, 2026-10-13); everything else (markers, towers, POIs, bridges, forests, water and its blockers) is authored
  in `art/world/export/world_landscape_<size>.tscn`, per size, and never placed by script. Rebake the navmesh (and the map
  picture after a ground change) by hand. **Water:** no bank walls; `NavigationObstacle3D` blockers under
  `Waters/<body>/Blockers` carve only up to just over the water, so bridges work by being placed, then rebaking. No fords:
  rivers are crossed by bridges only (Austin, 2026-10-13). The old pipeline is in `tools/deprecated/` (one-time use, not maintained).


### Debug Access
- **F3** — Toggle debug overlay (network, players, FPS, corruption sites, units, good-faction growth)
- **Esc** — Open in-game pause menu. All debug actions live in the Debug panel on the right:
  - Add Dummy Player (host)
  - Toggle God Mode
  - Kill Avatar (host)
  - Spawn Enemy at Camera (host) — spawns at wherever the crosshair pointed when you paused
  - Spawn Minion at Camera (host) — same
  - Take Nearest Site (host) — hands the corruption site nearest the camera to you
  - +1 Remains at Tower (host) — a body to raise at your summoning circle
  - Order Avatar to Camera (host) — move order for the released (AI-driven) avatar, same routing as war-table orders
  - Give Me the Paladin (host) — moves him to your tower gate and makes you his owner (at the city centre he would start the gauntlet); scry at a Palantir, then E again to possess him
  - Toggle Aggro Rings (shows each minion's aggro radius, faction-colored)
  - Toggle True Positions (host) — the map floor also shows every group where it really is: pale "TRUE" pieces with
    their status; the prompt gives the next waypoint (Austin, 2026-10-13, for debugging pathing)

  One-shot buttons auto-close the menu. Toggles (god mode, aggro rings) keep it open.
  Host-only buttons are disabled for clients.

---

## 3. File and directory layout

```
res://
├── scenes/                   # .tscn files, grouped by feature
│   ├── player/
│   ├── actors/enemy/
│   ├── actors/player/
│   ├── interactibles/
│   └── world/
├── scripts/                  # .gd files that aren't attached to a single scene
│   ├── interactibles/
│   └── (autoloads, managers, components)
├── assets/                   # Art, audio, fonts (raw imports)
├── addons/                   # Third-party plugins (netfox, etc.) — DO NOT EDIT unless asked
└── project.godot
```

**Rules:**
- Keep a scene's script in the same folder as its `.tscn`, with the same base name (`player.tscn` ↔ `player.gd`).
- One scene = one responsibility. If a scene is doing two things, split it.
- Never put project code under `addons/` — that directory is for installed plugins.
- Asset filenames use `snake_case`. Never put spaces in filenames.

---

## 4. Architecture

- **Networking:** Godot ENet P2P with host authority, using netfox addon for rollback
- **Player scenes:** `scenes/actors/player/overlord/overlord_actor.tscn` (first-person tower body, spawned per-peer) and `scenes/actors/player/avatar/avatar_actor.tscn` (shared 3rd-person body). Both inherit `scenes/actors/player/player_actor.tscn`, which extends `Actor` (CharacterBody3D + state machine + rollback sync).
- **Player authority:** Set via node name matching peer ID
- **Netfox rollback:** State properties synced via RollbackSynchronizer, input gathered in `before_tick_loop`

> **Networking changes — read first:** `docs/technical/netfox-reference.md` is the project-specific cheat sheet for `RollbackSynchronizer`, `RewindableState(Machine)`, `NetworkTime.*`, `_rollback_tick`, authority transfer, damage/HP sync, and the vanilla Godot 4 RPC footguns. Read it BEFORE editing any of those — it'll save re-explaining the same pitfalls. Skip when the change is unrelated to networking.

---

## 5. GDScript style — hard rules

These are non-negotiable. They exist because GDScript is permissive and Claude (and humans) can write code that "works" but breaks in subtle ways at runtime.

### 5.1 Static typing — always

Every `var`, parameter, return type, and collection element type **must** be annotated. No exceptions, no inferred-only declarations for class members.

```gdscript
# WRONG
var speed = 100
var enemies = []
func take_damage(amount):
    health -= amount

# RIGHT
var speed: float = 100.0
var enemies: Array[Enemy] = []
func take_damage(amount: int) -> void:
    health -= amount
```

- Typed arrays: `Array[Card]`, never bare `Array`.
- Typed dictionaries (Godot 4.4+): `Dictionary[String, int]` when supported.
- `@export` and `@onready` vars must have explicit type annotations.
- Use `void` for functions that don't return anything — don't omit it.
- Local variables inside short functions may use `:=` inference when the type is obvious from the right-hand side.

### 5.2 Naming

| Thing | Convention | Example |
|---|---|---|
| Files (scripts, scenes, assets) | `snake_case` | `player_controller.gd` |
| Classes (`class_name`) | `PascalCase` | `class_name PlayerController` |
| Nodes in the scene tree | `PascalCase` | `PlayerSprite`, `AttackArea` |
| Functions and variables | `snake_case` | `current_health`, `take_damage()` |
| Private members | `_leading_underscore` | `_internal_state` |
| Constants and enum members | `CONSTANT_CASE` | `MAX_SPEED`, `State.IDLE` |
| Signals | past-tense `snake_case` | `health_changed`, `enemy_died` |

Signals describe **what happened**, not what should happen. `health_changed`, not `change_health`.

### 5.3 Script file order

Follow Godot's recommended order so files are scannable:

```gdscript
class_name MyClass
extends Node

## Docstring goes here, with two ##.

# 1. Signals
signal health_changed(new_value: int)

# 2. Enums
enum State { IDLE, MOVING, ATTACKING }

# 3. Constants
const MAX_HEALTH: int = 100

# 4. @export vars
@export var speed: float = 200.0

# 5. Public vars
var current_health: int = MAX_HEALTH

# 6. Private vars
var _state: State = State.IDLE

# 7. @onready vars
@onready var _sprite: Sprite2D = %Sprite

# 8. Built-in virtual methods (_ready, _process, _physics_process, _input...)
func _ready() -> void:
    pass

# 9. Public methods
func take_damage(amount: int) -> void:
    pass

# 10. Private methods
func _update_state() -> void:
    pass
```

### 5.4 Node references — use `%UniqueName`, not `$Path/To/Node`

Mark important nodes as "Unique Name in Owner" (the `%` prefix) in the editor. Then reference them with `%NodeName`. This survives scene refactoring; `$Path/To/Node` does not.

```gdscript
# WRONG — brittle, breaks when the tree changes
@onready var sprite: Sprite2D = $VisualContainer/Sprite

# RIGHT — survives reorganization
@onready var sprite: Sprite2D = %Sprite
```

Use `$Path` only for nodes that are guaranteed direct children and that you're certain will never move.

### 5.5 No Python idioms

GDScript looks like Python but isn't. These are the substitutions LLMs most often get wrong:

| Python-ish (wrong) | GDScript (right) |
|---|---|
| `len(arr)` | `arr.size()` |
| `None` | `null` |
| `arr.append(x)` | `arr.push_back(x)` (or `append`, both work, prefer `push_back`) |
| `True` / `False` | `true` / `false` |
| `print(f"x={x}")` | `print("x=", x)` or `"x=%s" % x` |
| `for i in range(10):` | `for i in range(10):` (this one works) |

### 5.6 Other rules

- Tabs for indentation, not spaces.
- One statement per line.
- No magic numbers — use `const` or an enum.
- `@warning_ignore` is **banned** unless the line above states, in a comment, exactly why the warning is a false positive.
- Use `assert()` for preconditions in development builds.

### 5.7 Editor-first — nodes live in scenes, not in code

Austin's rule (2026-10-09): "Nodes should never need to be created from code unless they are explicitly a dynamic
asset, i.e. new troops being made from corpses."

**Editor-first: never construct nodes in code unless they are genuinely dynamic; dynamic things instantiate authored scenes.**

- Everything static (looks, meshes, lights, collision shapes, UI panels/labels/buttons, camera rigs, child helper
  nodes, audio players) is a node in a `.tscn` (or a `.tres`), so it can be seen and edited in the Godot editor. Code
  finds it with `%UniqueName` or an `@export` reference and only drives its properties (text, colour, visibility).
- Dynamic things (units, bodies, a piece per reported group, a marker per known point, a crate per good, a button per
  choice) are created with `PackedScene.instantiate()`. The scene is authored, internals and all; hand the scene to the
  script with an `@export var thing_scene: PackedScene` set in the owning `.tscn`. Never `Node.new()` plus
  `add_child()` plus property setup.
- A material or mesh that code mutates per instance (tint by owner, size by radius) is a `sub_resource` with
  `resource_local_to_scene = true`, so each instance gets its own copy.
- Node-typed `@export`s in a hand-written `.tscn` need `node_paths=PackedStringArray("name")` on the node line, or
  they load as `null`.
- Data-only objects may be built in code (RefCounted/Resource data, `Image`/`ImageTexture` from terrain,
  `ImmediateMesh`/`ArrayMesh` line geometry refilled from data, `AudioStreamGenerator`, `AudioServer` buses, typed
  Dictionaries). Say why in a one-line comment.
- Tools (shot rig, playtests, tests, `scripts/build/`) may build nodes. The audit of every construction site and its
  verdict is `docs/technical/editor-first-audit.md`.

---

## 6. Scenes (`.tscn` files) — handle with care

The `.tscn` file format is text-based but **fragile in specific ways**: renumbering subresource IDs, restructuring an existing node tree, or touching large auto-generated blobs (animation tracks, navmesh data) can silently corrupt the scene. *Appending* new instances or new built-in nodes following an existing pattern is safe.

**Default to editing `.tscn` directly when the change is:**
- Instancing a scene as a child of a parent scene (one new `[ext_resource]` + one `[node ... instance=ExtResource(...)]` block, optionally with a transform)
- Adding a new built-in node (MeshInstance3D, Area3D, CollisionShape3D, …) as a child, including new `[sub_resource]` blocks Claude introduces for it
- Setting or changing an exported property on an existing node (`speed = 200.0`, `material_override = SubResource(...)`)
- Adjusting an existing node's transform
- Creating a brand-new small inherited scene that mirrors an existing pattern (greybox interactibles, simple props)

**Hand off to the user for in-editor work when the change involves:**
- Reordering or renumbering existing `[ext_resource]` / `[sub_resource]` IDs
- Restructuring an existing node hierarchy (re-parenting, deleting nodes that other nodes reference)
- `AnimationPlayer` tracks, NavigationMesh polygon arrays, baked lighting, GridMap cell data, or other large auto-generated blobs
- Anything where you're uncertain about the on-disk format

**Always:**
- After any `.tscn` edit, ask the user to verify in-editor (don't invoke the Godot CLI yourself).
- When adding a node block, copy an existing block of the same kind as a template and change only what differs.
- Pick a fresh `unique_id` and a fresh `[ext_resource]` `id` (keep the local `<num>_<short>` suffix style of the surrounding file).

Same rules apply to `.tres` files. For scenes that need to be *generated from scratch* with many computed subresources (procedural maps, generated decks), use a build script (`scripts/build/build_<name>.gd`) that calls `PackedScene.pack()` rather than emitting tscn text by hand.

### 6.1 Imported 3D assets — never reference raw `.glb`/`.fbx` from gameplay scenes

For any animated character or configurable mesh, create a sibling inherited `.tscn` next to the import (**Scene → New Inherited Scene**) and reference that from gameplay. Skins/variants get their own inherited scene from the base model. Actor-specific gameplay (hurtbox, weapon bone attachments, state machine) lives on the actor scene, **not** on the model scene.

Animation libraries live in external `.res`/`.tres` files, referenced by the model scene's `AnimationPlayer`. Call clips as `<library>/<clip>` (e.g. `large-male/Attack`, `male_animation_lib/idle`).

Full procedure, layer responsibilities, and current actor audit: `docs/technical/3d-asset-pipeline.md`.

---

## 7. Signals, autoloads, and inter-node communication

### 7.1 Signal-first communication

Prefer signals over direct method calls when a node needs to notify others of state changes. This keeps coupling loose and lets scenes be reused.

```gdscript
# In Player
signal died

func _take_lethal_damage() -> void:
    died.emit()

# In GameManager
func _ready() -> void:
    %Player.died.connect(_on_player_died)

func _on_player_died() -> void:
    show_game_over()
```

- Use the **callable syntax** (`signal.connect(callable)`), not the old string-based `connect("signal", target, "method")` from Godot 3.
- Signal handlers are conventionally named `_on_<source>_<signal>` (e.g., `_on_player_died`).
- Disconnect signals in `_exit_tree()` only if the receiver outlives the sender. Otherwise Godot cleans them up.

### 7.2 Autoloads (singletons) — use sparingly

Autoloads are Godot's singleton pattern: nodes registered in **Project Settings → Autoload** that exist for the lifetime of the game. They're useful but addictive.

**Use an autoload for:**
- An `EventBus` (signal-only router for decoupling distant systems).
- Persistent game state (`GameState`, `SaveManager`).
- Cross-scene services (`AudioManager`, `SceneTransitioner`).

**Do not:**
- Put gameplay logic in autoloads. Logic belongs in scenes.
- Create circular dependencies between autoloads — Godot will hang on boot.
- Access another autoload from `_init()`. Use `_ready()`.
- Call `get_tree().current_scene` from an autoload's `_ready()` — the scene may not exist yet. Use `get_tree().root.get_child(-1)` or defer with `call_deferred`.
- Free an autoload manually. Ever.
- Use an autoload for pure data with no signals or `_process` — use a `class_name` script with `static var` instead.

### 7.3 Dependency injection over global lookup

When a scene needs something from outside itself, prefer to have a parent inject it rather than the scene reaching out via `get_node("/root/...")`. This keeps scenes reusable.

```gdscript
# WRONG — scene now depends on a specific tree shape
func _ready() -> void:
    var inventory = get_node("/root/Main/Player/Inventory")

# RIGHT — parent passes it in
func setup(inventory: Inventory) -> void:
    _inventory = inventory
```

---

## 8. Resources (`.tres`) for data

Use custom `Resource` subclasses for data that designers tweak (item stats, enemy configs, dialogue trees) instead of hardcoding constants or parsing JSON.

```gdscript
class_name ItemData
extends Resource

@export var display_name: String = ""
@export var max_stack: int = 1
@export var icon: Texture2D
```

Designers can then create `.tres` files in the editor and tweak them visually. Code references them via `@export var item: ItemData`.

---

## 9. Godot 3 → 4 gotchas (LLMs hallucinate these constantly)

If you find yourself writing any of the left-hand column, **stop**. The right-hand column is the Godot 4 equivalent.

| Godot 3 (wrong in this project) | Godot 4 (correct) |
|---|---|
| `KinematicBody2D` / `KinematicBody` | `CharacterBody2D` / `CharacterBody3D` |
| `Spatial` | `Node3D` |
| `RigidBody` (3D) | `RigidBody3D` |
| `move_and_slide(velocity)` | Set `self.velocity = ...`, then `move_and_slide()` (no args) |
| `instance()` on a `PackedScene` | `instantiate()` |
| `connect("signal", obj, "method")` | `signal.connect(obj.method)` |
| `yield(timer, "timeout")` | `await timer.timeout` |
| `deg2rad()` / `rad2deg()` | `deg_to_rad()` / `rad_to_deg()` |
| `rand_range()` | `randf_range()` / `randi_range()` |
| `randomize()` (manual call) | Automatic — no call needed |
| `BUTTON_LEFT` | `MOUSE_BUTTON_LEFT` |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` |
| `translation` (3D) | `position` |
| `export var x = 1` | `@export var x: int = 1` |
| `onready var x = ...` | `@onready var x: Type = ...` |
| `tool` | `@tool` |
| `setget` | Property `get:` / `set:` blocks |
| `Transform` (3D) | `Transform3D` |
| `Vector3.UP * delta * 9.8` for gravity | Use `get_gravity()` on `CharacterBody3D` or read project setting |

When in doubt, check `godot --version` and consult the actual API docs — do not guess from memory.

---

## 10. Performance and pitfalls

- **Don't `get_node()` in `_process` or `_physics_process`.** Cache references in `@onready`.
- **Use `_physics_process` for movement and physics; `_process` for visuals and UI.**
- **Avoid `await` inside `_physics_process`** — it desyncs with the physics tick.
- **`queue_free()` not `free()`** for nodes during gameplay. `free()` is immediate and unsafe mid-frame.
- **Use object pooling** for high-frequency spawns (bullets, particles, damage numbers). Don't `instantiate()` 60 times a second.
- **Signals are not free**, but they're cheap. Don't avoid them for performance — avoid them for clarity reasons only.
- **`Array.size() == 0` is fine, but `is_empty()` is clearer.**

---

## 11. Workflow expectations for Claude

When making changes:

1. **Read before writing.** Look at the existing scene and any sibling scripts to match conventions before adding new code.
2. **Match the surrounding style** even if it differs slightly from this guide. Consistency within a file beats global purity.
3. **Make the smallest change that solves the problem.** Don't refactor adjacent code unless asked.
4. **Engine settings before tools (Austin, 2026-10-13).** When something misbehaves, understand it as Godot sees it and
   find the built-in setting that fixes it; tell Austin the setting and value (or ask if it sounds right) and let him
   change or approve it. Never build a custom tool, script or pipeline around an engine problem. This has gone wrong
   at least three times: the runtime-generated map floor, the sync/size/areas build pipeline, and the navmesh "refine"
   bake tool (a slow GDScript pass compensating for Recast's `detail_sample_max_error`, a one-field setting). Each was
   expensive, against Godot conventions and slowed the whole development cycle. All are now deprecated.
5. **Don't invoke the Godot CLI** (no `godot --headless --check-only` or similar), except `tools/gut.sh` for the touched system's tests. Hand off to the user for in-editor verification after non-trivial changes.
6. **For scene changes, do the safe edits yourself** (instancing, new built-in nodes, property/transform tweaks — see Section 6). Hand off to the editor only for the unsafe categories listed there. Whichever path you take, summarize the change so the user can verify in-editor.
7. **Surface architectural decisions** — if a request requires a new autoload, a new signal between distant systems, or changing the scene tree shape, propose the change and wait for confirmation before implementing.
8. **Never silently install plugins** into `addons/`. Ask first.

---

## 12. Project-specific notes — Corruption

### Documentation
- **`docs/GDD.md` — the design (v2, clean-slate rework 2026-10-08). Start here.** Only it is Austin's design; everything
  below predates it and is reference only where it disagrees. Source interview: `docs/design/interview.md`.
  Never make creative/content calls; mark stand-ins `PLACEHOLDER:` and list them in `PLACEHOLDERS.md`.
- `docs/one-pager.md` — Visual summary of the old design (reference only, superseded by the GDD)
- `docs/systems/` — One page per major system of the old design (reference only, superseded by the GDD)
- `docs/technical/mvp-roadmap.md` — the June 2026 MVP plan, built on the old design (reference only; new work comes from the GDD v2 tickets)
- `docs/technical/build-phases.md` — tier history (0–4) + standing test checklists for implemented-but-unverified systems
- `docs/technical/changelog.md` — Dated record of shipped work, verification passes, and design calls. Don't read it for current state — it's history; consult only when you need when/why something changed.
- `docs/technical/netfox-reference.md` — Project-specific netfox + RPC cheat sheet. Read before any networking change (see § 4).
- `docs/Corruption_GDD_v0.1.md` — Original GDD (reference, superseded by modular docs)

### Current state

The game is being rebuilt to the GDD v2 (`docs/GDD.md`) on branch `gdd-v2-overhaul`; plan and status in
`docs/technical/gdd-v2-overhaul.md`. Removed as superseded: the summoning currency, the upgrade altar, the numeric
corruption score, divine intervention, the scripted Guardian/Seraph bosses and the Gem, AstralProjection, Avatar
hold-E site capture (`CaptureChannel` / `ChannelState`), the `AvatarClaim` tower station, the Paladin passing to whoever
lands the killing blow, and the four-faction picker.

### World blockout (`art/world/`, `tools/blender/`)

PLACEHOLDER geography built in Blender 4.5 from Austin's sketch: `art/world/source/world_landscape.blend` (the whole
landscape, 1 unit = 1 m, 2000 x 1500 m until the scale test #603; `.gdignore`d, tiles come with #605), `props.blend`
(linked props), `pois/<name>.blend` (one per sketch place, plus `_template`, `holy_site`, `graveyard`) and 32 px nearest-
filtered textures. Austin edits the .blends by hand from here; the old generators are in `tools/deprecated/blender/` and
overwrite hand edits, so don't run them. The four towers are left unplaced (`tower_slot_1..4`). Names and
layout are unconfirmed (#606). See `art/world/README.md`.

**Update 2026-10-09 (second version):** `source/world_landscape.blend` is AUSTIN'S hand-made map (original:
`source/reference/corruption-map-original.blend`; generated blockout: `world_landscape_generated_placeholder.blend`). +Y is
north. Ground = `geo` (authored at 2000 x 2000 m; the 400 m map is its own file, `world_landscape_400m.blend`); `elder wood`, `northwood`, `Pale River`, `The Still Lake` are position guides only (not in the glb; their stand-in forests and water were grown once and now live in the landscape scenes); the empties were the POI and tower
markers (his spellings, e.g. `Avequel'la`, `Hopes Gate`, `far harbor`); since 2026-10-13 the markers are Node3Ds of the same names in
`art/world/export/world_landscape_<size>.tscn`, edited in Godot, each with its place scene `art/world/pois/<snake>.tscn` (snake_case: lowercase, spaces
to `_`, apostrophes dropped) under it. Placeholder textures came from
`tools/deprecated/blender/texture_austin_map.py`; the ground's texture choice is his vertex paint (`Splat` layer, `add_splat.py`, README "Painting the ground"); geometry untouched, checksummed. POI files with no marker yet: `northwood`, `old_gate`,
`elder_woods`, `holy_site`, `graveyard`. Tower markers: `Volcano Tower`, `Forest Tower` (plus the `Avequel'la` and `Naf Ishun` POI markers); see README "Tower locations". No roads or scale figure in his file.

### Resource-driven data (Tier 4 refactor)

Gameplay data lives in `.tres` files under `res://data/`, authored as custom `Resource` subclasses. Code references them via `@export` — never by string path or metadata. Dictionaries of magic strings were replaced with typed fields during the Tier 4 refactor; prefer that pattern for new systems.

| Resource class | Script | Directory | Purpose |
|---|---|---|---|
| `AbilityData` | `scripts/ability_data.gd` | `data/abilities/` | Avatar ability stats + effect scene |
| `SiteType` | `scripts/sites/site_type.gd` | `data/sites/` | Corruption site types: capability, threshold, timings |
| `MinionType` | `scripts/minion_type.gd` | `data/minions/` | Minion/enemy stats (incl. bosses) |

### Ability architecture

Each avatar ability is an `AbilityEffect` subclass (scripts/abilities/<id>_effect.gd) attached to a scene (`scenes/abilities/<id>.tscn`). `AvatarAbilities` instances the scene, calls `activate()`, and aggregates combat queries (damage multiplier, lifesteal, invisibility, channel state) across the `Array[AbilityEffect] _active`. To end an ability early, call `abilities.cancel(&"ability_id")`.

### Corruption sites (GDD §7)

Corruption is not a resource: there is no score. `CorruptionSite` (`scenes/sites/corruption_site.gd`, group
`&"corruption_sites"`) is host-authoritative presence capture: allied strength inside `radius` (each unit's
`MinionType.strength`; the Paladin counts `AVATAR_STRENGTH`) must meet the type's threshold, then progress runs at
`strength / threshold` speed. Contested (two sides present) freezes it; a rival undoes your progress before adding
theirs; the good faction alone purifies; nobody present slips it back. Holding a site grants its `SiteType.capability`
(`SiteCapability` constants) — ask `GameState.has_capability(peer, cap)` / `count_capability`. Each tower has a
permanent `TowerSite` held by its owner (sackable, never lost). `GameState.site_changed` fires on every peer (beacons,
tower restoration). `GoodFaction` (world node) raises every threshold over time, darkens sites and ends the match in a
draw.

### Information, orders and groups (GDD §3–§5)

- **No free information.** Each player's `WorldModel` (`scripts/knowledge/world_model.gd`, on their own machine) changes
  only through `KnowledgeManager` reports: groups at their own tower gate (live), couriers and groups coming home,
  beacons (`site_changed`, seen by all), and what the Paladin's controller sees. The simulation never reads it.
- **Neighbours (Austin, 2026-10-13):** "Get rid of the roads mechanism ... add a type to all walkable locations, build
  a node tree of neighbors, and then the walk paths from each can be emergent" (roads as models may come back later).
  Every walkable place is a `MapPoint` under `World/MapPoints` with a `kind` and `neighbors` (`Array[MapPoint]`, picked
  in the Inspector; two-way: A–B counts if either lists the other). `PointGraph` (`scripts/map/point_graph.gd`) finds
  the shortest way along neighbours (Dijkstra, cost = straight-line distance) through the points the player knows; an
  order's `route` is where each point on that way stands, per group (`routes`/`paths`). A group walks it point to point
  (`GroupManager`) and the navmesh finds the way between two points; couriers do the same
  (`KnowledgeManager._by_neighbors`: point stops with nothing to hand over). The shipped neighbours are stand-ins (one
  pair per old road). Tests: `tests/unit/test_point_graph.gd`, `tests/component/test_point_routes.gd`.
- **Groups** (`scripts/groups/`): every player unit is in a `UnitGroup` (host-side, `GroupManager` node in the world).
  Orders go to groups: walk the route's points, then the goal (`OrderGoal`): hold (`GO_HERE`, `CORRUPT`), watch and
  come home (`ASSESS`), or a registered `goal_handlers` callable (haul, capture, the dead, offers). A group that can't
  reach its next point, or gets no closer for `GIVE_UP_SECONDS` (fighting pauses it), stops and forms ranks
  (`status = &"stuck"`, `stuck_pos`; snapshots carry `progress`: en_route / arrived / stuck / returning / holding) until
  new orders (Austin, 2026-10-13, #626). Units log sightings into their group's log; a
  report is `GroupManager.make_report(group)`.
- **Couriers**: a pool per player (`KnowledgeManager.get_couriers_home`, starting `MatchConfig.STARTING_COURIERS`).
  `request_dispatch(order)` (owner) → host spawns a courier that visits each group's believed position, hands over the
  order, takes the group's report, walks any scouting route, and reports at home (`courier_arrived_home`). Couriers
  killed by a rival count as captured (`courier_lost`; readable with `can_read_couriers`). `CourierErrand`
  (`scripts/knowledge/courier_errand.gd`, #627): a courier that gets no closer to its stop turns home and reports what it
  could not do (`undelivered`, desk records of kind `courier`); blocked on the way home it stops and is reported lost
  (`courier_stranded`); a group it was sent to, seen in line of sight, is recognised (its state comes home; a check
  needs nothing more). Groups with
  `auto_courier` send a runner home on the first hit. Training: `request_train_courier()`.
- **The map floor** (`scenes/map/`, `MapFloor` in each tower, 14 m on the hall floor) is an authored scene (Austin,
  2026-10-13): `illustration` is the background texture; every point marker (`Markers/*`, `map_point_marker.tscn`,
  `point_id`, `label_text`, `disc_color`) and neighbour link (`Links/*`, `map_link_line.tscn`: a straight strip between
  its `From` and `To` ends, editable children) is a node in `map_floor.tscn`. The root's "Copy map points and links"
  inspector button (open `map_floor.tscn` first), or `godot --headless --path . res://scripts/build/build_map_floor.tscn`,
  adds a marker for each `World/MapPoints` point and a line for each neighbour pair that the floor lacks (markers scaled,
  a line's ends on its markers); existing ones are left alone unless `overwrite_on_copy` (`OVERWRITE=1`). In play, code
  only shows known points and links, highlights, and draws pieces, pencil and ink.
  `MapPoint`s (`World/MapPoints`) are known at start or discovered by reports. A point with a `location` (its place's marker in the landscape) stands at that place's `Arrival`
  marker, a Marker3D in the place's POI scene (`art/world/pois/<place>.tscn`) that Austin moves to where it counts as reached (2026-10-13); tower points stand at their tower's courier gate. `MapPiece` chess pieces from beliefs (E
  select, LMB move by hand); looking at a point while authoring lights up the way there (`MapFloor.plan_to`, the
  markers' and links' `Highlight`); E on it = destination → a scroll in hand (`OverlordActor.held_order`, Q tears it up; its route
  pencilled along the floor's links) → the advisor (`advisor_handoff.gd` + `AdvisorDialogue`) asks the goal and
  dispatches. Sent orders darken in ink. Debug: `KnowledgeManager.INSTANT_COMMANDS`. Tests: `tests/unit/test_world_model.gd`; milestone `tests/integration/test_orders.tscn`.
- **Expected state (Austin, 2026-10-09):** a unit that leaves the tower's range never becomes unorderable or "stale".
  `request_dispatch` gives each ordered group a `WorldModel.expectations[gid]` (path = where the map had it + the
  route; position walks the path at `EXPECTED_SPEED` from the order, clamped at the destination). The piece stands at
  `WorldModel.group_position` and is drawn translucent (`MapPiece.belief` = `&"expected"`). It becomes `&"missing"`
  (grey, "?") only when information contradicts: a courier fails to find the group where expected and along its route
  (`failures` in the report -> `mark_missing`). A report on the route confirms it (`&"confirmed"`, re-anchored; looks
  confirmed `CONFIRMED_SECONDS`, then extrapolates again); a report far off the route or with a different goal
  replaces the expectation with what was seen; "arrived" or "came home" ends it. Age alone never marks a piece
  missing (`stale` only adds "old news" to the prompt). Couriers go to `group_position` (the old code used the last
  report, so a group that had left the gate was never found, the order never arrived, and the map showed it at the
  gate forever), then search `COURIER_SEARCH_POINTS` places along the route (`CourierArrivalState._begin_search`)
  before failing. A courier snapshot taken as an order is handed over carries `before_cmd` so the group's old goal is
  not read as a contradiction. `OrderGoal.Goal.CHECK` ("Check that my orders were followed", offered for any group
  scroll) sends a courier to the expected positions to take reports with `order.check = true`: no `set_order`, no
  expectation change, stage `&"checked"`. Own pieces are always selectable (`is_mine`).

### Desk (`scripts/interactibles/desk.gd`)

`Desk` is one per tower (`tower.tscn`, hall floor). E at your own desk (`is_active_for_local_peer`) opens a code-built book
UI: tabs for "All" (newest first, ticks as mm:ss), one per record `kind` in `WorldModel.records`, and a Notes page bound to
`WorldModel.notes`. It claims the modal lock, frees the mouse, disables the rig's `PlayerInput`, refreshes on
`record_added`, and closes on Esc / E / Q (E/Q ignored while typing in Notes). Test: `tests/component/test_desk.gd`.

### Balcony and day/night (`scripts/interactibles/balcony.gd`, `scripts/day_night.gd`)

`Balcony` is one per tower (`tower.tscn`, on the west balcony, hall floor), owner-only like the desk. E takes the camera to
a code-built lookout (`LookoutPivot` -> `LookoutPitch` -> `LookoutCamera`, 90 deg, far 1500) five metres above the post,
facing the map centre; mouse or right stick turns it, E / Q returns. Debug: with the project setting `corruption/debug/free_lookout` on (Austin, 2026-10-13; off by default)
the lookout is a free camera over the whole map (WASD where you look, Space/C up/down, Shift faster). It claims the modal lock and calls
`set_overlord_active(false)` / `PlayerInput.input_enabled`, restoring both on close. Beacons (`CorruptionSite`) are
unshaded with `disable_fog`, so they read from there day or night. `DayNight` (`world.tscn`, one node) is the host's clock
(`time_of_day` 0 = midnight, 0.5 = noon, `DAY_SECONDS` long), pushed to clients with a reliable RPC on connect and every
`SYNC_SECONDS`; it rotates `World/Atmosphere/DirectionalLight3D` (a moon by night) and tints light, sky and ambient.
**Flavour only** until the open question (#574) says otherwise. Tests: `tests/component/test_balcony.gd`, `test_day_night.gd`. Shot rig:
`SHOT_GIVE_SITE=SiteChapel SHOT_TIME=0.95` in `tools/shots/shot.gd`.

### Mirror (GDD §10, `scripts/interactibles/mirror.gd`)

Live calls and recorded messages; each tower's mirror belongs to `Tower.owner_peer_id` and only its owner uses it. E at your
mirror -> pick a rival (A/D) -> E **rings** their mirror (`GameState.mirror_ring`); their mirror glows and chimes (stand-in
look/sound, `_setup_ring_effects`) until they answer with E, you hang up (E/Q), or `RING_TIMEOUT` passes. Answered: `State.LIVE`,
both mirrors show the other player's ghost on `mirror_stage.tscn`, driven by streamed pose frames (`GameState.mirror_live_pose`,
unreliable, `LIVE_POSE_RATE`) plus voice chunks (`mirror_live_audio`, int16, downsampled); E on either side ends it
(`mirror_call_end`). Unanswered or busy: the caller is told and it falls straight into `RECORDING` (10 s max) -> `PREVIEW` ->
`deliver_mirror_message` as before. CALLING/LIVE/RECORDING/PREVIEW hold the modal lock so E works while looking away.
**Poses are skeleton data, not animation names:** `MirrorCodec` (`scripts/mirror_codec.gd`) packs the model's root transform
relative to the mirror plus every `Skeleton3D` bone rotation (int16 quaternion) into one `PackedByteArray` frame;
`MirrorMessage` stores recorded frames as `pose_data` / `pose_frame_size`. The ghost's AnimationPlayer is stopped and
`MirrorCodec.apply_pose` writes the bones. All RPCs are `rpc_id` to the target peer; the sender id comes from
`get_remote_sender_id()`. Tests: `tests/unit/test_mirror_codec.gd`, `tests/component/test_mirror.gd` (real two-peer streaming is untested).

### The Paladin (GDD §8, `scenes/actors/player/avatar/`)

One shared `AvatarActor` (`World/Avatar`), always awake: unowned he fights for the good faction. Children added in code:
- **`PaladinHold`** (`paladin_hold.gd`, host-authoritative, synced): *takeover* — while his HP is at or below
  `TAKEOVER_HP_FRACTION`, player troop strength within `TAKEOVER_RADIUS` (same counting as `CorruptionSite`) that meets
  `TAKEOVER_THRESHOLD` builds that player's `takeover[peer]`; his company present freezes it; contested = most strength
  wins, ties freeze (stand-in for #573). *Overpower* — a Palantir viewer with more `AVATAR_CONTROL` sites than his owner
  calls `request_overpower()`; it runs while they keep looking. *Hold* — `hold` (0..1) fades over `HOLD_SECONDS` unless
  he is inside one of his owner's held sites (towers count); at 0 the good faction has him back.
- **Zero HP** (`AvatarActor._die`): owner → -1 (controller dropped), no teleport; after `RECOVER_DELAY` he gets up in
  place at `RECOVER_HP_FRACTION`. HP changes from outside combat (recovery, regen, a new owner's full heal) are queued
  in `_pending_hp` / `heal()` and applied inside his `_rollback_tick` on the host, or netfox restores the old value.
- **Attacks** (Austin, 2026-10-14): left mouse is a light string (`AttackState` -> `LightAttack2State` -> `LightAttack3State`),
  right mouse the strong attack (`HeavyAttackState`); each `AttackState` node names its clip, `damage_multiplier`, and
  `next_light`/`next_heavy` from `combo_window_start` (decided from held, synced input). Abilities are on 1 and 2.
- **Control tiers** (`get_control_level` = 1 + owner's `AVATAR_CONTROL` sites, capped; unowned = max): `can_use(action)`
  gates run/jump/roll/attack in `PlayerState` and abilities in `AvatarActor` + `AvatarAbilities` (host).
  `strike(target, dmg)` is the one place his blows land; below `RESIST_GOOD_BELOW_LEVEL` it refuses good-faction targets
  (`resisted` signal + a "He resists" flash). Table: `CONTROL_UNLOCKS` (stand-in for #582).
- **`AvatarAI`** drives him whenever nobody does: owned, it follows courier routes and fights within his tiers;
  unowned, below `RECOVER_BELOW_FRACTION` it walks him to the city centre (`holy_site` group node, else the origin) and
  regenerates him there, and at full strength hunts the nearest held non-tower site.
- **Palantir** (`scripts/interactibles/palantir.gd`): anyone scries (E, Q to leave); the owner presses E while scrying
  to possess; others may E to overpower. It stands on the tower's second floor where Austin placed it, with a 1 m
  trigger sphere: the interaction ray (3.5 m) never hits an Area it starts inside, so a bigger sphere made it dead
  up close. Tests: `tests/component/test_palantir.gd`; milestone (the interaction ray) `tests/integration/test_palantir.tscn`. Viewers are seat-coloured orbs at their cameras (`_update_watcher_orbs`).
- **`PaladinVoice`** (`paladin_voice.gd`): proximity-free voice among `get_paladin_voice_peers()`, the mirror's
  capture-bus + `MirrorCodec` approach (bus `PaladinMic`). Real multi-peer voice is untested.
- Tests: `tests/component/test_paladin.gd`, `test_site_encounter.gd`.

### Endgame (GDD §9, `scenes/world/places/holy_site.gd`)

`HolySite` (`World/Places/HolySite`, group `holy_site`, city centre) watches the Paladin: when his owner has him alive within
`radius`, `start_gauntlet` runs. The other players, weakest first (`strength_of`: held non-tower sites, boss-type sites weigh
`BOSS_SITE_WEIGHT`), each play a **`BossActor`** (`boss_scene`, Austin 2026-10-13) as that turn's boss, hp and damage scaled by
strength (`_scale_boss`). Each boss that dies brings on the next; none left -> `GameState.announce_win(owner)`. If the Paladin
dies (`AvatarActor.died`) the current boss's player takes him (`set_avatar_owner`, deferred past his own owner wipe), the
gauntlet ends and he is pinned at that player's tower gate (`PLACEHOLDER: #576`). Losing his owner some other way aborts.
`GoodFaction`'s draw step calls `HolySite.lock_all`. State is mirrored in static vars (`HolySite.state`, `boss_peer`, ...) for the
F3 overlay.
- **`BossActor`** (`scenes/actors/boss/`, inherits `player_actor.tscn` like the Paladin): spawned on every peer by the `_spawn_boss`
  RPC as `HolySite/Boss<peer>` and freed by `_free_boss`. Netfox predicts the driving peer's `BossInput` (`input_dir`,
  `attack_pick`) and `BossCamera` (an `AvatarCamera`); the host is state authority (`attack_index`, `attack_time` are rollback
  state). `take_control(peer)` sets input/camera authority and idles that peer's overlord (and its HUD); `release_control()`
  hands the view back. Allegiance = the boss's peer. Never staggered; walk only. Blows to it queue in `incoming_damage` (applied
  in its rollback tick, as the Paladin's are).
- **Attacks** are `BossAttack` resources (`data/bosses/placeholder/`, all PLACEHOLDER): windup (shown by `TellArea`/`TellLabel`
  and a body glow), active (`BossAttackState` -> `strike_targets`, host only, a box in front of the model, once per target),
  recovery. Keys are the attacks' `input_action`s.
- **`BossAI`** drives it on the host when nobody plays it: a CPU seat (`DebugManager.is_dummy`) from the start, or a boss whose
  peer disconnected (`HolySite._on_peer_disconnected` -> `release_control`). Walks at the Paladin, random attack in reach.
- `data/minions/boss_form.tres` survives only for the runestone's sealed Dark Lord. Real two-process play is untested.
Tests: `tests/component/test_holy_site.gd`, `test_boss_actor.gd`; milestone `tests/integration/test_endgame.tscn`.

### Treasure room and ledger (`scripts/interactibles/treasure_room.gd`, `ledger.gd`)

Each `tower.tscn` has a `TreasureRoom` (a MultiMesh of crates, one per good up to `MAX_CRATES`, plus a "Goods: N" plaque, driven
by `MinionManager.get_treasury(tower owner)`; invisible unless the tower is yours) and a `Ledger` interactable (E opens a
panel: the treasury, then `WorldModel.ledger` entries newest first with their age; modal like the desk). The ledger fills
from `report["resources"]`; groups note the resource sites they pass (`UnitGroup.seen_resources`) so a haul reports the mine.
Test: `tests/component/test_treasure.gd`.

### Getting better (GDD §5, `scripts/groups/`)

- **Experience:** `GroupManager._gain_experience` — a kill credits the killer's nearest group within `KILL_CREDIT_RADIUS`
  (`Training.XP_PER_KILL`), fighting earns `XP_PER_FIGHT_SECOND`. Crossing a `Maneuver.experience_required` learns it.
- **`Maneuver`** (`maneuver.gd`, `data/maneuvers/*.tres`, placeholders, #581): recorded only, no combat effect yet. Learning
  writes a `maneuver` record on the desk (reports carry `"records": [{kind, title, text}]`).
- **Teaching:** the advisor's "teach" option -> `KnowledgeManager.request_teach` -> `GroupManager.begin_teaching`: the
  best-taught leader at home teaches one maneuver to the home group that knows fewest; both groups are busy
  `Training.TEACHING_SECONDS` (`UnitGroup.busy_seconds`) and refuse orders. Succession keeps some maneuvers (already built).
- **Relics:** `Relic` (`relic.gd`, `data/relics/*.tres`, placeholders, #580) lie at `RelicPlace` nodes under `World/Places`.
  Goal `OrderGoal.Goal.RETRIEVE` ("bring back what lies here", offered at sites) -> `FieldWork._retrieve` picks one up
  (`carrying = &"relic"`, `carry_amount` = relic index); unloaded at home it calls `Relic.apply` (sets `UnitGroup.auto_courier`;
  the old route-point relic does nothing now, a placeholder) and writes a `relic` desk record. A fallen carrier drops it back (`RelicPlace.restore`).
- Offers: groups with `MinionActor.parley_mode` do not attack nobles; captures skip nobles.
- **MVP switch (Austin, 2026-10-13, #632/#563):** `MatchConfig.humans_kill_only` (static var, default true; tests reset it in
  `StageTest.after_each`). On: no `CAPTURE`/`OFFER` goals offered (`OrderGoal.goals_for`, advisor), their handlers finish at once,
  `capture_mode`/`parley_mode` no longer spare humans (they kill), no thralls at a chapel (`_held_chapel`), and a `ResourceSite`
  is worked only by one of your undead (`GO_HERE` posts them there; no villager overseers spawn). Off restores all of it.
- Test: `tests/component/test_growth.gd`.

### Interactable focus — raycast-pull, not poll-push

**Advisor placement (Austin, 2026-10-09):** the advisor no longer follows the overlord. When the overlord is within `STATION_RANGE` (advisor_placement.gd) of any `Interactable` in his tower he walks to a navmesh spot beside it, off the map floor's square plus a margin, clear of the overlord-station line, and faces the overlord; otherwise he stays put (or goes home if he is on the floor). `scenes/actors/minion/advisor_placement.gd` + `advisor_idle_state.gd`/`advisor_follow_state.gd`; spacing numbers are `PLACEHOLDER: tuning` consts.

Interactables (war table, palantir, altar, summoning circle, advisor handoff, gem, gem site, mirror, etc.) all extend `Interactable` (Area3D, `scenes/interactibles/interactable.gd`). Focus is driven from the **player side**, not from each interactable.

Each local player rig (`OverlordActor`, `AvatarActor`) carries:
- A `RayCast3D` named `InteractionRayCast` parented under `Camera3D` (target_position = -3.5m forward, `collision_mask = 17` = world bit + interactable bit, `hit_back_faces = false`, `collide_with_areas = true`). Updates every physics step by Godot.
- An `InteractionFocus` controller node (`scripts/interaction_focus.gd`) wired to that raycast and the rig. Each `_physics_process` it reads the ray, walks up the hit collider's parent chain to find an `Interactable` ancestor, and `_assign`s focus — calling `set_focused(false, ...)` on the previously-focused interactable and `set_focused(true, owner_actor)` on the new one. After assigning, it calls `_refresh_prompt()` on the current target so subclasses with state-dependent prompts (resource counts, mirror state, war table selection size) stay live.

Interactable areas live on `collision_layer = 16` (bit 5) so the ray hits them; the world (bit 1) is also in the mask so walls block line-of-sight. A nested solid (e.g. the war table's `Solid` StaticBody3D, layer 1) gets hit first when the player aims at the visible mesh — the walk-up still resolves to the parent `Interactable`, so focus lands on the right node.

Subclass surface: just `set_focused(focused, who)` is called by the controller. Inside `set_focused`, the base updates `_player_in_range` / `_avatar_in_range`, flips `_is_focused`, and refreshes the prompt. Subclasses override `get_prompt_text()` / `get_prompt_color()` / `_on_interact()` and call `_refresh_prompt()` when their state changes mid-focus.

**Modal lock** — `Interactable._modal_holder` is a static var. Subclasses that take over the camera or block out the world (war table, palantir scry) call `_claim_modal()` on entry and `_release_modal()` on exit; while a modal is held, `InteractionFocus` pins focus to the holder regardless of where the ray points, so the player can still press E/Q to exit. Stateful interactables that DON'T take over the camera (upgrade altar, summoning circle, mirror) leave their `_active` flag in their own state and let normal raycast focus apply — looking away hides the prompt, looking back restores it with the current state.

**Pause integration** — `in_game_menu.gd:_set_gameplay_input(false)` disables `process_mode` on every `Interactable` and `InteractionFocus` in the tree and calls `InteractionUI.hide_prompt()`. It deliberately does NOT call `set_focused(false)` — pause should not tear down active modal modes. Resume re-enables and `show_prompt()`s the existing source.

**Player rig pinning during war table** — `PlayerActor.pin_transform(xform)` / `unpin_transform()` writes a target transform that gets re-applied at the end of every `_rollback_tick`. Plain `global_transform = ...` is fine for one-shot teleports (avatar respawn) but doesn't survive the rollback recorder during continuous activity — pinning makes `on_record_tick` capture the pinned value so subsequent `on_prepare_tick` restores keep it. War Table uses this to plant the overlord at the StandPoint while the camera takes over.

### Per-peer game state APIs (`GameState`)

- **Allegiance, not faction, decides hostility.** `Actor.get_allegiance()` is the owning peer id (minions:
  `owner_peer_id`; the Paladin: his owner; overlords: themselves) or `GameConstants.GOOD_SIDE` (-1) for the good
  faction. MVP: every player is Undead (`PLAYABLE_FACTIONS = [UNDEATH]`), so factions only pick rosters and art.
- **Towers are picked (Austin, 2026-10-13, #630):** in the lobby each seat (players and, by the host, CPUs) picks one of the
  four towers on its player panel (`PlayerPanel.TowerSelector`; names are the tower markers' in the landscape scene, read by
  `TowerPicks.slot_names`). One seat per tower, Start stays disabled until every seat has one, and picking clears your ready like a
  faction change. `Lobby.player_towers` syncs like the faction (`_sync_all_state`, late joiners included) and `Lobby._on_start_pressed`
  sends `GameState.sync_tower_picks` -> `GameState.tower_picks` (peer -> `Tower.slot_index`) and `player_slots`. The seat's slot is the pick
  (`MultiplayerManager.claim_slot` / `get_player_slot`; no picks = join order, for the sandbox and tests). At match start every peer's
  `MinionManager._setup_minions_node` calls `TowerPicks.remove_unpicked`: a tower in no pick leaves the tree whole (building, spawn point,
  trickle, map floor, beacon, `TowerSite`, advisor) with its rally point and its gate `MapPoint` (the other points drop it as a
  neighbour, the floors drop its marker and links). Pair rally points by the tower's authored `slot_index`, never by list position.
  The baked navmesh still has the removed towers' footprint. A 2-player match runs on two towers. Tests: `tests/unit/test_tower_picks.gd`,
  `tests/component/test_tower_pick_match.gd`.
- `GameState.get_player_color(peer)` — seat colour (by tower slot); `get_player_name(peer)`.
- `GameState.get_held_sites(peer)` / `count_held_sites(peer)` / `has_capability(peer, cap)` — see Corruption sites.
- `GameState.match_pace` (`MatchConfig.Pace`, picked by the host in the lobby) scales unit speed and the good
  faction's growth clock. `GameState.world_size` (`MatchConfig.WorldSize`, picked beside it) decides which world scene loads
  (`MatchConfig.world_scene()`); tests and the shot rig take `WORLD_SIZE=400m|2km|6km`.
- `GameState.avatar_owner_peer_id` (-1 = the good faction has him) and `avatar_peer_id` (controller, -1 = AI-driven).
  `request_possess_avatar()` (owner only, from a Palantir) / `request_recall_avatar()` (Q in his body);
  `set_avatar_owner(peer)` on the host (also drops the controller). Ownership moves only through `PaladinHold` and
  zero HP; see "The Paladin".
- Palantir viewers: `GameState.request_set_watching(bool)` (host keeps `watchers`, mirrored to all), `is_watching`,
  `watcher_positions` (remote viewers' cameras), `get_paladin_voice_peers()` (viewers + controller).
- Summoning costs remains, not currency: `MinionManager.get_remains(peer)` / `add_remains` /
  `request_raise_from_remains(type)`; `spawn_unit_for_peer(peer, type, pos)` for system spawns.

### What's built

The GDD v2 overhaul is in progress on branch `gdd-v2-overhaul`; its phase list and status are in
`docs/technical/gdd-v2-overhaul.md`, and every stand-in is in `PLACEHOLDERS.md`.
