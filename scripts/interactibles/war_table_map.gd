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

## Authored chess-piece scene used for every belief stack on the diorama. Root
## is a `WarTablePiece` (Interactable / Area3D) carrying its own collider; the
## map stamps each live stack's root with `member_ids` (Array[int]),
## `owner_peer_id`, and `faction` metadata, which the piece's prompt + select
## logic reads back. MeshInstance3D descendants are recursively faction-tinted.
## A `Label3D` named `CountBadge` (visible iff member count > 1) sits on top.
##
## Leave null to fall back to a procedural cylinder mesh (no collider — pieces
## won't be focusable in fallback mode, but stacks still render).
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
## Draft arrow — red, drawn while the order is still a plan on the table
## (pre-Paper, freely cancelable via Reset). Source → destination.
const DRAFT_ARROW_COLOR: Color = Color(0.85, 0.25, 0.25)
## Readied arrow — amber, drawn after the overlord interacts with the Paper
## but before the Advisor dispatches a courier. Visually says "committed,
## waiting on transit."
const READIED_ARROW_COLOR: Color = Color(0.95, 0.65, 0.15)
## Reality overlay marker color — yellow so it doesn't clash with the red
## draft arrows (debug-distinct, unambiguous).
const REALITY_MARKER_COLOR: Color = Color(1.0, 0.85, 0.15)
## Tint multiplied onto a piece's base material when it's in the overlord's
## active selection (war-table commanding flow).
const SELECTION_TINT: Color = Color(1.6, 1.6, 0.5, 1.0)
## Two pieces whose believed positions are within this distance (in TABLE-LOCAL
## meters) merge into a single stack. ~2.5× piece_radius — close enough that
## the cylinders look "touching" on the diorama, far enough that adjacent-but-
## distinct minions stay visually separate. Sub-stack selection is delegated to
## the WarTableStackInspector ghost popup (auto-opens above multi-member
## stacks); E on the stack itself = "select all available members."
const MERGE_DISTANCE: float = 0.15

## A believed sighting older than this many seconds renders with a "?" badge —
## the broadcast network hasn't refreshed it recently, so the overlord can't
## trust the position anymore. Computed in ticks via KnowledgeManager.UPDATE_INTERVAL.
const STALE_THRESHOLD_SECONDS: float = 3.0

## Stack key: sorted member ids joined by "," (e.g. &"5,12,17"). Stable across
## frames as long as the same set of minions cluster together. Visual nodes
## persist across frames keyed by this; when membership changes, the old stack
## is freed and a new one is born — fine for now, phase 3 polish can tween.
var _stacks: Dictionary[StringName, Node3D] = {}
var _stack_targets: Dictionary[StringName, Vector3] = {}
var _stack_factions: Dictionary[StringName, int] = {}
var _stacks_root: Node3D
## Tinted material cache for chess pieces. Key built from
## "<base_material_id>_<faction>_<selected_int>" so each authored mesh+faction
## combination gets exactly one duplicated StandardMaterial3D — its
## albedo_color is set to the faction tint (multiplying the authored
## albedo_texture, e.g. concrete) instead of replacing the whole material.
var _tinted_piece_materials: Dictionary[String, StandardMaterial3D] = {}
## Per-minion-id selection set. Selection is a set of minion ids — stacks are
## just a visual grouping. A stack is highlighted iff at least one of its
## members is in this dict.
var _selected_member_ids: Dictionary[int, bool] = {}
## Tower markers — one per anchor passed in via set_tower_anchors().
var _tower_anchors: Array[Node3D] = []
var _tower_pieces: Array[Node3D] = []
var _towers_root: Node3D
## cmd_id -> { "orders": Array[MeshInstance3D], "route_arrows": Array[MeshInstance3D] }
##   orders:        one arrow per leg in the draft (each leg = one minion's
##                  snapshot source_pos → target_pos). Red while draft, amber
##                  while readied, black once dispatched.
##   route_arrows:  poly-line of segments spawn → leg0 → leg1 → ... → legN
##                  (one MeshInstance3D per segment). Only populated once
##                  dispatched; matches the TSP-ordered route the courier
##                  actually walks.
var _command_visuals: Dictionary[int, Dictionary] = {}
var _commands_root: Node3D
## courier minion id -> small marker MeshInstance3D
var _reality_pieces: Dictionary[int, MeshInstance3D] = {}
var _reality_root: Node3D
var _arrow_material: StandardMaterial3D
var _draft_arrow_material: StandardMaterial3D
var _readied_arrow_material: StandardMaterial3D
var _route_material: StandardMaterial3D
var _reality_material: StandardMaterial3D

func _ready() -> void:
	_stacks_root = Node3D.new()
	_stacks_root.name = "Stacks"
	add_child(_stacks_root)
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
	if _stacks.is_empty():
		return
	var t: float = clampf(piece_lerp_speed * delta, 0.0, 1.0)
	for key in _stacks:
		var stack: Node3D = _stacks[key]
		if not is_instance_valid(stack):
			continue
		var target: Vector3 = _stack_targets.get(key, stack.position)
		stack.position = stack.position.lerp(target, t)

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
	# Cluster believed minions by (owner, faction, proximity) and render one
	# stack per cluster. Map = representation: minions that physically cross
	# paths in the world don't imply shared orders, but on the table their
	# pieces collapse into a single stack with a count badge.
	var clusters := _cluster_minions(model)
	var seen_keys: Dictionary[StringName, bool] = {}
	for cluster in clusters:
		var key: StringName = cluster["key"]
		seen_keys[key] = true
		_render_stack(cluster)
	var dead: Array[StringName] = []
	for key in _stacks.keys():
		if key not in seen_keys:
			dead.append(key)
	for key in dead:
		var stack := _stacks[key]
		if is_instance_valid(stack):
			stack.queue_free()
		_stacks.erase(key)
		_stack_targets.erase(key)
		_stack_factions.erase(key)
	_render_pending_commands(model)
	_render_reality_couriers()

func clear_pieces() -> void:
	for stack in _stacks.values():
		if is_instance_valid(stack):
			stack.queue_free()
	_stacks.clear()
	_stack_targets.clear()
	_stack_factions.clear()

func _cluster_minions(model: WorldModel) -> Array[Dictionary]:
	## Greedy proximity clustering scoped to (owner_peer_id, faction). Iterates
	## minion ids in sorted order so cluster keys are deterministic across
	## frames — a stack with the same membership reuses its visual node and
	## doesn't flicker. Same owner + same faction is a precondition: mixed-
	## ownership stacks would mislead the player, and friendly/enemy lines
	## should never visually merge.
	##
	## Returns Array[Dictionary] where each entry has:
	##   key: StringName             — sorted member ids, comma-joined
	##   member_ids: Array[int]      — minions in the cluster
	##   owner_peer_id: int          — shared by all members
	##   faction: int                — shared by all members
	##   centroid: Vector3           — average TABLE-LOCAL position
	var entries: Array[Dictionary] = []
	for id in model.believed_friendly_minions.keys():
		entries.append(_entry_to_record(id, model.believed_friendly_minions[id]))
	for id in model.believed_enemy_minions.keys():
		entries.append(_entry_to_record(id, model.believed_enemy_minions[id]))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])

	var clusters: Array[Dictionary] = []
	var merge_dist_sq: float = MERGE_DISTANCE * MERGE_DISTANCE
	for e in entries:
		var pos_local: Vector3 = world_to_table_local(e["pos"])
		var merged: bool = false
		for c in clusters:
			if c["owner_peer_id"] != e["owner_peer_id"] or c["faction"] != e["faction"]:
				continue
			var cx: Vector3 = c["centroid"]
			var dx: float = cx.x - pos_local.x
			var dz: float = cx.z - pos_local.z
			if dx * dx + dz * dz > merge_dist_sq:
				continue
			var members: Array[int] = c["member_ids"]
			members.append(e["id"])
			var n: int = members.size()
			# Running mean — keeps centroid honest as members join.
			c["centroid"] = cx * (float(n - 1) / float(n)) + pos_local * (1.0 / float(n))
			# Cluster freshness = freshest member. Show stale "?" only when
			# every belief in this cluster has aged out.
			c["last_updated_tick"] = max(int(c["last_updated_tick"]), int(e["last_updated_tick"]))
			merged = true
			break
		if not merged:
			var fresh: Array[int] = [e["id"]]
			clusters.append({
				"member_ids": fresh,
				"owner_peer_id": e["owner_peer_id"],
				"faction": e["faction"],
				"centroid": pos_local,
				"last_updated_tick": int(e["last_updated_tick"]),
			})

	# Assign canonical keys after clustering settles.
	for c in clusters:
		var ids: Array[int] = c["member_ids"]
		ids.sort()
		c["member_ids"] = ids
		var key_str: String = ""
		for i in ids.size():
			if i > 0:
				key_str += ","
			key_str += str(ids[i])
		c["key"] = StringName(key_str)
	return clusters

func _entry_to_record(id: int, entry: Dictionary) -> Dictionary:
	return {
		"id": id,
		"pos": entry.get("pos", Vector3.ZERO) as Vector3,
		"owner_peer_id": int(entry.get("owner_peer_id", -1)),
		"faction": int(entry.get("faction", GameConstants.Faction.NEUTRAL)),
		"last_updated_tick": int(entry.get("last_updated_tick", 0)),
	}

func _render_stack(cluster: Dictionary) -> void:
	var key: StringName = cluster["key"]
	var member_ids: Array[int] = cluster["member_ids"]
	var faction: int = cluster["faction"]
	var owner_pid: int = cluster["owner_peer_id"]
	var target: Vector3 = cluster["centroid"]
	var last_updated_tick: int = int(cluster.get("last_updated_tick", 0))
	var existed: bool = key in _stacks
	var stack := _get_or_create_stack(key, member_ids, faction, owner_pid)
	if not existed:
		# Snap brand-new stacks to their target so they don't swoop in from the
		# origin. Existing stacks update the lerp target and _process eases.
		stack.position = target
	_stack_targets[key] = target
	_stack_factions[key] = faction
	_update_count_badge(stack, member_ids.size())
	_update_stale_badge(stack, last_updated_tick)

func _update_stale_badge(stack: Node3D, last_updated_tick: int) -> void:
	## Show the "?" badge when every belief in this cluster has aged past
	## STALE_THRESHOLD_SECONDS — i.e., the broadcast network hasn't refreshed
	## the cluster recently. Hidden when fresh.
	var badge := stack.get_node_or_null(^"StaleBadge") as Label3D
	if badge == null:
		return
	var current_tick: int = KnowledgeManager.current_tick()
	var age_ticks: int = current_tick - last_updated_tick
	var stale_threshold_ticks: int = int(STALE_THRESHOLD_SECONDS / KnowledgeManager.UPDATE_INTERVAL)
	badge.visible = age_ticks > stale_threshold_ticks

func _get_or_create_stack(key: StringName, member_ids: Array[int], faction: int, owner_peer_id: int) -> Node3D:
	var stack: Node3D = _stacks.get(key)
	if stack == null or not is_instance_valid(stack):
		stack = _instantiate_piece()
		stack.name = "Stack_%s" % str(key)
		_stacks_root.add_child(stack)
		_stacks[key] = stack
	# Re-stamp metadata on the stack root every render so ownership changes
	# (e.g. Eldritch dominate dissolving a cluster) propagate to the piece's
	# prompt + selection logic. member_ids gets duplicated so a later mutation
	# of the cluster array can't silently rewrite the metadata.
	stack.set_meta(&"member_ids", member_ids.duplicate())
	stack.set_meta(&"owner_peer_id", owner_peer_id)
	stack.set_meta(&"faction", faction)
	var any_selected: bool = false
	for mid in member_ids:
		if _selected_member_ids.get(mid, false):
			any_selected = true
			break
	_apply_faction_tint(stack, faction, any_selected)
	return stack

func _update_count_badge(stack: Node3D, count: int) -> void:
	var badge := stack.get_node_or_null(^"CountBadge") as Label3D
	if badge == null:
		return
	if count > 1:
		badge.text = str(count)
		badge.visible = true
	else:
		badge.visible = false

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
##
## Skips WarTableGhost subtrees — those handle their own per-member highlight
## independently of the stack-level "any selected" tint, so we don't want the
## stack's selected/unselected state painting over them.
func _apply_faction_tint(root: Node, faction: int, selected: bool) -> void:
	if root is MeshInstance3D:
		_tint_mesh_instance(root as MeshInstance3D, faction, selected)
	for child in root.get_children():
		if child is WarTableGhost:
			continue
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
## right material to every stack so toggling shows immediately. Selection
## highlight is only applied to **single-member** stacks — for multi-member
## stacks the per-member feedback lives on the ghost popup, and lighting up
## the parent piece would wrongly imply "this whole group is selected" when
## the player has only picked some members. Multi-member stacks therefore
## stay at their plain faction tint regardless of selection state.
func set_selected_pieces(ids: Array[int]) -> void:
	var new_selected: Dictionary[int, bool] = {}
	for id in ids:
		new_selected[id] = true
	# Re-tint every stack. Tinted materials are cached, so the cost per call
	# is one set_surface_override_material per mesh per stack — cheap.
	for key in _stacks.keys():
		var stack: Node3D = _stacks[key]
		if not is_instance_valid(stack):
			continue
		var faction: int = _stack_factions.get(key, GameConstants.Faction.NEUTRAL)
		var member_ids: Array = stack.get_meta(&"member_ids", [] as Array)
		var any_selected: bool = false
		if member_ids.size() == 1:
			# Single-member: the piece IS the only "ghost"; show selection here.
			if new_selected.get(int(member_ids[0]), false):
				any_selected = true
		_apply_faction_tint(stack, faction, any_selected)
	_selected_member_ids = new_selected

# --- Pending commands (belief layer: intent arrows + midpoint pawns) ---

func _render_pending_commands(model: WorldModel) -> void:
	## Each entry in model.pending_commands renders by stage:
	##   "draft"      → one red ORDER arrow per leg (source_pos → target_pos).
	##                  Mutable on the table; cancelable via Reset.
	##   "readied"    → same arrows, recolored amber. Player has interacted with
	##                  the Paper; the orders are committed but the Advisor
	##                  hasn't dispatched a courier yet.
	##   "dispatched" → same arrows, recolored black, plus a blue COURIER ROUTE
	##                  arrow spawn_pos → centroid. (Phase 4 will swap the
	##                  route to a multi-stop visualization.)
	## Each promotion flips the order arrows' color in place; dispatch also adds
	## the route arrow. To see the courier's actual world position rather than
	## the symbolic route, flip SHOW_REALITY (debug overlay).
	var seen: Dictionary[int, bool] = {}
	# Track which couriers have already had their route arrows drawn this frame
	# so multiple entries sharing one courier (post-batching) don't redraw the
	# polyline N times. The first entry to render for a given courier owns the
	# route visuals; later entries skip and have their route_arrows freed.
	var couriers_route_drawn: Dictionary[int, int] = {}
	for cmd_id in model.pending_commands.keys():
		seen[cmd_id] = true
		var entry: Dictionary = model.pending_commands[cmd_id]
		var stage: StringName = entry.get("stage", &"dispatched")
		var target_world: Vector3 = entry.get("target_pos", Vector3.ZERO)
		var target_local: Vector3 = world_to_table_local(target_world)
		var legs: Array = entry.get("legs", [])
		# Fallback for old-shape entries that lack `legs`: synthesize a single
		# leg from the centroid source_pos so the arrow still draws.
		if legs.is_empty():
			var fallback_source: Vector3 = entry.get("source_pos", Vector3.ZERO)
			legs = [{"source_pos": fallback_source, "minion_ids": entry.get("minion_ids", [])}]
		var visuals: Dictionary = _command_visuals.get(cmd_id, {})
		var orders: Array = visuals.get("orders", [])
		var labels: Array = visuals.get("order_labels", [])
		var arrow_mat: StandardMaterial3D = _get_arrow_material_for_stage(stage)
		# Reuse existing arrows when possible, append more if leg count grew.
		for i in legs.size():
			var leg: Dictionary = legs[i]
			var source_world: Vector3 = leg.get("source_pos", Vector3.ZERO)
			var source_local: Vector3 = world_to_table_local(source_world)
			var arrow: MeshInstance3D
			if i < orders.size() and is_instance_valid(orders[i]):
				arrow = orders[i]
			else:
				arrow = _make_arrow_mesh()
				_commands_root.add_child(arrow)
				if i < orders.size():
					orders[i] = arrow
				else:
					orders.append(arrow)
			_orient_arrow(arrow, source_local, target_local)
			arrow.material_override = arrow_mat
			# Order count badge — visible only when the leg covers >1 minion,
			# so the player can see at a glance how many minions an arrow
			# applies to. Lives at the arrow's midpoint.
			var leg_minion_count: int = (leg.get("minion_ids", []) as Array).size()
			var label: Label3D
			if i < labels.size() and is_instance_valid(labels[i]):
				label = labels[i]
			else:
				label = _make_order_count_label()
				_commands_root.add_child(label)
				if i < labels.size():
					labels[i] = label
				else:
					labels.append(label)
			if leg_minion_count > 1:
				label.text = str(leg_minion_count)
				label.position = (source_local + target_local) * 0.5 + Vector3(0, 0.04, 0)
				label.visible = true
			else:
				label.visible = false
		# Trim excess if legs shrank (e.g. a future courier path peeled some
		# off mid-flight).
		while orders.size() > legs.size():
			var extra: MeshInstance3D = orders.pop_back()
			if is_instance_valid(extra):
				extra.queue_free()
		while labels.size() > legs.size():
			var extra_lbl: Label3D = labels.pop_back()
			if is_instance_valid(extra_lbl):
				extra_lbl.queue_free()
		visuals["orders"] = orders
		visuals["order_labels"] = labels
		# Courier route polyline: spawn → leg0 → leg1 → ... → legN. One arrow
		# per consecutive pair. Only present after dispatch — and only one
		# entry per courier owns the route visuals so batched entries (multiple
		# entries on one courier) don't all redraw the same lines.
		var route_arrows: Array = visuals.get("route_arrows", [])
		var courier_id: int = int(entry.get("courier_id", -1))
		var should_draw_route: bool = (
			stage == &"dispatched"
			and (courier_id < 0 or courier_id not in couriers_route_drawn)
		)
		if should_draw_route:
			if courier_id >= 0:
				couriers_route_drawn[courier_id] = cmd_id
			var route_waypoints: Array = entry.get("route_waypoints", [])
			# Fallback for any legacy entry that lacks route_waypoints: synth a
			# 2-point route from spawn_pos → source_pos so something still draws.
			if route_waypoints.size() < 2:
				route_waypoints = [
					entry.get("spawn_pos", Vector3.ZERO),
					entry.get("source_pos", Vector3.ZERO),
				]
			var segment_count: int = route_waypoints.size() - 1
			for i in segment_count:
				var a_world: Vector3 = route_waypoints[i]
				var b_world: Vector3 = route_waypoints[i + 1]
				var a_local: Vector3 = world_to_table_local(a_world)
				var b_local: Vector3 = world_to_table_local(b_world)
				var seg: MeshInstance3D
				if i < route_arrows.size() and is_instance_valid(route_arrows[i]):
					seg = route_arrows[i]
				else:
					seg = _make_arrow_mesh()
					_commands_root.add_child(seg)
					if i < route_arrows.size():
						route_arrows[i] = seg
					else:
						route_arrows.append(seg)
				_orient_arrow(seg, a_local, b_local)
				seg.material_override = _get_route_material()
			while route_arrows.size() > segment_count:
				var extra: MeshInstance3D = route_arrows.pop_back()
				if is_instance_valid(extra):
					extra.queue_free()
			visuals["route_arrows"] = route_arrows
		else:
			# Either pre-dispatch OR another entry on this courier already
			# drew the route — drop any stale arrows we held.
			for r in route_arrows:
				if is_instance_valid(r):
					r.queue_free()
			visuals.erase("route_arrows")
		_command_visuals[cmd_id] = visuals
	# Drop visuals for commands that have completed (courier despawned, or a
	# draft that was abandoned).
	var dead: Array[int] = []
	for cmd_id in _command_visuals.keys():
		if cmd_id not in seen:
			dead.append(cmd_id)
	for cmd_id in dead:
		var v: Dictionary = _command_visuals[cmd_id]
		var orders_dead: Array = v.get("orders", [])
		for o in orders_dead:
			if is_instance_valid(o):
				o.queue_free()
		var labels_dead: Array = v.get("order_labels", [])
		for lbl in labels_dead:
			if is_instance_valid(lbl):
				lbl.queue_free()
		var route_dead: Array = v.get("route_arrows", [])
		for r in route_dead:
			if is_instance_valid(r):
				r.queue_free()
		_command_visuals.erase(cmd_id)

func _get_arrow_material_for_stage(stage: StringName) -> StandardMaterial3D:
	if stage == &"draft":
		return _get_draft_arrow_material()
	if stage == &"readied":
		return _get_readied_arrow_material()
	return _get_arrow_material()

func _make_arrow_mesh() -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.004, 1.0)
	inst.mesh = mesh
	inst.material_override = _get_arrow_material()
	return inst

func _make_order_count_label() -> Label3D:
	## World-space billboarded count badge that floats over an order arrow's
	## midpoint. Hidden until the leg covers >1 minion.
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.pixel_size = 0.0006
	lbl.font_size = 56
	lbl.outline_size = 12
	lbl.modulate = Color(1, 1, 0.7, 1)
	lbl.outline_modulate = Color(0, 0, 0, 1)
	lbl.visible = false
	return lbl

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

func _get_readied_arrow_material() -> StandardMaterial3D:
	if _readied_arrow_material == null:
		_readied_arrow_material = StandardMaterial3D.new()
		_readied_arrow_material.albedo_color = READIED_ARROW_COLOR
		_readied_arrow_material.roughness = 0.6
	return _readied_arrow_material

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
