# Refactor TODO — Codebase Audit (2026-04-11)

Full audit of all `.gd` files against `CLAUDE.md` style guide. Organized by priority.

---

## Critical Bugs (Will crash or produce wrong behavior)

- [x] **`trait_tag` vs `trait` property mismatch** — `scripts/faction_data.gd` defines `trait_tag` but `scripts/minion.gd:46` and `scripts/interactibles/summoning_circle.gd:39-40` access it as `mtype.trait`. Runtime crash on minion spawn.
- [x] **Minion faces backwards when attacking** — `scripts/minion.gd:113` — `look_at(target_pos)` where `target_pos = global_position - dir` makes minion face away from target. Should be `global_position + dir`.
- [x] **perspective_manager adds wrong model** — `scenes/player/PerspectiveManager/perspective_manager.gd:28` — `world_model_container.add_child(current_view_model)` should be `current_world_model`.
- [x] **enemy_manager return type lies** — `scripts/enemy_manager.gd:18` — Says `-> EnemyActor` but `get_node_or_null()` can return `null`. Callers assuming non-null will crash.

---

## High Priority (Performance / correctness)

### Cache `get_node()` calls out of `_process` / `_physics_process`

Every-frame `get_tree().current_scene.get_node_or_null(...)` calls. Must cache in `_ready()` or `@onready`.

- [x] `scenes/actors/enemy/enemy_actor.gd:67` — EnemyManager lookup in `_physics_process`
- [x] `scripts/minion.gd:65-66,117,141` — MinionManager lookup in `_physics_process` (3 call sites)
- [x] `scripts/territory_manager.gd:67` — MinionManager lookup in `_tick_corruption()`
- [x] `scripts/guardian_boss.gd:59` — TerritoryManager lookup in `_physics_process`
- [x] `scripts/astral_projection.gd:29` — Avatar lookup in `_process`
- [x] `scripts/interactibles/gem.gd:6,17,31` — GuardianBoss lookup in `get_prompt_text()` / `get_prompt_color()` (called every frame)

### Untyped `tick()` parameters in movement states

- [x] `scripts/states/movement/idle_state.gd:3` — `func tick(delta, tick, is_fresh):` → `(delta: float, tick: int, is_fresh: bool) -> void`
- [x] `scripts/states/movement/move_state.gd:3` — same
- [x] `scripts/states/movement/fall_state.gd:3` — same
- [x] `scripts/states/movement/jump_state.gd:6` — same

### Untyped arrays and dictionaries

- [x] `scripts/game_state.gd:18` — `watcher_positions: Dictionary` → `Dictionary[int, Vector3]`
- [x] `scripts/game_state.gd:20` — `influence: Dictionary` → `Dictionary[int, float]`
- [x] `scripts/avatar_abilities.gd:12` — `_cooldowns: Dictionary` → `Dictionary[String, float]`
- [x] `scripts/avatar_abilities.gd:13` — `_active_effects: Dictionary` → `Dictionary[String, float]`
- [x] `scripts/minion_manager.gd:23` — `resources: Dictionary` → `Dictionary[int, float]`
- [x] `scripts/minion_manager.gd:51` — `get_all_minions() -> Array` → `-> Array[Minion]`
- [x] `scripts/minion_manager.gd:59` — `get_minions_for_player() -> Array` → `-> Array[Minion]`
- [x] `scripts/territory_manager.gd:66` — `minion_cells: Dictionary` → `Dictionary[Vector2i, int]`
- [x] `scripts/territory_manager.gd:83` — `cells_to_remove: Array` → `Array[Vector2i]`
- [x] `scenes/actors/enemy/states/attack_state.gd:10` — `_hit_targets: Array` → `Array[Node3D]`
- [x] `scenes/actors/player/states/attack_state.gd:13` — `_hit_targets: Array` → `Array[Node3D]`
- [x] `scenes/actors/player/player_actor.gd:18` — `_watcher_orbs: Dictionary` → `Dictionary[int, MeshInstance3D]`

### Duplicate `move_player()` across movement states

- [x] `scripts/states/movement/move_state.gd`, `fall_state.gd`, `jump_state.gd` all contain identical `move_player()` body. Extract into `MovementState` base class.

---

## Medium Priority (Style guide compliance)

### Missing `-> void` return types (~100+ functions)

Affected in nearly every file. Batch fix file-by-file. Worst offenders:

- [x] All interactible scripts (`avatar_claim.gd`, `gem.gd`, `mirror.gd`, `palantir.gd`, `gem_site.gd`, `ritual_site.gd`, `summoning_circle.gd`, `upgrade_altar.gd`, `war_table.gd`)
- [x] All state scripts (enemy states, player states, actor states, movement states)
- [x] All manager scripts (`minion_manager.gd`, `territory_manager.gd`, `boss_manager.gd`, `enemy_manager.gd`)
- [x] All menu scripts (`main_menu.gd`, `enet_menu.gd`, `noray_menu.gd`, `in_game_menu.gd`, `win_screen.gd`)
- [x] All network scripts (`network_manager.gd`, `multiplayer_manager.gd`, `enet_network.gd`, `noray_network.gd`)
- [x] Core scripts (`player.gd`, `avatar.gd`, `avatar_input.gd`, `avatar_camera.gd`, `camera_input.gd`, `enemy.gd`, `debug_manager.gd`, `debug_overlay.gd`, `lobby.gd`, `interaction_ui.gd`, `minion.gd`)

### Missing explicit type annotations on variables

- [x] `scripts/debug_manager.gd:11` — `_player_scene = preload(...)` → `: PackedScene`
- [x] `scripts/player.gd:3-4` — `const SPEED = 5.0` → `: float`
- [x] `scripts/player.gd:7` — `var gravity = ...` → `: float`
- [x] `scripts/player.gd:14` — `@onready var rollback_synchronizer = ...` → add type
- [x] `scripts/player.gd:16` — `var _animation_player` → `: AnimationPlayer`
- [x] `scripts/avatar.gd:7-8` — `const SPEED`, `const JUMP_VELOCITY` → `: float`
- [x] `scripts/avatar.gd:12` — `var gravity = ...` → `: float`
- [x] `scripts/avatar.gd:19` — `@onready var rollback_synchronizer = ...` → add type
- [x] `scripts/network/network_manager.gd:7-10` — all `const` missing types
- [x] `scripts/network/network_manager.gd:23-28` — 6 vars missing types
- [x] `scripts/network/noray_network.gd:5-6` — `_port`, `_current_host_oid` missing types
- [x] `lobby.gd:3-6` — all 4 `@onready` vars missing types
- [x] `scripts/menus/main_menu.gd:8` — `_is_hosting` missing type
- [x] `scripts/menus/enet_menu.gd:9-10` — `is_hosting`, `networkConnection_configs` missing types
- [x] `scenes/player/PerspectiveManager/perspective_resource.gd:4` — `@export var damage = 10` → `: int`
- [x] `scripts/avatar_camera.gd:28` — `func _input(event)` → `(event: InputEvent)`
- [x] `scripts/camera_input.gd:31` — `func _input(event)` → `(event: InputEvent)`

### Constants using `:=` instead of explicit types

Style guide requires explicit types on all constants. Pervasive across: `scripts/avatar.gd`, `scripts/enemy.gd`, `scripts/avatar_camera.gd`, `scripts/camera_input.gd`, and most files with `const` declarations.

### Magic numbers → named constants

- [x] **Collision layers**: `collision_layer = 4` / `collision_mask = 1` / `collision_layer = 8` in `enemy_actor.gd:27-28`, `minion.gd:51-52`
- [x] **Colors**: Hardcoded `Color(...)` in interactibles, `avatar.gd:145-152`, `avatar_claim.gd:18-19`, `gem.gd:20-25`
- [x] **Death/timing values**: `2.0` in `player_actor.gd:48`, `enemy_actor.gd:66`; `0.1` sync intervals; `0.5` stagger durations
- [x] **Sizes/offsets**: `Vector3(0.3, 0.3, 0.3)` in `avatar.gd:145`, `Vector3(0, 1.5, 0)` in `palantir.gd:65`, `Vector3(0, 8, 8)` in `astral_projection.gd:31`
- [x] **Combat**: `0.3` lifesteal ratio in `scenes/actors/player/states/attack_state.gd:95`
- [x] **Interpolation**: `10.0 * delta` in `enemy.gd:48-49`

---

## Low Priority (Cleanup)

- [x] **Naming**: `scripts/menus/enet_menu.gd:10` — `networkConnection_configs` → `network_connection_configs`
- [x] **Naming**: `scripts/camera_input.gd:3` — `camera_3D` → `camera_3d`
- [x] **Dead code**: `scripts/boss_manager.gd:34-35` — signal connection check against empty `Callable()` always false
- [x] **Logic clarity**: `scripts/states/movement/movement_state.gd:49` — `get_jump() -> float` naming suggests bool
- [x] **Script order**: `scripts/debug_overlay.gd:145` — signal declared mid-file, should be at top
- [x] **Spacing**: Inconsistent ` : Type` vs `: Type` in perspective_manager.gd, movement_state.gd
- [x] **Typo**: `scripts/menus/main_menu.gd:32` — `secondary_menu.is_hosting =_is_hosting` missing space
- [x] **Missing `class_name`**: `lich.gd`, `lich_arms.gd`, `first_person_view_model.gd`, `player_panel.gd` (not strictly required)
- [x] **`$Path` references**: `lich.gd:4`, `lich_arms.gd:4` — `$AnimationPlayer` could use `%AnimationPlayer`
- [x] **Hardcoded strings**: Animation names like `"ArmatureAction"`, `"Idle"` in `lich.gd`, `lich_arms.gd`
