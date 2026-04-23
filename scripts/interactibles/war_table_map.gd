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

var _pieces: Dictionary[int, MeshInstance3D] = {}
var _pieces_root: Node3D
var _materials: Dictionary[int, StandardMaterial3D] = {}

func _ready() -> void:
	_pieces_root = Node3D.new()
	_pieces_root.name = "Pieces"
	add_child(_pieces_root)

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

func clear_pieces() -> void:
	for piece in _pieces.values():
		if is_instance_valid(piece):
			piece.queue_free()
	_pieces.clear()

func _render_bucket(bucket: Dictionary, seen: Dictionary[int, bool]) -> void:
	for id in bucket.keys():
		var entry: Dictionary = bucket[id]
		seen[id] = true
		var piece := _get_or_create_piece(id, int(entry.get("faction", GameConstants.Faction.NEUTRAL)))
		piece.position = world_to_table_local(entry.get("pos", Vector3.ZERO))

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
