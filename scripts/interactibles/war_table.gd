extends Interactable

## War Table interactible in each tower.
## Overlord interacts to enter a top-down map view.
## Click to set waypoints for their minions. E again to exit.
## Faction-specific features:
##   Eldritch: Right-click enemy minion to dominate (convert to your faction)
##   Nature/Fey: See enemy minion positions on the map
##   Demonic: Shift+click to command a single nearest minion

@export var map_camera: Camera3D

var _war_table_active: bool = false
var _active_peer_id: int = -1
var _active_faction: int = -1

func _interactable_ready() -> void:
	if map_camera:
		map_camera.current = false

func _on_player_exited() -> void:
	if _war_table_active:
		_exit_war_table()

func get_prompt_text() -> String:
	if _war_table_active:
		var base = "Click to command minions | E to exit"
		match _active_faction:
			GameConstants.Faction.ELDRITCH:
				base += "\nRight-click enemy minion to dominate"
			GameConstants.Faction.NATURE_FEY:
				base += "\nEnemy positions visible (Fey sight)"
			GameConstants.Faction.DEMONIC:
				base += "\nShift+click for single minion command"
		return base
	elif is_overlord_in_range():
		return "Press E to use War Table"
	return "War Table"

func get_prompt_color() -> Color:
	if _war_table_active:
		return Color(0.4, 1, 0.4)
	elif is_overlord_in_range():
		return Color(1, 1, 0)
	return Color(0.6, 0.6, 0.6)

func _on_interact() -> void:
	if _war_table_active:
		_exit_war_table()
		return
	if not is_overlord_in_range():
		return
	var peer_id = get_overlord_peer_id()
	if get_local_peer_id() != peer_id:
		return
	if GameState.is_avatar(peer_id):
		return
	_enter_war_table(peer_id)

func _unhandled_input(event: InputEvent) -> void:
	if _war_table_active and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Input.is_key_pressed(KEY_SHIFT) and _active_faction == GameConstants.Faction.DEMONIC:
				_command_nearest_minion(event.position)
			else:
				_command_move_to_click(event.position)
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_RIGHT and _active_faction == GameConstants.Faction.ELDRITCH:
			_attempt_dominate(event.position)
			get_viewport().set_input_as_handled()
			return
	super(event)

func _enter_war_table(peer_id: int) -> void:
	_war_table_active = true
	_active_peer_id = peer_id
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if mm:
		_active_faction = mm._get_player_faction(peer_id)
	if map_camera:
		map_camera.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_prompt()

func _exit_war_table() -> void:
	_war_table_active = false
	_active_peer_id = -1
	_active_faction = -1
	if map_camera:
		map_camera.current = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if _player_in_range:
		var ci = _player_in_range.get_node_or_null("CameraInput") as CameraInput
		if ci and ci.camera_3d:
			ci.camera_3d.current = true
	_refresh_prompt()

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	if not map_camera:
		return Vector3.ZERO
	var from = map_camera.project_ray_origin(screen_pos)
	var dir = map_camera.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.001:
		return Vector3.ZERO
	var t = -from.y / dir.y
	if t < 0:
		return Vector3.ZERO
	return from + dir * t

func _command_move_to_click(screen_pos: Vector2) -> void:
	var world_pos = _screen_to_world(screen_pos)
	if world_pos == Vector3.ZERO:
		return
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if mm:
		mm.command_minions_move(world_pos)

func _command_nearest_minion(screen_pos: Vector2) -> void:
	## Demonic faction: Shift+click commands only the nearest minion to the click.
	var world_pos = _screen_to_world(screen_pos)
	if world_pos == Vector3.ZERO:
		return
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if not mm:
		return
	var my_minions = mm.get_minions_for_player(_active_peer_id)
	if my_minions.is_empty():
		return
	var closest: MinionActor = null
	var closest_dist := INF
	for m in my_minions:
		var d = m.global_position.distance_to(world_pos)
		if d < closest_dist:
			closest_dist = d
			closest = m
	if closest:
		mm.command_minion_move(closest.name.to_int(), world_pos)

func _attempt_dominate(screen_pos: Vector2) -> void:
	## Eldritch faction: Right-click near an enemy minion to dominate it.
	var world_pos = _screen_to_world(screen_pos)
	if world_pos == Vector3.ZERO:
		return
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if not mm:
		return
	# Find nearest enemy minion within 3 units of click
	var best: MinionActor = null
	var best_dist := 3.0
	for m in mm.get_all_minions():
		if m.owner_peer_id == _active_peer_id:
			continue
		if not m.can_take_damage():
			continue
		var d = m.global_position.distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			best = m
	if best:
		mm.request_dominate_minion(best.name.to_int(), _active_peer_id)

func _refresh_prompt() -> void:
	if _is_focused and _player_in_range:
		InteractionUI.set_prompt(self, get_prompt_text(), get_prompt_color())
