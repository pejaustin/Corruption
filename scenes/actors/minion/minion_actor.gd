class_name MinionActor extends Actor

## Host-authoritative minion built on the Actor scene stack.
## AI runs on the host; state is broadcast via MinionManager sync.
## Stats applied from a MinionType resource via apply_type().

const COLLISION_LAYER_MINION: int = 8
const COLLISION_MASK_WORLD: int = 1
## World only. Same-faction and cross-faction minion spacing is handled by the
## NavigationAgent3D's RVO avoidance, not by physical bodies blocking each
## other — that pile-up was wedging late arrivers behind the first to reach a
## shared waypoint, leaving them stuck in chase.
const COLLISION_MASK_MOVEMENT: int = COLLISION_MASK_WORLD
const DEATH_CLEANUP_TIME: float = 1.5
const INTERPOLATION_SPEED: float = 10.0

signal minion_died(minion: MinionActor)

## Per-type scenes (skeleton_actor.tscn etc.) set this in the inspector; stats
## are auto-applied on _ready(). Left null for generic scenes that get their
## type assigned at runtime via apply_type().
@export var minion_type: MinionType

## When true, the minion cannot take damage while in StaggerState (bosses, etc.).
## Placeholder: will eventually be driven by model-scene animation triggers that
## toggle hitbox/invulnerability windows frame-by-frame.
@export var stagger_invulnerable: bool = false

var owner_peer_id: int = -1
var minion_type_id: StringName = &""
var minion_trait: StringName = &""
var waypoint: Vector3 = Vector3.ZERO
## Courier-only payload. Populated by KnowledgeManager.dispatch_readied when
## the courier is spawned. courier_arrival_state pops the head leg as the
## courier arrives at each cluster, dispatches every sub_order at that source
## (each sub_order may target a different position), and sets `waypoint` to
## the next leg's source_pos (or return_pos if the queue is empty).
##
## Each leg: {
##     source_pos: Vector3,
##     sub_orders: Array[{minion_ids: Array[int], target_pos: Vector3}],
## }
## Legs are TSP-greedy ordered from the tower spawn at dispatch time;
## colocated minions (within ~3m world) share a leg even when their targets
## differ. A leg with multiple sub_orders (= multiple distinct targets being
## delivered to one source cluster) is the multi-order batching case driven
## by MinionType.max_orders.
var delivery_legs: Array[Dictionary] = []
var return_pos: Vector3 = Vector3.INF
## Per-leg failures accumulated during the trip. Each entry: {minion_ids,
## target_pos, leg_source}. Reported to KnowledgeManager on home arrival so
## the overlord knows their belief was stale and which orders went undelivered.
var delivery_failures: Array[Dictionary] = []
## Mirrored from MinionType — read by courier_arrival_state to decide visibility
## and loiter time at each leg's source. Default zero (non-courier minions).
var courier_visual_range: float = 0.0
var courier_wait_seconds: float = 0.0
## Optional Area3D the courier should despawn upon entering. Set by
## KnowledgeManager.dispatch_readied when the tower's CourierSpawn is an Area3D
## (the canonical setup). Zone overlap is the authoritative arrival test
## because point-distance checks fail when CourierSpawn sits on a slope or at
## slightly different Y than the navmesh polygon under the courier's feet.
## Falls back to the distance check when null (e.g. test harness using a plain
## Marker3D as a spawn).
var return_zone: Area3D = null
## Set by _on_link_reached when the nav agent hits a NavigationLink3D in the
## "jumpable" group. JumpState reads this to aim its arc.
var jump_target: Vector3 = Vector3.INF

var move_speed: float = 3.5
var attack_damage: int = 10
var attack_cooldown: float = 1.5
var attack_range: float = 1.8
var aggro_radius: float = 8.0
var max_hp_value: int = 40
## Resolved from MinionType — read by states (MinionState._check_retreat) and
## RetreatState. Defaults keep legacy minions retreat-immune.
var can_retreat: bool = false
var retreat_hp_threshold: float = 0.3
## Field log — host-only. Each entry: { id, pos, faction, owner_peer_id,
## observed_tick }. Populated by _observe() while we're in the field. Flushed
## into the owner's WorldModel on arrival home (RetreatState) and cleared.
## Keyed by minion id so a single observed enemy only contributes one entry —
## later sightings of the same target overwrite the earlier one.
var _field_log: Dictionary[int, Dictionary] = {}

var attack_timer: float = 0.0
var _death_timer: float = 0.0
var _pending_raise_pos: Vector3 = Vector3.ZERO

## Last avoidance-adjusted velocity from NavigationAgent3D. ChaseState calls
## nav.set_velocity(desired) each tick; the agent emits velocity_computed with
## the safe value (one tick of latency, normal for RVO). ChaseState reads this
## and applies it to actor.velocity instead of the raw desired velocity.
var safe_velocity: Vector3 = Vector3.ZERO

# Client-side interp targets
var _target_pos: Vector3
var _target_rot: float

var _minion_manager: Node
var _aggro_ring: MeshInstance3D
## Translucent sphere visualization of `courier_visual_range`, toggleable via
## DebugManager.show_courier_visual_range. Built lazily in apply_type when the
## type has a non-zero range (so non-couriers don't carry the overhead).
var _visual_range_overlay: MeshInstance3D
## Throttle for the host-side observation sweep — runs every OBSERVE_INTERVAL
## seconds rather than every physics tick to keep the actor loop cheap.
const OBSERVE_INTERVAL: float = 0.25
## Range within which an actor counts as "observed" by this minion. Smaller
## than aggro_radius — the minion only sees what's near, even if it can't
## fight everything within its sight.
const OBSERVE_RADIUS: float = 12.0
var _observe_timer: float = 0.0
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	super()
	add_to_group(&"minions")
	_target_pos = global_position
	_target_rot = rotation.y
	collision_layer = COLLISION_LAYER_MINION
	collision_mask = COLLISION_MASK_MOVEMENT
	_minion_manager = get_tree().current_scene.get_node_or_null("MinionManager")
	if nav_agent:
		nav_agent.link_reached.connect(_on_link_reached)
		nav_agent.velocity_computed.connect(_on_velocity_computed)
	_setup_aggro_ring()
	if minion_type != null:
		apply_type(minion_type.duplicate_for_match())
	if nav_agent:
		nav_agent.max_speed = move_speed

func _setup_aggro_ring() -> void:
	_aggro_ring = MeshInstance3D.new()
	_aggro_ring.name = "AggroRing"
	_aggro_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aggro_ring)
	_aggro_ring.visible = DebugManager.show_aggro_rings
	DebugManager.aggro_rings_toggled.connect(_on_aggro_rings_toggled)
	_refresh_aggro_ring()

func _on_aggro_rings_toggled(new_visible: bool) -> void:
	if _aggro_ring:
		_aggro_ring.visible = new_visible

func _refresh_aggro_ring() -> void:
	if _aggro_ring == null:
		return
	var segments: int = 48
	var verts := PackedVector3Array()
	for i in segments + 1:
		var a: float = TAU * float(i) / float(segments)
		verts.push_back(Vector3(cos(a) * aggro_radius, 0.05, sin(a) * aggro_radius))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = get_faction_color()
	mat.no_depth_test = true
	mesh.surface_set_material(0, mat)
	_aggro_ring.mesh = mesh

func _on_velocity_computed(safe_vel: Vector3) -> void:
	safe_velocity = safe_vel

func _on_link_reached(details: Dictionary) -> void:
	# Host decides movement; clients are interpolated so they skip jump state.
	if not multiplayer.is_server():
		return
	var link_node := details.get("owner") as Node
	if link_node == null or not link_node.is_in_group(JumpableLink.GROUP):
		return
	jump_target = details.get("link_exit_position", global_position)
	if _state_machine and _state_machine.state != &"JumpState":
		_state_machine.transition(&"JumpState")

func apply_type(mtype: MinionType) -> void:
	minion_type_id = mtype.id
	max_hp_value = mtype.hp
	hp = mtype.hp
	attack_damage = mtype.damage
	move_speed = mtype.speed
	attack_cooldown = mtype.attack_cooldown
	attack_range = mtype.attack_range
	aggro_radius = mtype.aggro_radius
	minion_trait = mtype.trait_tag
	can_retreat = mtype.can_retreat
	retreat_hp_threshold = mtype.retreat_hp_threshold
	courier_visual_range = mtype.courier_visual_range
	courier_wait_seconds = mtype.courier_wait_seconds
	_refresh_aggro_ring()
	_refresh_visual_range_overlay()

func _refresh_visual_range_overlay() -> void:
	## Tear down or rebuild the translucent visual-range sphere whenever
	## courier_visual_range changes. Non-couriers (range = 0) get nothing.
	if courier_visual_range <= 0.0:
		if _visual_range_overlay and is_instance_valid(_visual_range_overlay):
			_visual_range_overlay.queue_free()
			_visual_range_overlay = null
		return
	if _visual_range_overlay == null:
		_visual_range_overlay = MeshInstance3D.new()
		_visual_range_overlay.name = "VisualRangeOverlay"
		_visual_range_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_visual_range_overlay)
		DebugManager.courier_visual_range_toggled.connect(_on_visual_range_toggled)
	var mesh := SphereMesh.new()
	mesh.radius = courier_visual_range
	mesh.height = courier_visual_range * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.85, 1.0, 0.18)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, mat)
	_visual_range_overlay.mesh = mesh
	_visual_range_overlay.visible = DebugManager.show_courier_visual_range

func _on_visual_range_toggled(visible: bool) -> void:
	if _visual_range_overlay and is_instance_valid(_visual_range_overlay):
		_visual_range_overlay.visible = visible

func get_max_hp() -> int:
	return max_hp_value

func get_attack_damage() -> int:
	return attack_damage

func get_stagger_duration() -> float:
	return 0.3

func can_take_damage() -> bool:
	if _state_machine.state == &"DeathState":
		return false
	if stagger_invulnerable and _state_machine.state == &"StaggerState":
		return false
	return hp > 0

func get_faction_color() -> Color:
	return GameConstants.faction_colors.get(faction, Color.WHITE)

func _die() -> void:
	super()
	_death_timer = 0.0
	collision_layer = 0
	velocity = Vector3.ZERO
	minion_died.emit(self)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		_interpolate_client(delta)
		return

	force_update_is_on_floor()
	if not is_on_floor():
		apply_gravity(delta)

	# Only retreat-capable minions accumulate a field log — non-retreaters
	# never make the trip home, so the log would be wasted CPU.
	if can_retreat:
		_observe_timer += delta
		if _observe_timer >= OBSERVE_INTERVAL:
			_observe_timer = 0.0
			_observe()

	# Courier homeward despawn: if our body's CollisionShape3D is overlapping
	# the return_zone Area3D's CollisionShape3D AND we have nothing left to
	# deliver, we're home — despawn. Runs every host tick regardless of state
	# machine so we don't depend on ChaseState transitioning to arrival_state
	# (which can fail when the navmesh edge keeps the courier orbiting outside
	# the nav-finished threshold). return_zone is only set for couriers, so
	# the null guard implicitly skips every other minion type.
	#
	# Before despawning, flush any accumulated delivery_failures into the
	# owner's WorldModel so the overlord gets a "missing" report for orders
	# the courier couldn't deliver.
	if return_zone != null and is_instance_valid(return_zone) and delivery_legs.is_empty():
		if return_zone.overlaps_body(self):
			if not delivery_failures.is_empty():
				KnowledgeManager.notify_delivery_failures(owner_peer_id, delivery_failures)
				delivery_failures.clear()
			if _minion_manager and _minion_manager.has_method("notify_minion_died"):
				_minion_manager.notify_minion_died(self)
				return

	_state_machine._rollback_tick(delta, 0, true)

	if _state_machine.state == &"DeathState":
		_death_timer += delta
		if _death_timer >= DEATH_CLEANUP_TIME:
			if _minion_manager and _minion_manager.has_method("notify_minion_died"):
				_minion_manager.notify_minion_died(self)
			else:
				queue_free()

func _interpolate_client(delta: float) -> void:
	global_position = global_position.lerp(_target_pos, INTERPOLATION_SPEED * delta)
	rotation.y = lerp_angle(rotation.y, _target_rot, INTERPOLATION_SPEED * delta)

func _observe() -> void:
	## Host-only. Sweep nearby actors and stash a sighting per hostile into
	## _field_log so RetreatState can flush it to the owner's WorldModel on
	## arrival home. Friendlies are intentionally not logged — the WorldModel's
	## live broadcast path already covers your own units when in range.
	if owner_peer_id < 0:
		return  # neutral / world enemies have nothing to report
	var observed_tick: int = KnowledgeManager.current_tick()
	for node in get_tree().get_nodes_in_group(&"actors"):
		var other := node as Node3D
		if other == null or other == self:
			continue
		if global_position.distance_to(other.global_position) > OBSERVE_RADIUS:
			continue
		var observed_id: int = -1
		var observed_owner: int = -1
		var observed_faction: int = GameConstants.Faction.NEUTRAL
		if other is MinionActor:
			var mo: MinionActor = other
			if mo.owner_peer_id == owner_peer_id:
				continue  # ignore friendlies
			observed_id = mo.name.to_int()
			observed_owner = mo.owner_peer_id
			observed_faction = mo.faction
		else:
			# Avatar / other non-minion actors aren't logged to _field_log
			# yet; the WorldModel's avatar slot is a separate concern.
			continue
		_field_log[observed_id] = {
			"id": observed_id,
			"pos": other.global_position,
			"owner_peer_id": observed_owner,
			"faction": observed_faction,
			"observed_tick": observed_tick,
		}

func sync_from_server(pos: Vector3, rot_y: float, new_state: StringName, new_hp: int) -> void:
	_target_pos = pos
	_target_rot = rot_y
	if _state_machine and _state_machine.state != new_state:
		_state_machine.state = new_state
	hp = new_hp
	if _state_machine and _state_machine.state == &"DeathState" and collision_layer != 0:
		collision_layer = 0
