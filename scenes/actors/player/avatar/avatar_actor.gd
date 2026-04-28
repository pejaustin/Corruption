class_name AvatarActor extends PlayerActor

## The shared Paladin vessel. Dormant when unclaimed.
## When a player claims it, their input drives this entity
## while their Overlord body stays idle in the tower.

const WATCHER_ORB_DISTANCE: float = 2.5
const WATCHER_ORB_HEIGHT: float = 2.0
const DEATH_TRANSFER_DELAY: float = 2.0
const RESPAWN_POSITION: Vector3 = Vector3(0.1, 0.04, -0.06)
const WATCHER_ORB_SIZE: Vector3 = Vector3(0.3, 0.3, 0.3)
const WATCHER_ORB_COLOR: Color = Color(0.4, 0.6, 1.0, 0.7)
const WATCHER_ORB_EMISSION: Color = Color(0.4, 0.6, 1.0)
const WATCHER_ORB_EMISSION_ENERGY: float = 2.0

@onready var avatar_input: AvatarInput = $AvatarInput
@onready var avatar_camera: AvatarCamera = $AvatarCamera
@onready var watcher_label: Label3D = $WatcherLabel

var controlling_peer_id: int = -1
var is_dormant: bool = true
var god_mode: bool = false
var _watcher_orbs: Dictionary[int, MeshInstance3D] = {}
# Tracks who dealt the killing blow for hostile takeover
var last_damage_source_peer: int = -1
# Faction abilities
var abilities: AvatarAbilities
# The CaptureChannel currently locking this avatar (null when not channeling).
# Read by ChannelState; written by CaptureChannel when the channel starts/ends.
var active_channel: CaptureChannel = null

func _ready() -> void:
	super()
	_set_dormant_visual(true)
	GameState.watcher_count_changed.connect(_on_watcher_count_changed)
	_update_watcher_label(0)
	# Create abilities node
	abilities = AvatarAbilities.new()
	abilities.name = "AvatarAbilities"
	add_child(abilities)

# --- Combat overrides ---

func can_take_damage() -> bool:
	if god_mode or is_dormant:
		return false
	return hp > 0

## No take_damage override needed — Actor.take_damage handles it.
## Damage from outside rollback (enemies) goes through incoming_damage instead.

## Called by host (enemy/minion attacks) to apply damage through the rollback owner,
## since incoming_damage is a state-synced property owned by the controlling peer.
@rpc("any_peer", "call_local", "reliable")
func apply_incoming_damage(amount: int, source_peer: int) -> void:
	incoming_damage += amount
	last_damage_source_peer = source_peer

func _die() -> void:
	super()
	if multiplayer.is_server():
		get_tree().create_timer(DEATH_TRANSFER_DELAY).timeout.connect(_on_death_transfer)

func _on_death_transfer() -> void:
	if not multiplayer.is_server():
		return
	# Hostile takeover: if a minion killed the Avatar, its owner becomes Avatar
	if last_damage_source_peer > 0 and last_damage_source_peer != controlling_peer_id:
		var old = GameState.avatar_peer_id
		GameState._set_avatar.rpc(-1)
		GameState._set_avatar.rpc(last_damage_source_peer)
		_respawn.rpc()
		last_damage_source_peer = -1
		return
	# Influence fallback: highest influence peer takes over
	var best = GameState.get_highest_influence_peer()
	if best > 0 and best != controlling_peer_id:
		var old = GameState.avatar_peer_id
		GameState._set_avatar.rpc(-1)
		GameState._set_avatar.rpc(best)
		_respawn.rpc()
		last_damage_source_peer = -1
		return
	# Default: round-robin
	GameState.release_avatar()
	_respawn.rpc()
	last_damage_source_peer = -1

@rpc("authority", "call_local", "reliable")
func _respawn() -> void:
	# Don't call deactivate() here — release_avatar() already triggered
	# _on_avatar_changed which activates the next peer and deactivates the old.
	# We just need to reset the Avatar's physical state for the new controller.
	global_position = RESPAWN_POSITION
	velocity = Vector3.ZERO
	hp = get_max_hp()
	hp_changed.emit(hp)
	_state_machine.transition(&"IdleState")

# --- Activation ---

func activate(peer_id: int) -> void:
	controlling_peer_id = peer_id
	is_dormant = false
	hp = get_max_hp()
	hp_changed.emit(hp)
	avatar_input.set_controller(peer_id)
	avatar_camera.activate(peer_id)
	rollback_synchronizer.process_settings()
	_set_dormant_visual(false)
	# Inherit the controlling peer's faction so hostility checks work
	# (e.g. MinionState.find_hostile_target treats NEUTRAL-vs-NEUTRAL as ALLIED).
	faction = GameState.get_faction(peer_id)
	if abilities:
		abilities.setup(self, faction)

func deactivate() -> void:
	controlling_peer_id = -1
	is_dormant = true
	faction = GameConstants.Faction.NEUTRAL
	avatar_input.set_controller(-1)
	avatar_camera.deactivate()
	rollback_synchronizer.process_settings()
	_set_dormant_visual(true)
	velocity = Vector3.ZERO
	_state_machine.transition(&"IdleState")

func _set_dormant_visual(dormant: bool) -> void:
	if _model:
		_model.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if controlling_peer_id != multiplayer.get_unique_id():
		return
	if not avatar_input.input_enabled:
		return
	# During a capture channel, ignore every avatar input. Pause menu still
	# works (handled elsewhere) and the interact key is consumed by the
	# focused Interactable, which routes it to capture_channel.request_cancel().
	if active_channel != null and active_channel.is_active():
		return
	if event.is_action_pressed("cancel"):
		GameState.request_recall_avatar()
	if abilities:
		if event.is_action_pressed("secondary_ability"):
			abilities.activate_ability(0)
		elif event.is_action_pressed("item_1"):
			abilities.activate_ability(1)
		elif event.is_action_pressed("item_2"):
			abilities.activate_ability(2)

# --- Watchers ---

func _on_watcher_count_changed(count: int) -> void:
	_update_watcher_label(count)

func _update_watcher_label(count: int) -> void:
	if not watcher_label:
		return
	if count > 0:
		watcher_label.visible = true
		watcher_label.text = "(%d watching)" % count
	else:
		watcher_label.visible = false

func _create_watcher_orb() -> MeshInstance3D:
	var orb = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = WATCHER_ORB_SIZE
	orb.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = WATCHER_ORB_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = WATCHER_ORB_EMISSION
	mat.emission_energy_multiplier = WATCHER_ORB_EMISSION_ENERGY
	orb.set_surface_override_material(0, mat)
	add_child(orb)
	return orb

func _process(_delta: float) -> void:
	var positions = GameState.watcher_positions
	for peer_id in _watcher_orbs.keys():
		if peer_id not in positions:
			_watcher_orbs[peer_id].queue_free()
			_watcher_orbs.erase(peer_id)
	for peer_id in positions:
		if peer_id not in _watcher_orbs:
			_watcher_orbs[peer_id] = _create_watcher_orb()
		var cam_pos: Vector3 = positions[peer_id]
		var dir = (cam_pos - global_position)
		dir.y = 0
		if dir.length() > 0.1:
			dir = dir.normalized()
		else:
			dir = Vector3.FORWARD
		_watcher_orbs[peer_id].position = dir * WATCHER_ORB_DISTANCE + Vector3(0, WATCHER_ORB_HEIGHT, 0)
