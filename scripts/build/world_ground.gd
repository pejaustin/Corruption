extends RefCounted
## The ground (`geo`) of one exported landscape size, for the build and bake tools (tools/bake_*.gd,
## scripts/build/build_world_sizes.gd): height lookups by ray, and the size's factors against the 2 km map.
## Used as `const Ground = preload("res://scripts/build/world_ground.gd")` (tools run before the class cache exists).

const LANDSCAPE: String = "res://art/world/export/world_landscape_%s.glb"

var size: String
var tri: TriangleMesh
var xf: Transform3D
## The ground's box in world space.
var box: AABB

func load_size(p_size: String) -> void:
	size = p_size
	var land: Node3D = (load(LANDSCAPE % size) as PackedScene).instantiate()
	var geo := land.get_node("geo") as MeshInstance3D
	tri = geo.mesh.generate_triangle_mesh()
	xf = geo.transform  # the glb's root is the origin
	box = xf * geo.mesh.get_aabb()
	land.free()

func y_at(x: float, z: float) -> float:
	## Ground height at x, z, or NAN outside the ground.
	var inv := xf.affine_inverse()
	var a: Vector3 = inv * Vector3(x, 3000.0, z)
	var b: Vector3 = inv * Vector3(x, -3000.0, z)
	var hit := tri.intersect_ray(a, (b - a).normalized())
	return NAN if hit.is_empty() else (xf * (hit["position"] as Vector3)).y

func factors_against(reference: RefCounted) -> Vector2:
	## (wide, tall): how much wider and taller this size's ground is than `reference`'s (the 2 km map).
	var ref_box: AABB = reference.get("box")
	return Vector2(box.size.x / ref_box.size.x, box.size.y / ref_box.size.y)
