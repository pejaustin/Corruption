class_name Interactable extends Area3D

## Base class for all interactible objects.
##
## Handles:
## - Body enter/exit tracking (Player for Overlord mode, PlayerActor for Avatar mode)
## - Prompt text routing to the HUD via InteractionUI singleton
## - Aim-based focus: Overlord must look at the interactible to see the prompt
## - Subclasses override get_prompt_text(), get_prompt_color(), and _on_interact()

## How close the player/Avatar must be for the prompt to appear.
## The Area3D collision shape handles proximity; this is just for
## the aim check to kick in.
@export var aim_angle_threshold: float = 30.0  # degrees

var _player_in_range: Player = null
var _avatar_in_range: PlayerActor = null
var _is_focused: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_interactable_ready()

## Override in subclass for additional setup. Called at the end of _ready().
func _interactable_ready() -> void:
	pass

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = body
	elif body is PlayerActor:
		_avatar_in_range = body

func _on_body_exited(body: Node3D) -> void:
	if body is Player and body == _player_in_range:
		_player_in_range = null
		if _is_focused:
			_is_focused = false
			InteractionUI.clear_prompt(self)
		_on_player_exited()
	elif body is PlayerActor and body == _avatar_in_range:
		_avatar_in_range = null
		if _is_focused:
			_is_focused = false
			InteractionUI.clear_prompt(self)
		_on_avatar_exited()

## Called when the Overlord player leaves range. Override for cleanup.
func _on_player_exited() -> void:
	pass

## Called when the Avatar leaves range. Override for cleanup.
func _on_avatar_exited() -> void:
	pass

func _process(_delta: float) -> void:
	var should_focus = _check_focus()
	if should_focus and not _is_focused:
		_is_focused = true
		_update_ui_prompt()
	elif not should_focus and _is_focused:
		_is_focused = false
		InteractionUI.clear_prompt(self)
	elif should_focus and _is_focused:
		# Refresh prompt text (it may change dynamically)
		_update_ui_prompt()

func _check_focus() -> bool:
	# Check Overlord player focus (proximity + aim)
	if _player_in_range and _is_local_player(_player_in_range):
		if _is_player_aiming_at_us(_player_in_range):
			return true
	# Check Avatar focus (just proximity — 3rd person doesn't need aim check)
	if _avatar_in_range and not _avatar_in_range.is_dormant:
		if _avatar_in_range.controlling_peer_id == multiplayer.get_unique_id():
			return true
	return false

func _is_local_player(player: Player) -> bool:
	return multiplayer.get_unique_id() == player.name.to_int()

func _is_player_aiming_at_us(player: Player) -> bool:
	var cam_input: CameraInput = player.get_node_or_null("CameraInput")
	if not cam_input or not cam_input.camera_3d:
		return false
	var cam: Camera3D = cam_input.camera_3d
	# Direction from camera to interactable
	var to_target = (global_position - cam.global_position).normalized()
	# Camera forward direction
	var cam_forward = -cam.global_basis.z
	var angle = rad_to_deg(cam_forward.angle_to(to_target))
	return angle < aim_angle_threshold

func _update_ui_prompt() -> void:
	var text = get_prompt_text()
	var color = get_prompt_color()
	InteractionUI.set_prompt(self, text, color)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_focused:
		return
	if event.is_action_pressed("player_action_1"):
		_on_interact()

## Override in subclass: return the prompt text for the current state.
func get_prompt_text() -> String:
	return "Press E"

## Override in subclass: return the prompt color for the current state.
func get_prompt_color() -> Color:
	return Color.WHITE

## Override in subclass: called when the player presses interact while focused.
func _on_interact() -> void:
	pass

## Helpers for subclasses

func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()

func is_overlord_in_range() -> bool:
	return _player_in_range != null and _is_local_player(_player_in_range)

func is_avatar_in_range() -> bool:
	return _avatar_in_range != null and not _avatar_in_range.is_dormant and _avatar_in_range.controlling_peer_id == get_local_peer_id()

func get_overlord_peer_id() -> int:
	if _player_in_range:
		return _player_in_range.name.to_int()
	return -1

## Returns the "Model" container from interactable.tscn. Subclass scenes must
## drop their visual (mesh, GLB instance, etc.) as a child of this node.
func get_model() -> Node3D:
	return get_node_or_null(^"Model") as Node3D
