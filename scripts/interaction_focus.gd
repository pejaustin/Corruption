class_name InteractionFocus extends Node

## Drives focus on Interactables for ONE local player. Lives as a child of
## the player rig (OverlordActor). Each frame:
##   1. Read the camera's interaction RayCast3D.
##   2. Walk up from the hit collider to find an Interactable ancestor.
##   3. Tell the previously-focused Interactable it lost focus and the new
##      one (if any) that it gained focus, with this player as the owner.
## Interactables themselves don't poll cameras — they just receive
## set_focused() calls and forward to their prompt + handler logic.
##
## When an Interactable holds the modal lock (War Table active, etc.) it
## stays focused regardless of the raycast — exit input still routes to it
## even when the camera has been pointed elsewhere.

@export var raycast: RayCast3D
@export var owner_actor: Node3D

var _current: Interactable = null

func _physics_process(_delta: float) -> void:
	if not _is_local_authority():
		_assign(null)
		return
	# Modal lock takes precedence over the raycast — whoever holds it stays
	# focused so the player can still press E to exit.
	if Interactable.has_modal():
		_assign(Interactable._modal_holder)
	else:
		_assign(_resolve_hit())
	# Refresh the focused prompt every frame so subclasses with state-
	# dependent text (altar resource count, mirror recording timer,
	# summoning circle minion count, war table selection size) stay live.
	# _refresh_prompt is a no-op when not focused, so it's free for
	# unfocused interactables.
	if _current and is_instance_valid(_current):
		_current._refresh_prompt()

func _resolve_hit() -> Interactable:
	if raycast == null or not raycast.is_inside_tree():
		return null
	if not raycast.is_colliding():
		return null
	var node: Node = raycast.get_collider()
	while node != null:
		if node is Interactable:
			return node
		node = node.get_parent()
	return null

func _assign(target: Interactable) -> void:
	if target == _current:
		return
	if _current and is_instance_valid(_current):
		_current.set_focused(false, owner_actor)
	_current = target
	if _current:
		_current.set_focused(true, owner_actor)

func _is_local_authority() -> bool:
	## Only the local player drives focus — remote peers see other players'
	## rigs but should not be raycasting on their behalf.
	if owner_actor == null:
		return false
	if owner_actor is OverlordActor:
		return owner_actor.name.to_int() == multiplayer.get_unique_id()
	if owner_actor is AvatarActor:
		var av := owner_actor as AvatarActor
		return av.controlling_peer_id == multiplayer.get_unique_id() and not av.is_dormant
	return false

func _exit_tree() -> void:
	# Make sure the last-focused interactable doesn't hang on to a stale
	# prompt when the player rig is freed.
	clear_focus()

## Pause menu calls this when disabling gameplay input — drops the focused
## prompt so it doesn't sit on screen underneath the menu.
func clear_focus() -> void:
	_assign(null)
