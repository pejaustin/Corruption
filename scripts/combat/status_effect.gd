class_name StatusEffect extends Resource

## Tier G — declarative description of a temporary effect on an Actor.
##
## Authored as `.tres` files under `data/status/`. The runtime live state is
## `ActiveStatus` (an inner class on `StatusController`), which references
## one of these resources by id and tracks `enter_tick` / `last_tick_fired`
## / `stacks` per-actor. The resource itself is shared, immutable from
## gameplay's perspective — never mutate fields after authoring.
##
## Tick model:
## - `duration_ticks` is a count of netfox ticks (30Hz). -1 = until cleared.
## - `tick_interval_ticks` fires `on_tick` every N ticks while active.
##   0 = no periodic tick (purely a stat modifier — slow, silence, etc.).
## - `damage_per_tick` is applied via `Actor.take_damage`, so block / parry /
##   posture / lifesteal / friendly-fire all reconcile correctly. Negative
##   values heal.
##
## Stacks:
## - `max_stacks` ≥ 1. Re-applying an existing status with `stacks < max_stacks`
##   bumps the stack count; behavior at the cap depends on `refresh_on_apply`.
## - `refresh_on_apply` resets the duration window on re-apply (Souls-style
##   bleed: fresh hit refreshes the bleed timer).
##
## Sync:
## - The list of active status IDs is host-authoritative and propagated as
##   a `PackedStringArray` state_property on the controlling actor's
##   RollbackSynchronizer (`StatusController:active_status_ids`). Format per
##   entry is `"<id>:<enter_tick>:<stacks>"`. Resource data itself is constant
##   so clients can re-read fields by id without serializing them.
##
## Hooks:
## - `on_apply` fires once on first apply (or on stack increment if you
##   subclass). `on_tick` fires at `tick_interval_ticks` cadence. `on_expire`
##   fires when the duration runs out OR when `clear` is called externally.
## - The default body of all three is empty — the data-driven path
##   (`damage_per_tick`, `move_speed_mult`, `attack_speed_mult`) covers Tier G.
##   Subclass for special-case behavior (e.g. an effect that also drains
##   ultimate charge per tick).

## StringName id used for catalog lookup. MUST match the `.tres` filename
## (minus `.tres`) for `lookup` to find it.
@export var id: StringName = &""

## Human-readable label for HUD / debug overlays.
@export var display_name: String = ""

## Duration in netfox ticks. -1 = permanent (until manually cleared).
## ~30Hz default tickrate; 90 ticks ≈ 3 s.
@export var duration_ticks: int = 90

## Periodic tick cadence in netfox ticks. 0 = no periodic damage / no tick
## hook firing. The status still expires by `duration_ticks`.
@export var tick_interval_ticks: int = 30

## Per-tick damage applied when `tick_interval_ticks > 0`. Positive harms,
## negative heals (heal applies via `take_damage(-amount)` — Tier H rewires
## to a typed heal channel if needed).
@export var damage_per_tick: int = 0

## Damage type tag forwarded to the victim's `damage_type_resistances`
## lookup in `Actor.take_damage`. Defaults to `&"physical"` for parity with
## untyped attacks.
@export var damage_type: StringName = &"physical"

## Multiplicative movement-speed modifier. < 1.0 slows; > 1.0 hastens.
## Aggregated by `StatusController.get_movement_mult`.
@export var move_speed_mult: float = 1.0

## Multiplicative attack-speed modifier (drives `AnimationPlayer.speed_scale`
## in light_attack_state). < 1.0 slows swings; > 1.0 hastens.
@export var attack_speed_mult: float = 1.0

## Stack cap. 1 = singleton (re-apply only refreshes). > 1 = additive stacks
## (re-apply increments up to this cap).
@export var max_stacks: int = 1

## When true, re-applying the status resets `enter_tick` so the duration
## window starts over. When false, the original duration is preserved (the
## new application is a stack-only event).
@export var refresh_on_apply: bool = true

## Optional cosmetic spawned as a child of the affected actor on apply,
## queue_free'd on expire. Skipped during rollback resimulation (Tier G's
## VFX gate pattern). Designers wire the scene per-status; can be left null
## for status types that need no visual (e.g. silence).
@export var visual_scene: PackedScene = null

## Subclass hook — called when the status is first applied to an actor.
## `stacks` is the count AFTER the apply (so first apply = 1, additive
## stack = 2, etc.). Default no-op; data-driven defaults handle Tier G.
func on_apply(_actor: Actor, _stacks: int) -> void:
	pass

## Subclass hook — called every `tick_interval_ticks` while active. Default
## body is the data-driven `damage_per_tick` application; `StatusController`
## handles that itself, so subclass overrides should add specialized
## behavior on top (NOT replace the data-driven damage — that runs in the
## controller).
func on_tick(_actor: Actor, _stacks: int) -> void:
	pass

## Subclass hook — called when the status expires (duration ran out or
## `clear` invoked externally). Default no-op; the controller cleans up
## the visual_scene instance.
func on_expire(_actor: Actor) -> void:
	pass

# --- Catalog ---

## Lazy in-process catalog of every StatusEffect under `res://data/status/`,
## keyed by `id`. Mirrors `AttackData.lookup` — call once on first use, no
## further filesystem hits. State sync (`StatusController.active_status_ids`)
## stores ids only; clients reconstruct effects via this catalog.
static var _catalog: Dictionary[StringName, StatusEffect] = {}
static var _catalog_loaded: bool = false

const _STATUS_DIR: String = "res://data/status/"

static func lookup(id: StringName) -> StatusEffect:
	if not _catalog_loaded:
		_load_catalog()
	return _catalog.get(id, null)

static func clear_catalog() -> void:
	_catalog.clear()
	_catalog_loaded = false

static func _load_catalog() -> void:
	_catalog.clear()
	_catalog_loaded = true
	var d: DirAccess = DirAccess.open(_STATUS_DIR)
	if d == null:
		return
	d.list_dir_begin()
	var name: String = d.get_next()
	while name != "":
		if not d.current_is_dir() and name.ends_with(".tres"):
			var path: String = _STATUS_DIR + name
			var res := load(path) as StatusEffect
			if res != null and res.id != &"":
				_catalog[res.id] = res
		name = d.get_next()
