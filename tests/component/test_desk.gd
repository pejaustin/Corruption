extends "res://tests/support/stage_test.gd"

## The desk book (GDD §2): opens at your own desk, shows records by kind, refreshes live,
## and keeps your notes in the WorldModel. Records are added to the model directly.

const DESK := preload("res://scenes/interactibles/desk.tscn")

var desk: Desk
var player: OverlordActor
var model: WorldModel

func before_each() -> void:
	await super()
	player = add_overlord()
	desk = DESK.instantiate() as Desk
	stage.add_child(desk)
	model = KnowledgeManager.get_model(1)

func after_each() -> void:
	if desk.is_open():
		desk.close_book()
	KnowledgeManager.reset()
	await super()

func test_the_book_opens_and_takes_the_modal_lock() -> void:
	desk.open_book(player)
	assert_true(desk.is_open())
	assert_true(Interactable.has_modal())

func test_closing_releases_the_modal_lock() -> void:
	desk.open_book(player)
	desk.close_book()
	assert_false(desk.is_open())
	assert_false(Interactable.has_modal())

func test_a_rivals_desk_does_not_open() -> void:
	var rival := DESK.instantiate() as Desk
	add_tower(2).add_child(rival)
	rival.open_book(player)
	assert_false(rival.is_open())

func test_records_show_newest_first() -> void:
	model.add_record(&"report", "Scout returns", "Grey wolves near the ford.", 600)
	model.add_record(&"relic", "Bone crown", "Held at the chapel.", 1200)
	desk.open_book(player)
	assert_eq(desk.get_shown_titles(), ["Bone crown", "Scout returns"] as Array[String])

func test_an_open_book_refreshes_live() -> void:
	desk.open_book(player)
	model.add_record(&"report", "Scout returns", "", 600)
	assert_eq(desk.get_shown_titles(), ["Scout returns"] as Array[String])

func test_a_kind_page_filters() -> void:
	model.add_record(&"report", "Scout returns", "", 600)
	model.add_record(&"relic", "Bone crown", "", 1200)
	desk.open_book(player)
	desk.show_page(&"relic")
	assert_eq(desk.get_shown_titles(), ["Bone crown"] as Array[String])

func test_ticks_show_as_match_time() -> void:
	assert_eq(desk.format_tick(NetworkTime.tickrate * 125), "02:05")

func test_notes_persist_in_the_model_and_reload() -> void:
	desk.open_book(player)
	desk.show_page(&"notes")
	desk.get_notes_edit().text = "Mind the ford."
	desk.close_book()
	assert_eq(model.notes, "Mind the ford.")
	desk.open_book(player)
	desk.show_page(&"notes")
	assert_eq(desk.get_notes_edit().text, "Mind the ford.")
