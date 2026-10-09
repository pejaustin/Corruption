extends Interactable

## Palantir scrying orb (GDD §8). Any player at any Palantir can look in and
## see the Paladin live (a 3rd-person camera orbiting him); every viewer shows
## up to the others as a ghostly orb where their camera is, and viewers and his
## controller hear each other (PaladinVoice).
##
## It is also where you drive him. While looking in:
## - his owner presses E to take direct control (Q in his body lets go and
##   puts them back at the tower);
## - a player with more AVATAR_CONTROL sites than his owner presses E to begin
##   overpowering him (PaladinHold), which runs while they keep looking.
## Q stops looking.

const SCRY_DISTANCE: float = 6.0
const SCRY_HEIGHT: float = 3.0
const SCRY_PIVOT_HEIGHT: float = 1.5
const CAMERA_MOUSE_ROTATION_SPEED: float = 0.005
const CAMERA_JOYSTICK_ROTATION_SPEED: float = 5.0
const CAMERA_X_ROT_MIN: float = deg_to_rad(-70)
const CAMERA_X_ROT_MAX: float = deg_to_rad(60)
## Seconds between prompt refreshes while looking in (hold / overpower readouts).
const PROMPT_REFRESH_SECONDS: float = 0.25
const PROMPT_COLOR: Color = Color(0.5, 0.8, 1)

var _is_scrying: bool = false
var _scry_camera: Camera3D
var _scry_pivot: Node3D
var _overlord_camera: Camera3D
var _scrying_player: OverlordActor
var _prompt_timer: float = 0.0

func _interactable_ready() -> void:
	GameState.avatar_changed.connect(_on_avatar_changed)

func _unhandled_input(event: InputEvent) -> void:
	if _is_scrying:
		if event.is_action_pressed("cancel"):
			_stop_scrying(true)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("interaction"):
			_on_scry_interact()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_rotate_scry_camera(event.relative * CAMERA_MOUSE_ROTATION_SPEED)
			get_viewport().set_input_as_handled()
		return
	super(event)

func _process(delta: float) -> void:
	super(delta)
	if not _is_scrying or _scry_pivot == null:
		return
	var avatar := _find_avatar()
	if avatar:
		_scry_pivot.global_position = avatar.global_position + Vector3(0, SCRY_PIVOT_HEIGHT, 0)
	var joy_input := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if joy_input != Vector2.ZERO:
		_rotate_scry_camera(joy_input * CAMERA_JOYSTICK_ROTATION_SPEED * delta)
	if _scry_camera:
		# Everyone else draws this viewer's orb here.
		GameState.update_watcher_position.rpc(_scry_camera.global_position)
	_prompt_timer -= delta
	if _prompt_timer <= 0.0:
		_prompt_timer = PROMPT_REFRESH_SECONDS
		_refresh_prompt()

func get_prompt_text() -> String:
	# PLACEHOLDER: wording — every Palantir prompt below.
	if not _is_scrying:
		if is_overlord_in_range():
			return "Press E to scry"
		return "Palantir"
	var me := get_local_peer_id()
	var hold := _find_hold()
	if GameState.is_avatar_owner(me):
		var pct := roundi((hold.hold if hold else 1.0) * 100.0)
		return "The Paladin is yours (hold %d%%). E to take control, Q to return" % pct
	if hold and hold.overpower.has(me):
		return "Overpowering him: %d%%. Q to return" % roundi(hold.get_overpower(me) * 100.0)
	if hold and hold.can_overpower(me):
		return "E to overpower his hold, Q to return"
	return "Q to return"

func get_prompt_color() -> Color:
	return PROMPT_COLOR

func _on_interact() -> void:
	if _is_scrying or not is_overlord_in_range():
		return
	if get_overlord_peer_id() != get_local_peer_id():
		return
	_start_scrying()

func _on_scry_interact() -> void:
	var me := get_local_peer_id()
	if GameState.is_avatar_owner(me):
		if not GameState.has_avatar():
			# Stop looking first (gives the overlord back), then take him; the
			# avatar_changed handler swaps the overlord out for his body.
			_stop_scrying(true)
			GameState.request_possess_avatar()
		return
	var hold := _find_hold()
	if hold and hold.can_overpower(me) and not hold.overpower.has(me):
		hold.request_overpower()
		_refresh_prompt()

func _rotate_scry_camera(move: Vector2) -> void:
	if not _scry_pivot:
		return
	_scry_pivot.rotate_y(-move.x)
	var cam_rot := _scry_pivot.get_node("CamRot") as Node3D
	cam_rot.rotation.x = clampf(cam_rot.rotation.x - move.y, CAMERA_X_ROT_MIN, CAMERA_X_ROT_MAX)

func _start_scrying() -> void:
	var avatar := _find_avatar()
	if avatar == null:
		return
	_is_scrying = true
	# Pin the player's gaze to us so the prompt and E/Q stay routed here even
	# though the camera is now a separate scry rig.
	_claim_modal()
	_scrying_player = _player_in_range
	if _scrying_player:
		_scrying_player.set_overlord_active(false)
		_overlord_camera = _scrying_player._camera_input.camera_3d

	_scry_pivot = Node3D.new()
	_scry_pivot.name = "ScryPivot"
	var cam_rot := Node3D.new()
	cam_rot.name = "CamRot"
	_scry_pivot.add_child(cam_rot)
	_scry_camera = Camera3D.new()
	_scry_camera.name = "ScryCamera"
	_scry_camera.position = Vector3(0, SCRY_HEIGHT, SCRY_DISTANCE)
	cam_rot.add_child(_scry_camera)
	get_tree().current_scene.add_child(_scry_pivot)
	_scry_pivot.global_position = avatar.global_position + Vector3(0, SCRY_PIVOT_HEIGHT, 0)
	_scry_camera.current = true
	GameState.request_set_watching(true)
	_refresh_prompt()

func _stop_scrying(restore_overlord: bool) -> void:
	if not _is_scrying:
		return
	_is_scrying = false
	_release_modal()
	if restore_overlord:
		if _scrying_player and is_instance_valid(_scrying_player):
			_scrying_player.set_overlord_active(true)
		elif _overlord_camera and is_instance_valid(_overlord_camera):
			_overlord_camera.current = true
	_scrying_player = null
	_overlord_camera = null
	if _scry_pivot and is_instance_valid(_scry_pivot):
		_scry_pivot.queue_free()
	_scry_pivot = null
	_scry_camera = null
	GameState.request_set_watching(false)
	_refresh_prompt()

func _on_avatar_changed(_old: int, new_peer: int) -> void:
	# Taking direct control replaces the scry camera with his own.
	if _is_scrying and new_peer == get_local_peer_id():
		_stop_scrying(false)

func _find_avatar() -> AvatarActor:
	return get_tree().current_scene.get_node_or_null(^"World/Avatar") as AvatarActor

func _find_hold() -> PaladinHold:
	var avatar := _find_avatar()
	return avatar.hold if avatar else null
