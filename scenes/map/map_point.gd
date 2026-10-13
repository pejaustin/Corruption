@tool
class_name MapPoint extends Marker3D

## One selectable point of the strategic map (GDD §3: "Illustrated features ...
## and a discrete set of selectable points. Many points, including far ones, are
## known at the start; others are missing and get filled in from what couriers
## bring home"). Authored in the world scene under World/MapPoints at the real
## place it stands for; the tower map floors draw them scaled down. Orders
## target points, never free positions.
##
## Every walkable place is a point with a `kind`, joined to the points next to it
## by `neighbors` (Austin, 2026-10-13: "add a type to all walkable locations, build
## a node tree of neighbors, and then the walk paths from each can be emergent").
## An order walks from point to point along the neighbours (PointGraph); between
## two points the navmesh finds the way.
##
## Which points exist, their names and neighbours are Austin's (ticket #584): the
## shipped layout is a placeholder.

const GROUP: StringName = &"map_points"

## What kind of place a point is (every walkable point has one): the goals an order there offers (OrderGoal) and its
## marker's colour on the map floor follow it.
enum Kind { ROAD, CROSSING, SETTLEMENT, CITY, SITE, RESOURCE, TOWER, LANDMARK }

## Stable id used in orders and per-player knowledge. Defaults to the node name.
@export var point_id: StringName
@export var display_name: String = ""
@export var kind: Kind = Kind.ROAD
## Known to every player from the first minute; otherwise discovered when a
## courier or group returns from passing near it.
@export var known_at_start: bool = true
## Optional: the corruption site / resource / settlement node this point is for.
@export var target: NodePath
## Tower points: snap onto the courier gate of the tower in this slot.
@export var tower_slot: int = -1
## The points next to this one: a unit here may walk straight to any of them. Two-way: listing B on A is enough for
## A–B (listing it on both is harmless). Pick them in the Inspector (drag MapPoints from the scene tree).
## PLACEHOLDER: the shipped neighbours are one pair per old road (2026-10-13), not designed (PLACEHOLDERS.md).
@export var neighbors: Array[MapPoint] = []

func _ready() -> void:
	if point_id == &"":
		point_id = StringName(name)
	if Engine.is_editor_hint():
		return
	add_to_group(GROUP)
	_snap.call_deferred()

func get_target_node() -> Node:
	if target.is_empty():
		return null
	return get_node_or_null(target)

func get_label() -> String:
	return display_name if display_name != "" else String(point_id)

func _snap() -> void:
	if tower_slot >= 0:
		# The tower in this slot (its slot_index, as MinionManager.bind_tower_markers uses it).
		for n in get_tree().get_nodes_in_group(Tower.GROUP):
			var t := n as Tower
			if t and t.slot_index == tower_slot and t.courier_spawn:
				global_position = t.courier_spawn.global_position
				return
	# Drop onto the ground below (terrain or static geometry).
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, global_position + Vector3.DOWN * 200.0, 1)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position

static func spot_in_world(p: MapPoint, world: Node) -> Vector3:
	## Where `p` stands in play, read from a world scene that is not in the tree (tools): a tower point on its
	## tower's courier gate (as _snap puts it), any other where it is authored.
	var xf := Transform3D.IDENTITY
	var n: Node = p
	if p.tower_slot >= 0:
		for t in world.find_children("Tower", "Node3D", true, false):
			if int(t.get("slot_index")) == p.tower_slot and t.has_node("CourierSpawn"):
				n = t.get_node("CourierSpawn")
				break
	while n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf.origin

static func all_points(tree: SceneTree) -> Array[MapPoint]:
	var out: Array[MapPoint] = []
	for n in tree.get_nodes_in_group(GROUP):
		if n is MapPoint:
			out.append(n)
	return out

static func find(tree: SceneTree, id: StringName) -> MapPoint:
	for p in all_points(tree):
		if p.point_id == id:
			return p
	return null
