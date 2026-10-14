extends "res://tests/support/stage_test.gd"

## The Paladin (GDD §8): ownership, control tiers, resistance, zero HP, and his hold
## (fading, contest takeover, overpower). Strength near him is set directly; who counts
## is tested once in test_a_takeover_counts_nearby_troops.

const AVATAR := preload("res://scenes/actors/player/avatar/avatar_actor.tscn")
const SITE := preload("res://scenes/sites/corruption_site.tscn")

var avatar: AvatarActor
var hold: PaladinHold

func before_each() -> void:
	await super()
	avatar = AVATAR.instantiate() as AvatarActor
	stage.add_child(avatar)
	avatar.process_mode = Node.PROCESS_MODE_DISABLED
	hold = avatar.hold

func _temples(peer: int, n: int) -> void:
	## `peer` holds n AVATAR_CONTROL sites (temples without their dungeon), far from the Paladin.
	var control := SiteType.new()
	control.capability = SiteCapability.AVATAR_CONTROL
	for i in n:
		var site := SITE.instantiate() as CorruptionSite
		site.site_type = control
		site.position = Vector3(1000 + i * 50, 0, 0)
		stage.add_child(site)
		site.set_physics_process(false)
		site._change_holder(peer)

# --- Ownership and control tiers ---

func test_unowned_he_fights_for_the_good_faction_with_nothing_locked() -> void:
	assert_eq(avatar.get_allegiance(), GameConstants.GOOD_SIDE)
	assert_eq(avatar.get_control_level(), AvatarActor.CONTROL_LEVEL_MAX)

func test_owned_he_fights_for_his_owner() -> void:
	GameState.set_avatar_owner(1)
	assert_eq(avatar.get_allegiance(), 1)

func test_control_level_is_one_plus_the_owners_control_sites() -> void:
	GameState.set_avatar_owner(1)
	assert_eq(avatar.get_control_level(), 1)
	_temples(1, 2)
	assert_eq(avatar.get_control_level(), 3)

func test_control_level_is_capped() -> void:
	GameState.set_avatar_owner(1)
	_temples(1, AvatarActor.CONTROL_LEVEL_MAX + 2)
	assert_eq(avatar.get_control_level(), AvatarActor.CONTROL_LEVEL_MAX)

func test_each_action_unlocks_at_its_level() -> void:
	GameState.set_avatar_owner(1)
	_temples(1, AvatarActor.CONTROL_LEVEL_MAX - 1)
	var sites := GameState.get_all_sites()
	for held in AvatarActor.CONTROL_LEVEL_MAX:
		for i in sites.size():
			sites[i].holder_peer_id = 1 if i < held else -1
		for action in AvatarActor.CONTROL_UNLOCKS:
			var allowed: bool = 1 + held >= AvatarActor.CONTROL_UNLOCKS[action]
			assert_eq(avatar.can_use(action), allowed, "%s at level %d" % [action, 1 + held])

# --- Resistance ---

func test_below_the_resist_level_he_will_not_strike_the_good_faction() -> void:
	var knight := spawn(&"holy_knight", GameConstants.GOOD_SIDE)
	GameState.set_avatar_owner(1)
	_temples(1, AvatarActor.RESIST_GOOD_BELOW_LEVEL - 2)
	var hp := knight.hp
	assert_false(avatar.strike(knight, 10))
	assert_eq(knight.hp, hp)

func test_at_the_resist_level_he_strikes_the_good_faction() -> void:
	var knight := spawn(&"holy_knight", GameConstants.GOOD_SIDE)
	GameState.set_avatar_owner(1)
	_temples(1, AvatarActor.RESIST_GOOD_BELOW_LEVEL - 1)
	var hp := knight.hp
	assert_true(avatar.strike(knight, 10))
	assert_eq(knight.hp, hp - 10)

func test_he_never_resists_striking_a_rivals_unit() -> void:
	var skeleton := spawn(&"skeleton", 2)
	GameState.set_avatar_owner(1)
	assert_false(avatar.resists_striking(skeleton))

func test_unowned_he_never_resists() -> void:
	var knight := spawn(&"holy_knight", GameConstants.GOOD_SIDE)
	assert_false(avatar.resists_striking(knight))

# --- Zero HP ---

func test_defeating_a_neutral_paladin_gives_you_control_at_full_hp() -> void:
	avatar.last_hit_by = 2
	avatar.take_damage(avatar.hp)
	assert_eq(GameState.avatar_owner_peer_id, 2)
	assert_false(hold.is_contested())
	assert_eq(avatar._pending_hp, avatar.get_max_hp())

func test_zero_hp_while_held_wipes_his_owner_and_opens_a_contest() -> void:
	GameState.set_avatar_owner(1)
	avatar.take_damage(avatar.hp)
	assert_false(GameState.has_avatar_owner())
	assert_false(GameState.has_avatar())
	assert_true(hold.is_contested())

func test_after_zero_hp_he_gets_up_weak() -> void:
	GameState.set_avatar_owner(1)
	avatar.take_damage(avatar.hp)
	avatar._recover_in_place()
	assert_eq(avatar._pending_hp, maxi(1, int(avatar.get_max_hp() * AvatarActor.RECOVER_HP_FRACTION)))

func test_a_new_owner_drops_whoever_was_driving() -> void:
	GameState.set_avatar_owner(1)
	GameState.request_possess_avatar()
	assert_true(GameState.is_avatar(1))
	GameState.set_avatar_owner(2)
	assert_false(GameState.has_avatar())

func test_the_debug_hand_over_moves_him_to_your_gate() -> void:
	var paladin := add_avatar()
	var gate := Node3D.new()
	stage.add_child(gate)
	gate.global_position = Vector3(300, 0, 40)
	mm.bind_peer_courier_spawn(1, gate)
	DebugManager.give_paladin_to_self()
	assert_true(GameState.is_avatar_owner(1))
	assert_eq(paladin.global_position, gate.global_position + Vector3.UP)

# --- Hold ---

func test_away_from_corruption_the_hold_fades() -> void:
	GameState.set_avatar_owner(1)
	hold._tick_hold(PaladinHold.HOLD_SECONDS / 2.0)
	assert_almost_eq(hold.hold, 0.5, 0.001)

func test_an_empty_hold_loses_him_to_the_good_faction() -> void:
	GameState.set_avatar_owner(1)
	hold._tick_hold(PaladinHold.HOLD_SECONDS)
	assert_false(GameState.has_avatar_owner())

func test_inside_a_held_site_the_hold_stays_full() -> void:
	GameState.set_avatar_owner(1)
	var site := SITE.instantiate() as CorruptionSite
	stage.add_child(site)
	site.set_physics_process(false)
	site._change_holder(1)
	hold.hold = 0.3
	hold._tick_hold(10.0)
	assert_eq(hold.hold, 1.0)

func test_a_new_owner_starts_with_a_full_hold() -> void:
	GameState.set_avatar_owner(1)
	hold.hold = 0.2
	GameState.set_avatar_owner(2)
	assert_eq(hold.hold, 1.0)

# --- Contest takeover ---

func _contest(strengths: Dictionary, seconds: float) -> void:
	hold.present_strength.clear()
	for side in strengths:
		hold.present_strength[side] = strengths[side]
	hold._advance_takeover(seconds)

func test_no_contest_no_takeover() -> void:
	_contest({1: 10.0}, 5.0)
	assert_eq(hold.get_takeover(1), 0.0)

func test_troops_meeting_the_threshold_build_progress() -> void:
	hold.open_contest()
	_contest({1: PaladinHold.TAKEOVER_THRESHOLD}, PaladinHold.TAKEOVER_SECONDS / 2.0)
	assert_almost_eq(hold.get_takeover(1), 0.5, 0.001)

func test_under_the_threshold_nothing_builds() -> void:
	hold.open_contest()
	_contest({1: PaladinHold.TAKEOVER_THRESHOLD - 0.1}, 5.0)
	assert_eq(hold.get_takeover(1), 0.0)

func test_a_finished_takeover_wins_him() -> void:
	hold.open_contest()
	_contest({1: PaladinHold.TAKEOVER_THRESHOLD}, PaladinHold.TAKEOVER_SECONDS)
	assert_eq(GameState.avatar_owner_peer_id, 1)
	assert_false(hold.is_contested())

func test_his_company_freezes_the_takeover() -> void:
	hold.open_contest()
	_contest({1: 3.0, GameConstants.GOOD_SIDE: 1.0}, 5.0)
	assert_eq(hold.get_takeover(1), 0.0)

func test_the_strongest_side_progresses() -> void:
	hold.open_contest()
	_contest({1: 6.0, 2: 3.0}, 1.0)
	assert_gt(hold.get_takeover(1), 0.0)
	assert_eq(hold.get_takeover(2), 0.0)

func test_a_tie_freezes_everyone() -> void:
	hold.open_contest()
	_contest({1: 3.0, 2: 3.0}, 5.0)
	assert_eq(hold.get_takeover(1), 0.0)
	assert_eq(hold.get_takeover(2), 0.0)

func test_a_stalled_takeover_fades() -> void:
	hold.open_contest()
	_contest({1: 3.0}, PaladinHold.TAKEOVER_SECONDS / 2.0)
	_contest({}, PaladinHold.TAKEOVER_FADE_SECONDS / 4.0)
	assert_almost_eq(hold.get_takeover(1), 0.25, 0.001)

func test_a_takeover_counts_nearby_troops() -> void:
	var near := spawn(&"skeleton", 1, Vector3(3, 0, 0))
	spawn(&"skeleton", 2, Vector3(PaladinHold.TAKEOVER_RADIUS + 1.0, 0, 0))
	var courier := spawn(&"skeleton", 1, Vector3(1, 0, 0))
	courier.minion_trait = &"courier"
	hold._measure_presence()
	assert_eq(hold.present_strength, {1: near.strength} as Dictionary[int, float])

# --- Overpower ---

func test_overpowering_needs_more_control_sites_than_his_owner() -> void:
	GameState.set_avatar_owner(2)
	_temples(2, 1)
	_temples(1, 1)
	assert_false(hold.can_overpower(1))
	_temples(1, 1)
	assert_true(hold.can_overpower(1))
	assert_false(hold.can_overpower(2), "never his own owner")

func test_overpower_starts_only_while_looking_through_a_palantir() -> void:
	_temples(1, 1)
	hold.request_overpower()
	assert_false(hold.overpower.has(1))
	GameState.request_set_watching(true)
	hold.request_overpower()
	assert_true(hold.overpower.has(1))

func test_a_finished_overpower_takes_him() -> void:
	_temples(1, 1)
	GameState.request_set_watching(true)
	hold.request_overpower()
	hold._tick_overpower(PaladinHold.OVERPOWER_SECONDS)
	assert_eq(GameState.avatar_owner_peer_id, 1)

func test_looking_away_stops_the_overpower() -> void:
	_temples(1, 1)
	GameState.request_set_watching(true)
	hold.request_overpower()
	GameState.request_set_watching(false)
	hold._tick_overpower(1.0)
	assert_false(hold.overpower.has(1))

# --- AI ---

func test_unowned_and_weak_he_goes_to_recover() -> void:
	avatar.hp = int(avatar.get_max_hp() * AvatarAI.RECOVER_BELOW_FRACTION) - 1
	avatar.avatar_ai.drive(avatar.avatar_input)
	assert_true(avatar.avatar_ai.is_recovering())

func test_he_stays_recovering_until_full() -> void:
	avatar.hp = 1
	avatar.avatar_ai.drive(avatar.avatar_input)
	avatar.hp = avatar.get_max_hp() - 1
	avatar.avatar_ai.drive(avatar.avatar_input)
	assert_true(avatar.avatar_ai.is_recovering())
	avatar.hp = avatar.get_max_hp()
	avatar.avatar_ai.drive(avatar.avatar_input)
	assert_false(avatar.avatar_ai.is_recovering())
