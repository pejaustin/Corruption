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


### Debug Keys
- **F2** — Spawn dummy player (fills next tower slot, up to 4)
- **F3** — Toggle debug overlay (network, players, factions, FPS, influence, minions, territory, boss)
- **F4** — Toggle god mode for Avatar
- **F5** — Force-kill Avatar (test death transfer)
- **F6** — Spawn enemy at camera target
- **F7** — Spawn minion at camera target
- **F8** — Add 10 influence to self

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
- **Player scene:** `scenes/player/player.tscn` — CharacterBody3D with movement state machine, rollback sync, PerspectiveManager
- **Player authority:** Set via node name matching peer ID
- **Netfox rollback:** State properties synced via RollbackSynchronizer, input gathered in `before_tick_loop`

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

The `.tscn` file format is text-based but **fragile**. A misplaced subresource ID or stale `ext_resource` reference will silently corrupt the scene.

**Rules for Claude:**
1. **Prefer creating/modifying scenes through the Godot editor when possible.** If the user is editing in-editor, just write the script and tell them what nodes to add.
2. **If you must create a `.tscn` programmatically**, do it via a build script (`scripts/build/build_<name>.gd`) that runs in the editor or headless and uses `PackedScene.pack()`. The build script is the source of truth; the `.tscn` is compiled output. Never hand-edit `.tscn` line by line.
3. **Never reorder or renumber** `[ext_resource]` / `[sub_resource]` IDs in an existing `.tscn`.
4. When adding a node to an existing scene via text edit, copy an existing node block as a template and change only the necessary fields.
5. After any `.tscn` change, run `godot --headless --check-only` to verify it loads.

Same rules apply to `.tres` (Resource) files.

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
4. **Run validation** (`godot --headless --check-only`, `gdlint`) before saying you're done.
5. **For scene changes, prefer instructing the user** to make them in the editor over hand-editing `.tscn`. If you do edit `.tscn`, explain what you did so the user can verify in the editor.
6. **Surface architectural decisions** — if a request requires a new autoload, a new signal between distant systems, or changing the scene tree shape, propose the change and wait for confirmation before implementing.
7. **Never silently install plugins** into `addons/`. Ask first.

---

## 12. Project-specific notes — Corruption

### Documentation
- `docs/one-pager.md` — Visual summary of the entire game
- `docs/systems/` — One page per major system (combat, overlord mode, factions, territory, bosses, multiplayer, progression)
- `docs/technical/build-phases.md` — **MVP tier tracker with current progress** (start here for what to build next)
- `docs/Corruption_GDD_v0.1.md` — Original GDD (reference, superseded by modular docs)

### Current State (Tiers 0-2 Complete, Tier 3 Scripts Ready)

Tiers 0-2 are fully playable. Tier 3 scripts are implemented but need editor setup.

#### What's built
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
