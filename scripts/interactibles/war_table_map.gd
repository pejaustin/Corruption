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

## Debug overlay: when true, the war table additionally renders a small red
## marker at every live courier's actual world position regardless of belief.
## The belief layer (intent arrows + midpoint pawns) keeps drawing underneath.
## Runtime-mutable so test harnesses can flip it without restarting.
static var SHOW_REALITY: bool = false

## Belief layer (intent): courier color, used for the midpoint pawn that
## appears once a courier has been dispatched.
const COURIER_INTENT_COLOR: Color = Color(0.6, 0.8, 1.0)
## Dispatched arrow — black "ink on the map," signalling a courier is on the
## road carrying this order.
const COURIER_ARROW_COLOR: Color = Color(0.05, 0.05, 0.05)
## Draft arrow — red, drawn while the order is still a plan in the overlord's
## hands (post-table-click, pre-Advisor-handoff). Flips to COURIER_ARROW_COLOR
## in place when the Advisor takes the order.
const DRAFT_ARROW_COLOR: Color = Color(0.85, 0.25, 0.25)
## Reality overlay marker color — yellow so it doesn't clash with the red
## draft arrows (debug-distinct, unambiguous).
const REALITY_MARKER_COLOR: Color = Color(1.0, 0.85, 0.15)

var _pieces: Dictionary[int, MeshInstance3D] = {}
var _piece_targets: Dictionary[int, Vector3] = {}
var _pieces_root: Node3D
var _materials: Dictionary[int, StandardMaterial3D] = {}
## cmd_id -> { "arrow": MeshInstance3D, "pawn": MeshInstance3D }
var _command_visuals: Dictionary[int, Dictionary] = {}
var _commands_root: Node3D
## courier minion id -> small marker MeshInstance3D
var _reality_pieces: Dictionary[int, MeshInstance3D] = {}
var _reality_root: Node3D
var _arrow_material: StandardMaterial3D
var _draft_arrow_material: StandardMaterial3D
var _intent_material: StandardMaterial3D
var _reality_material: StandardMaterial3D

func _ready() -> void:
	_pieces_root = Node3D.new()
	_pieces_root.name = "Pieces"
	add_child(_pieces_root)
	_commands_root = Node3D.new()
	_commands_root.name = "Commands"
	add_child(_commands_root)
	_reality_root = Node3D.new()
	_reality_root.name = "Reality"
	add_child(_reality_root)

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
	_render_pending_commands(model)
	_render_reality_couriers()

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

# --- Pending commands (belief layer: intent arrows + midpoint pawns) ---

func _render_pending_commands(model: WorldModel) -> void:
	## Each entry in model.pending_commands renders by stage:
	##   "draft"      → red arrow only (plan, not yet dispatched)
	##   "dispatched" → black arrow + courier-colored midpoint pawn
	## When the Advisor handoff promotes draft → dispatched, the SAME arrow
	## flips color in place; the midpoint pawn appears at handoff. To see the
	## courier's actual position rather than the symbolic midpoint, flip
	## SHOW_REALITY (debug overlay).
	var seen: Dictionary[int, bool] = {}
	for cmd_id in model.pending_commands.keys():
		seen[cmd_id] = true
		var entry: Dictionary = model.pending_commands[cmd_id]
		var stage: StringName = entry.get("stage", &"dispatched")
		var start_world: Vector3 = entry.get("start_pos", Vector3.ZERO)
		var target_world: Vector3 = entry.get("target_pos", Vector3.ZERO)
		var start_local: Vector3 = world_to_table_local(start_world)
		var target_local: Vector3 = world_to_table_local(target_world)
		var visuals: Dictionary = _command_visuals.get(cmd_id, {})
		var arrow: MeshInstance3D = visuals.get("arrow")
		if arrow == null or not is_instance_valid(arrow):
			arrow = _make_arrow_mesh()
			_commands_root.add_child(arrow)
		_orient_arrow(arrow, start_local, target_local)
		arrow.material_override = _get_arrow_material_for_stage(stage)
		visuals["arrow"] = arrow
		# Midpoint pawn lives only on dispatched entries — drafts are pure
		# plan, no courier on the road yet.
		var pawn: MeshInstance3D = visuals.get("pawn")
		if stage == &"dispatched":
			if pawn == null or not is_instance_valid(pawn):
				pawn = _make_intent_pawn_mesh()
				_commands_root.add_child(pawn)
			pawn.position = (start_local + target_local) * 0.5
			visuals["pawn"] = pawn
		else:
			if pawn != null and is_instance_valid(pawn):
				pawn.queue_free()
			visuals.erase("pawn")
		_command_visuals[cmd_id] = visuals
	# Drop visuals for commands that have completed (courier despawned, or a
	# draft that was abandoned).
	var dead: Array[int] = []
	for cmd_id in _command_visuals.keys():
		if cmd_id not in seen:
			dead.append(cmd_id)
	for cmd_id in dead:
		var v: Dictionary = _command_visuals[cmd_id]
		var arrow := v.get("arrow") as MeshInstance3D
		var pawn := v.get("pawn") as MeshInstance3D
		if is_instance_valid(arrow):
			arrow.queue_free()
		if is_instance_valid(pawn):
			pawn.queue_free()
		_command_visuals.erase(cmd_id)

func _get_arrow_material_for_stage(stage: StringName) -> StandardMaterial3D:
	if stage == &"draft":
		return _get_draft_arrow_material()
	return _get_arrow_material()

func _make_arrow_mesh() -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.004, 1.0)
	inst.mesh = mesh
	inst.material_override = _get_arrow_material()
	return inst

func _make_intent_pawn_mesh() -> MeshInstance3D:
	## Intent pawn: a small box, distinct from the cylinder used for live
	## sightings, so the eye can tell "in transit (belief)" from "spotted".
	var inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(piece_radius * 1.4, piece_radius * 1.6, piece_radius * 0.6)
	inst.mesh = mesh
	inst.material_override = _get_intent_material()
	return inst

func _orient_arrow(arrow: MeshInstance3D, start_local: Vector3, target_local: Vector3) -> void:
	var diff := target_local - start_local
	var length: float = diff.length()
	if length < 0.001:
		arrow.visible = false
		return
	arrow.visible = true
	var midpoint: Vector3 = (start_local + target_local) * 0.5
	# BoxMesh's z extent is 1.0 (we set size.z = 1.0 above), so a uniform-Z
	# scale of `length` makes the box span exactly start→target along its
	# local Z axis. Orient via looking_at (Z = -forward in Godot, so we
	# negate the direction).
	var dir: Vector3 = diff / length
	var basis := Basis.looking_at(-dir, Vector3.UP)
	var t := Transform3D(basis, midpoint)
	t = t.scaled_local(Vector3(1.0, 1.0, length))
	arrow.transform = t

func _get_arrow_material() -> StandardMaterial3D:
	if _arrow_material == null:
		_arrow_material = StandardMaterial3D.new()
		_arrow_material.albedo_color = COURIER_ARROW_COLOR
		_arrow_material.roughness = 0.7
	return _arrow_material

func _get_draft_arrow_material() -> StandardMaterial3D:
	if _draft_arrow_material == null:
		_draft_arrow_material = StandardMaterial3D.new()
		_draft_arrow_material.albedo_color = DRAFT_ARROW_COLOR
		_draft_arrow_material.roughness = 0.7
	return _draft_arrow_material

func _get_intent_material() -> StandardMaterial3D:
	if _intent_material == null:
		_intent_material = StandardMaterial3D.new()
		_intent_material.albedo_color = COURIER_INTENT_COLOR
		_intent_material.roughness = 0.5
	return _intent_material

# --- Reality overlay (debug: actual courier positions) ---

func _render_reality_couriers() -> void:
	## Reality is read straight from MinionManager — bypasses every WorldModel
	## and renders ground truth. Cleared whenever SHOW_REALITY is off.
	if not SHOW_REALITY:
		_clear_reality_pieces()
		return
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		_clear_reality_pieces()
		return
	var seen: Dictionary[int, bool] = {}
	for m in mm.get_all_minions():
		if not is_instance_valid(m):
			continue
		if m.minion_trait != &"courier":
			continue
		var id: int = m.name.to_int()
		seen[id] = true
		var piece: MeshInstance3D = _reality_pieces.get(id)
		if piece == null or not is_instance_valid(piece):
			piece = _make_reality_marker_mesh()
			_reality_root.add_child(piece)
			_reality_pieces[id] = piece
		piece.position = world_to_table_local(m.global_position) + Vector3(0, piece_radius * 0.2, 0)
	var dead: Array[int] = []
	for id in _reality_pieces.keys():
		if id not in seen:
			dead.append(id)
	for id in dead:
		var p := _reality_pieces[id]
		if is_instance_valid(p):
			p.queue_free()
		_reality_pieces.erase(id)

func _clear_reality_pieces() -> void:
	for p in _reality_pieces.values():
		if is_instance_valid(p):
			p.queue_free()
	_reality_pieces.clear()

func _make_reality_marker_mesh() -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = piece_radius * 0.4
	mesh.height = piece_radius * 0.8
	inst.mesh = mesh
	inst.material_override = _get_reality_material()
	return inst

func _get_reality_material() -> StandardMaterial3D:
	if _reality_material == null:
		_reality_material = StandardMaterial3D.new()
		_reality_material.albedo_color = REALITY_MARKER_COLOR
		_reality_material.roughness = 0.4
	return _reality_material
