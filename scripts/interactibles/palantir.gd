extends Interactable

## Palantir scrying orb. Overlord interacts to enter scrying mode:
## Camera warps to a 3rd-person view orbiting the Avatar.
## A greybox cube appears at the scry camera position visible to the Avatar.
## Press Q to return to Overlord mode.

var _is_scrying := false
var _scry_camera: Camera3D
var _scry_cube: MeshInstance3D
var _scry_pivot: Node3D
var _overlord_camera: Camera3D

const SCRY_DISTANCE: float = 6.0
const SCRY_HEIGHT: float = 3.0
const CAMERA_MOUSE_ROTATION_SPEED: float = 0.005
const CAMERA_JOYSTICK_ROTATION_SPEED: float = 5.0
const CAMERA_X_ROT_MIN: float = deg_to_rad(-70)
const CAMERA_X_ROT_MAX: float = deg_to_rad(60)

func _interactable_ready() -> void:
	GameState.avatar_changed.connect(func(_o, _n): _on_avatar_changed())

func get_prompt_text() -> String:
	if _is_scrying:
		return "Q to return"
	elif is_overlord_in_range():
		return "Press E to scry"
	return "Palantir"

func get_prompt_color() -> Color:
	return Color(0.5, 0.8, 1)

func _on_interact() -> void:
	if _is_scrying:
		return  # Use Q to exit, not E
	if not is_overlord_in_range():
		return
	_start_scrying()

func _unhandled_input(event: InputEvent) -> void:
	if _is_scrying:
		# Q to exit scrying
		if event.is_action_pressed("cancel"):
			_stop_scrying()
			get_viewport().set_input_as_handled()
			return
		# Mouse look while scrying
		if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_rotate_scry_camera(event.relative * CAMERA_MOUSE_ROTATION_SPEED)
			get_viewport().set_input_as_handled()
		return
	# Delegate to base class for focus-based interact
	super(event)

func _process(delta: float) -> void:
	super(delta)
	if _is_scrying and _scry_pivot:
		var avatar = get_tree().current_scene.get_node_or_null("World/Avatar")
		if avatar and avatar is AvatarActor:
			_scry_pivot.global_position = avatar.global_position + Vector3(0, 1.5, 0)

		# Joystick camera
		var joy_input = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
		if joy_input != Vector2.ZERO:
			_rotate_scry_camera(joy_input * CAMERA_JOYSTICK_ROTATION_SPEED * delta)

		# Broadcast camera position to all peers
		if _scry_camera:
			GameState.update_watcher_position.rpc(_scry_camera.global_position)

func _rotate_scry_camera(move: Vector2) -> void:
	if not _scry_pivot:
		return
	_scry_pivot.rotate_y(-move.x)
	var cam_rot = _scry_pivot.get_node("CamRot")
	cam_rot.rotation.x = clamp(cam_rot.rotation.x + (-1 * move.y), CAMERA_X_ROT_MIN, CAMERA_X_ROT_MAX)

func _start_scrying() -> void:
	var avatar = get_tree().current_scene.get_node_or_null("World/Avatar")
	if not avatar or not avatar is AvatarActor:
		return

	_is_scrying = true
	# Pin the player's gaze to us so the prompt and Q-input stay routed here
	# even though the camera is now a separate scry rig.
	_claim_modal()

	# Disable Overlord input and save camera reference
	var player = _player_in_range
	if player:
		player.set_overlord_active(false)
		_overlord_camera = player._camera_input.camera_3d

	# Build scry rig: pivot -> cam_rot -> camera + cube
	_scry_pivot = Node3D.new()
	_scry_pivot.name = "ScryPivot"

	var cam_rot = Node3D.new()
	cam_rot.name = "CamRot"
	_scry_pivot.add_child(cam_rot)

	_scry_camera = Camera3D.new()
	_scry_camera.name = "ScryCamera"
	_scry_camera.position = Vector3(0, SCRY_HEIGHT, SCRY_DISTANCE)
	cam_rot.add_child(_scry_camera)

	# Greybox cube visible to the Avatar player
	_scry_cube = MeshInstance3D.new()
	_scry_cube.name = "ScryCube"
	var box = BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	_scry_cube.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.6, 0.8, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_scry_cube.set_surface_override_material(0, mat)
	_scry_camera.add_child(_scry_cube)

	get_tree().current_scene.add_child(_scry_pivot)
	_scry_pivot.global_position = avatar.global_position + Vector3(0, 1.5, 0)

	# Only make current on the local scrying peer
	var peer_id = _player_in_range.name.to_int()
	if multiplayer.get_unique_id() == peer_id:
		_scry_camera.current = true

	GameState.request_add_watcher.rpc_id(1)

func _stop_scrying() -> void:
	_is_scrying = false
	_release_modal()

	# Re-enable Overlord
	if _player_in_range:
		_player_in_range.set_overlord_active(true)
	elif _overlord_camera:
		_overlord_camera.current = true

	_overlord_camera = null

	if _scry_pivot and is_instance_valid(_scry_pivot):
		_scry_pivot.queue_free()
		_scry_pivot = null
		_scry_camera = null
		_scry_cube = null

	var my_peer = multiplayer.get_unique_id()
	GameState.remove_watcher_position(my_peer)
	GameState.request_remove_watcher.rpc_id(1)

func _on_avatar_changed() -> void:
	if _is_scrying and not GameState.has_avatar():
		_stop_scrying()
