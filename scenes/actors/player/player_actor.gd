class_name PlayerActor extends Actor

## The shared Paladin vessel. Dormant when unclaimed.
## When a player claims it, their input drives this entity
## while their Overlord body stays idle in the tower.

const WATCHER_ORB_DISTANCE := 2.5
const WATCHER_ORB_HEIGHT := 2.0

@onready var avatar_input: AvatarInput = $AvatarInput
@onready var avatar_camera: AvatarCamera = $AvatarCamera
@onready var rollback_synchronizer = $RollbackSynchronizer
@onready var watcher_label: Label3D = $WatcherLabel

var controlling_peer_id: int = -1
var is_dormant: bool = true
var god_mode: bool = false
var _watcher_orbs: Dictionary = {}

func _ready():
	super()
	rollback_synchronizer.process_settings()
	_set_dormant_visual(true)
	GameState.watcher_count_changed.connect(_on_watcher_count_changed)
	_update_watcher_label(0)

# --- Combat overrides ---

func can_take_damage() -> bool:
	if god_mode or is_dormant:
		return false
	return hp > 0

## No take_damage override needed — Actor.take_damage handles it.
## Damage from outside rollback (enemies) goes through incoming_damage instead.

func _die():
	super()
	if multiplayer.is_server():
		get_tree().create_timer(2.0).timeout.connect(_on_death_transfer)

func _on_death_transfer():
	if not multiplayer.is_server():
		return
	GameState.release_avatar()
	_respawn.rpc()

@rpc("authority", "call_local", "reliable")
func _respawn():
	deactivate()
	global_position = Vector3(0.1, 0.04, -0.06)
	hp = get_max_hp()
	hp_changed.emit(hp)

# --- Activation ---

func activate(peer_id: int):
	controlling_peer_id = peer_id
	is_dormant = false
	hp = get_max_hp()
	hp_changed.emit(hp)
	avatar_input.set_controller(peer_id)
	avatar_camera.activate(peer_id)
	rollback_synchronizer.process_settings()
	_set_dormant_visual(false)

func deactivate():
	controlling_peer_id = -1
	is_dormant = true
	avatar_input.set_controller(-1)
	avatar_camera.deactivate()
	rollback_synchronizer.process_settings()
	_set_dormant_visual(true)
	velocity = Vector3.ZERO
	_state_machine.transition(&"IdleState")

func _set_dormant_visual(dormant: bool):
	if _model:
		_model.visible = true

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("avatar_recall") and controlling_peer_id == multiplayer.get_unique_id():
		GameState.request_recall_avatar()

# --- Watchers ---

func _on_watcher_count_changed(count: int):
	_update_watcher_label(count)

func _update_watcher_label(count: int):
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
	box.size = Vector3(0.3, 0.3, 0.3)
	orb.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.6, 1.0, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.6, 1.0)
	mat.emission_energy_multiplier = 2.0
	orb.set_surface_override_material(0, mat)
	add_child(orb)
	return orb

func _process(_delta: float):
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
