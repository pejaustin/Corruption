extends "res://tools/tests/test_base.gd"

## The treasure room and ledger (GDD §2, §6): the room shows the tower's goods
## exactly and only to its owner; the ledger lists the latest reports.

func run_tests() -> void:
	var world := await load_world()
	var mm := world.get_node("MinionManager") as MinionManager
	var room: TreasureRoom = null
	var ledger: Ledger = null
	var foreign: TreasureRoom = null
	for t in world.get_node("World/Env/Towers").get_children():
		var tower := t as Tower
		if tower == null:
			continue
		if tower.owner_peer_id == 1:
			room = tower.get_node_or_null("TreasureRoom") as TreasureRoom
			ledger = tower.get_node_or_null("Ledger") as Ledger
		elif foreign == null:
			foreign = tower.get_node_or_null("TreasureRoom") as TreasureRoom
	check(room != null and ledger != null, "peer 1's tower has a treasure room and a ledger")
	if room == null or ledger == null:
		return
	check(room.visible and room.get_crate_count() == 0, "an empty treasury shows no crates")
	mm.add_treasury(1, 37)
	await frames(5)
	check(room.get_goods() == 37 and room.get_crate_count() == 37, "the room shows each good (%d crates)" % room.get_crate_count())
	check(room.get_plaque_text() == "Goods: 37", "the plaque says the exact number")
	mm.add_treasury(1, 500)
	await frames(5)
	check(room.get_crate_count() == TreasureRoom.MAX_CRATES and room.get_plaque_text() == "Goods: 537", "crates cap, the plaque stays exact")
	check(foreign == null or not foreign.visible, "another player's room is empty to you")

	var model := KnowledgeManager.get_model(1)
	var now := NetworkTime.tick
	model.ledger[&"MineSE"] = {"pile": 12, "tick": now}
	model.ledger[&"MineNW"] = {"pile": 40, "tick": now + 1}
	var lines := ledger.get_lines()
	check(lines.size() == 3 and lines[0] == "In the treasure room: 537", "the ledger opens with what the tower holds")
	check(lines[1].begins_with("MineNW"), "newest report first")
	check(ledger.format_age(now - NetworkTime.tickrate * 125).begins_with("02:"), "age is shown as mm:ss")

	var player := world.find_child("1", true, false) as OverlordActor
	ledger.open_ledger(player)
	await frames(3)
	check(ledger.is_open() and Interactable.has_modal(), "the ledger opens and takes the modal lock")
	ledger.close_ledger()
	check(not ledger.is_open() and not Interactable.has_modal(), "closing releases the modal lock")
