extends "res://tests/support/stage_test.gd"

## Melee combat: who is hostile to whom, what a landed blow does, and that hitboxes find
## hurtboxes. Blows are fed to AttackState._check_hits through a stubbed hitbox; only
## test_a_hitbox_reports_an_overlapping_hurtbox_once uses real physics overlap.

const CATALOG := preload("res://data/minion_catalog.tres")

func _attack_state(unit: MinionActor) -> Node:
	return unit.get_node(^"RewindableStateMachine/AttackState")

func _blow(attacker: MinionActor, target: Actor, multiplier := 1.0) -> void:
	## One landed blow from `attacker` on `target`'s hurtbox, as the attack window reports it.
	var hitbox: AttackHitbox = partial_double(AttackHitbox).new()
	stub(hitbox, "get_new_hits").to_return([target.get_node(^"%Hurtbox")])
	stub(hitbox, "get_damage_multiplier").to_return(multiplier)
	add_child_autofree(hitbox)
	_attack_state(attacker)._check_hits(hitbox)

# --- Every unit can fight ---

func test_every_unit_type_has_a_hitbox_and_a_hurtbox() -> void:
	for packed in CATALOG.scenes:
		if packed == null:
			continue
		var unit := packed.instantiate()
		assert_not_null(unit.get_node_or_null(^"%AttackHitbox"), "%s has an AttackHitbox" % packed.resource_path)
		assert_not_null(unit.get_node_or_null(^"%Hurtbox"), "%s has a Hurtbox" % packed.resource_path)
		unit.free()

# --- Hostility ---

func test_rival_sides_are_hostile_and_allies_are_not() -> void:
	var a := spawn(&"skeleton", 1)
	var b := spawn(&"skeleton", 2)
	var c := spawn(&"skeleton", 1)
	var knight := spawn(&"holy_knight", GameConstants.GOOD_SIDE)
	assert_true(a.is_hostile_to(b))
	assert_true(a.is_hostile_to(knight))
	assert_false(a.is_hostile_to(c))

func test_an_offer_does_not_attack_a_noble() -> void:
	var a := spawn(&"skeleton", 1)
	var noble := spawn(&"noble", GameConstants.GOOD_SIDE)
	assert_true(a.is_hostile_to(noble))
	a.parley_mode = true
	assert_false(a.is_hostile_to(noble))

func test_a_capture_group_stops_at_a_beaten_human_and_at_nobles() -> void:
	var a := spawn(&"skeleton", 1)
	var villager := spawn(&"villager", GameConstants.GOOD_SIDE)
	var noble := spawn(&"noble", GameConstants.GOOD_SIDE)
	a.capture_mode = true
	assert_true(a.is_hostile_to(villager))
	villager.hp = 1
	assert_false(a.is_hostile_to(villager))
	assert_false(a.is_hostile_to(noble))

# --- A landed blow ---

func test_a_blow_deals_the_attackers_damage() -> void:
	var a := spawn(&"skeleton", 1)
	var b := spawn(&"holy_knight", GameConstants.GOOD_SIDE)
	var hp := b.hp
	_blow(a, b)
	assert_eq(b.hp, hp - a.attack_damage)
	assert_eq(b.last_hit_by, 1)

func test_the_hitbox_profile_scales_the_blow() -> void:
	var a := spawn(&"skeleton", 1)
	var b := spawn(&"holy_knight", GameConstants.GOOD_SIDE)
	var hp := b.hp
	_blow(a, b, 2.0)
	assert_eq(b.hp, hp - a.attack_damage * 2)

func test_a_blow_never_lands_on_an_ally() -> void:
	var a := spawn(&"skeleton", 1)
	var b := spawn(&"skeleton", 1)
	var hp := b.hp
	_blow(a, b)
	assert_eq(b.hp, hp)

func test_capture_blows_stop_short_of_death() -> void:
	var a := spawn(&"skeleton", 1)
	var villager := spawn(&"villager", GameConstants.GOOD_SIDE)
	a.capture_mode = true
	a.attack_damage = villager.hp * 10
	_blow(a, villager)
	assert_eq(villager.hp, 1)

func test_a_blow_on_the_paladin_queues_damage_for_his_rollback_tick() -> void:
	var a := spawn(&"skeleton", 2)
	var avatar := (preload("res://scenes/actors/player/avatar/avatar_actor.tscn").instantiate()) as AvatarActor
	stage.add_child(avatar)
	avatar.process_mode = Node.PROCESS_MODE_DISABLED
	_blow(a, avatar)
	assert_eq(avatar.incoming_damage, a.attack_damage)
	assert_eq(avatar.last_hit_by, 2)

# --- Damage and death ---

func test_damage_lowers_hp() -> void:
	var b := spawn(&"holy_knight", GameConstants.GOOD_SIDE)
	var hp := b.hp
	b.take_damage(5)
	assert_eq(b.hp, hp - 5)

func test_lethal_damage_kills() -> void:
	var b := spawn(&"holy_knight", GameConstants.GOOD_SIDE)
	watch_signals(b)
	b.take_damage(b.hp)
	assert_eq(b.hp, 0)
	assert_signal_emitted(b, "minion_died")
	assert_false(b.can_take_damage(), "the dead take no more damage")

# --- Hit detection (real physics) ---

func test_a_hitbox_reports_an_overlapping_hurtbox_once() -> void:
	var a := spawn(&"skeleton", 1)
	var b := spawn(&"holy_knight", GameConstants.GOOD_SIDE)
	var hitbox := a.get_node(^"%AttackHitbox") as AttackHitbox
	var hurtbox := b.get_node(^"%Hurtbox") as Hurtbox
	b.global_position = hitbox.global_position - (hurtbox.global_position - b.global_position)
	hitbox.enable()
	await wait_physics_frames(2)
	assert_has(hitbox.get_new_hits(), hurtbox)
	assert_does_not_have(hitbox.get_new_hits(), hurtbox, "reported once per swing")
	hitbox.disable()
	hitbox.enable()
	await wait_physics_frames(2)
	assert_has(hitbox.get_new_hits(), hurtbox, "a new swing hits again")
