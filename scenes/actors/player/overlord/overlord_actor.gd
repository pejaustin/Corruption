class_name OverlordActor extends PlayerActor

## Per-player tower body. First-person perspective, Lich model.
## Always active (unlike the Avatar, which is dormant when unclaimed).
## When a player claims the Avatar, `set_overlord_active(false)` idles this
## body until they return.

@export var _player_input: PlayerInput
@export var _camera_input: CameraInput

var _overlord_active: bool = true
## The scroll of orders in this overlord's hand (GDD §3: "a scroll of orders
## appears in your hand"), empty when holding nothing. Local to its owner:
## { group_ids, believed, route_points, route, dest_point, dest_kind }.
var held_order: Dictionary = {}
var _scroll_visual: MeshInstance3D

## Public accessor for the player's visual model. Use this instead of
## get_node("Model") so consumers don't depend on child naming.
func get_model() -> Node3D:
	return _model

## The dark lord himself fights for his own seat. He isn't a combatant: units
## that reach a tower sack it (CorruptionSite, GDD §7) rather than kill him.
func get_allegiance() -> int:
	return str(name).to_int()

func can_take_damage() -> bool:
	return false

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

# --- The scroll of orders (held item) ---

func hold_order(order: Dictionary) -> void:
	held_order = order.duplicate(true)
	_show_scroll(true)

func take_order() -> Dictionary:
	var order := held_order
	held_order = {}
	_show_scroll(false)
	return order

func is_holding_order() -> bool:
	return not held_order.is_empty()

func _show_scroll(show: bool) -> void:
	## PLACEHOLDER: art — a rolled scroll held at the bottom right of the view.
	if _scroll_visual == null and show:
		var cam := _camera_input.camera_3d if _camera_input else null
		if cam == null:
			return
		_scroll_visual = MeshInstance3D.new()
		_scroll_visual.name = "HeldScroll"
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.03
		mesh.bottom_radius = 0.03
		mesh.height = 0.28
		_scroll_visual.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.84, 0.66)
		_scroll_visual.material_override = mat
		_scroll_visual.position = Vector3(0.22, -0.2, -0.45)
		_scroll_visual.rotation = Vector3(0.3, 0.0, 1.2)
		_scroll_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cam.add_child(_scroll_visual)
	if _scroll_visual:
		_scroll_visual.visible = show

func _unhandled_input(event: InputEvent) -> void:
	if multiplayer.get_unique_id() != str(name).to_int() or not _overlord_active:
		return
	# Q tears up the scroll in hand.
	if event.is_action_pressed("cancel") and is_holding_order() and not Interactable.has_modal():
		take_order()
		KnowledgeManager.advisor_spoke.emit("PLACEHOLDER: You tear up the orders.")
		get_viewport().set_input_as_handled()
