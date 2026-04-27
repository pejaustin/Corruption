class_name WarTableMap extends Node3D

## Diorama map on the War Table surface. Two responsibilities:
##   1. Convert between world-space coordinates (real battlefield) and
##      table-local coordinates (a point on the diorama surface).
##   2. Render chess-piece markers for every minion in a WorldModel,
##      colored by faction and positioned via the mapping.
##
## The node should be placed as a child of the War Table, at the top
## surface of the TableTop mesh (so local Y=0 is the diorama floor).

## World point that sits at the center of the diorama.
@export var map_world_center: Vector3 = Vector3.ZERO

## Size (X, Z) of the world region this diorama represents, in meters.
@export var map_world_size: Vector2 = Vector2(30.0, 30.0)

## Physical size (X, Z) of the drawable diorama surface, in local meters.
## Defaults match the 3x2 table top mesh in war_table.tscn.
@export var table_surface_size: Vector2 = Vector2(3.0, 2.0)

## Height above the diorama floor at which pieces sit.
@export var piece_height: float = 0.08
@export var piece_radius: float = 0.06

## How quickly pieces interpolate toward their target table-local position.
## Higher = snappier; lower = floatier. The lerp factor each tick is
## `clamp(piece_lerp_speed * delta, 0, 1)`, so 12.0 reaches ~half in one
## frame at 60 Hz and ~98% in 0.3s — fast enough to feel reactive while
## hiding the per-frame teleporting that came from snapping.
@export var piece_lerp_speed: float = 12.0

var _pieces: Dictionary[int, MeshInstance3D] = {}
var _piece_targets: Dictionary[int, Vector3] = {}
var _pieces_root: Node3D
var _materials: Dictionary[int, StandardMaterial3D] = {}

func _ready() -> void:
	_pieces_root = Node3D.new()
	_pieces_root.name = "Pieces"
	add_child(_pieces_root)

func _process(delta: float) -> void:
	if _pieces.is_empty():
		return
	var t: float = clampf(piece_lerp_speed * delta, 0.0, 1.0)
	for id in _pieces:
		var piece: MeshInstance3D = _pieces[id]
		if not is_instance_valid(piece):
			continue
		var target: Vector3 = _piece_targets.get(id, piece.position)
		piece.position = piece.position.lerp(target, t)

# --- Mapping ---

func world_to_table_local(world_pos: Vector3) -> Vector3:
	var dx: float = world_pos.x - map_world_center.x
	var dz: float = world_pos.z - map_world_center.z
	var sx: float = table_surface_size.x / map_world_size.x
	var sz: float = table_surface_size.y / map_world_size.y
	return Vector3(dx * sx, piece_height, dz * sz)

func table_local_to_world(table_local: Vector3) -> Vector3:
	var sx: float = map_world_size.x / table_surface_size.x
	var sz: float = map_world_size.y / table_surface_size.y
	return Vector3(
		map_world_center.x + table_local.x * sx,
		map_world_center.y,
		map_world_center.z + table_local.z * sz,
	)

## Converts a world-space point that hit the diorama plane into the
## corresponding world battlefield coordinate.
func table_world_hit_to_world(hit_world: Vector3) -> Vector3:
	return table_local_to_world(to_local(hit_world))

## Intersects a camera ray with the diorama plane (at this node's global Y).
## Returns Vector3.INF on miss.
func camera_ray_to_world(cam: Camera3D, screen_pos: Vector2) -> Vector3:
	if cam == null:
		return Vector3.INF
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.001:
		return Vector3.INF
	var plane_y: float = global_position.y
	var t: float = (plane_y - from.y) / dir.y
	if t < 0.0:
		return Vector3.INF
	var hit: Vector3 = from + dir * t
	return table_world_hit_to_world(hit)

# --- Piece rendering ---

func render_from_model(model: WorldModel) -> void:
	if model == null:
		return
	var seen: Dictionary[int, bool] = {}
	_render_bucket(model.believed_friendly_minions, seen)
	_render_bucket(model.believed_enemy_minions, seen)
	var to_remove: Array[int] = []
	for id in _pieces.keys():
		if id not in seen:
			to_remove.append(id)
	for id in to_remove:
		var piece := _pieces[id]
		if is_instance_valid(piece):
			piece.queue_free()
		_pieces.erase(id)
		_piece_targets.erase(id)

func clear_pieces() -> void:
	for piece in _pieces.values():
		if is_instance_valid(piece):
			piece.queue_free()
	_pieces.clear()
	_piece_targets.clear()

func _render_bucket(bucket: Dictionary, seen: Dictionary[int, bool]) -> void:
	for id in bucket.keys():
		var entry: Dictionary = bucket[id]
		seen[id] = true
		var faction: int = int(entry.get("faction", GameConstants.Faction.NEUTRAL))
		var target: Vector3 = world_to_table_local(entry.get("pos", Vector3.ZERO))
		var existed: bool = id in _pieces
		var piece := _get_or_create_piece(id, faction)
		# Snap brand-new pieces to their target so they don't swoop in from
		# the origin. Existing pieces just update the lerp target and the
		# _process pass eases them over.
		if not existed:
			piece.position = target
		_piece_targets[id] = target

func _get_or_create_piece(id: int, faction: int) -> MeshInstance3D:
	var piece: MeshInstance3D = _pieces.get(id)
	if piece and is_instance_valid(piece):
		piece.material_override = _material_for_faction(faction)
		return piece
	piece = MeshInstance3D.new()
	piece.name = "Piece_%d" % id
	var mesh := CylinderMesh.new()
	mesh.top_radius = piece_radius * 0.4
	mesh.bottom_radius = piece_radius
	mesh.height = piece_radius * 2.5
	piece.mesh = mesh
	piece.material_override = _material_for_faction(faction)
	_pieces_root.add_child(piece)
	_pieces[id] = piece
	return piece

func _material_for_faction(faction: int) -> StandardMaterial3D:
	if faction in _materials:
		return _materials[faction]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GameConstants.faction_colors.get(faction, Color.WHITE)
	mat.roughness = 0.5
	_materials[faction] = mat
	return mat
