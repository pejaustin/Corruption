extends Node

## Plays the game like a person: every action is a real InputEvent pushed
## through Input.parse_input_event(), so it travels the same path as a
## keyboard and mouse (action map, _unhandled_input, mouse look, the
## interaction raycast). Nothing here calls game logic.
##
## Needs a windowed run (screenshots read the viewport). Output PNGs go to
## $PLAYTEST_DIR (default /tmp/claude-1000/playtest).

const MOUSE_SENS: float = 0.005  # CameraInput.CAMERA_MOUSE_ROTATION_SPEED
const AIM_TOLERANCE: float = 0.012  # radians

var player: Node3D
var camera: Camera3D
var out_dir: String = "/tmp/claude-1000/playtest"
var _held: Dictionary[StringName, bool] = {}

func _init() -> void:
	var env := OS.get_environment("PLAYTEST_DIR")
	if env != "":
		out_dir = env

func bind(p_player: Node3D, p_camera: Camera3D) -> void:
	player = p_player
	camera = p_camera
	DirAccess.make_dir_recursive_absolute(out_dir)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout

## What the on-screen interaction prompt says right now ("" when hidden).
func prompt() -> String:
	var label: RichTextLabel = InteractionUI.get("_prompt_label")
	if label == null or not is_instance_valid(label) or not label.visible:
		return ""
	return label.get_parsed_text()

func say(msg: String) -> void:
	print("[driver] %s | prompt: \"%s\"" % [msg, prompt()])

# --- Raw events ---

func _action(name: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)

func hold_action(name: StringName) -> void:
	if _held.get(name, false):
		return
	_held[name] = true
	_action(name, true)

func release_action(name: StringName) -> void:
	if not _held.get(name, false):
		return
	_held[name] = false
	_action(name, false)

func release_all() -> void:
	for n in _held.keys():
		release_action(n)

func press_action(name: StringName, hold_seconds: float = 0.1) -> void:
	say("press %s" % name)
	_action(name, true)
	await seconds(hold_seconds)
	_action(name, false)
	await frames(3)

func key(keycode: Key) -> void:
	say("key %s" % OS.get_keycode_string(keycode))
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await frames(2)
	await frames(3)

func click(button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	say("click %d" % button)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = get_viewport().get_visible_rect().size * 0.5
		Input.parse_input_event(ev)
		await frames(2)

func look(dx: float, dy: float) -> void:
	## Mouse motion when the mouse is captured. A headless run never gets a
	## captured mouse (CameraInput then ignores motion), so the same look is
	## sent through the right-stick actions, which drive the same rotation.
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		await _look_with_stick(dx * MOUSE_SENS, dy * MOUSE_SENS)
		return
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(dx, dy)
	ev.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(ev)
	await get_tree().process_frame

func _look_with_stick(yaw_rad: float, pitch_rad: float) -> void:
	# CameraInput turns total * 5 * delta radians per frame from camera_* actions.
	var per_unit: float = CameraInput.CAMERA_JOYSTICK_ROTATION_SPEED * maxf(get_process_delta_time(), 0.001)
	var sx := clampf(yaw_rad / per_unit, -1.0, 1.0)
	var sy := clampf(pitch_rad / per_unit, -1.0, 1.0)
	_stick(&"camera_right", &"camera_left", sx)
	_stick(&"camera_down", &"camera_up", sy)
	await get_tree().process_frame
	await get_tree().process_frame
	_stick(&"camera_right", &"camera_left", 0.0)
	_stick(&"camera_down", &"camera_up", 0.0)

func _stick(pos: StringName, neg: StringName, v: float) -> void:
	for pair in [[pos, maxf(v, 0.0)], [neg, maxf(-v, 0.0)]]:
		var ev := InputEventAction.new()
		ev.action = pair[0]
		ev.pressed = pair[1] > 0.0
		ev.strength = pair[1]
		Input.parse_input_event(ev)

# --- Aiming and walking ---

func _angles_to(world_pos: Vector3) -> Vector2:
	## (yaw error, pitch error) in radians; positive yaw = target is left.
	var local := camera.global_basis.inverse() * (world_pos - camera.global_position)
	return Vector2(atan2(-local.x, -local.z), atan2(local.y, Vector2(local.x, local.z).length()))

func aim_at(world_pos: Vector3, max_steps: int = 80) -> bool:
	for i in max_steps:
		var err := _angles_to(world_pos)
		if absf(err.x) < AIM_TOLERANCE and absf(err.y) < AIM_TOLERANCE:
			await frames(3)  # let the raycast catch up
			return true
		# CameraInput: yaw -= dx*s, pitch -= dy*s.
		var dx := clampf(-err.x / MOUSE_SENS, -120.0, 120.0)
		var dy := clampf(-err.y / MOUSE_SENS, -120.0, 120.0)
		await look(dx, dy)
	var e := _angles_to(world_pos)
	print("[driver] aim gave up: yaw err %.3f pitch err %.3f (cam pitch %.1f deg, cam y %.2f, target %s)" % [e.x, e.y, rad_to_deg(camera.global_rotation.x), camera.global_position.y, world_pos])
	return false

func walk_to(world_xz: Vector2, radius: float = 0.3, timeout: float = 25.0) -> bool:
	## Hold forward while steering the view toward a point on the ground.
	var elapsed := 0.0
	while elapsed < timeout:
		var here := Vector2(player.global_position.x, player.global_position.z)
		var to := world_xz - here
		if to.length() <= radius:
			release_all()
			await frames(10)
			return true
		var target := Vector3(world_xz.x, camera.global_position.y, world_xz.y)
		var err := _angles_to(target)
		await look(clampf(-err.x / MOUSE_SENS, -150.0, 150.0), 0.0)
		if absf(err.x) < 0.5:
			hold_action(&"forward")
		else:
			release_action(&"forward")
		elapsed += get_process_delta_time()
	release_all()
	return false

func screenshot(shot_name: String) -> String:
	await frames(6)
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(shot_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[driver] screenshot ", path)
	return path
