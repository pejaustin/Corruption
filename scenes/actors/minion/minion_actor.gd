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
## Set by _on_link_reached when the nav agent hits a NavigationLink3D in the
## "jumpable" group. JumpState reads this to aim its arc.
var jump_target: Vector3 = Vector3.INF

var move_speed: float = 3.5
var attack_damage: int = 10
var attack_cooldown: float = 1.5
var attack_range: float = 1.8
var aggro_radius: float = 8.0
var max_hp_value: int = 40

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
	_refresh_aggro_ring()

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

func sync_from_server(pos: Vector3, rot_y: float, new_state: StringName, new_hp: int) -> void:
	_target_pos = pos
	_target_rot = rot_y
	if _state_machine and _state_machine.state != new_state:
		_state_machine.state = new_state
	hp = new_hp
	if _state_machine and _state_machine.state == &"DeathState" and collision_layer != 0:
		collision_layer = 0
