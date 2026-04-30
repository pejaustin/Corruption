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
	# Tier F — anti-degen LOS cooldown extension. Opt-in per ability via
	# `requires_los`. When true and the caster has no hostile in line-of-sight
	# at cast-time, the recorded cooldown is multiplied by `los_cooldown_mult`
	# so blind-firing from cover is taxed. Default behavior (requires_los =
	# false) is unchanged. See docs/technical/tier-f-implementation.md.
	var cd: float = ability.cooldown
	if ability.requires_los and not _has_hostile_los():
		cd *= ability.los_cooldown_mult
	_cooldowns[ability_id] = cd
	_spawn_effect(ability)
	ability_activated.emit(ability_id)

## Tier F — true iff the caster has line-of-sight to at least one hostile
## actor right now. Implementation: ray-cast from the actor's chest to each
## hostile in the actors group; return on the first clear path. Cheap, single-
## frame check (no caching) — only fires on ability cast, which is bounded by
## cooldown. KnowledgeManager-aware version is documented as a follow-up
## (per docs/systems/avatar-combat.md §13 anti-camp); for now the simple
## raycast suffices.
func _has_hostile_los() -> bool:
	if _actor == null:
		return false
	var space := _actor.get_world_3d().direct_space_state
	if space == null:
		return false
	var origin: Vector3 = _actor.global_position + Vector3(0, 1.2, 0)
	for n in _actor.get_tree().get_nodes_in_group(&"actors"):
		var a := n as Actor
		if a == null or a == _actor:
			continue
		if not is_instance_valid(a):
			continue
		if a.hp <= 0:
			continue
		if not _actor.is_hostile_to(a):
			continue
		var target_pos: Vector3 = a.global_position + Vector3(0, 1.2, 0)
		var query := PhysicsRayQueryParameters3D.create(origin, target_pos)
		# Exclude both the caster's collider and the target's so we hit only
		# world geometry between them. Hurtbox / hitbox layers are area-only
		# anyway, but the caster's own CharacterBody3D body would otherwise
		# auto-collide.
		query.exclude = [_actor.get_rid(), a.get_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			# No occluder — clear LOS to this hostile.
			return true
	return false

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
