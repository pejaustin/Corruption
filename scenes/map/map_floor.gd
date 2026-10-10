class_name MapFloor extends Node3D

## The tower's map: a huge stone floor drawn as a rough sketch of the land
## (GDD §3, Q1, Q8–Q10). It shows what its owner believes, never the truth:
## the map points they know, chess pieces where reports last put their groups
## and the enemy, and the ink of orders already sent.
##
## Making an order (Q9): select one or more of your pieces (E), or E on your
## own tower's point to send a courier alone; then walk across the floor — the
## points you step on become the route (up to your granularity, Q2); then E
## on a point to make it the destination. A scroll of orders appears in your
## hand; give it to the advisor, who asks what the orders are.
## Pieces can be picked up (left mouse) and put down anywhere to guess or plan
## (Q10); asking the advisor to update the map puts them back.
##
## Only the tower's owner sees anything drawn on it.

signal selection_changed

## Side of the square floor, in metres.
@export var floor_size: float = 14.0
## The part of the world the floor depicts (x, z).
## PLACEHOLDER: the whole of Austin's 2 km map (the picture is tools/bake_map_illustration.gd's).
@export var world_rect: Rect2 = Rect2(-1000.0, -1000.0, 2000.0, 2000.0)
## The floor's picture of that part of the world (the 2 km one here; the other world sizes' landscape scenes set theirs).
@export var illustration: Texture2D
## Authored scenes the floor instances: a marker per known point, a piece per
## reported group (the Paladin has his own), and the route and ink ribbons.
@export var marker_scene: PackedScene
@export var piece_scene: PackedScene
@export var avatar_piece_scene: PackedScene
@export var route_line_scene: PackedScene
@export var ink_line_scene: PackedScene

## PLACEHOLDER: art direction — ink and parchment colours (the pencil and route
## colours live in map_line_pencil.tscn and map_line_route.tscn).
const INK_COLOR: Color = Color(0.08, 0.06, 0.05)
## Stepping this close (floor metres) to a point adds it to the route.
const STEP_RADIUS: float = 0.45
## Seconds for a sent order's route to darken in ink (ticket #538).
const INK_SECONDS: float = 3.0
## Reports older than this (seconds) make a piece "old news" (never missing).
const STALE_SECONDS: float = 90.0
## Enemy sightings closer than this share one piece, as a fraction of the world's width (so the same on the floor at every
## world size). PLACEHOLDER: tuning — was 15 m on the 360 m map; 0.04 is 80 m on the 2 km map (14 m of floor).
const ENEMY_CLUSTER_FRACTION: float = 0.04
const REFRESH_INTERVAL: float = 0.2
const HEIGHT: float = 0.02

var _markers: Dictionary[StringName, MapPointMarker] = {}
var _pieces: Dictionary[int, MapPiece] = {}
var _refresh_timer: float = 0.0
var _ink_started: Dictionary[int, float] = {}

## Order authoring (local).
var selected_groups: Array[int] = []
var authoring: bool = false
var path_points: Array[StringName] = []
## Piece being carried by hand (MapPiece key), or 0.
var carried_piece: int = 0

@onready var _illustration_plane: MeshInstance3D = %Illustration
@onready var _routes_root: Node3D = %Routes
@onready var _markers_root: Node3D = %Markers
@onready var _pieces_root: Node3D = %Pieces
@onready var _ink_root: Node3D = %Ink
@onready var _draft_line: MeshInstance3D = %DraftLine

func _ready() -> void:
	_fit_floor()

# --- Ownership ---

func get_tower() -> Tower:
	var n: Node = get_parent()
	while n:
		if n is Tower:
			return n
		n = n.get_parent()
	return null

func is_active_for_local_peer() -> bool:
	var t := get_tower()
	if t == null:
		return true
	return t.owner_peer_id == multiplayer.get_unique_id() and t.owner_peer_id > 0

func local_player() -> OverlordActor:
	var scene := get_tree().current_scene
	var spawn := scene.get_node_or_null("World/PlayerSpawnPoint") if scene else null
	if spawn == null:
		return null
	return spawn.get_node_or_null(str(multiplayer.get_unique_id())) as OverlordActor

func model() -> WorldModel:
	return KnowledgeManager.local_model()

# --- Coordinates ---

func world_to_floor(world: Vector3) -> Vector3:
	## World position -> this node's local floor position.
	var u := (world.x - world_rect.position.x) / world_rect.size.x - 0.5
	var v := (world.z - world_rect.position.y) / world_rect.size.y - 0.5
	return Vector3(u * floor_size, HEIGHT, v * floor_size)

func floor_to_world(local: Vector3) -> Vector3:
	var u := local.x / floor_size + 0.5
	var v := local.z / floor_size + 0.5
	return Vector3(world_rect.position.x + u * world_rect.size.x, 0.0, world_rect.position.y + v * world_rect.size.y)

func global_to_floor(global_pos: Vector3) -> Vector3:
	var local := to_local(global_pos)
	local.y = HEIGHT
	return local

# --- Per-frame ---

func _process(delta: float) -> void:
	if not is_active_for_local_peer():
		visible_content(false)
		return
	visible_content(true)
	_update_carried_piece()
	if authoring:
		_track_walk()
	_update_draft_line()
	_update_ink(delta)
	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL:
		return
	_refresh_timer = 0.0
	_sync_markers()
	_sync_routes()
	_sync_pieces()
	_sync_ink()

func visible_content(show: bool) -> void:
	for n in [_routes_root, _markers_root, _pieces_root, _ink_root, _draft_line]:
		if n and n.visible != show:
			n.visible = show

# --- Selection and authoring ---

func toggle_group(group_id: int) -> void:
	if group_id in selected_groups:
		selected_groups.erase(group_id)
	else:
		selected_groups.append(group_id)
	authoring = not selected_groups.is_empty()
	if not authoring:
		path_points.clear()
	selection_changed.emit()

func start_courier_route() -> void:
	## E on your own tower's point: a courier alone, leaving from home.
	selected_groups.clear()
	path_points.clear()
	authoring = true
	selection_changed.emit()

func cancel_authoring() -> void:
	selected_groups.clear()
	path_points.clear()
	authoring = false
	selection_changed.emit()

func path_limit() -> int:
	## Order granularity (GDD Q2, ticket #539): how many route points an order
	## may carry. Widened later by training and relics.
	return MatchConfig.STARTING_ROUTE_POINTS + GameState.get_route_point_bonus(multiplayer.get_unique_id())

func finish_at(point: MapPoint) -> void:
	## E on a point while authoring: it becomes the destination and the order
	## goes into your hand as a scroll.
	var player := local_player()
	if player == null or not authoring:
		return
	var route_points: Array[StringName] = []
	for p in path_points:
		if p != point.point_id:
			route_points.append(p)
	var route: Array = []
	for pid in route_points:
		var mp := MapPoint.find(get_tree(), pid)
		if mp:
			route.append(mp.global_position)
	route.append(point.global_position)
	var believed: Dictionary = {}
	for gid in selected_groups:
		believed[gid] = model().group_position(gid, KnowledgeManager.current_tick())
	route_points.append(point.point_id)
	player.hold_order({
		"group_ids": selected_groups.duplicate(),
		"believed": believed,
		"route_points": route_points,
		"route": route,
		"dest_point": point.point_id,
		"dest_kind": point.kind,
	})
	cancel_authoring()

func _track_walk() -> void:
	var player := local_player()
	if player == null:
		return
	var here := global_to_floor(player.global_position)
	if absf(here.x) > floor_size * 0.5 or absf(here.z) > floor_size * 0.5:
		return
	for id in _markers:
		var m := _markers[id]
		if Vector2(m.position.x - here.x, m.position.z - here.z).length() > STEP_RADIUS:
			continue
		if not path_points.is_empty() and path_points[-1] == id:
			return
		if id in path_points:
			# Walking back over a point undoes the route back to it.
			path_points.resize(path_points.find(id) + 1)
			return
		if path_points.size() >= path_limit():
			return
		path_points.append(id)
		return

# --- Pieces carried by hand ---

func pick_up(key: int) -> void:
	carried_piece = key

func put_down() -> void:
	if carried_piece == 0:
		return
	var piece: MapPiece = _pieces.get(carried_piece)
	if piece:
		model().piece_overrides[carried_piece] = floor_to_world(piece.position)
	carried_piece = 0

func _update_carried_piece() -> void:
	if carried_piece == 0:
		return
	var piece: MapPiece = _pieces.get(carried_piece)
	var player := local_player()
	if piece == null or player == null:
		carried_piece = 0
		return
	var ahead := player.global_position - player.global_basis.z * 0.8
	var p := global_to_floor(ahead)
	p.x = clampf(p.x, -floor_size * 0.5, floor_size * 0.5)
	p.z = clampf(p.z, -floor_size * 0.5, floor_size * 0.5)
	piece.position = p

func _unhandled_input(event: InputEvent) -> void:
	if not is_active_for_local_peer():
		return
	if carried_piece != 0 and event.is_action_pressed("primary_ability"):
		put_down()
		get_viewport().set_input_as_handled()
	elif authoring and event.is_action_pressed("cancel"):
		cancel_authoring()
		get_viewport().set_input_as_handled()

# --- Drawing: points and routes ---

func _sync_markers() -> void:
	var m := model()
	for p in MapPoint.all_points(get_tree()):
		var known := m.is_point_known(p.point_id)
		var marker: MapPointMarker = _markers.get(p.point_id)
		if known and marker == null:
			marker = MapPointMarker.create(marker_scene, self, p)
			_markers_root.add_child(marker)
			marker.position = world_to_floor(p.global_position)
			_markers[p.point_id] = marker
		elif not known and marker:
			marker.queue_free()
			_markers.erase(p.point_id)

func _sync_routes() -> void:
	## Roads between known points (PLACEHOLDER art: thin ink strokes).
	var wanted: Dictionary[String, bool] = {}
	for p in MapPoint.all_points(get_tree()):
		if p.point_id not in _markers:
			continue
		for q in p.get_linked_points():
			if q.point_id not in _markers:
				continue
			var a := String(p.point_id)
			var b := String(q.point_id)
			var key := "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
			wanted[key] = true
			if _routes_root.has_node(key.replace("|", "__")):
				continue
			var line := route_line_scene.instantiate() as MeshInstance3D
			line.name = key.replace("|", "__")
			_set_line(line, [world_to_floor(p.global_position), world_to_floor(q.global_position)], 0.03)
			_routes_root.add_child(line)
	for child in _routes_root.get_children():
		if not wanted.has(String(child.name).replace("__", "|")):
			child.queue_free()

# --- Drawing: pieces ---

func _sync_pieces() -> void:
	var m := model()
	var me := multiplayer.get_unique_id()
	var tick := KnowledgeManager.current_tick()
	var rate := float(NetworkTime.tickrate) if NetworkTime.tickrate > 0 else 30.0
	var wanted: Dictionary[int, bool] = {}
	for gid in m.believed_groups:
		var e: Dictionary = m.believed_groups[gid]
		var key: int = gid
		wanted[key] = true
		var piece := _get_piece(key, me, gid == KnowledgeManager.AVATAR_ID)
		piece.group_id = gid
		piece.count = int(e.get("count", 1))
		piece.stale = (tick - int(e.get("tick", tick))) / rate > STALE_SECONDS
		piece.selected = gid in selected_groups
		piece.status = e.get("status", &"")
		piece.belief = m.piece_state(gid)
		if gid == KnowledgeManager.AVATAR_ID:
			piece.belief = &"confirmed"
		if carried_piece != key:
			var at: Vector3 = m.group_position(gid, tick) if gid != KnowledgeManager.AVATAR_ID else e.get("pos", Vector3.ZERO)
			piece.position = world_to_floor(m.piece_position(key, at))
		piece.refresh()
	for cluster in _enemy_clusters(m):
		var key: int = -1000000 - int(cluster["id"])
		wanted[key] = true
		var piece := _get_piece(key, int(cluster["owner"]), int(cluster["id"]) == KnowledgeManager.AVATAR_ID)
		piece.group_id = 0
		piece.count = int(cluster["count"])
		piece.stale = (tick - int(cluster["tick"])) / rate > STALE_SECONDS
		piece.selected = false
		if carried_piece != key:
			piece.position = world_to_floor(m.piece_position(key, cluster["pos"]))
		piece.refresh()
	for key in _pieces.keys():
		if not wanted.has(key):
			_pieces[key].queue_free()
			_pieces.erase(key)

func _get_piece(key: int, owner: int, is_avatar: bool) -> MapPiece:
	var piece: MapPiece = _pieces.get(key)
	if piece == null:
		piece = MapPiece.create(avatar_piece_scene if is_avatar else piece_scene, self, key, owner, is_avatar)
		_pieces_root.add_child(piece)
		_pieces[key] = piece
	return piece

func _enemy_clusters(m: WorldModel) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for uid in m.believed_enemies:
		var e: Dictionary = m.believed_enemies[uid]
		var pos: Vector3 = e.get("pos", Vector3.ZERO)
		var owner := int(e.get("owner_peer_id", -1))
		var merged := false
		for c in out:
			if int(c["owner"]) == owner and (c["pos"] as Vector3).distance_to(pos) <= world_rect.size.x * ENEMY_CLUSTER_FRACTION and uid != KnowledgeManager.AVATAR_ID and int(c["id"]) != KnowledgeManager.AVATAR_ID:
				c["count"] = int(c["count"]) + 1
				c["tick"] = maxi(int(c["tick"]), int(e.get("tick", 0)))
				merged = true
				break
		if not merged:
			out.append({"id": uid, "owner": owner, "pos": pos, "count": 1, "tick": int(e.get("tick", 0))})
	return out

# --- Drawing: draft path and ink ---

func _update_draft_line() -> void:
	if not authoring:
		_draft_line.visible = false
		return
	var pts: Array[Vector3] = []
	if selected_groups.is_empty():
		var t := get_tower()
		var home := _tower_point()
		if home:
			pts.append(world_to_floor(home.global_position))
	else:
		var m := model()
		for gid in selected_groups:
			var e: Dictionary = m.believed_groups.get(gid, {})
			if not e.is_empty():
				pts.append(world_to_floor(m.piece_position(gid, m.group_position(gid, KnowledgeManager.current_tick()))))
				break
	for pid in path_points:
		var marker: MapPointMarker = _markers.get(pid)
		if marker:
			pts.append(marker.position)
	var player := local_player()
	if player:
		pts.append(global_to_floor(player.global_position))
	_draft_line.visible = pts.size() >= 2
	if pts.size() >= 2:
		_set_line(_draft_line, pts, 0.025)

func _sync_ink() -> void:
	var m := model()
	var wanted: Dictionary[int, bool] = {}
	for cmd in m.orders:
		var o: Dictionary = m.orders[cmd]
		if o.get("stage", &"") not in [&"dispatched", &"delivered"] or int(o.get("goal", 0)) == OrderGoal.Goal.CHECK:
			continue
		if _superseded(m, int(cmd)):
			continue
		wanted[cmd] = true
		var node_name := "Order%d" % cmd
		if _ink_root.has_node(node_name):
			continue
		var line := ink_line_scene.instantiate() as MeshInstance3D
		line.name = node_name
		line.set_meta(&"points", _order_points(o))
		_ink_root.add_child(line)
		_ink_started[cmd] = 0.0
	for child in _ink_root.get_children():
		var cmd := String(child.name).trim_prefix("Order").to_int()
		if not wanted.has(cmd):
			child.queue_free()
			_ink_started.erase(cmd)

func _superseded(m: WorldModel, cmd: int) -> bool:
	## A later order to any of the same groups replaces this one's ink.
	var groups: Array = m.orders[cmd].get("group_ids", [])
	for other in m.orders:
		if int(other) <= cmd:
			continue
		if m.orders[other].get("stage", &"") not in [&"dispatched", &"delivered"] or int(m.orders[other].get("goal", 0)) == OrderGoal.Goal.CHECK:
			continue
		for g in m.orders[other].get("group_ids", []):
			if g in groups:
				return true
	return false

func _order_points(o: Dictionary) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var groups: Array = o.get("group_ids", [])
	if groups.is_empty():
		var home := _tower_point()
		if home:
			pts.append(world_to_floor(home.global_position))
	for pid in o.get("route_points", []):
		var p := MapPoint.find(get_tree(), StringName(pid))
		if p:
			pts.append(world_to_floor(p.global_position))
	return pts

func _update_ink(delta: float) -> void:
	## The route darkens like spreading ink from its start to its end.
	for child in _ink_root.get_children():
		var cmd := String(child.name).trim_prefix("Order").to_int()
		var t: float = _ink_started.get(cmd, INK_SECONDS)
		if t >= INK_SECONDS and child.has_meta(&"inked"):
			continue
		t = minf(INK_SECONDS, t + delta)
		_ink_started[cmd] = t
		var pts: Array = child.get_meta(&"points", [])
		var typed: Array[Vector3] = []
		for p in pts:
			typed.append(p)
		_set_line(child as MeshInstance3D, _partial(typed, t / INK_SECONDS), 0.05)
		if t >= INK_SECONDS:
			child.set_meta(&"inked", true)

static func _partial(pts: Array[Vector3], fraction: float) -> Array[Vector3]:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var want := total * clampf(fraction, 0.0, 1.0)
	var out: Array[Vector3] = []
	if pts.is_empty():
		return out
	out.append(pts[0])
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if want >= seg:
			out.append(pts[i])
			want -= seg
		else:
			out.append(pts[i - 1].lerp(pts[i], want / maxf(seg, 0.001)))
			break
	return out

func _tower_point() -> MapPoint:
	var t := get_tower()
	if t == null:
		return null
	for p in MapPoint.all_points(get_tree()):
		if p.kind == MapPoint.Kind.TOWER and p.tower_slot == t.slot_index:
			return p
	return null

# --- Mesh helpers ---

# Data-only: the ribbon geometry (an ImmediateMesh authored on the line scene) is
# refilled from the route's points as they change.
static func _set_line(mi: MeshInstance3D, pts: Array[Vector3], width: float) -> void:
	## A flat ribbon on the floor through `pts`.
	var mesh := mi.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if pts.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var dir := b - a
		dir.y = 0.0
		if dir.length() < 0.0001:
			continue
		var side := Vector3(-dir.z, 0.0, dir.x).normalized() * width * 0.5
		var lift := Vector3(0, 0.005, 0)
		mesh.surface_add_vertex(a - side + lift)
		mesh.surface_add_vertex(b - side + lift)
		mesh.surface_add_vertex(b + side + lift)
		mesh.surface_add_vertex(a - side + lift)
		mesh.surface_add_vertex(b + side + lift)
		mesh.surface_add_vertex(a + side + lift)
	mesh.surface_end()

# --- The floor itself ---

func _fit_floor() -> void:
	## The plane and its material are authored in map_floor.tscn;
	## this sizes the plane to floor_size and puts `illustration` on its material (the material is local to the scene).
	(_illustration_plane.mesh as PlaneMesh).size = Vector2(floor_size, floor_size)
	(_illustration_plane.material_override as StandardMaterial3D).albedo_texture = illustration
