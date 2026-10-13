extends "res://tests/support/stage_test.gd"

## Who counts toward a corruption site's strength (GDD §7): each fighting unit inside the
## radius counts its type's strength, by allegiance. The contest rules that use these
## numbers are test_corruption_site's.

const SITE := preload("res://scenes/sites/corruption_site.tscn")

var site: CorruptionSite

func before_each() -> void:
	await super()
	site = SITE.instantiate() as CorruptionSite
	site.radius = 10.0
	stage.add_child(site)
	site.set_physics_process(false)

func test_a_unit_inside_counts_its_strength_for_its_owner() -> void:
	var unit := spawn(&"skeleton", 1, Vector3(3, 0, 0))
	site._measure_presence()
	assert_eq(site.present_strength.get(1, 0.0), unit.strength)

func test_units_add_up_by_side() -> void:
	var a := spawn(&"skeleton", 1, Vector3(1, 0, 0))
	var b := spawn(&"skeleton", 1, Vector3(-1, 0, 0))
	var knight := spawn(&"holy_knight", GameConstants.GOOD_SIDE, Vector3(0, 0, 2))
	site._measure_presence()
	assert_eq(site.present_strength.get(1, 0.0), a.strength + b.strength)
	assert_eq(site.present_strength.get(GameConstants.GOOD_SIDE, 0.0), knight.strength)

func test_a_unit_outside_the_radius_does_not_count() -> void:
	spawn(&"skeleton", 1, Vector3(10.5, 0, 0))
	site._measure_presence()
	assert_false(site.present_strength.has(1))

func test_height_does_not_matter() -> void:
	spawn(&"skeleton", 1, Vector3(3, 40, 0))
	site._measure_presence()
	assert_true(site.present_strength.has(1))

func test_non_combat_units_do_not_count() -> void:
	for t in CorruptionSite.NON_COMBAT_TRAITS:
		var unit := spawn(&"skeleton", 1, Vector3(1, 0, 0))
		unit.minion_trait = t
	site._measure_presence()
	assert_false(site.present_strength.has(1))

func test_a_dead_unit_does_not_count() -> void:
	var unit := spawn(&"skeleton", 1, Vector3(1, 0, 0))
	unit.hp = 0
	site._measure_presence()
	assert_false(site.present_strength.has(1))
