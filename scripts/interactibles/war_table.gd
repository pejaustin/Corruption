class_name WarTable extends Interactable

## War Table interactible in each tower.
## Overlord interacts to enter a top-down map view.
## Click to set waypoints for their minions. E again to exit.
## Faction-specific features:
##   Eldritch: Right-click enemy minion to dominate (convert to your faction)
##   Nature/Fey: See enemy minion positions on the map
##   Demonic: Shift+click to command a single nearest minion

## Marker3D (or any Node3D) whose global_transform defines the top-down view
## target. The overlord's camera is tweened to this transform while the table
## is active. Position it straight above the area of interest, rotated -90° on X.
@export var map_view_point: Node3D

## Marker3D (or any Node3D) where the overlord stands while using the table.
## The player is tweened here so their rig (and thus the first-person hands)
## ends up at a consistent pose. Face the marker toward the table.
@export var stand_point: Node3D

## Diorama surface that renders WorldModel belief and maps table clicks to
## world coordinates. Child Node3D with WarTableMap script.
@export var map: WarTableMap

## Mapping config. Authored here on the interactable rather than on the Map
## child so per-tower regions live next to the rest of the table's setup.
## Setters tunnel through to `map` when it's assigned; values are re-applied
## once in `_interactable_ready` to cover the scene-load case where `map`
## hadn't been resolved yet when these setters first ran.
@export var map_world_size: Vector2 = Vector2(30.0, 30.0):
	set(value):
		map_world_size = value
		if map:
			map.map_world_size = value
@export var map_world_center: Vector3 = Vector3.ZERO:
	set(value):
		map_world_center = value
		if map:
			map.map_world_center = value

const TAKEOVER_DURATION: float = 0.6
const RELEASE_DURATION: float = 0.4

var _war_table_active: bool = false
var _active_peer_id: int = -1
var _active_faction: int = -1
var _player_tween: Tween
var _player_return_transform: Transform3D = Transform3D.IDENTITY

func _interactable_ready() -> void:
	if map:
		map.map_world_size = map_world_size
		map.map_world_center = map_world_center

func _process(delta: float) -> void:
	super(delta)
	if not map:
		return
	# Render the local peer's belief whenever they're near or using this table.
	# A proper "any tower shows its owning overlord's belief" pass comes once
	# tower↔overlord bindings are threaded through — for now the table is tied
	# to whoever is standing next to it.
	var peer_id := _active_peer_id if _war_table_active else get_overlord_peer_id()
	if peer_id == -1:
		return
	map.render_from_model(KnowledgeManager.get_model(peer_id))

func _check_focus() -> bool:
	# While the table is driving the camera, keep focus sticky so the exit
	# prompt stays up and the E key still routes here.
	if _war_table_active and _player_in_range and _is_local_player(_player_in_range):
		return true
	return super()

func _on_body_exited(body: Node3D) -> void:
	# While the war table is active we tween the player to a stand point that
	# lies outside the Area3D — physics then reports an exit we want to ignore.
	# Keep the player reference intact so the exit prompt and _refresh_prompt
	# still have something to work with. A real exit only happens via E input
	# (_on_interact → _exit_war_table).
	if _war_table_active and body is OverlordActor and body == _player_in_range:
		return
	super(body)

func _on_player_exited() -> void:
	# Only reachable when the player leaves without being tweened out (normal
	# walk-away). _on_body_exited above filters the tween-induced case.
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
	_active_faction = GameState.get_faction(peer_id)
	_set_overlord_input_enabled(false)
	_tween_player_to_stand()
	var ci := _get_overlord_camera_input()
	if ci and map_view_point:
		ci.take_over(map_view_point.global_transform, TAKEOVER_DURATION)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_prompt()

func _exit_war_table() -> void:
	_war_table_active = false
	_active_peer_id = -1
	_active_faction = -1
	var ci := _get_overlord_camera_input()
	if ci:
		ci.release(RELEASE_DURATION)
	_tween_player_back()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_set_overlord_input_enabled(true)
	_refresh_prompt()

func _tween_player_to_stand() -> void:
	if not _player_in_range or not stand_point:
		return
	if _player_tween and _player_tween.is_valid():
		_player_tween.kill()
	_player_return_transform = _player_in_range.global_transform
	# Zero velocity so physics doesn't fight the tween.
	_player_in_range.velocity = Vector3.ZERO
	_player_in_range.set_physics_process(false)
	var start_xform := _player_in_range.global_transform
	var end_xform := stand_point.global_transform
	_player_tween = create_tween()
	_player_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_player_tween.tween_method(
		func(t: float) -> void: _set_player_global(start_xform.interpolate_with(end_xform, t)),
		0.0, 1.0, TAKEOVER_DURATION
	)

func _tween_player_back() -> void:
	if not _player_in_range:
		return
	if _player_tween and _player_tween.is_valid():
		_player_tween.kill()
	var start_xform := _player_in_range.global_transform
	var end_xform := _player_return_transform
	_player_tween = create_tween()
	_player_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_player_tween.tween_method(
		func(t: float) -> void: _set_player_global(start_xform.interpolate_with(end_xform, t)),
		0.0, 1.0, RELEASE_DURATION
	)
	_player_tween.tween_callback(_finish_player_tween_back)

func _set_player_global(xform: Transform3D) -> void:
	if _player_in_range:
		_player_in_range.global_transform = xform

func _finish_player_tween_back() -> void:
	if _player_in_range:
		_player_in_range.set_physics_process(true)

func _get_overlord_camera_input() -> CameraInput:
	if not _player_in_range:
		return null
	return _player_in_range.get_node_or_null("CameraInput") as CameraInput

func _set_overlord_input_enabled(enabled: bool) -> void:
	if not _player_in_range:
		return
	var pi := _player_in_range.get_node_or_null("PlayerInput") as PlayerInput
	if pi:
		pi.input_enabled = enabled

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	## Raycast the overlord camera against the diorama plane and convert the
	## hit point into world-space battlefield coordinates via the map.
	var ci := _get_overlord_camera_input()
	if not ci or not ci.camera_3d or not map:
		return Vector3.ZERO
	var world_pos: Vector3 = map.camera_ray_to_world(ci.camera_3d, screen_pos)
	if world_pos == Vector3.INF:
		return Vector3.ZERO
	return world_pos

func _command_move_to_click(screen_pos: Vector2) -> void:
	var world_pos = _screen_to_world(screen_pos)
	if world_pos == Vector3.ZERO:
		return
	KnowledgeManager.issue_move_command(_active_peer_id, world_pos)

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
