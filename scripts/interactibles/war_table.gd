class_name WarTable extends Interactable

## War Table interactible in each tower.
##
## The table is no longer a modal "press E to use" surface. Every affordance on
## the table is its own discrete Interactable, all driven by E:
##   - WarTablePiece (cluster on the diorama) — E selects all available members.
##   - WarTableGhost (per-member ghost spawned by the inspector) — E toggles one.
##   - WarTableMapTarget (flat area over the diorama) — E records a draft for
##     the current selection at the aim point.
##   - WarTablePaper (orders scroll on the table) — E promotes drafts → readied.
##   - WarTableReset (reset prop on the table) — E clears drafts + selection.
##
## The Advisor (separate interactable, on the advisor minion) consumes readied
## orders and dispatches couriers. See advisor_handoff.gd.
##
## This script is a passive container for the local peer's selection state and
## the focus telemetry the StackInspector needs. The table itself is still an
## Interactable so it shows up in groups / world queries, but its prompt stays
## blank (its pieces speak for it).

## Diorama surface that renders WorldModel belief and maps table clicks to
## world coordinates. Child Node3D with WarTableMap script.
@export var map: WarTableMap

## Mapping config. Authored here on the interactable rather than on the Map
## child so per-tower regions live next to the rest of the table's setup.
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

## Local-peer selection. Children of this node (pieces, ghosts, map-target)
## mutate this via the toggle_* / clear_selection methods below.
var _selected_minion_ids: Array[int] = []
## Focus telemetry. The piece sets _focused_stack on its own focus events; the
## ghost sets _focused_ghost. The StackInspector reads both to keep the popup
## open while the player aims at any of the popup-group nodes.
var _focused_stack: WarTablePiece = null
var _focused_ghost: WarTableGhost = null
## The stack whose ghost popup is currently latched open. Set by E on a
## multi-member piece (toggle); cleared by the inspector's grace-timer when
## the player aims away from the popup group for too long, by E on the same
## piece a second time, or by the stack despawning.
var _popup_for_stack: WarTablePiece = null

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
	# Each overlord's war table is private — a foreign tower's table renders
	# nothing on this client. The local peer only sees / acts on their own
	# tower's belief. Test harnesses without a Tower parent are treated as
	# locally-owned so they keep working.
	if not is_active_for_local_peer():
		map.clear_pieces()
		return
	var peer_id := multiplayer.get_unique_id()
	if peer_id == -1:
		return
	map.render_from_model(KnowledgeManager.get_model(peer_id))
	map.set_selected_pieces(_selected_minion_ids)

func is_active_for_local_peer() -> bool:
	## True when this table is owned by the local peer (or has no Tower parent,
	## i.e. test harness). Children (Piece / Ghost / MapTarget / Paper / Reset)
	## bail out with empty prompts and no-op interacts when this is false.
	var tower := _find_owning_tower()
	if tower == null:
		return true
	return tower.owner_peer_id == multiplayer.get_unique_id()

func _find_owning_tower() -> Tower:
	var n: Node = get_parent()
	while n:
		if n is Tower:
			return n as Tower
		n = n.get_parent()
	return null

# --- Prompt: the table itself doesn't prompt; its child interactables do. ---

func get_prompt_text() -> String:
	return ""

func get_prompt_color() -> Color:
	return Color(0.6, 0.6, 0.6)

func _on_interact() -> void:
	pass

# --- Selection API (called by piece / ghost / map-target / reset). ---

func toggle_select(member_ids: Array[int]) -> void:
	## "Select-all" semantics: if every id in `member_ids` is already in the
	## selection, remove them all; otherwise add the missing ones. Used for the
	## piece's "[E] select all" path (multi-member stack interaction).
	if member_ids.is_empty():
		return
	var all_in: bool = true
	for mid in member_ids:
		if not _selected_minion_ids.has(mid):
			all_in = false
			break
	if all_in:
		for mid in member_ids:
			_selected_minion_ids.erase(mid)
	else:
		for mid in member_ids:
			if not _selected_minion_ids.has(mid):
				_selected_minion_ids.append(mid)

func toggle_select_one(member_id: int) -> void:
	## Per-member toggle. Used by ghosts in the inspector popup.
	if _selected_minion_ids.has(member_id):
		_selected_minion_ids.erase(member_id)
	else:
		_selected_minion_ids.append(member_id)

func is_selected(member_id: int) -> bool:
	return _selected_minion_ids.has(member_id)

func clear_selection() -> void:
	_selected_minion_ids.clear()

func has_selection() -> bool:
	return not _selected_minion_ids.is_empty()

func get_selection_size() -> int:
	return _selected_minion_ids.size()

# --- Drafts (called by map-target). ---

func issue_draft_at_aim(player: OverlordActor) -> bool:
	## Project the player's screen-center crosshair onto the diorama plane,
	## convert to world battlefield coords, and record a draft for the current
	## selection. Clears selection on success. Returns false if there's no
	## selection or the projection missed.
	if _selected_minion_ids.is_empty():
		return false
	if player == null or map == null:
		return false
	var ci := player.get_node_or_null("CameraInput") as CameraInput
	if ci == null or ci.camera_3d == null:
		return false
	var screen_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var world_pos: Vector3 = map.camera_ray_to_world(ci.camera_3d, screen_center)
	if world_pos == Vector3.INF:
		return false
	KnowledgeManager.issue_move_command(multiplayer.get_unique_id(), _selected_minion_ids, world_pos)
	_selected_minion_ids.clear()
	return true

# --- Focus telemetry (called by piece / ghost). ---

func notify_stack_focus(stack: WarTablePiece) -> void:
	_focused_stack = stack

func notify_ghost_focus(ghost: WarTableGhost) -> void:
	_focused_ghost = ghost

# --- Popup latch (called by piece on E). ---

func toggle_popup_for(stack: WarTablePiece) -> void:
	## E on a multi-member piece toggles its ghost popup. E on the same piece
	## again closes it. E on a different multi-member piece closes the previous
	## popup and opens this one.
	if _popup_for_stack == stack:
		_popup_for_stack = null
	else:
		_popup_for_stack = stack

func is_popup_open_for(stack: WarTablePiece) -> bool:
	return _popup_for_stack == stack and is_instance_valid(_popup_for_stack)
