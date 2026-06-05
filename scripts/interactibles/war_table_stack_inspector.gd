class_name WarTableStackInspector extends Node

## Owns the ghost-popup state for a single WarTable. The popup is now latched
## explicitly:
##   - E on a multi-member piece sets `WarTable._popup_for_stack`.
##   - The inspector mirrors that latch — spawn ghosts when it's set, despawn
##     when it's cleared.
##   - A grace timer auto-clears the latch when neither the source stack nor
##     any of its ghosts have been focused for AUTO_CLOSE_SECONDS — handles
##     "I aimed away and forgot to close it" without immediately yanking the
##     popup the moment the player flicks at the MapTarget.

@export var ghost_scene: PackedScene
## Radius of the ghost ring around the source stack, in TABLE-LOCAL meters.
@export var ghost_radius: float = 0.10
## Vertical offset of the ghost ring above the stack origin, in TABLE-LOCAL
## meters.
@export var ghost_height: float = 0.20
## Local scale applied to instantiated MinionType.model_scene visuals so they
## fit on the diorama. ~0.05 makes a ~2m-tall character render as a 10cm icon.
@export var model_visual_scale: float = 0.05
## Seconds the popup-group can be unfocused before the popup auto-closes.
@export var auto_close_seconds: float = 1.5

var _table: WarTable
var _open_stack: WarTablePiece = null
var _ghosts: Array[WarTableGhost] = []
var _away_timer: float = 0.0

func _ready() -> void:
	_table = _find_war_table()

func _process(delta: float) -> void:
	if _table == null:
		return
	# If the source stack vanished mid-popup (cluster reshuffle, minion died,
	# etc.) the ghost children went with it — drop our reference and clear
	# the latch so the next E reopens cleanly.
	if _open_stack and not is_instance_valid(_open_stack):
		_table._popup_for_stack = null
		_open_stack = null
		_ghosts.clear()
	# Mirror WarTable's latch.
	var desired: WarTablePiece = _table._popup_for_stack
	if desired and not is_instance_valid(desired):
		desired = null
		_table._popup_for_stack = null
	if desired != _open_stack:
		_close_popup()
		if desired and _is_multi_member(desired):
			_open_popup(desired)
			_away_timer = 0.0
	# Auto-close grace timer: if the popup is open AND nothing in the popup
	# group is focused, count down. Reset to 0 the moment focus returns.
	if _open_stack:
		if _is_group_focused():
			_away_timer = 0.0
		else:
			_away_timer += delta
			if _away_timer >= auto_close_seconds:
				_table._popup_for_stack = null
				_close_popup()

func _is_group_focused() -> bool:
	if _table._focused_stack == _open_stack:
		return true
	if _table._focused_ghost and is_instance_valid(_table._focused_ghost):
		var src := _table._focused_ghost.get_source_stack()
		if src == _open_stack:
			return true
	return false

func _is_multi_member(stack: WarTablePiece) -> bool:
	var ids: Array = stack.get_meta(&"member_ids", [] as Array)
	return ids.size() >= 2

func _open_popup(stack: WarTablePiece) -> void:
	if ghost_scene == null:
		return
	_open_stack = stack
	var ids: Array = stack.get_meta(&"member_ids", [] as Array)
	var owner_pid: int = int(stack.get_meta(&"owner_peer_id", -1))
	var faction: int = int(stack.get_meta(&"faction", GameConstants.Faction.NEUTRAL))
	var n := ids.size()
	for i in n:
		var ghost: WarTableGhost = ghost_scene.instantiate() as WarTableGhost
		if ghost == null:
			continue
		stack.add_child(ghost)
		var theta: float = float(i) * TAU / float(n)
		ghost.position = Vector3(
			cos(theta) * ghost_radius,
			ghost_height,
			sin(theta) * ghost_radius,
		)
		ghost.setup(int(ids[i]), owner_pid, faction)
		_apply_minion_model(ghost, int(ids[i]))
		_ghosts.append(ghost)

func _close_popup() -> void:
	for g in _ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_ghosts.clear()
	_open_stack = null

func _apply_minion_model(ghost: WarTableGhost, member_id: int) -> void:
	## Best-effort: look up the live MinionActor and instantiate its
	## MinionType.model_scene as the ghost's visual. If we can't find the
	## actor or the type lacks a model_scene, the ghost keeps its authored
	## DefaultMesh (a small yellow sphere) so the player can still see and
	## aim at it.
	var mm := _get_minion_manager()
	if mm == null:
		return
	var actor := mm.get_minion_by_id(member_id)
	if actor == null or actor.minion_type == null:
		return
	var model_scene: PackedScene = actor.minion_type.model_scene
	if model_scene == null:
		return
	var visual: Node = model_scene.instantiate()
	var node3d: Node3D = visual as Node3D
	if node3d == null:
		visual.queue_free()
		return
	node3d.scale = Vector3.ONE * model_visual_scale
	# Hide the authored DefaultMesh so we don't double-render.
	if ghost.visual_root:
		var fallback := ghost.visual_root.get_node_or_null(^"DefaultMesh") as MeshInstance3D
		if fallback:
			fallback.visible = false
		ghost.visual_root.add_child(node3d)
	else:
		ghost.add_child(node3d)

func _get_minion_manager() -> MinionManager:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("MinionManager") as MinionManager

func _find_war_table() -> WarTable:
	var n: Node = get_parent()
	while n:
		if n is WarTable:
			return n as WarTable
		n = n.get_parent()
	return null
