class_name AvatarAbilities extends Node

## Manages faction-specific abilities for the Avatar.
## Attached to the PlayerActor. Abilities come from FactionData.
## Host-authoritative: ability activation is validated on the server.

signal ability_activated(ability_id: String)
signal ability_ready(ability_id: String)
signal cooldown_updated(ability_id: String, remaining: float)

var _abilities: Array[AvatarAbility] = []
var _cooldowns: Dictionary[String, float] = {}
var _active_effects: Dictionary[String, float] = {}
var _faction: int = -1
var _actor: PlayerActor

func setup(actor: PlayerActor, faction: int) -> void:
	_actor = actor
	_faction = faction
	_abilities = FactionData.get_avatar_abilities(faction)
	_cooldowns.clear()
	_active_effects.clear()
	for ability in _abilities:
		_cooldowns[ability.id] = 0.0

func get_abilities() -> Array[AvatarAbility]:
	return _abilities

func get_cooldown(ability_id: String) -> float:
	return _cooldowns.get(ability_id, 0.0)

func is_ready(ability_id: String) -> bool:
	return _cooldowns.get(ability_id, 0.0) <= 0.0

func is_active(ability_id: String) -> bool:
	return _active_effects.has(ability_id)

func _physics_process(delta: float) -> void:
	# Tick cooldowns
	for id in _cooldowns:
		if _cooldowns[id] > 0:
			_cooldowns[id] = max(0, _cooldowns[id] - delta)
			if _cooldowns[id] <= 0:
				ability_ready.emit(id)

	# Tick active effects
	var expired: Array = []
	for id in _active_effects:
		_active_effects[id] -= delta
		if _active_effects[id] <= 0:
			expired.append(id)
	for id in expired:
		_deactivate_effect(id)
		_active_effects.erase(id)

func activate_ability(index: int) -> void:
	## Called locally by the controlling peer, forwarded to host.
	if index < 0 or index >= _abilities.size():
		return
	var ability = _abilities[index]
	if not is_ready(ability.id):
		return
	_request_activate.rpc_id(1, ability.id)

@rpc("any_peer", "call_local", "reliable")
func _request_activate(ability_id: String) -> void:
	if not multiplayer.is_server():
		return
	if not is_ready(ability_id):
		return
	var ability = _find_ability(ability_id)
	if not ability:
		return
	_do_activate.rpc(ability_id)

@rpc("authority", "call_local", "reliable")
func _do_activate(ability_id: String) -> void:
	var ability = _find_ability(ability_id)
	if not ability:
		return
	_cooldowns[ability_id] = ability.cooldown
	_apply_effect(ability_id)
	ability_activated.emit(ability_id)

func _find_ability(ability_id: String) -> AvatarAbility:
	for a in _abilities:
		if a.id == ability_id:
			return a
	return null

# --- Effect application ---
# Each ability ID maps to a specific gameplay effect.

func _apply_effect(ability_id: String) -> void:
	match ability_id:
		"life_drain":
			_active_effects["life_drain"] = 5.0  # 5 seconds
		"corpse_explosion":
			_do_corpse_explosion()
		"hellfire_strike":
			_active_effects["hellfire_strike"] = 0.0  # Next attack only
		"demon_rage":
			_active_effects["demon_rage"] = 8.0
		"camouflage":
			_active_effects["camouflage"] = 10.0
			if _actor and _actor._model:
				_actor._model.visible = false
		"entangle":
			_do_entangle()
		"mind_blast":
			_do_mind_blast()
		"eldritch_ritual":
			_active_effects["eldritch_ritual"] = 5.0  # Channeling

func _deactivate_effect(ability_id: String) -> void:
	match ability_id:
		"camouflage":
			if _actor and _actor._model:
				_actor._model.visible = true
		"demon_rage":
			pass  # Just stops the buff
		"life_drain":
			pass

# --- Damage modifiers (queried by combat system) ---

func get_damage_multiplier() -> float:
	var mult := 1.0
	if is_active("hellfire_strike"):
		mult *= 3.0
		# Consume the effect
		_active_effects.erase("hellfire_strike")
	if is_active("demon_rage"):
		mult *= 2.0
	return mult

func should_lifesteal() -> bool:
	return is_active("life_drain")

func is_camouflaged() -> bool:
	return is_active("camouflage")

func is_channeling_ritual() -> bool:
	return is_active("eldritch_ritual")

# --- AoE abilities ---

func _do_corpse_explosion() -> void:
	if not _actor or not multiplayer.is_server():
		return
	# Find dead enemies within range and deal AoE damage
	var enemies_node = get_tree().current_scene.get_node_or_null("World/Enemies")
	if not enemies_node:
		return
	# Deal damage to all living enemies near the avatar
	for child in enemies_node.get_children():
		if child is EnemyActor and child.hp > 0:
			if _actor.global_position.distance_to(child.global_position) < 8.0:
				child.take_damage(40)

func _do_entangle() -> void:
	if not _actor or not multiplayer.is_server():
		return
	# Stagger all enemies within range
	var enemies_node = get_tree().current_scene.get_node_or_null("World/Enemies")
	if not enemies_node:
		return
	for child in enemies_node.get_children():
		if child is EnemyActor and child.hp > 0:
			if _actor.global_position.distance_to(child.global_position) < 6.0:
				child._state_machine.transition(&"StaggerState")

func _do_mind_blast() -> void:
	if not _actor or not multiplayer.is_server():
		return
	# Stagger all enemies in a cone in front of avatar
	var enemies_node = get_tree().current_scene.get_node_or_null("World/Enemies")
	if not enemies_node:
		return
	var forward = -_actor.global_basis.z
	for child in enemies_node.get_children():
		if child is EnemyActor and child.hp > 0:
			var to_enemy = (child.global_position - _actor.global_position).normalized()
			var angle = rad_to_deg(forward.angle_to(to_enemy))
			if angle < 45.0 and _actor.global_position.distance_to(child.global_position) < 10.0:
				child._state_machine.transition(&"StaggerState")
