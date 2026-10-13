extends "res://tests/support/stage_test.gd"

## The treasure room and ledger (GDD §2, §6): the room shows the tower's goods exactly and
## only to its owner; the ledger lists the latest reports. Goods are set on the treasury.

const ROOM := preload("res://scenes/interactibles/treasure_room.tscn")
const LEDGER := preload("res://scenes/interactibles/ledger.tscn")

func after_each() -> void:
	if Interactable.has_modal():
		Interactable._modal_holder._release_modal()
	KnowledgeManager.reset()
	await super()

func _room(owner_peer := 1) -> TreasureRoom:
	var room := ROOM.instantiate() as TreasureRoom
	add_tower(owner_peer).add_child(room)
	return room

func test_an_empty_treasury_shows_no_crates() -> void:
	var room := _room()
	assert_true(room.visible)
	assert_eq(room.get_crate_count(), 0)

func test_the_room_shows_each_good_and_the_exact_number() -> void:
	var room := _room()
	mm.add_treasury(1, 37)
	room._refresh()
	assert_eq(room.get_crate_count(), 37)
	assert_eq(room.get_plaque_text(), "Goods: 37")

func test_crates_cap_but_the_plaque_stays_exact() -> void:
	var room := _room()
	mm.add_treasury(1, TreasureRoom.MAX_CRATES + 37)
	room._refresh()
	assert_eq(room.get_crate_count(), TreasureRoom.MAX_CRATES)
	assert_eq(room.get_plaque_text(), "Goods: %d" % (TreasureRoom.MAX_CRATES + 37))

func test_a_rivals_room_is_hidden() -> void:
	var room := _room(2)
	mm.add_treasury(2, 10)
	room._refresh()
	assert_false(room.visible)

func _ledger() -> Ledger:
	var ledger := LEDGER.instantiate() as Ledger
	add_tower(1).add_child(ledger)
	return ledger

func test_the_ledger_opens_with_the_treasury_then_newest_report_first() -> void:
	var ledger := _ledger()
	mm.add_treasury(1, 537)
	var model := KnowledgeManager.get_model(1)
	model.ledger[&"MineSE"] = {"pile": 12, "tick": 100}
	model.ledger[&"MineNW"] = {"pile": 40, "tick": 101}
	var lines := ledger.get_lines()
	assert_eq(lines.size(), 3)
	assert_eq(lines[0], "In the treasure room: 537")
	assert_string_contains(lines[1], "40 goods")

func test_report_age_shows_as_minutes_and_seconds() -> void:
	var ledger := _ledger()
	assert_string_starts_with(ledger.format_age(NetworkTime.tick - NetworkTime.tickrate * 125), "02:")

func test_a_report_with_resources_fills_the_ledger() -> void:
	KnowledgeManager.deliver_report(1, {"source": &"returned", "resources": [{"site": &"MineSE", "pile": 12}]})
	assert_eq(KnowledgeManager.get_model(1).ledger[&"MineSE"]["pile"], 12)

func test_the_ledger_opens_and_closes_with_the_modal_lock() -> void:
	var ledger := _ledger()
	var player := add_overlord()
	ledger.open_ledger(player)
	assert_true(ledger.is_open() and Interactable.has_modal())
	ledger.close_ledger()
	assert_false(ledger.is_open() or Interactable.has_modal())
