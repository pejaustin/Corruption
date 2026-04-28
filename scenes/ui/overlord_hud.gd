class_name OverlordHUD
extends CanvasLayer

## Per-local-peer HUD shown while in the tower as Overlord. Attached as a
## child of overlord_actor.tscn. Each peer's overlord is named with its
## peer_id, so we match against multiplayer.get_unique_id() — root-node
## multiplayer_authority isn't transferred per-peer for overlords.
##
## Visibility tracks "in tower" state: hide while this peer is controlling
## the avatar (AvatarHUD takes over the prompt slot), show otherwise.

@onready var _interaction_prompt: RichTextLabel = %InteractionPrompt

func _ready() -> void:
	var parent := get_parent()
	if parent == null or multiplayer.get_unique_id() != str(parent.name).to_int():
		queue_free()
		return
	GameState.avatar_changed.connect(_on_avatar_changed)
	_refresh()

func _on_avatar_changed(_old: int, _new: int) -> void:
	_refresh()

func _refresh() -> void:
	var in_tower := GameState.avatar_peer_id != multiplayer.get_unique_id()
	visible = in_tower
	if in_tower:
		InteractionUI.register_prompt(_interaction_prompt)

func _exit_tree() -> void:
	if _interaction_prompt and is_instance_valid(_interaction_prompt):
		InteractionUI.deregister_prompt(_interaction_prompt)
