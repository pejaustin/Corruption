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
## courier-delivered routes via command_route().
##
## Unclaimed (owner -1, GDD §8 Q16) he serves the good faction: when weak he
## walks home to the city centre and regenerates there; at full strength he
## hunts the nearest site a player holds and fights there (his presence
## purifies it, CorruptionSite). Owned, he skips targets he would resist and
## does not pick fights while his owner's control can't attack.

const AGGRO_RADIUS: float = 10.0
const LEASH_RADIUS: float = 15.0
const ATTACK_RANGE: float = 2.0
const ARRIVE_RADIUS: float = 1.5
const RUN_DISTANCE: float = 8.0
const REPATH_INTERVAL: float = 0.5
## Group of a node marking the city centre / holy site; world origin otherwise.
const HOLY_SITE_GROUP: StringName = &"holy_site"
## PLACEHOLDER: tuning — below this HP fraction the unclaimed Paladin goes home
## to recover, and stays until he is whole again.
const RECOVER_BELOW_FRACTION: float = 0.5
## PLACEHOLDER: tuning — he regenerates within this distance of the city centre.
const RECOVER_RADIUS: float = 6.0
## PLACEHOLDER: tuning — HP regenerated per second at the city centre.
const REGEN_PER_SECOND: float = 5.0
## Fraction of a site's radius he walks into before holding still there.
const SITE_STAND_FRACTION: float = 0.5

@onready var _avatar: AvatarActor = get_parent()
@onready var _nav_agent: NavigationAgent3D = get_node("../NavAgent")

var _target: MinionActor = null
var _waypoint: Vector3 = Vector3.ZERO
var _has_waypoint: bool = false
var _repath_timer: float = 0.0
## Remaining points of a courier-delivered route, walked in order.
var _route: Array[Vector3] = []
## Unclaimed: walking home to recover until whole.
var _recovering: bool = false
var _regen_carry: float = 0.0

func _ready() -> void:
	var input: AvatarInput = get_node("../AvatarInput")
	input.ai_driver = self

func _physics_process(delta: float) -> void:
	_repath_timer = maxf(0.0, _repath_timer - delta)
	if multiplayer.is_server():
		_regenerate(delta)

func is_driving() -> bool:
	## Whenever nobody drives him directly, for his owner or the good faction.
	return multiplayer.is_server() \
		and not GameState.has_avatar() \
		and not _avatar.is_dormant \
		and _avatar.hp > 0

func is_recovering() -> bool:
	return _recovering

func get_city_centre() -> Vector3:
	## Where the good faction takes him to recover: a node in HOLY_SITE_GROUP
	## if the map has one, else the world origin (the first map's city).
	var marker := get_tree().get_first_node_in_group(HOLY_SITE_GROUP) as Node3D
	if marker:
		return marker.global_position
	return Vector3.ZERO

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

	if not GameState.has_avatar_owner():
		_drive_unclaimed(input)
		return
	if _fight(input):
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

func _drive_unclaimed(input: AvatarInput) -> void:
	## GDD §8 (Q16): weak, the good faction recovers him; at full strength he
	## goes out to hunt and remove corruption.
	var max_hp := float(_avatar.get_max_hp())
	if float(_avatar.hp) < max_hp * RECOVER_BELOW_FRACTION:
		_recovering = true
	elif _avatar.hp >= _avatar.get_max_hp():
		_recovering = false
	var home := get_city_centre()
	if _recovering:
		_target = null
		_walk_to(home, RECOVER_RADIUS * SITE_STAND_FRACTION, input)
		return
	if _fight(input):
		return
	var site := _nearest_corrupted_site()
	if site:
		_walk_to(site.global_position, site.radius * SITE_STAND_FRACTION, input)
	else:
		_walk_to(home, RECOVER_RADIUS * SITE_STAND_FRACTION, input)

func _fight(input: AvatarInput) -> bool:
	## Chase and swing at the nearest hostile. False when there is none.
	if not _avatar.can_use(AvatarActor.ACTION_ATTACK):
		_target = null
		return false
	_update_target()
	if _target == null:
		return false
	var dist := _flat_distance(_target.global_position)
	if dist <= ATTACK_RANGE:
		_face(_target.global_position)
		input.attack_input = true
	else:
		_steer_toward(_target.global_position, input)
		input.run_input = dist > RUN_DISTANCE
	return true

func _walk_to(goal: Vector3, arrive: float, input: AvatarInput) -> void:
	var dist := _flat_distance(goal)
	if dist <= arrive:
		return
	_steer_toward(goal, input)
	input.run_input = dist > RUN_DISTANCE

func _nearest_corrupted_site() -> CorruptionSite:
	## The nearest site a player holds. Towers are left alone (they never
	## change hands); usable sites only.
	var best: CorruptionSite = null
	var best_dist := INF
	for node in GameState.get_all_sites():
		var site := node as CorruptionSite
		if site == null or site.permanent or site.unusable or not site.is_held():
			continue
		var d := _flat_distance(site.global_position)
		if d < best_dist:
			best_dist = d
			best = site
	return best

func _regenerate(delta: float) -> void:
	## Unclaimed and at the city centre, he heals (host; applied in his rollback tick).
	if GameState.has_avatar_owner() or _avatar.hp <= 0 or _avatar.hp >= _avatar.get_max_hp():
		_regen_carry = 0.0
		return
	if _flat_distance(get_city_centre()) > RECOVER_RADIUS:
		return
	_regen_carry += REGEN_PER_SECOND * delta
	var whole := floori(_regen_carry)
	if whole > 0:
		_regen_carry -= whole
		_avatar.heal(whole)

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
		if _avatar.resists_striking(minion):
			continue  # he won't strike the good faction for a weak owner
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
