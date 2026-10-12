class_name SiteEncounter extends Interactable

## The Paladin's encounter at a temple (mini-dungeon) or runestone (arena duel),
## Austin, 2026-10-12. A child of the CorruptionSite; sites with no encounter
## (towns, work sites, the chapel, towers) free it.
##
## The possessed Paladin presses E at the site (`request_enter`, the same call
## the test makes). The host pins him inside the encounter space, far below the
## map, and spawns its enemies from the space's EncounterSpawn markers.
## - Temple: all enemies dead -> `CorruptionSite.paladin_cleared`.
## - Runestone: the Dark Lord dead -> `CorruptionSite.win_runestone`.
## Either way he is moved back out to where he entered. Defeat follows
## AvatarActor._die; he is then moved out where he lies (not left in the dungeon).
## PLACEHOLDER: how entering and leaving work is not designed.

## Host and clients: an encounter began / ended. outcome: &"won" or &"lost" or &"aborted".
signal encounter_started(peer_id: int)
signal encounter_ended(outcome: StringName, peer_id: int)

## Seconds the Paladin is held at his new spot so netfox accepts the move.
const PIN_SECONDS: float = 0.5
## PLACEHOLDER: where the encounter spaces sit — this far below the map's origin,
## over the site's own x/z so two sites never overlap.
const SPACE_Y: float = -400.0
## How far from the site (horizontally) the Paladin must be to enter.
## PLACEHOLDER: tuning.
const ENTER_RADIUS: float = 6.0

var space: EncounterSpace
## Peer whose Paladin is inside; -1 = nobody. Host and clients.
var active_peer: int = -1

var _site: CorruptionSite
var _avatar: AvatarActor
var _mm: MinionManager
var _return_xform: Transform3D
var _foes: Array[MinionActor] = []
var _foes_left: int = 0

func _interactable_ready() -> void:
	_site = get_parent() as CorruptionSite
	if _site == null or _site.get_encounter() == SiteType.Encounter.NONE or _site.site_type.encounter_scene == null:
		queue_free()
		return
	space = _site.site_type.encounter_scene.instantiate() as EncounterSpace
	space.top_level = true
	_site.add_child.call_deferred(space)
	_place_space.call_deferred()

func _place_space() -> void:
	space.global_position = Vector3(_site.global_position.x, SPACE_Y, _site.global_position.z)

func is_active() -> bool:
	return active_peer != -1

func can_enter() -> bool:
	## Whether there is anything to do here: a temple with its forces in, a
	## runestone not yet spent.
	if _site == null or _site.unusable or is_active():
		return false
	if _site.is_kind(SiteType.PoiKind.TEMPLE):
		return _site.forces_present
	return not _site.is_spent()

# --- Prompt ---

func get_prompt_text() -> String:
	if not is_avatar_in_range():
		return ""
	if is_active():
		return "Someone is inside" # PLACEHOLDER: wording
	if not can_enter():
		return "Nothing left here" # PLACEHOLDER: wording
	if _site.is_kind(SiteType.PoiKind.TEMPLE):
		return "Press E to enter the temple" # PLACEHOLDER: wording
	return "Press E to face the sealed Dark Lord" # PLACEHOLDER: wording

func _on_interact() -> void:
	if is_avatar_in_range():
		request_enter()

# --- Entering ---

func request_enter() -> void:
	## What the interact prompt calls. The host decides.
	if multiplayer.is_server():
		try_enter(multiplayer.get_unique_id())
	else:
		_rpc_request_enter.rpc_id(1)

@rpc("any_peer", "reliable")
func _rpc_request_enter() -> void:
	if multiplayer.is_server():
		try_enter(multiplayer.get_remote_sender_id())

func try_enter(peer_id: int) -> bool:
	## Host: `peer_id` asks to take the Paladin in. They must own and drive him,
	## he must be standing at the site, alive, and there must be something to do.
	if not multiplayer.is_server() or space == null or not can_enter():
		return false
	if not GameState.is_avatar_owner(peer_id) or not GameState.is_avatar(peer_id):
		return false
	_avatar = get_tree().current_scene.get_node_or_null("World/Avatar") as AvatarActor
	_mm = get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if _avatar == null or _mm == null or _avatar.hp <= 0:
		return false
	var offset := _avatar.global_position - _site.global_position
	if Vector2(offset.x, offset.z).length() > ENTER_RADIUS:
		return false
	_return_xform = _avatar.global_transform
	_set_active.rpc(peer_id)
	_avatar.died.connect(_on_paladin_died, CONNECT_ONE_SHOT)
	_mm.minion_died.connect(_on_minion_died)
	_move_avatar(Transform3D(Basis.IDENTITY, space.entry.global_position))
	_spawn_foes()
	encounter_started.emit(peer_id)
	return true

func _spawn_foes() -> void:
	_foes.clear()
	for spawn in space.spawns():
		var id := _mm.spawn_neutral_minion(spawn.global_position + Vector3.UP * 0.5, spawn.minion_type)
		var foe := _mm.get_minion_by_id(id)
		if foe == null:
			continue
		if spawn.hp_override > 0:
			foe.max_hp_value = spawn.hp_override
			foe.hp = spawn.hp_override
		if spawn.damage_override > 0:
			foe.attack_damage = spawn.damage_override
		_foes.append(foe)
	_foes_left = _foes.size()

# --- Inside ---

func foes_alive() -> Array[MinionActor]:
	var out: Array[MinionActor] = []
	for foe in _foes:
		if is_instance_valid(foe) and foe.hp > 0:
			out.append(foe)
	return out

func _physics_process(_delta: float) -> void:
	if multiplayer.is_server() and is_active() and GameState.avatar_owner_peer_id != active_peer:
		_finish(&"aborted")  # a contest took him away

func _on_minion_died(minion: MinionActor) -> void:
	if not is_active() or minion not in _foes:
		return
	_foes.erase(minion)
	if _foes.is_empty():
		_finish(&"won")

func _on_paladin_died() -> void:
	## Host: he fell inside. AvatarAI/_die have taken their course; he is carried
	## out afterwards (deferred, so _die's owner wipe lands first).
	if is_active():
		_finish.call_deferred(&"lost")

func _finish(outcome: StringName) -> void:
	if not is_active():
		return
	var peer := active_peer
	if _mm and _mm.minion_died.is_connected(_on_minion_died):
		_mm.minion_died.disconnect(_on_minion_died)
	if _avatar and _avatar.died.is_connected(_on_paladin_died):
		_avatar.died.disconnect(_on_paladin_died)
	for foe in foes_alive():
		_mm.despawn_minion(foe)
	_foes.clear()
	_set_active.rpc(-1)
	_move_avatar(_return_xform)
	if outcome == &"won":
		if _site.is_kind(SiteType.PoiKind.TEMPLE):
			_site.paladin_cleared(peer)
		else:
			_site.win_runestone(peer)
	encounter_ended.emit(outcome, peer)

func _move_avatar(xform: Transform3D) -> void:
	## Pinned for a moment so the rollback tick keeps the new position.
	_avatar.pin_transform(xform)
	get_tree().create_timer(PIN_SECONDS).timeout.connect(_avatar.unpin_transform)

@rpc("authority", "call_local", "reliable")
func _set_active(peer_id: int) -> void:
	active_peer = peer_id
	_refresh_prompt()
