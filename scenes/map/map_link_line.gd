@tool
class_name MapLinkLine extends Node3D

## A straight line on the map floor between two neighbouring map points (MapPoint.neighbors). Authored in
## map_floor.tscn under Links, one per neighbour pair (MapFloor's "Copy map points and links" button adds the missing
## ones, their ends on the two points' markers); drag its From and To ends or restyle it there by hand. Shown in play
## once its owner knows both points, lit up while the way being chosen runs along it; pencil and ink follow it.
## The stroke is a flat strip (a 1 m plane, map_link_line.tscn's Ribbon, a wider Highlight under it) stretched
## between the two ends.
## PLACEHOLDER: art — a thin ink stroke, a red one under it when lit (map_link_line.tscn's Ribbon and Highlight).

## Height of the stroke above its ends, so it lies on the floor's picture.
const LIFT: float = 0.005

## The two map points (point ids) this line joins.
@export var from_point: StringName
@export var to_point: StringName
## Width of the stroke on the floor (metres), and of the lit stroke under it.
@export var width: float = 0.03:
	set(value):
		width = value
		_rebuild()
@export var highlight_width: float = 0.07:
	set(value):
		highlight_width = value
		_rebuild()

var highlighted: bool = false
var _drawn: PackedVector3Array = PackedVector3Array()

@onready var _from: Marker3D = %From
@onready var _to: Marker3D = %To
@onready var _ribbon: MeshInstance3D = %Ribbon
@onready var _highlight: MeshInstance3D = %Highlight

func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		set_process(false)

func _process(_delta: float) -> void:
	# Editor only: redraw when an end is dragged.
	if _drawn != _ends():
		_rebuild()

func ends_at(a: StringName, b: StringName) -> bool:
	return (from_point == a and to_point == b) or (from_point == b and to_point == a)

func points_in(space: Node3D, from: StringName) -> PackedVector3Array:
	## The line's two ends in `space`'s coordinates (the map floor's), starting at the end whose point id is `from`.
	var xf := space.global_transform.affine_inverse() * global_transform
	var out := PackedVector3Array([xf * _from.position, xf * _to.position])
	if from == to_point and from != from_point:
		out.reverse()
	return out

func set_highlighted(on: bool) -> void:
	highlighted = on
	_highlight.visible = on

func _ends() -> PackedVector3Array:
	return PackedVector3Array([_from.position, _to.position])

func _rebuild() -> void:
	if not is_node_ready():
		return
	_drawn = _ends()
	_stretch(_ribbon, width, 0.0)
	_stretch(_highlight, highlight_width, -LIFT * 0.5)

func _stretch(strip: MeshInstance3D, strip_width: float, drop: float) -> void:
	## The strip's plane from one end to the other, `strip_width` across.
	var a := _from.position
	var b := _to.position
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if along.length() < 0.0001:
		strip.scale = Vector3.ONE * 0.0001
		return
	var across := Vector3(-along.z, 0.0, along.x).normalized() * strip_width
	var mid := (a + b) * 0.5 + Vector3(0.0, LIFT + drop, 0.0)
	strip.transform = Transform3D(Basis(along, Vector3.UP, across), mid)
