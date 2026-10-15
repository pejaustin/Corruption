extends "res://tests/support/stage_test.gd"

## A boss form (BossActor, GDD §8 C9): its attack phases, who its blows hit, and who plays it. Driven by
## calling its attack state's tick directly; no fights are simulated.

const BOSS := preload("res://scenes/actors/boss/boss_actor.tscn")
const FRAME: float = 0.1

var boss: BossActor
var avatar: AvatarActor

func before_each() -> void:
	await super()
	avatar = add_avatar()
	GameState.set_avatar_owner(1)  # the Paladin fights for peer 1
	boss = _add_boss(2)

func _add_boss(peer: int) -> BossActor:
	var b := BOSS.instantiate() as BossActor
	b.setup(peer, 300, 20)
	stage.add_child(b)
	return b

func _attack_state() -> BossAttackState:
	return boss._state_machine.get_node(^"BossAttackState") as BossAttackState

func _start_attack(index: int) -> void:
	boss.attack_index = index
	_attack_state().enter(null, 0)

func _tick(seconds: float) -> void:
	_attack_state().tick(seconds, 0, true)

func test_an_attack_goes_windup_active_recovery() -> void:
	var attack := boss.attacks[0]
	_start_attack(0)
	assert_eq(boss.attack_phase(), BossAttack.Phase.WINDUP)
	_tick(attack.windup_seconds * 0.5)
	assert_eq(boss.attack_phase(), BossAttack.Phase.WINDUP)
	_tick(attack.windup_seconds * 0.5 + attack.active_seconds * 0.5)
	assert_eq(boss.attack_phase(), BossAttack.Phase.ACTIVE)
	_tick(attack.active_seconds * 0.5 + attack.recovery_seconds * 0.5)
	assert_eq(boss.attack_phase(), BossAttack.Phase.RECOVERY)
	_tick(attack.recovery_seconds)
	assert_eq(boss.attack_phase(), BossAttack.Phase.DONE)
	assert_eq(boss._state_machine.state, &"IdleState", "the blow over, he is free again")

func test_the_blow_hurts_only_in_the_active_phase() -> void:
	var attack := boss.attacks[0]
	avatar.global_position = Vector3(0, 0, attack.reach * 0.5)  # in front of him (the model faces +Z)
	_start_attack(0)
	_tick(attack.windup_seconds * 0.9)
	assert_eq(avatar.incoming_damage, 0, "nothing during the windup")
	_tick(attack.windup_seconds * 0.2)  # now inside the active window
	var expected := int(boss.get_attack_damage() * attack.damage_multiplier)
	assert_eq(avatar.incoming_damage, expected, "the blow lands when active")
	_tick(attack.active_seconds * 0.2)
	assert_eq(avatar.incoming_damage, expected, "and only once")
	_tick(attack.active_seconds + attack.recovery_seconds * 0.5)
	assert_eq(avatar.incoming_damage, expected, "nothing in the recovery")

func test_a_target_outside_the_box_is_missed() -> void:
	var attack := boss.attacks[0]
	avatar.global_position = Vector3(0, 0, -attack.reach)  # behind him
	_start_attack(0)
	_tick(attack.windup_seconds + attack.active_seconds * 0.5)
	assert_eq(boss.attack_phase(), BossAttack.Phase.ACTIVE)
	assert_eq(avatar.incoming_damage, 0)

func test_his_own_side_is_never_hurt() -> void:
	var attack := boss.attacks[0]
	GameState.set_avatar_owner(2)  # the Paladin is the boss's own player's now
	avatar.global_position = Vector3(0, 0, attack.reach * 0.5)
	_start_attack(0)
	_tick(attack.windup_seconds + attack.active_seconds * 0.5)
	assert_eq(avatar.incoming_damage, 0)

func test_the_attack_shows_a_tell_while_winding_up() -> void:
	var attack := boss.attacks[0]
	boss._update_tell()
	assert_false(boss._tell_label.visible, "no tell while he stands idle")
	boss._state_machine.state = &"BossAttackState"
	boss.attack_index = 0
	boss.attack_time = attack.windup_seconds * 0.5
	boss._update_tell()
	assert_true(boss._tell_label.visible, "the attack's name floats up")
	assert_true(boss._tell_area.visible, "and the ground where it will land is marked")
	assert_eq(boss._tell_label.text, attack.display_name)
	boss.attack_time = attack.total_seconds() - 0.01
	boss._update_tell()
	assert_false(boss._tell_label.visible, "gone in the recovery")

func test_the_picked_key_throws_that_attack() -> void:
	var idle := boss._state_machine.get_node(^"IdleState") as BossState
	boss.boss_input.attack_pick = 1
	assert_true(idle.try_attack())
	assert_eq(boss.attack_index, 1)
	assert_eq(boss._state_machine.state, &"BossAttackState")

func test_each_attack_has_its_own_key() -> void:
	var keys: Array[StringName] = []
	for attack in boss.attacks:
		assert_false(attack.input_action in keys, "no two attacks share a key")
		keys.push_back(attack.input_action)
	assert_eq(boss.boss_input.attack_actions, keys)

func test_blows_to_a_boss_are_queued_for_its_rollback_tick() -> void:
	boss.take_damage(30)
	assert_eq(boss.hp, 300, "not applied outside the tick, netfox would restore it")
	boss._rollback_tick(0.0, 0, true)
	assert_eq(boss.hp, 270)

func test_a_dead_boss_signals_it() -> void:
	watch_signals(boss)
	boss.take_damage(boss.hp)
	boss._rollback_tick(0.0, 0, true)
	assert_signal_emitted(boss, "died")

func test_a_player_boss_is_driven_by_its_peer_not_the_ai() -> void:
	assert_eq(boss.controlling_peer_id, 2)
	assert_eq(boss.boss_input.get_multiplayer_authority(), 2)
	assert_false(boss.boss_ai.is_driving())

func test_a_cpu_boss_is_driven_by_the_ai() -> void:
	var cpu := _add_boss(DebugManager.DUMMY_BASE_ID)
	assert_eq(cpu.controlling_peer_id, -1)
	assert_eq(cpu.boss_input.get_multiplayer_authority(), 1, "the host is its input authority")
	assert_true(cpu.boss_ai.is_driving())

func test_the_ai_walks_to_the_paladin_then_throws_an_attack() -> void:
	var cpu := _add_boss(DebugManager.DUMMY_BASE_ID)
	avatar.global_position = Vector3(30, 0, 0)
	cpu.boss_ai.drive(cpu.boss_input)
	assert_eq(cpu.boss_input.input_dir, Vector2(0, -1), "pushes forward, facing him")
	assert_eq(cpu.boss_input.attack_pick, -1, "too far to swing")
	avatar.global_position = Vector3(2, 0, 0)
	cpu.boss_ai.drive(cpu.boss_input)
	assert_gte(cpu.boss_input.attack_pick, 0, "in reach: swings")
	assert_eq(cpu.boss_input.input_dir, Vector2.ZERO, "standing still to do it")

func test_releasing_a_player_boss_hands_it_to_the_ai() -> void:
	boss.release_control()
	assert_eq(boss.controlling_peer_id, -1)
	assert_eq(boss.boss_input.get_multiplayer_authority(), 1)
	assert_true(boss.boss_ai.is_driving())

func test_each_attack_and_state_has_a_clip_the_model_can_play() -> void:
	var player: AnimationPlayer = boss._animation_player
	assert_not_null(player, "the model carries an AnimationPlayer")
	for attack in boss.attacks:
		assert_true(player.has_animation(attack.animation), "%s: no clip '%s'" % [attack.display_name, attack.animation])
	for state in boss._state_machine.get_children():
		var actor_state := state as ActorState
		if actor_state and actor_state.animation_name != "":
			assert_true(player.has_animation(actor_state.animation_name), "%s: no clip '%s'" % [state.name, actor_state.animation_name])

func test_an_attack_clip_is_stretched_over_the_whole_attack_within_the_speed_limits() -> void:
	var attack := boss.attacks[0]
	_start_attack(0)
	boss._play_attack_animation()
	assert_eq(boss._animation_player.current_animation, String(attack.animation))
	var length := boss._animation_player.get_animation(attack.animation).length
	var fit := length / attack.total_seconds()
	var expected := clampf(fit, BossActor.MIN_ATTACK_ANIMATION_SPEED, BossActor.MAX_ATTACK_ANIMATION_SPEED)
	assert_almost_eq(boss._animation_player.get_playing_speed(), expected, 0.01)

func test_the_windup_glow_has_a_mesh_and_an_overlay_to_raise() -> void:
	assert_not_null(boss.body_mesh, "Blackhorn's mesh is found by its path")
	assert_true(boss.body_mesh.material_overlay is StandardMaterial3D, "the glow overlay is set on it")

func test_the_paladins_driver_sees_the_boss_bar_while_the_boss_is_near() -> void:
	var bar := boss.get_node(^"BossBar") as BossBar
	assert_false(bar.should_show(), "nobody drives the Paladin yet")
	GameState._set_avatar(1)  # this peer (1) drives him; the boss is peer 2's
	assert_true(bar.should_show())
	boss.global_position = avatar.global_position + Vector3(0, 0, BossBar.SHOW_RANGE + 5.0)
	assert_false(bar.should_show(), "too far away")
	boss.global_position = avatar.global_position
	boss.hp = 0
	assert_false(bar.should_show(), "a dead boss shows no bar")
