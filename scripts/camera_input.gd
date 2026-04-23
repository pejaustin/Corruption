class_name CameraInput extends Node3D

@export var camera_mount : Node3D
@export var camera_rot : Node3D
@export var camera_3d : Camera3D
@export var rollback_synchronizer : RollbackSynchronizer

var camera_basis : Basis = Basis.IDENTITY

const CAMERA_MOUSE_ROTATION_SPEED: float = 0.005
const CAMERA_X_ROT_MIN: float = deg_to_rad(-70)
const CAMERA_X_ROT_MAX: float = deg_to_rad(60)
const CAMERA_UP_DOWN_MOVEMENT: int = -1
const CAMERA_JOYSTICK_ROTATION_SPEED: int = 5

## When true, the camera is externally controlled (WarTable, cutscene, etc.)
## and ignores mouse/joystick rotation. See take_over() / release().
var _overridden: bool = false
var _override_tween: Tween
var _original_camera_parent: Node = null
var _original_camera_index: int = -1
# View model (first-person hands) is detached from the camera during override
# so it stays anchored to the rig instead of flying off with the camera.
var _viewmodel: Node3D = null
var _viewmodel_original_parent: Node = null
var _viewmodel_original_index: int = -1


func _ready() -> void:
	NetworkTime.before_tick_loop.connect(_gather)

	if multiplayer.get_unique_id() == str(get_parent().name).to_int():
		camera_3d.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		camera_3d.current = false
		$CameraMount/CameraRot/Camera3D/ViewModel.visible = false


func _gather() -> void:
	camera_basis = get_camera_rotation_basis()

func _input(event: InputEvent) -> void:
	if _overridden:
		return
	if event is InputEventMouseMotion and is_multiplayer_authority() and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_camera(event.relative * CAMERA_MOUSE_ROTATION_SPEED)

func get_input_joystick(delta: float) -> void:
	if _overridden:
		return
	var total = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	rotate_camera(total * CAMERA_JOYSTICK_ROTATION_SPEED * delta)

func _process(delta: float) -> void:
	get_input_joystick(delta)

func rotate_camera(move: Vector2) -> void:
	camera_mount.rotate_y(-move.x)
	camera_rot.rotation.x = clamp(camera_rot.rotation.x + (CAMERA_UP_DOWN_MOVEMENT * move.y), CAMERA_X_ROT_MIN, CAMERA_X_ROT_MAX)

func get_camera_rotation_basis() -> Basis:
	return camera_mount.global_transform.basis

## External takeover: tween the Camera3D to an arbitrary global transform and
## hold it there. Mouse/joystick look is ignored until release() is called.
## Implemented by reparenting the Camera3D to the scene root for the duration
## of the override so the mount/rot rig no longer drives its transform.
func take_over(target_transform: Transform3D, duration: float = 0.6) -> void:
	if _override_tween and _override_tween.is_valid():
		_override_tween.kill()
	var start_xform := camera_3d.global_transform
	_overridden = true
	# Reparent to the scene root so the camera detaches from the rig entirely.
	if _original_camera_parent == null:
		# Leave the ViewModel (first-person hands) behind on the rig so it
		# stays anchored to the player instead of following the camera.
		_viewmodel = camera_3d.get_node_or_null("ViewModel") as Node3D
		if _viewmodel:
			_viewmodel_original_parent = _viewmodel.get_parent()
			_viewmodel_original_index = _viewmodel.get_index()
			_viewmodel.get_parent().remove_child(_viewmodel)
			camera_rot.add_child(_viewmodel)
		_original_camera_parent = camera_3d.get_parent()
		_original_camera_index = camera_3d.get_index()
		_original_camera_parent.remove_child(camera_3d)
		get_tree().current_scene.add_child(camera_3d)
		camera_3d.global_transform = start_xform
	_override_tween = create_tween()
	_override_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_override_tween.tween_method(
		func(t: float) -> void: _set_camera_global(start_xform.interpolate_with(target_transform, t)),
		0.0, 1.0, duration
	)

## Release the camera: tween back to the rig's current world transform, then
## re-parent the camera transform to the rig and re-enable mouse-look.
func release(duration: float = 0.4) -> void:
	if not _overridden:
		return
	if _override_tween and _override_tween.is_valid():
		_override_tween.kill()
	var start_xform := camera_3d.global_transform
	var end_xform := _rig_global_transform()
	_override_tween = create_tween()
	_override_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_override_tween.tween_method(
		func(t: float) -> void: _set_camera_global(start_xform.interpolate_with(end_xform, t)),
		0.0, 1.0, duration
	)
	_override_tween.tween_callback(_finish_release)

func is_taken_over() -> bool:
	return _overridden

func _set_camera_global(xform: Transform3D) -> void:
	camera_3d.global_transform = xform

func _rig_global_transform() -> Transform3D:
	# What the Camera3D's transform would be if it were back under the rig.
	return camera_rot.global_transform

func _finish_release() -> void:
	if _original_camera_parent:
		camera_3d.get_parent().remove_child(camera_3d)
		_original_camera_parent.add_child(camera_3d)
		if _original_camera_index >= 0:
			_original_camera_parent.move_child(camera_3d, _original_camera_index)
		camera_3d.transform = Transform3D.IDENTITY
		_original_camera_parent = null
		_original_camera_index = -1
	# Restore the ViewModel back under the camera.
	if _viewmodel and _viewmodel_original_parent:
		_viewmodel.get_parent().remove_child(_viewmodel)
		_viewmodel_original_parent.add_child(_viewmodel)
		if _viewmodel_original_index >= 0:
			_viewmodel_original_parent.move_child(_viewmodel, _viewmodel_original_index)
		_viewmodel.transform = Transform3D.IDENTITY
		_viewmodel = null
		_viewmodel_original_parent = null
		_viewmodel_original_index = -1
	_overridden = false

func _exit_tree() -> void:
	NetworkTime.before_tick_loop.disconnect(_gather)
