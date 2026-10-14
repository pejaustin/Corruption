extends GutTest

## Corruption sites (GDD §7): the contest rules, driven by setting the strength present
## and ticking the contest directly. Who counts as present is tested once, in
## test_site_presence; nothing here walks units in.

const SITE := preload("res://scenes/sites/corruption_site.tscn")
const P1 := 1
const P2 := 2

var site: CorruptionSite

func before_each() -> void:
	site = SITE.instantiate() as CorruptionSite
	site.site_type = _type(SiteCapability.NONE)
	add_child_autofree(site)
	site.set_physics_process(false)

func _type(capability: StringName, kind := SiteType.PoiKind.SITE) -> SiteType:
	var t := SiteType.new()
	t.capability = capability
	t.poi_kind = kind
	t.strength_threshold = 3.0
	t.corrupt_seconds = 10.0
	t.slip_seconds = 20.0
	t.purify_seconds = 5.0
	return t

func _tick(strengths: Dictionary, seconds: float) -> void:
	site.present_strength.clear()
	for side in strengths:
		site.present_strength[side] = strengths[side]
	site._tick_contest(seconds)

func test_under_the_threshold_nothing_happens() -> void:
	_tick({P1: 2.9}, 5.0)
	assert_eq(site.progress, 0.0)

func test_at_the_threshold_progress_builds() -> void:
	_tick({P1: 3.0}, 5.0)
	assert_almost_eq(site.progress, 0.5, 0.001)
	assert_eq(site.progress_peer_id, P1)

func test_more_strength_goes_proportionally_faster() -> void:
	_tick({P1: 6.0}, 2.5)
	assert_almost_eq(site.progress, 0.5, 0.001)

func test_full_progress_takes_the_site() -> void:
	watch_signals(site)
	_tick({P1: 3.0}, 10.0)
	assert_eq(site.holder_peer_id, P1)
	assert_signal_emitted_with_parameters(site, "holder_changed", [-1, P1])

func test_two_sides_present_freeze_it() -> void:
	_tick({P1: 3.0}, 5.0)
	_tick({P1: 3.0, P2: 3.0}, 5.0)
	assert_almost_eq(site.progress, 0.5, 0.001)

func test_a_rival_undoes_corruption_before_starting_their_own() -> void:
	_tick({P1: 3.0}, 5.0)
	_tick({P2: 3.0}, 2.0)
	assert_almost_eq(site.progress, 0.3, 0.001)
	assert_eq(site.progress_peer_id, P1)

func test_a_rival_corrupts_a_held_site_back_to_neutral_then_to_themselves() -> void:
	_tick({P1: 3.0}, 10.0)
	_tick({P2: 3.0}, 10.0)
	assert_eq(site.holder_peer_id, -1)
	_tick({P2: 3.0}, 10.0)
	assert_eq(site.holder_peer_id, P2)

func test_the_holder_present_keeps_it() -> void:
	_tick({P1: 3.0}, 10.0)
	_tick({P1: 1.0}, 100.0)
	assert_eq(site.holder_peer_id, P1)
	assert_eq(site.progress, 1.0)

func test_an_unguarded_site_slips_back_to_neutral() -> void:
	_tick({P1: 3.0}, 10.0)
	_tick({}, 10.0)
	assert_eq(site.holder_peer_id, P1, "half way")
	_tick({}, 10.0)
	assert_eq(site.holder_peer_id, -1)

func test_the_good_faction_purifies_unopposed() -> void:
	_tick({P1: 3.0}, 10.0)
	_tick({GameConstants.GOOD_SIDE: 1.0}, 5.0)
	assert_eq(site.holder_peer_id, -1)

func test_an_unusable_site_is_released_and_never_corrupts() -> void:
	_tick({P1: 3.0}, 10.0)
	site.make_unusable()
	assert_eq(site.holder_peer_id, -1)
	_tick({P1: 30.0}, 100.0)
	assert_eq(site.progress, 0.0)

func test_holding_a_site_grants_its_capability() -> void:
	site.site_type = _type(SiteCapability.DOMINATE_THRALLS)
	assert_false(GameState.has_capability(P1, SiteCapability.DOMINATE_THRALLS))
	_tick({P1: 3.0}, 10.0)
	assert_true(GameState.has_capability(P1, SiteCapability.DOMINATE_THRALLS))
	_tick({}, 20.0)
	assert_false(GameState.has_capability(P1, SiteCapability.DOMINATE_THRALLS), "lost with the site")

func test_a_permanent_site_never_changes_hands() -> void:
	site.set_permanent_holder(P1)
	site.present_strength = {P2: 10.0}
	site._tick_permanent()
	assert_eq(site.holder_peer_id, P1)
	assert_true(site.sacked, "hostiles and no defenders sack it")
	site.present_strength = {P2: 10.0, P1: 1.0}
	site._tick_permanent()
	assert_false(site.sacked, "a defender lifts the sack")
