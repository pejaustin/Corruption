extends "res://tests/support/stage_test.gd"

## A player's tower: the trickle of units that lets a beaten player rebuild (#577), and its
## restoration with the sites its owner holds. The trickle is fired by calling _on_trickle.

const SITE := preload("res://scenes/sites/corruption_site.tscn")

var tower: Tower

func before_each() -> void:
	await super()
	tower = add_tower(1)
	var gate := Node3D.new()
	gate.name = "CourierSpawn"
	tower.add_child(gate)
	tower.courier_spawn = gate

func test_binding_a_tower_starts_its_trickle() -> void:
	tower.bind_advisor(1, GameConstants.Faction.UNDEATH)
	assert_false((tower.get_node(^"TrickleTimer") as Timer).is_stopped())

func test_the_trickle_spawns_a_unit_for_its_owner() -> void:
	tower._on_trickle()
	assert_eq(tower.fighting_units(mm), 1)

func test_the_trickle_pauses_at_the_cap() -> void:
	for i in Tower.TRICKLE_CAP:
		spawn(&"skeleton", 1)
	tower._on_trickle()
	assert_eq(tower.fighting_units(mm), Tower.TRICKLE_CAP)

func test_couriers_do_not_count_toward_the_cap() -> void:
	for i in Tower.TRICKLE_CAP:
		spawn(&"skeleton", 1).minion_trait = &"courier"
	assert_eq(tower.fighting_units(mm), 0)

func test_restoration_grows_with_held_sites() -> void:
	assert_eq(tower.get_restoration(), 0.0)
	for i in Tower.WHOLE_AT_SITES:
		var site := SITE.instantiate() as CorruptionSite
		site.site_type = SiteType.new()
		stage.add_child(site)
		site.set_physics_process(false)
		site._change_holder(1)
	assert_eq(tower.get_restoration(), 1.0)
