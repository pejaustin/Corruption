class_name Balcony extends Interactable

## Balcony station in each tower (GDD §2: "mostly flavour: nearby territory, the
## day/night cycle, beacons in the sky when sites change hands"; interview Q8).
## E at your own balcony takes the camera to a lookout high on the tower that you
## turn with the mouse (like the palantir's scry camera); E or Q comes back.
## It claims the modal lock and pauses the rig's input while you look out.
## Flavour only: nothing here changes play.
## PLACEHOLDER: the balcony look (a stone post and a spyglass), the lookout's
## spot and every number and string below.

## PLACEHOLDER: tuning — where the lookout sits, relative to this station.
const LOOKOUT_OFFSET: Vector3 = Vector3(-3.0, 5.0, 0.0)
## PLACEHOLDER: tuning — wide view and a far plane long enough for beacons over
## sites ~150 m away.
const LOOKOUT_FOV: float = 90.0
const LOOKOUT_FAR: float = 1500.0
const MOUSE_ROTATION_SPEED: float = 0.004
const JOYSTICK_ROTATION_SPEED: float = 3.0
const PITCH_MIN: float = deg_to_rad(-60.0)
const PITCH_MAX: float = deg_to_rad(40.0)
# PLACEHOLDER: wording
const PROMPT_OPEN: String = "Press E to look out"
const PROMPT_CLOSE: String = "E / Q to return"

var _open: bool = false
var _player: OverlordActor = null
var _pivot: Node3D = null
var _pitch: Node3D = null
var _camera: Camera3D = null

func _interactable_ready() -> void:
	_build_lookout()

func get_prompt_text() -> String:
	if _open:
		return PROMPT_CLOSE
	if is_active_for_local_peer() and is_overlord_in_range():
		return PROMPT_OPEN
	return ""

func get_prompt_color() -> Color:
	return Color(0.7, 0.85, 1.0)

func is_active_for_local_peer() -> bool:
	## True when this balcony belongs to the local peer (or has no Tower
	## parent, i.e. a test harness).
	var tower := _find_owning_tower()
	if tower == null:
		return true
	return tower.owner_peer_id == multiplayer.get_unique_id()

func is_open() -> bool:
	return _open

func get_camera() -> Camera3D:
	return _camera

func open_lookout(player: OverlordActor) -> void:
	if _open or player == null or not is_active_for_local_peer():
		return
	_player = player
	_open = true
	_claim_modal()
	_set_player_input(false)
	_face_towards(Vector3.ZERO)
	_camera.current = true
	_refresh_prompt()

func close_lookout() -> void:
	if not _open:
		return
	_open = false
	_release_modal()
	_camera.current = false
	if _player != null and is_instance_valid(_player):
		_player.set_overlord_active(true)
		_set_player_input(true)
	_player = null
	_refresh_prompt()

func rotate_lookout(move: Vector2) -> void:
	## Turns the view by a mouse-motion-sized step.
	_pivot.rotate_y(-move.x)
	_pitch.rotation.x = clampf(_pitch.rotation.x - move.y, PITCH_MIN, PITCH_MAX)

func _on_interact() -> void:
	if _open:
		close_lookout()
	elif is_overlord_in_range():
		open_lookout(_player_in_range)

func _unhandled_input(event: InputEvent) -> void:
	if _open:
		if event.is_action_pressed("cancel") or event.is_action_pressed("interaction"):
			close_lookout()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			rotate_lookout((event as InputEventMouseMotion).relative * MOUSE_ROTATION_SPEED)
			get_viewport().set_input_as_handled()
		return
	super(event)

func _process(delta: float) -> void:
	super(delta)
	if not _open:
		return
	var joy: Vector2 = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if joy != Vector2.ZERO:
		rotate_lookout(joy * JOYSTICK_ROTATION_SPEED * delta)

func _exit_tree() -> void:
	if _open:
		close_lookout()

func _build_lookout() -> void:
	_pivot = Node3D.new()
	_pivot.name = "LookoutPivot"
	_pivot.position = LOOKOUT_OFFSET
	add_child(_pivot)
	_pitch = Node3D.new()
	_pitch.name = "LookoutPitch"
	_pivot.add_child(_pitch)
	_camera = Camera3D.new()
	_camera.name = "LookoutCamera"
	_camera.fov = LOOKOUT_FOV
	_camera.far = LOOKOUT_FAR
	_pitch.add_child(_camera)

func _face_towards(world_point: Vector3) -> void:
	## Yaw the lookout to face a point (the map centre) and level the pitch.
	var from: Vector3 = _pivot.global_position
	var flat: Vector3 = Vector3(world_point.x - from.x, 0.0, world_point.z - from.z)
	if flat.length() > 0.01:
		_pivot.global_rotation = Vector3(0.0, atan2(-flat.x, -flat.z), 0.0)
	_pitch.rotation = Vector3.ZERO

func _find_owning_tower() -> Tower:
	var n: Node = get_parent()
	while n:
		if n is Tower:
			return n as Tower
		n = n.get_parent()
	return null

func _set_player_input(enabled: bool) -> void:
	if _player == null:
		return
	if not enabled:
		_player.set_overlord_active(false)
	for c in _player.get_children():
		if c is PlayerInput:
			(c as PlayerInput).input_enabled = enabled
