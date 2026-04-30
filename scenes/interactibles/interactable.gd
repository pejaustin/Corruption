class_name Interactable extends Area3D

## Base class for all interactible objects.
##
## Focus is driven from the outside: each local player has an InteractionFocus
## controller that reads the camera's RayCast3D, finds the hit Interactable,
## and calls set_focused() on it. Interactables themselves do not poll
## cameras or run raycasts.
##
## Modal lock: while one Interactable holds it (e.g. War Table is open), the
## InteractionFocus controller routes focus to the holder regardless of where
## the player is aiming. Subclasses call _claim_modal / _release_modal.

## Layer interactable Area3Ds live on. Set in interactable.tscn so the
## camera's interaction RayCast3D (collision_mask = world | this bit) hits
## them on a forward look.
const INTERACTABLE_LAYER: int = 1 << 4

static var _modal_holder: Interactable = null

static func has_modal() -> bool:
	return _modal_holder != null and is_instance_valid(_modal_holder)

## Legacy field — kept so old scenes still load. Focus is now raycast-only;
## the cone threshold is unused.
@export var aim_angle_threshold: float = 30.0  # unused

var _is_focused: bool = false
## The local player currently aiming at us, set by InteractionFocus when it
## calls set_focused(true, who). Subclass logic (war_table tween, advisor
## handoff peer_id, palantir scry binding) reads these.
var _player_in_range: OverlordActor = null
var _avatar_in_range: AvatarActor = null

func _ready() -> void:
	_interactable_ready()

## Override in subclass for additional setup. Called at the end of _ready().
func _interactable_ready() -> void:
	pass

## Called by InteractionFocus when this Interactable gains or loses the
## local player's gaze. `who` is the OverlordActor or AvatarActor whose
## camera the ray came from (null on focus loss).
func set_focused(focused: bool, who: Node3D = null) -> void:
	if focused:
		if who is OverlordActor:
			_player_in_range = who
			_avatar_in_range = null
		elif who is AvatarActor:
			_avatar_in_range = who
			_player_in_range = null
		if not _is_focused:
			_is_focused = true
		_update_ui_prompt()
		return
	_player_in_range = null
	_avatar_in_range = null
	if _is_focused:
		_is_focused = false
		InteractionUI.clear_prompt(self)

## Refresh the prompt while focused — subclasses with state-dependent text
## (e.g. War Table changing prompt mid-session) call this after mutating.
func _refresh_prompt() -> void:
	if _is_focused:
		_update_ui_prompt()

## No-op so subclass `_process` overrides can call `super(delta)` safely
## without depending on whether the base does any per-frame work.
func _process(_delta: float) -> void:
	pass

func _update_ui_prompt() -> void:
	var text = get_prompt_text()
	var color = get_prompt_color()
	InteractionUI.set_prompt(self, text, color)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_focused:
		return
	if event.is_action_pressed("interaction"):
		_on_interact()
		# Consume so a second focused interactable in modal limbo doesn't
		# also process the same press.
		get_viewport().set_input_as_handled()

## Subclasses call this to announce they've taken over the player's input/UI
## (e.g. War Table activation). InteractionFocus pins focus on us until we
## release.
func _claim_modal() -> void:
	_modal_holder = self

## Subclasses call this when their modal session ends.
func _release_modal() -> void:
	if _modal_holder == self:
		_modal_holder = null

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

func _is_local_player(player: OverlordActor) -> bool:
	return player != null and multiplayer.get_unique_id() == player.name.to_int()

func is_overlord_in_range() -> bool:
	return _player_in_range != null

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
