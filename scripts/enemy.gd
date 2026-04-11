class_name Enemy extends CharacterBody3D

## Simple neutral guard enemy. Host-authoritative AI.
## Idles at patrol point, aggros on Avatar proximity, chases and attacks.

enum State { IDLE, CHASE, ATTACK, DEATH, STAGGER }

const SPEED := 3.0
const AGGRO_RADIUS := 8.0
const DEAGGRO_RADIUS := 12.0
const ATTACK_RANGE := 2.0
const ATTACK_DAMAGE := 15
const ATTACK_COOLDOWN := 1.2
const MAX_HP := 60
const STAGGER_DURATION := 0.4

@export var patrol_point: Vector3 = Vector3.ZERO

var hp: int = MAX_HP
var state: State = State.IDLE
var _attack_timer: float = 0.0
var _death_timer: float = 0.0
var _stagger_timer: float = 0.0
var _sync_timer: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Client-side interpolation target
var _target_pos: Vector3
var _target_rot: float

# Animation
var _anim_player: AnimationPlayer
var _current_anim: String = ""

func _ready():
	if patrol_point == Vector3.ZERO:
		patrol_point = global_position
	_target_pos = global_position
	_target_rot = rotation.y
	# Enemy collision is on layer 3 (bit 2) so Avatar hitbox (mask 4 = bit 2) detects it
	collision_layer = 4  # layer 3
	collision_mask = 1   # collide with world
	_anim_player = get_node_or_null("Model/AnimationPlayer")

func _physics_process(delta: float):
	if not multiplayer.is_server():
		# Clients interpolate toward the host-broadcast position
		global_position = global_position.lerp(_target_pos, 10.0 * delta)
		rotation.y = lerp_angle(rotation.y, _target_rot, 10.0 * delta)
		# Play animation matching current state
		match state:
			State.IDLE: _play_anim("Idle")
			State.CHASE: _play_anim("Walk")
			State.ATTACK: _play_anim("Attack")
			State.DEATH: _play_anim("Death")
			State.STAGGER: _play_anim("Stagger")
		return

	# Host runs AI
	if not is_on_floor():
		velocity.y -= gravity * delta

	match state:
		State.IDLE:
			_process_idle(delta)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK:
			_process_attack(delta)
		State.DEATH:
			_process_death(delta)
		State.STAGGER:
			_process_stagger(delta)

	if state != State.DEATH and state != State.STAGGER:
		move_and_slide()

	# Broadcast state to clients ~10 times/sec
	_sync_timer += delta
	if _sync_timer >= 0.1:
		_sync_timer = 0.0
		_sync_state.rpc(global_position, rotation.y, state, hp)

func _process_idle(delta: float):
	_play_anim("Idle")
	velocity.x = 0
	velocity.z = 0
	# Return to patrol point if drifted
	var to_patrol := patrol_point - global_position
	to_patrol.y = 0
	if to_patrol.length() > 1.0:
		var dir := to_patrol.normalized()
		velocity.x = dir.x * SPEED * 0.5
		velocity.z = dir.z * SPEED * 0.5
		_face_direction(dir)

	var avatar := _find_avatar()
	if avatar and _distance_to(avatar) < AGGRO_RADIUS:
		state = State.CHASE

func _process_chase(delta: float):
	var avatar := _find_avatar()
	if not avatar or avatar.is_dormant:
		state = State.IDLE
		return
	var dist := _distance_to(avatar)
	if dist > DEAGGRO_RADIUS:
		state = State.IDLE
		return
	if dist < ATTACK_RANGE:
		state = State.ATTACK
		_attack_timer = 0.0
		return
	# Move toward avatar
	_play_anim("Walk")
	var dir := (avatar.global_position - global_position)
	dir.y = 0
	dir = dir.normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	_face_direction(dir)

func _process_attack(delta: float):
	_play_anim("Attack")
	_attack_timer += delta
	velocity.x = 0
	velocity.z = 0
	var avatar := _find_avatar()
	if not avatar or avatar.is_dormant:
		state = State.IDLE
		return
	_face_direction((avatar.global_position - global_position).normalized())
	if _attack_timer >= ATTACK_COOLDOWN:
		var dist := _distance_to(avatar)
		if dist < ATTACK_RANGE * 1.5:
			avatar.take_damage(ATTACK_DAMAGE)
			_attack_timer = 0.0
			_current_anim = ""  # Force attack animation to replay
		else:
			state = State.CHASE

func _process_death(delta: float):
	_play_anim("Death")
	_death_timer += delta
	velocity = Vector3.ZERO
	if _death_timer >= 2.0:
		queue_free()

func _process_stagger(delta: float):
	_play_anim("Stagger")
	_stagger_timer += delta
	velocity.x = 0
	velocity.z = 0
	if _stagger_timer >= STAGGER_DURATION:
		state = State.CHASE

func take_damage(amount: int):
	if state == State.DEATH or state == State.STAGGER:
		return
	hp = max(0, hp - amount)
	if hp <= 0:
		state = State.DEATH
		_death_timer = 0.0
		# Disable collision so Avatar can walk through
		collision_layer = 0
		collision_mask = 0
	else:
		state = State.STAGGER
		_stagger_timer = 0.0

func _find_avatar() -> Avatar:
	var avatar_node = get_tree().current_scene.get_node_or_null("World/Avatar")
	if avatar_node and avatar_node is Avatar and not avatar_node.is_dormant:
		return avatar_node
	return null

func _distance_to(target: Node3D) -> float:
	var diff := global_position - target.global_position
	diff.y = 0
	return diff.length()

func _play_anim(anim_name: String):
	if _anim_player and _current_anim != anim_name:
		_current_anim = anim_name
		_anim_player.play("large-male/" + anim_name)

func _face_direction(dir: Vector3):
	if dir.length() < 0.01:
		return
	# Model faces +Z, but look_at points -Z at target, so look away from dir
	var target := global_position - dir
	look_at(target, Vector3.UP)

@rpc("authority", "call_remote", "unreliable")
func _sync_state(pos: Vector3, rot_y: float, new_state: int, new_hp: int):
	_target_pos = pos
	_target_rot = rot_y
	state = new_state as State
	hp = new_hp
	if state == State.DEATH and collision_layer != 0:
		collision_layer = 0
		collision_mask = 0
