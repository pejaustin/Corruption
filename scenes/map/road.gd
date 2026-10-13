@tool
class_name Road extends Path3D

## A road between two map points (Austin, 2026-10-13: "Each road is a Path3D in world.tscn between two MapPoints,
## with bridges as points on it; you draw them on the real terrain"). Orders follow roads: a group walks every point
## of the curve on its way, so a bridge is simply a curve point placed on a RiverCrossing. Lives under World/Roads.
##
## To draw one: instance scenes/map/road.tscn under World/Roads, set From Point and To Point, then add points with
## the Path3D toolbar from one end to the other. "Drop points onto the ground" puts every point on the terrain and
## the two ends on their map points. Roads are two-way; the graph of roads is RoadGraph.

const GROUP: StringName = &"roads"
## Units walk the road in steps no longer than this (metres): a long straight span between two curve points is cut
## into shorter ones so the navmesh path between them stays on the road.
## PLACEHOLDER: tuning, not designed.
const MAX_STEP_M: float = 40.0
## Curve tessellation for bends drawn with handles (Curve3D.tessellate).
const TESSELLATE_STAGES: int = 5
const TESSELLATE_DEGREES: float = 4.0
## How far above and below a point the ground is looked for.
const DROP_REACH_M: float = 500.0

@export var from_point: MapPoint
@export var to_point: MapPoint
@export_tool_button("Drop points onto the ground", "CurveTexture") var drop_onto_ground_button: Callable = drop_onto_ground

func _ready() -> void:
	if Engine.is_editor_hint():
		if curve == null:
			# Data-only: a new road needs its own curve to draw on.
			curve = Curve3D.new()
		return
	add_to_group(GROUP)

func get_length() -> float:
	return curve.get_baked_length() if curve else 0.0

func waypoints(forward: bool = true) -> Array[Vector3]:
	## The road's points in world space, from `from_point` to `to_point` (or back): every curve point (bridges
	## included), bends tessellated, and long spans cut to MAX_STEP_M. The two ends are its map points.
	var out: Array[Vector3] = []
	if curve == null or curve.point_count == 0:
		return out
	var pts := curve.tessellate(TESSELLATE_STAGES, TESSELLATE_DEGREES)
	var xf := global_transform
	for i in pts.size():
		var p: Vector3 = xf * pts[i]
		# The ends are where the points stand in play (a tower point stands on its tower's gate, MapPoint._snap).
		if i == 0 and from_point:
			p = from_point.global_position
		elif i == pts.size() - 1 and to_point:
			p = to_point.global_position
		if i > 0:
			var prev := out[out.size() - 1]
			var steps := ceili(prev.distance_to(p) / MAX_STEP_M)
			for k in range(1, steps):
				out.append(prev.lerp(p, float(k) / steps))
		out.append(p)
	if not forward:
		out.reverse()
	return out

func drop_onto_ground() -> void:
	## Editor button: each curve point onto the terrain below (or above) it, the ends onto their map points.
	if curve == null:
		return
	var space := get_world_3d().direct_space_state
	var inv := global_transform.affine_inverse()
	for i in curve.point_count:
		var at: Vector3 = global_transform * curve.get_point_position(i)
		if i == 0 and from_point:
			at = from_point.global_position
		elif i == curve.point_count - 1 and to_point:
			at = to_point.global_position
		else:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * DROP_REACH_M, at + Vector3.DOWN * DROP_REACH_M, 1))
			if not hit.is_empty():
				at = hit.position
		curve.set_point_position(i, inv * at)
