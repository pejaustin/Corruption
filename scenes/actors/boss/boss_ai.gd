class_name BossAI extends Node

## Host-side driver for a boss form nobody plays: a CPU seat (DebugManager dummy)
## or a peer who left. Like AvatarAI it writes the same inputs a player would,
## so the rollback loop consumes them as normal: it points the camera mount at
## the Paladin and pushes forward, and throws a random attack once he is in
## reach.

## PLACEHOLDER: tuning — seconds it waits between blows, "thinking".
const THINK_SECONDS: float = 0.8
## Stops walking this close (metres) so it does not shove him.
const STOP_DISTANCE: float = 2.0

@onready var _boss: BossActor = get_parent() as BossActor

var _think_left: float = 0.0
var _target: Actor = null

func _ready() -> void:
	(get_node("../BossInput") as BossInput).boss_ai = self

func _physics_process(delta: float) -> void:
	_think_left = maxf(0.0, _think_left - delta)

func is_driving() -> bool:
	## Whenever nobody plays him (host only), while he lives.
	return multiplayer.is_server() and _boss.controlling_peer_id <= 0 and _boss.hp > 0

func drive(input: BossInput) -> void:
	## Called by BossInput._gather on the host while is_driving().
	input.input_dir = Vector2.ZERO
	input.attack_pick = -1
	var target := _find_target()
	if target == null:
		return
	var flat := target.global_position - _boss.global_position
	flat.y = 0.0
	_face(flat)
	var attack_index := _pick_attack(flat.length())
	if attack_index >= 0 and _think_left <= 0.0:
		input.attack_pick = attack_index
		_think_left = THINK_SECONDS
	elif flat.length() > STOP_DISTANCE:
		input.input_dir = Vector2(0, -1)

func _pick_attack(distance: float) -> int:
	## A random attack that reaches him from here, or -1.
	var reaching: Array[int] = []
	for i in _boss.attacks.size():
		if distance <= _boss.attacks[i].reach + BossActor.TARGET_RADIUS:
			reaching.push_back(i)
	if reaching.is_empty():
		return -1
	return reaching[randi() % reaching.size()]

func _find_target() -> Actor:
	## The Paladin, while he lives; else the nearest hostile actor.
	if _target and is_instance_valid(_target) and _target.hp > 0:
		return _target
	_target = get_tree().current_scene.get_node_or_null("World/Avatar") as Actor
	if _target and _boss.is_hostile_to(_target) and _target.hp > 0:
		return _target
	_target = null
	var best := INF
	for node in get_tree().get_nodes_in_group(&"actors"):
		var other := node as Actor
		if other == null or not _boss.is_hostile_to(other) or not other.can_take_damage():
			continue
		var d := _boss.global_position.distance_to(other.global_position)
		if d < best:
			best = d
			_target = other
	return _target

func _face(flat_direction: Vector3) -> void:
	## Point the camera mount at the goal; "push forward" then walks that way.
	if flat_direction.length() < 0.05:
		return
	var mount: Node3D = _boss.boss_camera.camera_mount
	mount.global_basis = Basis.looking_at(flat_direction.normalized(), Vector3.UP)
	# The camera node gathered camera_basis earlier this tick, so write it directly.
	_boss.boss_camera.camera_basis = mount.global_basis
