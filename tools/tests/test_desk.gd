extends "res://tools/tests/test_base.gd"

## The desk book (GDD §2): opens at your own desk, shows records by kind,
## refreshes live, and keeps your notes in the WorldModel.

func run_tests() -> void:
	var world := await load_world()
	var desk: Desk = null
	for t in world.get_node("World/Env/Towers").get_children():
		if t is Tower and (t as Tower).owner_peer_id == 1:
			desk = t.get_node_or_null("Desk") as Desk
	check(desk != null, "peer 1's tower has a desk")
	var player := world.find_child("1", true, false) as OverlordActor
	check(player != null, "peer 1's overlord exists")
	if desk == null or player == null:
		return
	var model := KnowledgeManager.get_model(1)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var can_capture: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED  # headless may refuse capture
	model.add_record(&"report", "Scout returns", "Grey wolves near the ford.", 600)

	desk.open_book(player)
	await frames(3)
	check(desk.is_open() and Interactable.has_modal(), "book opens and takes the modal lock")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse is released while open")
	check(desk.get_shown_titles() == ["Scout returns"], "existing record shown")

	model.add_record(&"relic", "Bone crown", "Held at the chapel.", 1200)
	await frames(3)
	check(desk.get_shown_titles() == ["Bone crown", "Scout returns"], "live refresh, newest first")
	desk.show_page(&"relic")
	check(desk.get_shown_titles() == ["Bone crown"], "kind page filters")
	check(desk.format_tick(NetworkTime.tickrate * 125) == "02:05", "tick shown as match time")

	desk.show_page(&"notes")
	await frames(2)
	var edit := desk.get_notes_edit()
	check(edit != null, "notes page has a text box")
	edit.text = "Mind the ford."
	desk.close_book()
	check(model.notes == "Mind the ford.", "notes persist in the model")
	check(not desk.is_open() and not Interactable.has_modal(), "closing releases the modal lock")
	check(not can_capture or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "mouse recaptured on close")

	desk.open_book(player)
	desk.show_page(&"notes")
	check(desk.get_notes_edit().text == "Mind the ford.", "notes reload when reopened")
	desk.close_book()
