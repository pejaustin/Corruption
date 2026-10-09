class_name AvatarAI extends Node

## Host-side AI driver for the possessable Avatar.
## When the avatar is owned but uncontrolled, this node synthesizes the same
## inputs a player would produce: AvatarInput calls drive() from its
## before_tick_loop gather while is_driving(), so the rollback loop consumes
## AI input exactly like player input (host is input authority when released).
## Steering works by pointing the camera mount at the goal and "pushing
## forward" — camera_basis is already a synced input property, so clients
## replay the exact same movement.
##
## Behavior parity with minion AI: idle → aggro → chase → attack, plus
## war-table waypoints via command_move() (Phase C routes orders here).

const AGGRO_RADIUS: float = 10.0
const LEASH_RADIUS: float = 15.0
const ATTACK_RANGE: float = 2.0
const ARRIVE_RADIUS: float = 1.5
const RUN_DISTANCE: float = 8.0
const REPATH_INTERVAL: float = 0.5

@onready var _avatar: AvatarActor = get_parent()
@onready var _nav_agent: NavigationAgent3D = get_node("../NavAgent")

var _target: MinionActor = null
var _waypoint: Vector3 = Vector3.ZERO
var _has_waypoint: bool = false
var _repath_timer: float = 0.0
## Remaining points of a courier-delivered route, walked in order.
var _route: Array[Vector3] = []

func _ready() -> void:
	var input: AvatarInput = get_node("../AvatarInput")
	input.ai_driver = self

func _physics_process(delta: float) -> void:
	_repath_timer = maxf(0.0, _repath_timer - delta)

func is_driving() -> bool:
	return multiplayer.is_server() \
		and GameState.has_avatar_owner() \
		and not GameState.has_avatar() \
		and not _avatar.is_dormant \
		and _avatar.hp > 0

func command_move(pos: Vector3) -> void:
	## War-table order (Phase C) / debug hook: walk here, fighting anything
	## hostile that crosses the path.
	_waypoint = pos
	_has_waypoint = true

func command_route(route: Array) -> void:
	## Courier-delivered order: walk the route's points in order (GDD §8: "Left
	## alone, he follows orders, moves with armies").
	_route.clear()
	for p in route:
		_route.append(p)
	if _route.is_empty():
		return
	command_move(_route.pop_front())

func clear_orders() -> void:
	_has_waypoint = false
	_route.clear()
	_target = null

func drive(input: AvatarInput) -> void:
	## Called by AvatarInput._gather (host, before_tick_loop) while is_driving().
	input.input_dir = Vector2.ZERO
	input.jump_input = false
	input.run_input = false
	input.attack_input = false
	input.roll_input = false

	_update_target()
	if _target:
		var dist := _flat_distance(_target.global_position)
		if dist <= ATTACK_RANGE:
			_face(_target.global_position)
			input.attack_input = true
		else:
			_steer_toward(_target.global_position, input)
			input.run_input = dist > RUN_DISTANCE
		return
	if _has_waypoint:
		var dist := _flat_distance(_waypoint)
		if dist <= ARRIVE_RADIUS:
			_has_waypoint = false
			if not _route.is_empty():
				command_move(_route.pop_front())
			return
		_steer_toward(_waypoint, input)
		input.run_input = dist > RUN_DISTANCE

func _update_target() -> void:
	# Sticky: keep the current target while it's alive and inside the leash.
	if _target and is_instance_valid(_target) and _target.can_take_damage() \
			and _flat_distance(_target.global_position) <= LEASH_RADIUS:
		return
	_target = null
	var scene := get_tree().current_scene
	if not scene:
		return
	var mm = scene.get_node_or_null("MinionManager")
	if not mm:
		return
	var best_dist := AGGRO_RADIUS
	for minion in mm.get_all_minions():
		if not _avatar.is_hostile_to(minion):
			continue
		if not minion.can_take_damage():
			continue
		var d := _flat_distance(minion.global_position)
		if d < best_dist:
			best_dist = d
			_target = minion

func _steer_toward(goal: Vector3, input: AvatarInput) -> void:
	if _repath_timer <= 0.0 or _nav_agent.target_position.distance_to(goal) > 1.0:
		_nav_agent.target_position = goal
		_repath_timer = REPATH_INTERVAL
	var next := _nav_agent.get_next_path_position()
	var dir := next - _avatar.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	_face(_avatar.global_position + dir)
	# Mount faces the path — "push forward" exactly like a player holding W.
	input.input_dir = Vector2(0, -1)

func _face(world_point: Vector3) -> void:
	## Point the camera mount at the goal so the movement states'
	## camera-relative input and the model's facing both line up.
	var mount: Node3D = _avatar.avatar_camera.camera_mount
	var dir := world_point - _avatar.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	mount.global_basis = Basis.looking_at(dir.normalized(), Vector3.UP)
	# AvatarCamera sits earlier in the tree, so its before_tick_loop gather
	# already snapshotted camera_basis from the mount's PRE-rotation pose.
	# Write the input property directly so this tick's forward-push pairs
	# with this tick's heading, not last tick's.
	_avatar.avatar_camera.camera_basis = mount.global_basis

func _flat_distance(world_point: Vector3) -> float:
	## Horizontal distance from the avatar — same convention as
	## MinionState.distance_to(). Waypoints arrive with y = 0 (debug order,
	## later the war table), so a 3D distance would never close on raised
	## terrain; slopes would likewise skew aggro/attack-range checks.
	var diff := _avatar.global_position - world_point
	diff.y = 0.0
	return diff.length()
