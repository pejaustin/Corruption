@tool
class_name RiverCrossing
extends Marker3D
## A ford: a place where units cross Pale River (Austin, 2026-10-12: every town on the river is a crossing; Hopes Gate is
## three, its city gates spanning three river openings). Hung under a town's marker in
## art/world/export/world_landscape_<size>.tscn. It works by being placed: `Ford` is an invisible walkable slab, so the
## navmesh bake (the editor's, on World/Nav) lays a path across the water on it, above the river's height-limited
## blockers. The slab's top must be above the water's blocker band (the water surface + WATER_CLEARANCE_M in
## PLACEHOLDERS.md): put Ford's top a little over the water surface, then rebake the navmesh.

## PLACEHOLDER: how far around this point the river can be crossed, in metres (the Ford slab's radius).
@export var radius_m: float = 20.0:
	set(value):
		radius_m = value
		_fit_ford()

func _ready() -> void:
	_fit_ford()

func _fit_ford() -> void:
	## The slab's shape (local to each instance) follows radius_m.
	var shape := get_node_or_null("Ford/Shape") as CollisionShape3D
	if shape != null and shape.shape is CylinderShape3D:
		(shape.shape as CylinderShape3D).radius = radius_m
