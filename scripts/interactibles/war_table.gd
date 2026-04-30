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
## How close (in TABLE-LOCAL meters, i.e. on-diorama distance) a click must
## land to a believed-minion piece to count as a click on that piece. Measured
## on the table surface so it stays sane regardless of map_world_size — a
## world-meter radius would shrink to pixel-perfect on a 300×300 tower map.
## ~2× piece_radius keeps the click area roughly the visible footprint plus
## a small forgiveness band.
const PIECE_SELECT_LOCAL_RADIUS: float = 0.13

var _war_table_active: bool = false
var _active_peer_id: int = -1
var _active_faction: int = -1
var _player_tween: Tween
var _player_return_transform: Transform3D = Transform3D.IDENTITY
## Two-click command flow: first click on a piece adds it here, second click on
## empty map submits an order for these IDs. Cleared on submit and on exit.
var _selected_minion_ids: Array[int] = []

func _interactable_ready() -> void:
	if map:
		map.map_world_size = map_world_size
		map.map_world_center = map_world_center
	# Towers register themselves into Tower.GROUP in _ready, but the war table
	# inside a tower may resolve _interactable_ready before its sibling towers
	# have run theirs. Defer the lookup so all towers are in the group first.
	call_deferred("_populate_tower_pieces")

func _populate_tower_pieces() -> void:
	if not map:
		return
	var towers: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group(Tower.GROUP):
		if n is Node3D:
			towers.append(n)
	map.set_tower_anchors(towers)

func _process(delta: float) -> void:
	super(delta)
	if not map:
		return
	# In-universe the table is the overlord's living intel surface — the advisor
	# keeps it current whether or not the overlord is standing at it. So render
	# the local peer's belief every frame regardless of proximity. A proper "any
	# tower shows its owning overlord's belief" pass comes once tower↔overlord
	# bindings are threaded through; until then every visible table renders the
	# local peer's model.
	var peer_id := _active_peer_id if _war_table_active else multiplayer.get_unique_id()
	if peer_id == -1:
		return
	map.render_from_model(KnowledgeManager.get_model(peer_id))
	# Refresh selection highlighting every frame so pieces repaint immediately
	# when toggled. Empty array when the table isn't active so leftover pieces
	# don't keep glowing.
	var highlight: Array[int] = []
	if _war_table_active:
		highlight = _selected_minion_ids
	map.set_selected_pieces(highlight)

func get_prompt_text() -> String:
	if _war_table_active:
		var draft_count := KnowledgeManager.get_draft_count(_active_peer_id)
		var base: String
		if _selected_minion_ids.is_empty():
			base = "Click a minion piece to select"
		else:
			base = "Selected: %d | Click destination, or click pieces to add" % _selected_minion_ids.size()
		var footer := "[E] keep & exit  [Q] cancel & exit"
		if draft_count > 0 or not _selected_minion_ids.is_empty():
			footer += "  [⌫] undo"
		if draft_count > 0:
			footer += "   drafts: %d" % draft_count
		base += "\n" + footer
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
	if _war_table_active and event is InputEventKey and event.pressed and not event.echo:
		# Q (project's "cancel" action): leave the table AND throw away every
		# unhanded-off draft. Dispatched orders keep running — those couriers
		# are already in the world.
		if event.is_action_pressed(&"cancel"):
			KnowledgeManager.clear_drafts(_active_peer_id)
			_exit_war_table()
			get_viewport().set_input_as_handled()
			return
		# Backspace: progressively back out without exiting. First clears any
		# in-progress selection, otherwise pops the most recent draft.
		if event.keycode == KEY_BACKSPACE:
			if not _selected_minion_ids.is_empty():
				_selected_minion_ids = []
				_refresh_prompt()
			else:
				if KnowledgeManager.cancel_last_draft(_active_peer_id):
					_refresh_prompt()
			get_viewport().set_input_as_handled()
			return
	super(event)

func _enter_war_table(peer_id: int) -> void:
	_war_table_active = true
	_active_peer_id = peer_id
	_active_faction = GameState.get_faction(peer_id)
	# Claim the modal lock so other interactables (advisor, gem sites, …) stop
	# focusing or processing input while the table runs the camera and UI.
	_claim_modal()
	_set_overlord_input_enabled(false)
	# Camera takeover BEFORE the rig snap: take_over captures camera_3d's
	# current global as its tween-from point. Doing it before the snap means
	# the camera tween starts from the original first-person position rather
	# than teleporting sideways to follow the rig and then sliding up.
	var ci := _get_overlord_camera_input()
	if ci and map_view_point:
		ci.take_over(map_view_point.global_transform, TAKEOVER_DURATION)
	_tween_player_to_stand()
	# Zero camera_mount yaw / camera_rot pitch so when the camera releases on
	# exit it lands facing -Z relative to the rig (= toward the table, given
	# the StandPoint's identity rotation). Without this, the player keeps the
	# yaw they walked in with — and the camera tween-down ends at that old
	# angle, snapping the view away from the table.
	if ci:
		if ci.camera_mount:
			ci.camera_mount.rotation = Vector3.ZERO
		if ci.camera_rot:
			ci.camera_rot.rotation = Vector3.ZERO
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_prompt()

func _exit_war_table() -> void:
	_war_table_active = false
	_active_peer_id = -1
	_active_faction = -1
	_selected_minion_ids = []
	_release_modal()
	_tween_player_back()
	var ci := _get_overlord_camera_input()
	if ci:
		ci.release(RELEASE_DURATION)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_set_overlord_input_enabled(true)
	_refresh_prompt()

func _tween_player_to_stand() -> void:
	## Pin the rig at the stand point and visually slide the body Model from
	## "where the rig used to be" back to identity over TAKEOVER_DURATION.
	## Pinning (vs a one-shot transform set) is what survives netfox — see
	## PlayerActor.pin_transform.
	if not _player_in_range or not stand_point:
		return
	if _player_tween and _player_tween.is_valid():
		_player_tween.kill()
	_player_return_transform = _player_in_range.global_transform
	var model := _player_in_range.get_node_or_null(^"Model") as Node3D
	var pre_snap_model_global: Transform3D = model.global_transform if model else Transform3D.IDENTITY
	if _player_in_range is PlayerActor:
		(_player_in_range as PlayerActor).pin_transform(stand_point.global_transform)
	else:
		_player_in_range.global_transform = stand_point.global_transform
		_player_in_range.velocity = Vector3.ZERO
	if model:
		# Compensate the model so it visually stays where the rig used to be,
		# then tween its local transform back to identity (flush with the now-
		# pinned rig).
		model.global_transform = pre_snap_model_global
		var start_local := model.transform
		_player_tween = create_tween()
		_player_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_player_tween.tween_method(
			func(t: float) -> void: _set_model_local(model, start_local.interpolate_with(Transform3D.IDENTITY, t)),
			0.0, 1.0, TAKEOVER_DURATION
		)

func _tween_player_back() -> void:
	## Unpin so the rig is free to move again. We deliberately don't tween it
	## back to its pre-table position — the player ends up at the stand point
	## facing the table on exit (because we zeroed camera_mount on entry), and
	## can walk away from there. Trying to teleport-back would also fight the
	## rollback recorder, since the pinned transform is what's currently
	## recorded.
	if not _player_in_range:
		return
	if _player_tween and _player_tween.is_valid():
		_player_tween.kill()
	if _player_in_range is PlayerActor:
		(_player_in_range as PlayerActor).unpin_transform()
	# Snap the Model node back to identity in case its in-progress entry tween
	# left it offset. No exit tween — the camera's release is the visible
	# motion; the body following the camera doesn't need its own animation.
	var model := _player_in_range.get_node_or_null(^"Model") as Node3D
	if model:
		model.transform = Transform3D.IDENTITY

func _set_model_local(model: Node3D, xform: Transform3D) -> void:
	if model and is_instance_valid(model):
		model.transform = xform

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
	# Two-click flow: first try to hit a piece. If the click landed on one,
	# toggle it in the selection. Otherwise (empty map), if we have a selection
	# submit the command for it.
	var hit_id := _find_owned_piece_under_click(world_pos)
	if hit_id >= 0:
		if _selected_minion_ids.has(hit_id):
			_selected_minion_ids.erase(hit_id)
		else:
			_selected_minion_ids.append(hit_id)
		_refresh_prompt()
		return
	if _selected_minion_ids.is_empty():
		return
	KnowledgeManager.issue_move_command(_active_peer_id, _selected_minion_ids, world_pos)
	_selected_minion_ids = []
	_refresh_prompt()

func _find_owned_piece_under_click(world_pos: Vector3) -> int:
	if map == null:
		return -1
	var model := KnowledgeManager.get_model(_active_peer_id)
	if model == null:
		return -1
	# Hit-test in table-local meters so the threshold matches the visible piece
	# size regardless of map_world_size. World-space comparisons collapse to
	# pixel-perfect on large tower maps.
	var click_local: Vector3 = map.world_to_table_local(world_pos)
	var best_id: int = -1
	var best_dist: float = PIECE_SELECT_LOCAL_RADIUS
	# Only the local peer's own minions are commandable from this table —
	# clicking on a rival piece during the order phase shouldn't accidentally
	# select it.
	for mid in model.believed_friendly_minions.keys():
		var entry: Dictionary = model.believed_friendly_minions[mid]
		var owner_pid: int = int(entry.get("owner_peer_id", -1))
		if owner_pid != _active_peer_id:
			continue
		var piece_local: Vector3 = map.world_to_table_local(entry.get("pos", Vector3.ZERO))
		var dx: float = piece_local.x - click_local.x
		var dz: float = piece_local.z - click_local.z
		var d: float = sqrt(dx * dx + dz * dz)
		if d < best_dist:
			best_dist = d
			best_id = mid
	return best_id

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
