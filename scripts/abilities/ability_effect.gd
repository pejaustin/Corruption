class_name AbilityEffect extends Node3D

## Base class for Avatar ability effect scenes.
##
## When an AvatarAbility fires, its effect_scene is instanced as a child of
## the caster. AvatarAbilities sets `ability_id`, then calls `activate(caster)`.
## The effect owns its own visuals, timing, and gameplay. Subclasses override
## the hooks; the base handles the lifecycle and free.
##
## Instant effects leave `duration` at 0 (one-shot, freed after _on_activate).
## Timed buffs set `duration` in _on_activate and tick until expired.

signal expired

## Set by AvatarAbilities when the effect is spawned. Used for identity checks
## (is_active, cancel, etc).
var ability_id: StringName = &""

## 0 = instant/one-shot. Positive = duration in seconds before auto-expire.
var duration: float = 0.0

var caster: Node3D

var _elapsed: float = 0.0
var _expired: bool = false

func activate(caster_node: Node3D) -> void:
	caster = caster_node
	_on_activate()
	if duration <= 0.0:
		_expire()

func _process(delta: float) -> void:
	if _expired or duration <= 0.0:
		return
	_elapsed += delta
	_on_tick(delta)
	if _elapsed >= duration:
		_expire()

func force_expire() -> void:
	_expire()

func _expire() -> void:
	if _expired:
		return
	_expired = true
	_on_expire()
	expired.emit()
	queue_free()

# --- Overridable hooks ---

func _on_activate() -> void:
	pass

func _on_tick(_delta: float) -> void:
	pass

func _on_expire() -> void:
	pass

# --- Combat queries ---
# Defaults are no-op. Each effect overrides only what it affects.

func get_damage_multiplier() -> float:
	return 1.0

## If true, the next get_damage_multiplier() call consumes this effect.
## Used by one-shot strike buffs (e.g. Hellfire).
func consume_on_damage_query() -> bool:
	return false

func grants_lifesteal() -> bool:
	return false

func makes_invisible() -> bool:
	return false

func is_channeling() -> bool:
	return false
