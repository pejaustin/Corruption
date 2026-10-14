extends "res://tests/support/stage_test.gd"

## The Paladin's light string and strong attack (right mouse, Austin 2026-10-14): which input starts
## which attack and when a swing chains into the next. States are ticked directly; no fight is simulated.

var avatar: AvatarActor

func before_each() -> void:
	await super()
	avatar = add_avatar()
	# Still idle, but kept in the physics space: an attack's tick moves his body.
	avatar.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	avatar.process_mode = Node.PROCESS_MODE_INHERIT
	avatar.process_mode = Node.PROCESS_MODE_DISABLED

func _state(state_name: StringName) -> PlayerState:
	return avatar._state_machine.get_node(NodePath(String(state_name))) as PlayerState

func _swing(state_name: StringName, progress: float) -> void:
	## Into `state_name` with its clip `progress` of the way through, inputs released.
	avatar._state_machine.transition(state_name)
	var clip := _state(state_name).animation_name
	avatar._animation_player.play(clip)
	avatar._animation_player.seek(avatar._animation_player.current_animation_length * progress, true)
	avatar.avatar_input.attack_input = false
	avatar.avatar_input.heavy_input = false

func _tick(state_name: StringName) -> void:
	_state(state_name).tick(1.0 / 30.0, 0, true)

func test_right_mouse_throws_the_strong_attack_and_left_the_light() -> void:
	avatar.avatar_input.heavy_input = true
	assert_true(_state(&"IdleState").try_attack())
	assert_eq(avatar._state_machine.state, &"HeavyAttackState")
	avatar._state_machine.transition(&"IdleState")
	avatar.avatar_input.heavy_input = false
	avatar.avatar_input.attack_input = true
	assert_true(_state(&"IdleState").try_attack())
	assert_eq(avatar._state_machine.state, &"AttackState")

func test_a_light_swing_chains_into_the_next_late_in_the_swing() -> void:
	_swing(&"AttackState", 0.3)
	avatar.avatar_input.attack_input = true
	_tick(&"AttackState")
	assert_eq(avatar._state_machine.state, &"AttackState", "too early: no chain yet")
	_swing(&"AttackState", 0.7)
	avatar.avatar_input.attack_input = true
	_tick(&"AttackState")
	assert_eq(avatar._state_machine.state, &"LightAttack2State")

func test_the_light_string_is_three_swings_long() -> void:
	_swing(&"LightAttack2State", 0.7)
	avatar.avatar_input.attack_input = true
	_tick(&"LightAttack2State")
	assert_eq(avatar._state_machine.state, &"LightAttack3State")
	_swing(&"LightAttack3State", 0.7)
	avatar.avatar_input.attack_input = true
	_tick(&"LightAttack3State")
	assert_eq(avatar._state_machine.state, &"LightAttack3State", "the last swing chains no further light")

func test_a_strong_input_mid_string_switches_to_the_strong_attack() -> void:
	_swing(&"LightAttack2State", 0.7)
	avatar.avatar_input.heavy_input = true
	_tick(&"LightAttack2State")
	assert_eq(avatar._state_machine.state, &"HeavyAttackState")

func test_the_strong_attack_hits_harder() -> void:
	var light: float = _state(&"AttackState").get(&"damage_multiplier")
	var heavy: float = _state(&"HeavyAttackState").get(&"damage_multiplier")
	assert_gt(heavy, light)

func test_each_attack_has_a_clip_the_model_plays() -> void:
	for state_name: StringName in [&"AttackState", &"LightAttack2State", &"LightAttack3State", &"HeavyAttackState"]:
		var clip := _state(state_name).animation_name
		assert_true(avatar._animation_player.has_animation(clip), "%s: no clip '%s'" % [state_name, clip])
