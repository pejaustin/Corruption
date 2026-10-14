class_name BossState extends ActorState

## Base for a boss form's states: walking and facing from the driver's input and
## camera, and picking an attack. No run, jump or roll.

var boss: BossActor:
	get: return actor as BossActor

func get_movement_input() -> Vector2:
	return boss.boss_input.input_dir

func move_horizontal() -> void:
	var input_dir := get_movement_input()
	var direction := (boss.boss_camera.camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var target := direction * BossActor.WALK_SPEED
	if target:
		actor.velocity.x = target.x
		actor.velocity.z = target.z
	else:
		actor.velocity.x = move_toward(actor.velocity.x, 0, BossActor.WALK_SPEED)
		actor.velocity.z = move_toward(actor.velocity.z, 0, BossActor.WALK_SPEED)

func face_camera(delta: float) -> void:
	## Turn slowly toward where the camera looks (his front is the model's +Z).
	var q_from := actor._model.global_transform.basis.get_rotation_quaternion()
	var q_to := Transform3D().looking_at(boss.boss_camera.camera_basis.z, Vector3.UP).basis.get_rotation_quaternion()
	actor._model.global_transform.basis = Basis(q_from.slerp(q_to, clampf(delta * BossActor.TURN_SPEED, 0.0, 1.0)))

func try_attack() -> bool:
	## Throw the attack the driver asked for, if any.
	var pick := boss.boss_input.attack_pick
	if pick < 0 or pick >= boss.attacks.size():
		return false
	boss.attack_index = pick
	return actor.try_transition(&"BossAttackState")
