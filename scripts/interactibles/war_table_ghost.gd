class_name WarTableGhost extends Interactable

## Miniature visual of a single minion floating above a multi-member
## WarTablePiece. Spawned by WarTableStackInspector when the parent stack's
## popup is open. E toggles this single member id in the parent WarTable's
## selection.
##
## Highlight is per-ghost: only the ghost whose member is selected (or which is
## currently focused under the player's crosshair) glows. The parent stack's
## faction-tint walker skips ghost subtrees, so the stack-level "any selected"
## color doesn't bleed onto every ghost.

## Container under which the per-type model_scene is parented at spawn time.
## Authored as "Visual" in war_table_ghost.tscn so the inspector knows where
## to drop the cosmetic mesh without trampling on the Area3D's collider.
@export var visual_root: Node3D

@onready var _default_mesh: MeshInstance3D = get_node_or_null(^"Visual/DefaultMesh") as MeshInstance3D

var _default_material: StandardMaterial3D
var _highlight_material: StandardMaterial3D

func _interactable_ready() -> void:
	# Pre-build a default + highlighted material variant so we can swap them
	# on selection without rebuilding materials each frame. The base material
	# is the surface_material_override authored on DefaultMesh in the .tscn
	# (the SphereMesh sub-resource itself has no material assigned, so we
	# can't go through `_default_mesh.mesh.surface_get_material(0)` — that
	# returns null. `get_active_material(0)` falls through to the override).
	# We duplicate so per-ghost mutations don't bleed across siblings sharing
	# the authored resource.
	#
	# Default = the authored material verbatim (translucent gray, no
	# emission). Highlight = opaque bright yellow with strong emission so the
	# selected/hovered ghost is unmistakable.
	if _default_mesh:
		var base: Material = _default_mesh.get_active_material(0)
		if base is StandardMaterial3D:
			_default_material = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			_highlight_material = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			_highlight_material.albedo_color = Color(1.0, 0.95, 0.35, 1.0)
			_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			_highlight_material.emission_enabled = true
			_highlight_material.emission = Color(1.0, 0.9, 0.2, 1.0)
			_highlight_material.emission_energy_multiplier = 4.0
			_default_mesh.set_surface_override_material(0, _default_material)

func _process(_delta: float) -> void:
	# Each frame, decide whether this ghost should glow: yes if its member id
	# is in the table's selection OR the player is currently aiming at us.
	if _default_mesh == null:
		return
	if _default_material == null or _highlight_material == null:
		return
	var pid := get_local_peer_id()
	if int(get_meta(&"owner_peer_id", -1)) != pid:
		return
	var mid := int(get_meta(&"member_id", -1))
	if mid < 0:
		return
	var table := _find_war_table()
	var sel := false
	if table:
		sel = table.is_selected(mid)
	var highlight: bool = sel or _is_focused
	_default_mesh.set_surface_override_material(
		0,
		_highlight_material if highlight else _default_material,
	)

func setup(member_id: int, owner_pid: int, faction: int) -> void:
	set_meta(&"member_id", member_id)
	set_meta(&"owner_peer_id", owner_pid)
	set_meta(&"faction", faction)

func get_prompt_text() -> String:
	var table := _find_war_table()
	if table == null or not table.is_active_for_local_peer():
		return ""
	var pid := get_local_peer_id()
	if int(get_meta(&"owner_peer_id", -1)) != pid:
		return ""
	var mid := int(get_meta(&"member_id", -1))
	if mid < 0:
		return ""
	if KnowledgeManager.is_minion_pending(pid, mid):
		return ""
	if table.is_selected(mid):
		return "[E] deselect"
	return "[E] select"

func get_prompt_color() -> Color:
	return Color(1, 1, 0.5)

func _on_interact() -> void:
	var table := _find_war_table()
	if table == null or not table.is_active_for_local_peer():
		return
	var pid := get_local_peer_id()
	if int(get_meta(&"owner_peer_id", -1)) != pid:
		return
	var mid := int(get_meta(&"member_id", -1))
	if mid < 0:
		return
	if KnowledgeManager.is_minion_pending(pid, mid):
		return
	table.toggle_select_one(mid)

func set_focused(focused: bool, who: Node3D = null) -> void:
	super(focused, who)
	var table := _find_war_table()
	if table:
		table.notify_ghost_focus(self if focused else null)

func get_source_stack() -> WarTablePiece:
	var n: Node = get_parent()
	while n:
		if n is WarTablePiece:
			return n as WarTablePiece
		n = n.get_parent()
	return null

func _find_war_table() -> WarTable:
	var n: Node = get_parent()
	while n:
		if n is WarTable:
			return n as WarTable
		n = n.get_parent()
	return null
