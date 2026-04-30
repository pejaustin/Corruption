# CLAUDE.md — Godot 4 Project Guide

This file gives Claude Code the context it needs to make informed changes to a Godot 4 project. Read it before writing or editing any `.gd`, `.tscn`, or `.tres` file.

> **Engine version:** Godot 4.x. This project does **not** use Godot 3 — many APIs were renamed in 4.0 and the old names will silently fail or look right but be wrong. See "Godot 3 → 4 gotchas" below.

---

## 1. Project at a glance

- **Game type:** 4-player PvP Dark Lord simulator — 3D third-person (Avatar) + 3D first-person (Overlords)
- **Scripting language:** GDScript only
- **Target platforms:** Desktop
- **Entry scene:** `scenes/tower_scene.tscn` (the main game scene, loaded as GAME_SCENE despite the name)
- **Key autoloads:** `NetworkManager`, `DebugManager`, plus netfox autoloads (`NetworkTime`, `NetworkRollback`, etc.)
- **Game constants:** `scripts/game_constants.gd` — Factions enum, MAX_PLAYERS, faction names/colors
- **Full overview:** `docs/one-pager.md`

---

## 2. How to run, lint, and validate

TBD


### Debug Access
- **F3** — Toggle debug overlay (network, players, factions, FPS, influence, minions, territory, boss)
- **Esc** — Open in-game pause menu. All debug actions live in the Debug panel on the right:
  - Add Dummy Player (host)
  - Toggle God Mode
  - Kill Avatar (host)
  - Spawn Enemy at Camera (host) — spawns at wherever the crosshair pointed when you paused
  - Spawn Minion at Camera (host) — same
  - +10 Influence (host)
  - Cycle Faction (host)
  - Boost Corruption near origin (host)
  - Toggle Aggro Rings (shows each minion's aggro radius, faction-colored)

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
4. **Don't invoke the Godot CLI** (no `godot --headless --check-only` or similar). Hand off to the user for in-editor verification after non-trivial changes.
5. **For scene changes, do the safe edits yourself** (instancing, new built-in nodes, property/transform tweaks — see Section 6). Hand off to the editor only for the unsafe categories listed there. Whichever path you take, summarize the change so the user can verify in-editor.
6. **Surface architectural decisions** — if a request requires a new autoload, a new signal between distant systems, or changing the scene tree shape, propose the change and wait for confirmation before implementing.
7. **Never silently install plugins** into `addons/`. Ask first.

---

## 12. Project-specific notes — Corruption

### Documentation
- `docs/one-pager.md` — Visual summary of the entire game
- `docs/systems/` — One page per major system (combat, overlord mode, factions, territory, bosses, multiplayer, progression)
- `docs/technical/build-phases.md` — **MVP tier tracker with current progress** (start here for what to build next)
- `docs/technical/netfox-reference.md` — Project-specific netfox + RPC cheat sheet. Read before any networking change (see § 4).
- `docs/Corruption_GDD_v0.1.md` — Original GDD (reference, superseded by modular docs)

### Current State (Tiers 0-3 Complete, Tier 4 Scripts Ready)

Tiers 0-3 are playable. Tier 4 scripts are implemented (boss sequence, upgrade altars, rituals, abilities) but need editor setup.

### Resource-driven data (Tier 4 refactor)

Gameplay data lives in `.tres` files under `res://data/`, authored as custom `Resource` subclasses. Code references them via `@export` — never by string path or metadata. Dictionaries of magic strings were replaced with typed fields during the Tier 4 refactor; prefer that pattern for new systems.

| Resource class | Script | Directory | Purpose |
|---|---|---|---|
| `AbilityData` | `scripts/ability_data.gd` | `data/abilities/` | Avatar ability stats + effect scene |
| `UpgradeData` | `scripts/upgrade_data.gd` | `data/upgrades/` | Upgrade altar catalog (5 entries) |
| `RitualData` | `scripts/ritual_data.gd` | `data/rituals/` | Ritual site effects (3 entries) |
| `MinionType` | `scripts/minion_type.gd` | `data/minions/` | Minion/enemy stats (incl. bosses) |

### Ability architecture

Each avatar ability is an `AbilityEffect` subclass (scripts/abilities/<id>_effect.gd) attached to a scene (`scenes/abilities/<id>.tscn`). `AvatarAbilities` instances the scene, calls `activate()`, and aggregates combat queries (damage multiplier, lifesteal, invisibility, channel state) across the `Array[AbilityEffect] _active`. To end an ability early, call `abilities.cancel(&"ability_id")`.

### Boss sequence

`BossManager` (scripts/boss_manager.gd) exports `initial_boss: GuardianBoss`, `seraph_scene: PackedScene` (defaults to `corrupted_seraph.tscn`), and `seraph_spawn_point: Node3D`. Phase 2's `CorruptedSeraph` is an inherited scene of `guardian_boss.tscn` with a different `MinionType` — no runtime `set_script()` tricks.

### Information-warfare layer (`KnowledgeManager` autoload)

The War Table renders an overlord's **belief**, not truth. Each peer has a `WorldModel` (per-peer dict of believed minion sightings, timestamped) maintained by the `KnowledgeManager` autoload at `scripts/knowledge/`. War Table commands route through `KnowledgeManager.issue_move_command(peer_id, minion_ids: Array[int], target_pos)` — note the **selection-based** signature: a draft is for a specific set of minion ids, not "everything you own." Minion deaths fan out via `KnowledgeManager.notify_minion_removed(id)`.

The table uses a **two-click flow**: click a friendly piece on the diorama to toggle it in `WarTable._selected_minion_ids`, click empty map to submit. With `INSTANT_COMMANDS=false`, the submit records a draft entry (`stage`, `spawn_pos`, `source_pos`, `target_pos`, `minion_ids`, `courier_id`); E at the Advisor (`advisor_handoff.gd`) dispatches a real Courier per draft, which travels to the believed source, sets each delivery target's waypoint to `target_pos`, then walks home and despawns.

Two feature flags gate the "full information-warfare" behavior so the rest of the game keeps playing during iteration. Both are `static var` (runtime-mutable, e.g. test harnesses can A/B-toggle without restarting):
- `INFINITE_BROADCAST_RANGE: bool = true` — every minion updates every model every tick (belief ≈ truth). Flip off to tune broadcast range.
- `INSTANT_COMMANDS: bool = true` — commands apply immediately: each selected id's waypoint is set to the target via `MinionManager.command_minion_move`, no courier loop. Flip off to exercise the Courier dispatch path.

`WarTable` (script `scripts/interactibles/war_table.gd`, `class_name WarTable`) exports `map_world_size: Vector2` and `map_world_center: Vector3` directly on the interactable; the setters tunnel to the `Map` child's `WarTableMap` so per-tower regions are configured next to the rest of the table's setup. `WarTableMap` still owns `table_surface_size` and the piece spawner. `WarTableRange` is a `@tool` MeshInstance3D that draws a semi-transparent BoxMesh at the map's effective region so designers can see it in both editor and play.

Isolated iteration harness: `scenes/test/war_table_test.tscn` — runs the **real** `OverlordActor`, `WarTable.tscn`, `MinionManager`, and `MinionActor`s, single-peer via `OfflineMultiplayerPeer`. Edits to `war_table.tscn` propagate. Starter minions are authored as `StartingMinionSpec` Marker3D children under `World/StartingMinions` — set `type_id`/`faction`/`owner_peer_id` in the inspector and the controller spawns one real `MinionActor` per spec on `_ready`. Hotkeys `1`–`4` spawn factioned minions, `F` cycles your faction, `K`/`R` kill/reset, `T`/`B` toggle the flags above, `Esc` releases mouse, `Shift+Esc` quits.

Minion-vs-minion physical collision is intentionally OFF (`minion_actor.gd:COLLISION_MASK_MOVEMENT = COLLISION_MASK_WORLD`); the `NavigationAgent3D`'s RVO avoidance handles spacing instead. This sidesteps the cluster-stop bug where the first minion to reach a shared waypoint would park and physically block late arrivers from finishing their nav path.

Full design: `docs/systems/war-table.md`.

### Interactable focus — raycast-pull, not poll-push

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

- `GameState.get_faction(peer_id)` — authoritative lookup (checks overrides, then player_factions, falls back to round-robin). Use this instead of any per-manager faction resolution.
- `GameState.set_faction_override(peer_id, faction)` / `clear_faction_override(peer_id)` — for debug swap.
- `GameState.get_upgrade_level(peer_id, kind)` / `add_upgrade(peer_id, kind)` — upgrade state lives on GameState, not on nodes' metadata.
- `GameState.grant_eldritch_vision(peer_id, duration)` / `has_eldritch_vision(peer_id)` — ritual-granted temp buff with a ticking timer on GameState.

### What's built (Tiers 0-3)

- P2P lobby with faction selection (4 factions)
- Avatar claim/recall, 3rd-person combat, death → transfer cycle
- Neutral enemies with AI (patrol, aggro, attack)
- Animation-driven hitboxes, host-authoritative combat sync
- EnemyManager for networked enemy spawn/death
- Influence tracking with debug overlay
- MinionManager: spawning, AI (NavigationAgent3D), commands, sync
- TerritoryManager: grid-based corruption spread/decay
- GemSite capture points (minion clear → Avatar confirm → passive influence)
- Hostile takeover (minion kills Avatar → owner becomes Avatar)
- Influence fallback (neutral death → highest influence takes over)
- GuardianBoss (corruption-debuffed, defeat to win)
- AstralProjection spectator overlay for boss fights

#### What needs editor setup
See "Editor TODO" section at bottom of this file for nodes to add in scenes.
