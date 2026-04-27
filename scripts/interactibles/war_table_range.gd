@tool
class_name WarTableRange extends MeshInstance3D

## Semi-transparent ground marker showing the world region a WarTable
## represents. Self-positions at `war_table.map_world_center` and self-sizes
## to `war_table.map_world_size`. Reads from the WarTable (not its Map child)
## because WarTable is the authored source of truth for the region, and
## WarTable is not @tool — so in the editor the values only exist on the
## parent, not yet propagated into the child WarTableMap.
## Visible in both editor and runtime so level designers can see what the
## diorama thinks the battlefield looks like.

@export var war_table: WarTable:
	set(value):
		war_table = value
		_refresh()

@export var color: Color = Color(0.95, 0.75, 0.2, 0.02):
	set(value):
		color = value
		_refresh()

## Vertical extent of the box volume. The box is centered vertically on
## `map_world_center.y + height/2` so the bottom sits on the map plane.
@export var height: float = 20.0:
	set(value):
		height = value
		_refresh()

## First instance to enter the tree "wins" and renders; any additional
## ranges (the other three towers in world.tscn) hide themselves so the
## four overlapping boxes don't compound into an opaque slab. Applies in
## editor too — opening tower.tscn alone still shows the single range.
static var _active: WarTableRange = null

func _ready() -> void:
	if not is_instance_valid(_active):
		_active = self
	elif _active != self:
		visible = false
		return
	_refresh()

func _exit_tree() -> void:
	if _active == self:
		_active = null

func _process(_delta: float) -> void:
	# Tool-mode live refresh while the designer tweaks exports in the inspector.
	# Cheap: just assigns a mesh + material.
	if Engine.is_editor_hint() and visible:
		_refresh()

func _refresh() -> void:
	if war_table == null:
		mesh = null
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(war_table.map_world_size.x, height, war_table.map_world_size.y)
	mesh = bm
	# Setters fire during scene deserialization before the node is in the
	# tree; skip the transform write in that window to avoid the
	# `!is_inside_tree()` error. `_ready` calls `_refresh` once in-tree.
	if is_inside_tree():
		global_position = war_table.map_world_center + Vector3.UP * (height * 0.5)
	material_override = _build_material()

func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	return mat
