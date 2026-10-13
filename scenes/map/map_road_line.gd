@tool
class_name MapRoadLine extends Path3D

## A road drawn on the map floor. Authored in map_floor.tscn under Roads, one per World/Roads road (MapFloor's
## "Copy map points and roads" button traces the missing ones, scaled to the floor); reshape it with the Path3D tools
## or restyle its Ribbon there by hand. Shown in play once its owner knows both ends; an order's ink and pencil
## follow it. The ribbon is redrawn from the curve whenever the curve changes.
## PLACEHOLDER: art — a thin ink stroke (map_road_line.tscn's Ribbon material).

## The World/Roads road this line draws (its node name), and its two ends' point ids.
@export var road: StringName
@export var from_point: StringName
@export var to_point: StringName
## Width of the stroke on the floor (metres).
@export var width: float = 0.03:
	set(value):
		width = value
		_rebuild()

@onready var _ribbon: MeshInstance3D = %Ribbon

func _ready() -> void:
	curve_changed.connect(_rebuild)
	_rebuild()

func ends_at(a: StringName, b: StringName) -> bool:
	return (from_point == a and to_point == b) or (from_point == b and to_point == a)

func points_in(space: Node3D, from: StringName) -> PackedVector3Array:
	## The line's points in `space`'s coordinates (the map floor's), starting at the end whose point id is `from`.
	var out := PackedVector3Array()
	if curve == null:
		return out
	var xf := space.global_transform.affine_inverse() * global_transform
	for p in curve.tessellate():
		out.append(xf * p)
	if from == to_point and from != from_point:
		out.reverse()
	return out

func _rebuild() -> void:
	if not is_node_ready() or curve == null:
		return
	var line := PackedVector3Array()
	for p in curve.tessellate():
		line.append(p)
	var lines: Array[PackedVector3Array] = [line]
	MapFloor.set_ribbons(_ribbon, lines, width)
