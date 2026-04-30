class_name AvatarAbilities extends Node

## Per-Avatar ability manager. Holds cooldowns and active effect scenes.
##
## When an ability activates, we instance its `effect_scene` as a child of
## the actor and hand control to that scene via `AbilityEffect.activate()`.
## The effect drives its own lifecycle (buffs tick/expire, instants fire then
## free). Combat queries (damage mult, lifesteal, invisibility, channeling)
## aggregate across currently-active effects.
##
## Slot layout (Tier E):
##   - Slot 0: secondary_ability  (cooldown-gated)
##   - Slot 1: item_1             (cooldown-gated)
##   - Slot 2: item_2             (cooldown-gated)
##   - Slot 3: ultimate           (charge-gated via PlayerActor.ultimate_charge)
## The 4-slot layout is sourced from `FactionProfile.avatar_abilities` —
## indices 0..2 are the existing slots; index 3, if present, is the
## ultimate. Profiles with only 3 abilities silently lack an ultimate
## (slot 3 is null in `_abilities`).

signal ability_activated(ability_id: StringName)
signal ability_ready(ability_id: StringName)
signal abilities_initialized
## Tier E — fired when an activation request was rejected because the cost
## couldn't be paid (cost_resource pool empty). HUD/SFX hooks listen here
## for "blip" feedback. Empty signal payload (we don't pass cost details).
signal ability_cost_insufficient(ability_id: StringName)

const TOTAL_SLOTS: int = 4
const SLOT_SECONDARY: int = 0
const SLOT_ITEM_1: int = 1
const SLOT_ITEM_2: int = 2
const SLOT_ULTIMATE: int = 3

## Default resource pool when AvatarAbility.cost_resource is empty. Currently
## the only pool defined on GameState; future-proofing via the field on
## AvatarAbility lets us add per-faction pools without the cost system
## reading hard-coded names everywhere.
const DEFAULT_COST_RESOURCE: StringName = &"corruption_power"

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
		if ability:
			_cooldowns[ability.id] = 0.0
	abilities_initialized.emit()

func get_abilities() -> Array[AvatarAbility]:
	return _abilities

## Slot accessor. Returns null if the slot is empty / the faction has no
## ability authored at that index. Useful for HUD code that wants to display
## the ultimate without iterating.
func get_ability_at_slot(slot: int) -> AvatarAbility:
	if slot < 0 or slot >= _abilities.size():
		return null
	return _abilities[slot]

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
	if ability == null:
		return
	# Tier E — ultimates ignore cooldown and require full charge instead.
	if ability.is_ultimate:
		if not _actor or not _actor.is_ultimate_ready():
			return
	else:
		if not is_ready(ability.id):
			return
	# Tier E — resource cost gate (DORMANT BY DEFAULT: shipped abilities have
	# cost = 0 so this branch is a no-op for current content).
	if ability.cost > 0:
		var pool: StringName = ability.cost_resource if ability.cost_resource != &"" else DEFAULT_COST_RESOURCE
		if not _has_cost(pool, ability.cost):
			ability_cost_insufficient.emit(ability.id)
			return
	_request_activate.rpc_id(1, ability.id)

@rpc("any_peer", "call_local", "reliable")
func _request_activate(ability_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var ability := _find_ability(ability_id)
	if ability == null:
		return
	# Re-validate gates host-side. Charge is rollback-synced, cooldown is
	# host-authoritative; cost pool lives on GameState (host-authored).
	if ability.is_ultimate:
		if not _actor or not _actor.is_ultimate_ready():
			return
	else:
		if not is_ready(ability_id):
			return
	if ability.cost > 0:
		var pool: StringName = ability.cost_resource if ability.cost_resource != &"" else DEFAULT_COST_RESOURCE
		if not _has_cost(pool, ability.cost):
			return
		_pay_cost(pool, ability.cost)
	if ability.is_ultimate and _actor:
		_actor.drain_ultimate_charge()
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

# --- Tier E: Cost-gating helpers ---

func _has_cost(pool: StringName, amount: int) -> bool:
	var peer_id: int = _actor.controlling_peer_id if _actor else -1
	if peer_id <= 0:
		return false
	match pool:
		DEFAULT_COST_RESOURCE:
			return GameState.get_corruption_power(peer_id) >= amount
		_:
			# Unknown pool — gate closed. Designers should add a branch
			# when wiring a new resource.
			return false

func _pay_cost(pool: StringName, amount: int) -> void:
	var peer_id: int = _actor.controlling_peer_id if _actor else -1
	if peer_id <= 0:
		return
	match pool:
		DEFAULT_COST_RESOURCE:
			GameState.add_corruption_power(peer_id, -amount)
		_:
			pass

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
		if a and a.id == id:
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
