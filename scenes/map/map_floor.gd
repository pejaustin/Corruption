@tool
class_name MapFloor extends Node3D

## The tower's map: a huge stone floor drawn as a rough sketch of the land
## (GDD §3, Q1, Q8–Q10). It shows what its owner believes, never the truth:
## the map points they know, the lines between neighbours, chess pieces where reports
## last put their groups and the enemy, and the ink of orders already sent.
##
## Authored in map_floor.tscn (Austin, 2026-10-13): the picture is `illustration`; every point marker (Markers) and
## every line between two neighbouring points (Links, MapPoint.neighbors) is a node there, placed and styled by hand.
## The "Copy map points and links" button (open map_floor.tscn first) adds a marker for every MapPoint of
## `source_world` and a line for every neighbour pair that the floor lacks, scaled onto the floor; it leaves the ones
## already there alone unless "Overwrite On Copy" is ticked. In play, code only shows the points and links their
## owner knows, lights up a way, and draws the pieces and ink.
##
## Making an order (Austin, 2026-10-13): select one or more of your pieces (E), or E on your own tower's point to send
## a courier alone; look at a destination point and the way there lights up on the floor (the shortest along
## neighbouring points you know); E on it takes the order into your hand as a scroll, and its route is pencilled in;
## give it to the advisor, who asks what the orders are, and the route darkens in ink once a courier carries it.
## Pieces can be picked up (left mouse) and put down anywhere to guess or plan (Q10); asking the advisor to update
## the map puts them back.
##
## Only the tower's owner sees anything drawn on it.

signal selection_changed

## Side of the square floor, in metres.
@export var floor_size: float = 14.0:
	set(value):
		floor_size = value
		_fit_floor()
## The part of the world the floor depicts (x, z).
## PLACEHOLDER: the whole of Austin's 2 km map (the picture is tools/bake_map_illustration.gd's).
@export var world_rect: Rect2 = Rect2(-1000.0, -1000.0, 2000.0, 2000.0)
## The floor's picture of that part of the world (the 2 km one here; the other world sizes' landscape scenes set theirs).
@export var illustration: Texture2D:
	set(value):
		illustration = value
		_fit_floor()
## Authored scenes the floor instances in play: a piece per reported group (the Paladin has his own) and an ink
## ribbon per sent order.
@export var piece_scene: PackedScene
@export var avatar_piece_scene: PackedScene
@export var ink_line_scene: PackedScene

@export_group("Copy from the world")
## The world whose MapPoints and their neighbour links the button copies onto the floor.
@export_file("*.tscn") var source_world: String = "res://scenes/world/world.tscn"
## The scenes the button instances for a point and a link.
@export var marker_scene: PackedScene
@export var link_line_scene: PackedScene
## Tick to have the next copy also put back every marker and line already here where the world has it (your hand
## edits to them are lost) and remove those the world no longer has. Unticks itself after the copy.
@export var overwrite_on_copy: bool = false
@export_tool_button("Copy map points and links", "Duplicate") var copy_button: Callable = _on_copy_pressed

## Seconds for a sent order's route to darken in ink (ticket #538).
## PLACEHOLDER: tuning.
const INK_SECONDS: float = 3.0
## Reports older than this (seconds) make a piece "old news" (never missing).
const STALE_SECONDS: float = 90.0
## Enemy sightings closer than this share one piece, as a fraction of the world's width (so the same on the floor at every
## world size). PLACEHOLDER: tuning — was 15 m on the 360 m map; 0.04 is 80 m on the 2 km map (14 m of floor).
const ENEMY_CLUSTER_FRACTION: float = 0.04
const REFRESH_INTERVAL: float = 0.2
const HEIGHT: float = 0.02
const PENCIL_WIDTH: float = 0.025
const INK_WIDTH: float = 0.05

var _markers: Dictionary[StringName, MapPointMarker] = {}
var _link_lines: Array[MapLinkLine] = []
var _pieces: Dictionary[int, MapPiece] = {}
var _refresh_timer: float = 0.0
var _ink_started: Dictionary[int, float] = {}
var _active: bool = false

## Order authoring (local).
var selected_groups: Array[int] = []
var authoring: bool = false
## Piece being carried by hand (MapPiece key), or 0.
var carried_piece: int = 0
## The way to the destination being looked at while authoring (plan_to), or {}; and which destination and selection.
var _preview: Dictionary = {}
var _preview_key: String = ""

@onready var _illustration_plane: MeshInstance3D = %Illustration
@onready var _markers_root: Node3D = %Markers
@onready var _links_root: Node3D = %Links
@onready var _pieces_root: Node3D = %Pieces
@onready var _ink_root: Node3D = %Ink
@onready var _draft_line: MeshInstance3D = %DraftLine

func _ready() -> void:
	_fit_floor()
	if Engine.is_editor_hint():
		return
	for child in _markers_root.get_children():
		var marker := child as MapPointMarker
		if marker:
			marker.floor_map = self
			_markers[marker.point_id] = marker
			marker.set_shown(false)
	for child in _links_root.get_children():
		if child is MapLinkLine:
			_link_lines.append(child)
			(child as MapLinkLine).visible = false

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

func get_marker(point_id: StringName) -> MapPointMarker:
	return _markers.get(point_id)

func forget_point(point_id: StringName) -> void:
	## The point left the match (an unpicked tower's gate, TowerPicks.remove_unpicked): drop its marker and every
	## link line that ends at it.
	var marker: MapPointMarker = _markers.get(point_id)
	if marker != null:
		_markers.erase(point_id)
		marker.get_parent().remove_child(marker)
		marker.queue_free()
	for line in _link_lines.duplicate():
		if line.from_point == point_id or line.to_point == point_id:
			_link_lines.erase(line)
			line.get_parent().remove_child(line)
			line.queue_free()

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
	if Engine.is_editor_hint():
		return
	var active := is_active_for_local_peer()
	if active != _active:
		_active = active
		var roots: Array[Node3D] = [_pieces_root, _ink_root, _draft_line]
		for n in roots:
			n.visible = active
		_sync_markers()
		_sync_link_lines()
	if not active:
		return
	_update_carried_piece()
	_update_draft_line()
	_update_highlights()
	_update_ink(delta)
	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL:
		return
	_refresh_timer = 0.0
	_sync_markers()
	_sync_link_lines()
	_sync_pieces()
	_sync_ink()

# --- Selection and authoring ---

func toggle_group(group_id: int) -> void:
	if group_id in selected_groups:
		selected_groups.erase(group_id)
	else:
		selected_groups.append(group_id)
	authoring = not selected_groups.is_empty()
	_preview = {}
	_preview_key = ""
	selection_changed.emit()

func start_courier_route() -> void:
	## E on your own tower's point: a courier alone, leaving from home.
	selected_groups.clear()
	authoring = true
	_preview = {}
	_preview_key = ""
	selection_changed.emit()

func cancel_authoring() -> void:
	selected_groups.clear()
	authoring = false
	_preview = {}
	_preview_key = ""
	selection_changed.emit()

func plan_to(point: MapPoint) -> Dictionary:
	## The way for each selected group (or a courier from home) to `point`, along neighbouring points this player
	## knows: { points: every point on any of the ways, route_points / route: the first way's points and where they
	## stand, paths / routes: group id -> its way's points and where they stand }. Empty when no known way leads there.
	var tick := KnowledgeManager.current_tick()
	var m := model()
	var known := m.is_point_known
	var graph := PointGraph.from_tree(get_tree())
	var starts: Dictionary[int, MapPoint] = {}
	if selected_groups.is_empty():
		starts[0] = _tower_point()
	else:
		for gid in selected_groups:
			starts[gid] = PointGraph.nearest_point(get_tree(), m.group_position(gid, tick), known)
	var points: Array[StringName] = []
	var paths: Dictionary = {}
	var routes: Dictionary = {}
	var first: Dictionary = {}
	for key in starts:
		if starts[key] == null:
			return {}
		var way := graph.plan_route(starts[key], point, known)
		if way.is_empty():
			return {}
		if first.is_empty():
			first = way
		if key != 0:
			paths[key] = way["points"]
			routes[key] = way["route"]
		for pid in way["points"]:
			if pid not in points:
				points.append(pid)
	return {"points": points, "route_points": first["points"], "route": first["route"], "paths": paths, "routes": routes}

func preview_destination(marker: MapPointMarker) -> void:
	## A marker gained or lost the player's gaze: while authoring, light up the way there.
	_preview = {}
	_preview_key = ""
	if marker != null and marker.point != null and authoring:
		way_to(marker.point)

func way_to(point: MapPoint) -> Dictionary:
	## plan_to, kept while the destination and the selection stay the same (the prompt asks every frame).
	var key := "%s|%s" % [point.point_id, selected_groups]
	if key != _preview_key:
		_preview_key = key
		_preview = plan_to(point)
	return _preview

func finish_at(point: MapPoint) -> void:
	## E on a point while authoring: the way there is chosen and the order
	## goes into your hand as a scroll.
	var player := local_player()
	if player == null or not authoring:
		return
	var way := plan_to(point)
	if way.is_empty():
		return
	var believed: Dictionary = {}
	for gid in selected_groups:
		believed[gid] = model().group_position(gid, KnowledgeManager.current_tick())
	player.hold_order({
		"group_ids": selected_groups.duplicate(),
		"believed": believed,
		"route_points": way["route_points"],
		"route": way["route"],
		"paths": way["paths"],
		"routes": way["routes"],
		"dest_point": point.point_id,
		"dest_kind": point.kind,
	})
	cancel_authoring()

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
	if Engine.is_editor_hint() or not is_active_for_local_peer():
		return
	if carried_piece != 0 and event.is_action_pressed("primary_ability"):
		put_down()
		get_viewport().set_input_as_handled()
	elif authoring and event.is_action_pressed("cancel"):
		cancel_authoring()
		get_viewport().set_input_as_handled()

# --- Points and links: what the owner knows ---

func _sync_markers() -> void:
	var m := model()
	for id in _markers:
		var marker := _markers[id]
		if marker.point == null:
			marker.point = MapPoint.find(get_tree(), id)
		marker.set_shown(_active and marker.point != null and m.is_point_known(id))

func _sync_link_lines() -> void:
	var m := model()
	for line in _link_lines:
		line.visible = _active and m.is_point_known(line.from_point) and m.is_point_known(line.to_point)

func _update_highlights() -> void:
	## The points and links of the order in hand, else of the way being looked at.
	var lit: Array = _preview.get("points", []) if authoring else []
	var player := local_player()
	if player and player.is_holding_order():
		lit = _order_point_ids(player.held_order)
	for id in _markers:
		var on := id in lit
		if _markers[id].highlighted != on:
			_markers[id].set_highlighted(on)
	var lit_links: Array[MapLinkLine] = []
	var paths: Array = []
	if player and player.is_holding_order():
		paths = _order_paths(player.held_order)
	elif authoring and not _preview.is_empty():
		paths = _order_paths(_preview)
	for path in paths:
		for i in range(1, (path as Array).size()):
			var line := _link_line(StringName(path[i - 1]), StringName(path[i]))
			if line:
				lit_links.append(line)
	for line in _link_lines:
		var on := line in lit_links
		if line.highlighted != on:
			line.set_highlighted(on)

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
	_sync_truth_pieces(wanted)
	for key in _pieces.keys():
		if not wanted.has(key):
			_pieces[key].queue_free()
			_pieces.erase(key)

## Debug (DebugManager.show_true_pieces): every group also where it really is, on the host (groups are host-side).
const TRUTH_KEY_BASE: int = -2000000

func _sync_truth_pieces(wanted: Dictionary[int, bool]) -> void:
	if not DebugManager.show_true_pieces or not multiplayer.is_server():
		return
	var gm := get_tree().current_scene.get_node_or_null("GroupManager") as GroupManager
	if gm == null:
		return
	for g in gm.all_groups():
		var at := gm.get_centroid(g)
		if at == Vector3.INF:
			continue
		var key: int = TRUTH_KEY_BASE - g.id
		wanted[key] = true
		var piece := _get_piece(key, g.owner_peer_id, false)
		piece.group_id = g.id
		piece.count = g.member_ids.size()
		piece.selected = false
		piece.stale = false
		piece.status = g.status
		piece.belief = &"truth"
		piece.truth_waypoint = g.current_waypoint()
		piece.position = world_to_floor(at)
		piece.refresh()

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

# --- Drawing: the order in hand (pencil) and sent orders (ink) ---

func _update_draft_line() -> void:
	## The route of the order in hand, pencilled along the floor's links.
	var player := local_player()
	if player == null or not player.is_holding_order():
		_draft_line.visible = false
		return
	_draft_line.visible = true
	set_ribbons(_draft_line, _order_lines(player.held_order), PENCIL_WIDTH)

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
		line.set_meta(&"lines", _order_lines(o))
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

func _order_paths(o: Dictionary) -> Array:
	## An order's (or a planned way's) point paths: one per group, else the courier's.
	var paths: Array = (o.get("paths", {}) as Dictionary).values()
	if paths.is_empty():
		paths = [o.get("route_points", [])]
	return paths

func _order_point_ids(o: Dictionary) -> Array[StringName]:
	## Every point an order's routes pass.
	var out: Array[StringName] = []
	for path in _order_paths(o):
		for pid in path:
			if StringName(pid) not in out:
				out.append(StringName(pid))
	return out

func _order_lines(o: Dictionary) -> Array[PackedVector3Array]:
	## An order's routes on the floor: one line per group (or the courier's), along the floor's link lines.
	var out: Array[PackedVector3Array] = []
	for path in _order_paths(o):
		var typed: Array[StringName] = []
		for pid in path:
			typed.append(StringName(pid))
		var line := floor_path(typed)
		if line.size() >= 2:
			out.append(line)
	return out

func floor_path(path: Array[StringName]) -> PackedVector3Array:
	## A way through points as a line on this floor: along the link line between each two (straight from marker to
	## marker where the floor has none).
	var out := PackedVector3Array()
	for i in path.size():
		var marker: MapPointMarker = _markers.get(path[i])
		if i == 0:
			if marker:
				out.append(marker.position)
			continue
		var line := _link_line(path[i - 1], path[i])
		if line:
			var pts := line.points_in(self, path[i - 1])
			for k in range(0 if out.is_empty() else 1, pts.size()):
				out.append(Vector3(pts[k].x, HEIGHT, pts[k].z))
		elif marker:
			out.append(marker.position)
	return out

func _link_line(a: StringName, b: StringName) -> MapLinkLine:
	for line in _link_lines:
		if line.ends_at(a, b):
			return line
	return null

func _update_ink(delta: float) -> void:
	## The route darkens like spreading ink from its start to its end.
	for child in _ink_root.get_children():
		var cmd := String(child.name).trim_prefix("Order").to_int()
		var t: float = _ink_started.get(cmd, INK_SECONDS)
		if t >= INK_SECONDS and child.has_meta(&"inked"):
			continue
		t = minf(INK_SECONDS, t + delta)
		_ink_started[cmd] = t
		var lines: Array[PackedVector3Array] = []
		for line in child.get_meta(&"lines", []):
			lines.append(_partial(line, t / INK_SECONDS))
		set_ribbons(child as MeshInstance3D, lines, INK_WIDTH)
		if t >= INK_SECONDS:
			child.set_meta(&"inked", true)

static func _partial(pts: PackedVector3Array, fraction: float) -> PackedVector3Array:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	var want := total * clampf(fraction, 0.0, 1.0)
	var out := PackedVector3Array()
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
# refilled from the lines' points as they change.
static func set_ribbons(mi: MeshInstance3D, lines: Array[PackedVector3Array], width: float) -> void:
	## Flat ribbons on the floor along each line.
	var mesh := mi.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var any := false
	for pts in lines:
		if pts.size() >= 2:
			any = true
	if not any:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for pts in lines:
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
	if not is_node_ready():
		return
	(_illustration_plane.mesh as PlaneMesh).size = Vector2(floor_size, floor_size)
	(_illustration_plane.material_override as StandardMaterial3D).albedo_texture = illustration

# --- Copying the world's points and links onto the floor (editor tool, scripts/build/build_map_floor.gd) ---

func _on_copy_pressed() -> void:
	if get_tree().edited_scene_root != self:
		push_warning("Open scenes/map/map_floor.tscn and press Copy there: the markers and lines belong to that scene.")
		return
	print(copy_from_world(overwrite_on_copy))
	overwrite_on_copy = false
	notify_property_list_changed()

func copy_from_world(overwrite: bool) -> String:
	## Adds a marker under Markers for every MapPoint of `source_world`, and a line under Links for every pair of
	## neighbouring points (MapPoint.neighbors, either way round), that the floor does not have yet (matched by point
	## ids): markers placed by `world_to_floor`, a line's ends on its two markers. With `overwrite`, also puts back those
	## already here and removes those the world no longer has. Returns what it did.
	var markers := get_node(^"Markers")
	var links := get_node(^"Links")
	var world: Node = (load(source_world) as PackedScene).instantiate()
	var have_markers: Dictionary[StringName, MapPointMarker] = {}
	for c in markers.get_children():
		if c is MapPointMarker:
			have_markers[(c as MapPointMarker).point_id] = c
	var have_lines: Array[MapLinkLine] = []
	for c in links.get_children():
		if c is MapLinkLine:
			have_lines.append(c)
	var added := 0
	var reset := 0
	var seen_points: Dictionary[StringName, bool] = {}
	var spots: Dictionary[StringName, Vector3] = {}
	var points: Array[MapPoint] = []
	for p in world.get_node("World/MapPoints").get_children():
		var point := p as MapPoint
		if point == null:
			continue
		points.append(point)
		var id := _id_of(point)
		seen_points[id] = true
		var marker: MapPointMarker = have_markers.get(id)
		if marker != null and not overwrite:
			spots[id] = marker.position   # A line ends on the marker as it stands here.
			continue
		if marker == null:
			marker = marker_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as MapPointMarker
			marker.name = "Point_%s" % id
			markers.add_child(marker)
			marker.owner = self
			added += 1
		else:
			reset += 1
		marker.point_id = id
		marker.label_text = point.get_label()
		marker.disc_color = MapPointMarker.kind_color(point.kind)
		marker.position = world_to_floor(MapPoint.spot_in_world(point, world))
		spots[id] = marker.position
	var kept_lines: Array[MapLinkLine] = []
	for point in points:
		for n in point.neighbors:
			if n == null or n == point:
				continue
			var a := _id_of(point)
			var b := _id_of(n)
			var line: MapLinkLine = null
			for l in have_lines + kept_lines:
				if l.ends_at(a, b):
					line = l
					break
			if line != null and line in kept_lines:
				continue  # Listed on both points.
			if line != null:
				kept_lines.append(line)
				if not overwrite:
					continue
				reset += 1
			else:
				line = link_line_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as MapLinkLine
				line.name = "Link_%s_%s" % [a, b]
				links.add_child(line)
				line.owner = self
				set_editable_instance(line, true)   # So the ends' positions are saved, and can be dragged.
				kept_lines.append(line)
				added += 1
			line.from_point = a
			line.to_point = b
			(line.get_node(^"%From") as Node3D).position = spots[a] - line.position
			(line.get_node(^"%To") as Node3D).position = spots[b] - line.position
	var removed := 0
	if overwrite:
		for c in markers.get_children():
			if c is MapPointMarker and not seen_points.has((c as MapPointMarker).point_id):
				c.free()
				removed += 1
		for c in links.get_children():
			if c is MapLinkLine and c not in kept_lines:
				c.free()
				removed += 1
	world.free()
	return "[map floor] copied from %s: %d added, %d put back, %d removed" % [source_world, added, reset, removed]

static func _id_of(point: MapPoint) -> StringName:
	return point.point_id if point.point_id != &"" else StringName(point.name)
