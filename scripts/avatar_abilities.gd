class_name AvatarAbilities extends Node

## Per-Avatar ability manager. Holds cooldowns and active effect scenes.
##
## When an ability activates, we instance its `effect_scene` as a child of
## the actor and hand control to that scene via `AbilityEffect.activate()`.
## The effect drives its own lifecycle (buffs tick/expire, instants fire then
## free). Combat queries (damage mult, lifesteal, invisibility, channeling)
## aggregate across currently-active effects.

signal ability_activated(ability_id: StringName)
signal ability_ready(ability_id: StringName)
signal abilities_initialized

var _abilities: Array[AvatarAbility] = []
var _cooldowns: Dictionary[StringName, float] = {}
var _active: Array[AbilityEffect] = []
var _faction: int = -1
var _actor: AvatarActor

func setup(actor: AvatarActor, faction: int) -> void:
	_actor = actor
	_faction = faction
	_abilities = FactionData.get_avatar_abilities(faction)
	_cooldowns.clear()
	_clear_active()
	for ability in _abilities:
		_cooldowns[ability.id] = 0.0
	abilities_initialized.emit()

func get_abilities() -> Array[AvatarAbility]:
	return _abilities

func get_cooldown(ability_id: StringName) -> float:
	return _cooldowns.get(ability_id, 0.0)

func is_ready(ability_id: StringName) -> bool:
	return _cooldowns.get(ability_id, 0.0) <= 0.0

func is_active(ability_id: StringName) -> bool:
	for e in _active:
		if e.ability_id == ability_id:
			return true
	return false

func _process(delta: float) -> void:
	for id in _cooldowns:
		if _cooldowns[id] > 0:
			_cooldowns[id] = max(0.0, _cooldowns[id] - delta)
			if _cooldowns[id] <= 0:
				ability_ready.emit(id)

func activate_ability(index: int) -> void:
	## Called locally by the controlling peer; forwarded to host for validation.
	if index < 0 or index >= _abilities.size():
		return
	var ability := _abilities[index]
	if not is_ready(ability.id):
		return
	_request_activate.rpc_id(1, ability.id)

@rpc("any_peer", "call_local", "reliable")
func _request_activate(ability_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	if not is_ready(ability_id):
		return
	if _find_ability(ability_id) == null:
		return
	_do_activate.rpc(ability_id)

@rpc("authority", "call_local", "reliable")
func _do_activate(ability_id: StringName) -> void:
	var ability := _find_ability(ability_id)
	if ability == null:
		return
	_cooldowns[ability_id] = ability.cooldown
	_spawn_effect(ability)
	ability_activated.emit(ability_id)

func cancel(ability_id: StringName) -> void:
	## Force-expire any active effect matching this id.
	for effect in _active.duplicate():
		if effect.ability_id == ability_id:
			effect.force_expire()

# --- Effect lifecycle ---

func _spawn_effect(ability: AvatarAbility) -> void:
	if ability.effect_scene == null:
		push_warning("[AvatarAbilities] Ability '%s' has no effect_scene" % ability.id)
		return
	var effect := ability.effect_scene.instantiate() as AbilityEffect
	if effect == null:
		push_warning("[AvatarAbilities] Effect scene root is not AbilityEffect: %s" % ability.id)
		return
	effect.ability_id = ability.id
	_actor.add_child(effect)
	effect.expired.connect(_on_effect_expired.bind(effect))
	_active.append(effect)
	effect.activate(_actor)

func _on_effect_expired(effect: AbilityEffect) -> void:
	_active.erase(effect)

func _clear_active() -> void:
	for e in _active.duplicate():
		e.force_expire()
	_active.clear()

func _find_ability(id: StringName) -> AvatarAbility:
	for a in _abilities:
		if a.id == id:
			return a
	return null

# --- Combat queries ---
# Aggregate across active effects. Each effect's base class returns a no-op
# default; subclasses override only the axes they affect.

func get_damage_multiplier() -> float:
	var mult := 1.0
	var to_consume: Array[AbilityEffect] = []
	for e in _active:
		var m := e.get_damage_multiplier()
		if not is_equal_approx(m, 1.0):
			mult *= m
			if e.consume_on_damage_query():
				to_consume.append(e)
	for e in to_consume:
		e.force_expire()
	return mult

func should_lifesteal() -> bool:
	for e in _active:
		if e.grants_lifesteal():
			return true
	return false

func is_camouflaged() -> bool:
	for e in _active:
		if e.makes_invisible():
			return true
	return false

func is_channeling_ritual() -> bool:
	for e in _active:
		if e.is_channeling():
			return true
	return false
