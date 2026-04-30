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

## Authored chess-piece scene used for every minion belief marker. Root is a
## Node3D containing one or more MeshInstance3D descendants — the runtime
## applies the faction-tinted material_override to all of them.
## Leave null to fall back to the procedural cylinder mesh.
@export var piece_scene: PackedScene

## Authored scene used for the four tower markers. Same shape contract as
## piece_scene (Node3D root, MeshInstance3D descendants), but material is
## baked into the scene rather than overridden at runtime.
@export var tower_piece_scene: PackedScene

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

## Order arrow color when the courier is en route or has delivered — black ink
## on the map, source-of-minions → destination.
const COURIER_ARROW_COLOR: Color = Color(0.05, 0.05, 0.05)
## Courier route arrow: tower spawn → believed source. Drawn in courier blue
## so the eye reads "this is the runner's path" distinct from the order arrow.
const COURIER_ROUTE_COLOR: Color = Color(0.6, 0.8, 1.0)
## Draft arrow — red, drawn while the order is still a plan in the overlord's
## hands (post-table-click, pre-Advisor-handoff). Source → destination.
const DRAFT_ARROW_COLOR: Color = Color(0.85, 0.25, 0.25)
## Reality overlay marker color — yellow so it doesn't clash with the red
## draft arrows (debug-distinct, unambiguous).
const REALITY_MARKER_COLOR: Color = Color(1.0, 0.85, 0.15)
## Tint multiplied onto a piece's base material when it's in the overlord's
## active selection (war-table commanding flow).
const SELECTION_TINT: Color = Color(1.6, 1.6, 0.5, 1.0)

var _pieces: Dictionary[int, Node3D] = {}
var _piece_targets: Dictionary[int, Vector3] = {}
var _piece_factions: Dictionary[int, int] = {}
var _pieces_root: Node3D
## Tinted material cache for chess pieces. Key built from
## "<base_material_id>_<faction>_<selected_int>" so each authored mesh+faction
## combination gets exactly one duplicated StandardMaterial3D — its
## albedo_color is set to the faction tint (multiplying the authored
## albedo_texture, e.g. concrete) instead of replacing the whole material.
var _tinted_piece_materials: Dictionary[String, StandardMaterial3D] = {}
var _selected_piece_ids: Dictionary[int, bool] = {}
## Tower markers — one per anchor passed in via set_tower_anchors().
var _tower_anchors: Array[Node3D] = []
var _tower_pieces: Array[Node3D] = []
var _towers_root: Node3D
## cmd_id -> { "order": MeshInstance3D, "route": MeshInstance3D }
##   order: arrow source_pos → target_pos (red while draft, black once dispatched)
##   route: arrow spawn_pos → source_pos (only present once dispatched)
var _command_visuals: Dictionary[int, Dictionary] = {}
var _commands_root: Node3D
## courier minion id -> small marker MeshInstance3D
var _reality_pieces: Dictionary[int, MeshInstance3D] = {}
var _reality_root: Node3D
var _arrow_material: StandardMaterial3D
var _draft_arrow_material: StandardMaterial3D
var _route_material: StandardMaterial3D
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
	_towers_root = Node3D.new()
	_towers_root.name = "Towers"
	add_child(_towers_root)

func _process(delta: float) -> void:
	# Tower pieces don't move once placed, but their on-table positions depend
	# on map_world_size/map_world_center, which are tweakable at runtime via the
	# WarTable's setters. Re-syncing each frame is cheap (≤4 anchors) and keeps
	# them lined up regardless of when those values change.
	_reposition_towers()
	if _pieces.is_empty():
		return
	var t: float = clampf(piece_lerp_speed * delta, 0.0, 1.0)
	for id in _pieces:
		var piece: Node3D = _pieces[id]
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
		_piece_factions.erase(id)
	_render_pending_commands(model)
	_render_reality_couriers()

func clear_pieces() -> void:
	for piece in _pieces.values():
		if is_instance_valid(piece):
			piece.queue_free()
	_pieces.clear()
	_piece_targets.clear()
	_piece_factions.clear()

func _render_bucket(bucket: Dictionary, seen: Dictionary[int, bool]) -> void:
	for id in bucket.keys():
		var entry: Dictionary = bucket[id]
		seen[id] = true
		var faction: int = int(entry.get("faction", GameConstants.Faction.NEUTRAL))
		var target: Vector3 = world_to_table_local(entry.get("pos", Vector3.ZERO))
		var existed: bool = id in _pieces
		var piece := _get_or_create_piece(id, faction)
		_piece_factions[id] = faction
		# Snap brand-new pieces to their target so they don't swoop in from
		# the origin. Existing pieces just update the lerp target and the
		# _process pass eases them over.
		if not existed:
			piece.position = target
		_piece_targets[id] = target

func _get_or_create_piece(id: int, faction: int) -> Node3D:
	var piece: Node3D = _pieces.get(id)
	if piece and is_instance_valid(piece):
		_apply_faction_tint(piece, faction, _selected_piece_ids.get(id, false))
		return piece
	piece = _instantiate_piece()
	piece.name = "Piece_%d" % id
	_pieces_root.add_child(piece)
	_pieces[id] = piece
	_apply_faction_tint(piece, faction, _selected_piece_ids.get(id, false))
	return piece

func _instantiate_piece() -> Node3D:
	if piece_scene:
		var inst: Node = piece_scene.instantiate()
		var node3d: Node3D = inst as Node3D
		if node3d:
			return node3d
		push_warning("WarTableMap: piece_scene root must be Node3D; falling back to procedural mesh.")
		inst.queue_free()
	var piece := Node3D.new()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = piece_radius * 0.4
	mesh.bottom_radius = piece_radius
	mesh.height = piece_radius * 2.5
	mesh_inst.mesh = mesh
	piece.add_child(mesh_inst)
	return piece

## Walks `root` and its descendants, applying a faction-tinted variant of each
## MeshInstance3D's authored surface material. Albedo_color is set to the
## faction color (multiplying the authored albedo_texture, e.g. concrete) so
## the surface material's texture/normal/etc. survive the tint.
func _apply_faction_tint(root: Node, faction: int, selected: bool) -> void:
	if root is MeshInstance3D:
		_tint_mesh_instance(root as MeshInstance3D, faction, selected)
	for child in root.get_children():
		_apply_faction_tint(child, faction, selected)

func _tint_mesh_instance(mi: MeshInstance3D, faction: int, selected: bool) -> void:
	if mi.mesh == null:
		return
	# Always tint from the AUTHORED mesh material rather than the current
	# override. Reading the override means each select↔deselect toggle layered
	# on top of the previous variant — and the deselect path inherited the
	# selected variant's emission flag, so the yellow glow stuck. Going back
	# to the canonical authored base keeps cache keys stable and gives a
	# clean unselected state on every toggle.
	for s in mi.mesh.get_surface_count():
		var base: Material = mi.mesh.surface_get_material(s)
		mi.set_surface_override_material(s, _get_or_build_tinted_material(base, faction, selected))

func _get_or_build_tinted_material(base: Material, faction: int, selected: bool) -> StandardMaterial3D:
	var base_id: int = base.get_instance_id() if base else 0
	var key: String = "%d_%d_%d" % [base_id, faction, int(selected)]
	if key in _tinted_piece_materials:
		return _tinted_piece_materials[key]
	var color: Color = GameConstants.faction_colors.get(faction, Color.WHITE)
	if selected:
		color = color * SELECTION_TINT
	var mat: StandardMaterial3D
	if base is StandardMaterial3D:
		mat = (base as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		mat = StandardMaterial3D.new()
		mat.roughness = 0.5
	mat.albedo_color = color
	if selected:
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.95, 0.4)
		mat.emission_energy_multiplier = 0.6
	else:
		# Explicit so we don't inherit emission from the authored material.
		mat.emission_enabled = false
	_tinted_piece_materials[key] = mat
	return mat

## Called by WarTable each frame with the current selection. Re-applies the
## right material to every owned piece so toggling shows immediately.
func set_selected_pieces(ids: Array[int]) -> void:
	var new_selected: Dictionary[int, bool] = {}
	for id in ids:
		new_selected[id] = true
	# Re-tint every piece. Tinted materials are cached, so the cost per call
	# is one set_surface_override_material per mesh per piece — cheap.
	for id in _pieces.keys():
		var piece: Node3D = _pieces[id]
		if not is_instance_valid(piece):
			continue
		var faction: int = _piece_factions.get(id, GameConstants.Faction.NEUTRAL)
		_apply_faction_tint(piece, faction, new_selected.get(id, false))
	_selected_piece_ids = new_selected

# --- Pending commands (belief layer: intent arrows + midpoint pawns) ---

func _render_pending_commands(model: WorldModel) -> void:
	## Each entry in model.pending_commands renders by stage:
	##   "draft"      → red ORDER arrow source_pos → target_pos (no courier yet)
	##   "dispatched" → black ORDER arrow source_pos → target_pos
	##                  + blue COURIER ROUTE arrow spawn_pos → source_pos
	## Promotion at handoff flips the order arrow's color in place and adds the
	## route arrow. To see the courier's actual world position rather than the
	## symbolic route, flip SHOW_REALITY (debug overlay).
	var seen: Dictionary[int, bool] = {}
	for cmd_id in model.pending_commands.keys():
		seen[cmd_id] = true
		var entry: Dictionary = model.pending_commands[cmd_id]
		var stage: StringName = entry.get("stage", &"dispatched")
		var spawn_world: Vector3 = entry.get("spawn_pos", Vector3.ZERO)
		var source_world: Vector3 = entry.get("source_pos", Vector3.ZERO)
		var target_world: Vector3 = entry.get("target_pos", Vector3.ZERO)
		var source_local: Vector3 = world_to_table_local(source_world)
		var target_local: Vector3 = world_to_table_local(target_world)
		var visuals: Dictionary = _command_visuals.get(cmd_id, {})
		# Order arrow: source → destination, always present.
		var order: MeshInstance3D = visuals.get("order")
		if order == null or not is_instance_valid(order):
			order = _make_arrow_mesh()
			_commands_root.add_child(order)
		_orient_arrow(order, source_local, target_local)
		order.material_override = _get_arrow_material_for_stage(stage)
		visuals["order"] = order
		# Courier route arrow: spawn → source. Only after dispatch.
		var route: MeshInstance3D = visuals.get("route")
		if stage == &"dispatched":
			var spawn_local: Vector3 = world_to_table_local(spawn_world)
			if route == null or not is_instance_valid(route):
				route = _make_arrow_mesh()
				_commands_root.add_child(route)
			_orient_arrow(route, spawn_local, source_local)
			route.material_override = _get_route_material()
			visuals["route"] = route
		else:
			if route != null and is_instance_valid(route):
				route.queue_free()
			visuals.erase("route")
		_command_visuals[cmd_id] = visuals
	# Drop visuals for commands that have completed (courier despawned, or a
	# draft that was abandoned).
	var dead: Array[int] = []
	for cmd_id in _command_visuals.keys():
		if cmd_id not in seen:
			dead.append(cmd_id)
	for cmd_id in dead:
		var v: Dictionary = _command_visuals[cmd_id]
		var order := v.get("order") as MeshInstance3D
		var route := v.get("route") as MeshInstance3D
		if is_instance_valid(order):
			order.queue_free()
		if is_instance_valid(route):
			route.queue_free()
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

func _get_route_material() -> StandardMaterial3D:
	if _route_material == null:
		_route_material = StandardMaterial3D.new()
		_route_material.albedo_color = COURIER_ROUTE_COLOR
		_route_material.roughness = 0.5
	return _route_material

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

# --- Tower markers ---

## Place one tower-piece per anchor on the diorama. Caller passes the live
## Tower nodes (or any Node3Ds) — the map reads their global_position each
## frame, so towers staged via test harnesses still show up correctly.
func set_tower_anchors(anchors: Array[Node3D]) -> void:
	for p in _tower_pieces:
		if is_instance_valid(p):
			p.queue_free()
	_tower_pieces.clear()
	_tower_anchors = anchors.duplicate()
	if _towers_root == null:
		return
	for i in _tower_anchors.size():
		var anchor := _tower_anchors[i]
		if anchor == null:
			continue
		var piece := _instantiate_tower_piece()
		piece.name = "Tower_%d" % i
		_towers_root.add_child(piece)
		_tower_pieces.append(piece)
	_reposition_towers()

func _instantiate_tower_piece() -> Node3D:
	if tower_piece_scene:
		var inst: Node = tower_piece_scene.instantiate()
		var node3d: Node3D = inst as Node3D
		if node3d:
			return node3d
		push_warning("WarTableMap: tower_piece_scene root must be Node3D; falling back to procedural mesh.")
		inst.queue_free()
	var piece := Node3D.new()
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = piece_radius * 1.5
	mesh.bottom_radius = piece_radius * 1.5
	mesh.height = piece_radius * 3.0
	mesh_inst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.52, 0.48)
	mat.roughness = 0.85
	mesh_inst.material_override = mat
	piece.add_child(mesh_inst)
	return piece

func _reposition_towers() -> void:
	if _tower_pieces.is_empty():
		return
	for i in _tower_pieces.size():
		var piece := _tower_pieces[i]
		var anchor := _tower_anchors[i] if i < _tower_anchors.size() else null
		if not is_instance_valid(piece) or anchor == null or not is_instance_valid(anchor):
			continue
		piece.position = world_to_table_local(anchor.global_position)
