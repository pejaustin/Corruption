class_name OverlordActor extends PlayerActor

## Per-player tower body. First-person perspective, Lich model.
## Always active (unlike the Avatar, which is dormant when unclaimed).
## When a player claims the Avatar, `set_overlord_active(false)` idles this
## body until they return.

@export var _player_input: PlayerInput
@export var _camera_input: CameraInput

var _overlord_active: bool = true

## Public accessor for the player's visual model. Use this instead of
## get_node("Model") so consumers don't depend on child naming.
func get_model() -> Node3D:
	return _model

func _enter_tree() -> void:
	_player_input.set_multiplayer_authority(str(name).to_int())
	_camera_input.set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	super()
	faction = GameState.get_faction(str(name).to_int())
	# Hide the loading screen once our player is spawned in game and ready.
	if multiplayer.get_unique_id() == str(name).to_int():
		NetworkManager.hide_loading()
	else:
		# Other players' models should be on layer 1 (visible to everyone).
		_set_model_layer(1)

func set_overlord_active(active: bool) -> void:
	## Enable/disable this Overlord's input and camera.
	## Called when the player warps to/from the Avatar entity.
	_overlord_active = active
	var is_local := multiplayer.get_unique_id() == str(name).to_int()

	_player_input.input_enabled = active

	if is_local:
		if active:
			_camera_input.camera_3d.current = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			_camera_input.camera_3d.current = false

func _set_model_layer(layer: int) -> void:
	# Set all visual meshes on the Lich to the specified layer.
	# Layer 1 = visible to all cameras, Layer 2 = hidden from own camera.
	if _model == null:
		return
	var skeleton := _model.find_child("Skeleton3D", true, false)
	if skeleton == null:
		return
	var other_layer := 2 if layer == 1 else 1
	for node in skeleton.get_children():
		if node is VisualInstance3D:
			node.set_layer_mask_value(layer, true)
			node.set_layer_mask_value(other_layer, false)
