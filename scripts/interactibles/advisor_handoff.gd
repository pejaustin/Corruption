extends Interactable

## The advisor (GDD §2, §3; Q8, Q9): the main interface. Mounted on
## advisor_actor.tscn as a child Area3D. Only its own overlord can talk to it.
##
## With a scroll of orders in hand, the advisor asks what the orders are — the
## goals the destination allows (OrderGoal) — and dispatches them with a
## courier. Without one, the advisor can update the map to the latest reports,
## train a courier, or repeat the latest news.
## PLACEHOLDER: wording — every line here stands in for Austin's advisor (#585).

func get_prompt_text() -> String:
	if _player_in_range == null:
		return "Advisor"
	if not _is_owning_overlord_in_range():
		return "Another overlord's advisor"
	if _player_in_range.is_holding_order():
		return "[E] Hand the advisor your orders"
	return "[E] Speak with the advisor (%d couriers at home)" % KnowledgeManager.get_couriers_home(get_local_peer_id())

func get_prompt_color() -> Color:
	return Color(0.95, 0.85, 0.55)

func _on_interact() -> void:
	if not _is_owning_overlord_in_range():
		return
	var dialogue := AdvisorDialogue.get_instance(get_tree())
	if dialogue.is_open():
		return
	if _player_in_range.is_holding_order():
		_ask_goal(dialogue)
	else:
		_ask_general(dialogue)

func _ask_goal(dialogue: AdvisorDialogue) -> void:
	var player := _player_in_range
	var order := player.held_order
	var groups: Array = order.get("group_ids", [])
	var goals := OrderGoal.goals_for(int(order.get("dest_kind", MapPoint.Kind.ROAD)), not groups.is_empty())
	var labels: Array[String] = []
	var actions: Array[Callable] = []
	for goal in goals:
		# Captives are only worth taking with a corrupted chapel to bring them to.
		if goal == OrderGoal.Goal.CAPTURE and not GameState.has_capability(get_local_peer_id(), SiteCapability.DOMINATE_THRALLS):
			continue
		labels.append(OrderGoal.name_of(goal))
		if goal == OrderGoal.Goal.OFFER:
			actions.append(_ask_promise.bind(dialogue, player))
		else:
			actions.append(_dispatch.bind(player, goal, &""))
	labels.append("Not yet.")
	actions.append(func() -> void: pass)
	var dest := MapPoint.find(get_tree(), StringName(order.get("dest_point", &"")))
	var who := "a courier" if groups.is_empty() else ("%d group%s" % [groups.size(), "" if groups.size() == 1 else "s"])
	dialogue.ask("Orders for %s to %s. What are they to do?" % [who, dest.get_label() if dest else "?"], labels, actions)

func _ask_promise(dialogue: AdvisorDialogue, player: OverlordActor) -> void:
	## GDD Q23: a noble is bought with goods plus a promise, such as sparing
	## their settlement or assassinating a rival.
	var labels: Array[String] = ["Promise to spare their settlement.", "Promise to assassinate a rival.", "Not yet."]
	var actions: Array[Callable] = [
		_dispatch.bind(player, OrderGoal.Goal.OFFER, &"spare"),
		_dispatch.bind(player, OrderGoal.Goal.OFFER, &"assassinate"),
		func() -> void: pass,
	]
	dialogue.ask.call_deferred("And what do we promise them?", labels, actions)

func _dispatch(player: OverlordActor, goal: int, promise: StringName) -> void:
	var order := player.take_order()
	order["goal"] = goal
	if promise != &"":
		order["promise"] = promise
	KnowledgeManager.request_dispatch(order)

func _ask_general(dialogue: AdvisorDialogue) -> void:
	var labels: Array[String] = ["Update the map with the latest reports."]
	var actions: Array[Callable] = [_update_map]
	labels.append("What news?")
	actions.append(_repeat_news)
	labels.append("Train a new courier (takes one courier and one of the troops here).")
	actions.append(func() -> void: KnowledgeManager.request_train_courier())
	labels.append("Have a leader teach another group (both are busy a while).")
	actions.append(func() -> void: KnowledgeManager.request_teach())
	labels.append("Nothing.")
	actions.append(func() -> void: pass)
	dialogue.ask("My lord?", labels, actions)

func _update_map() -> void:
	## GDD Q10: asking the advisor resets the pieces to the latest reports.
	var model := KnowledgeManager.local_model()
	model.piece_overrides.clear()
	model.changed.emit()
	KnowledgeManager.advisor_spoke.emit("The pieces stand where the last reports put them.")

func _repeat_news() -> void:
	var lines := KnowledgeManager.local_model().last_report_lines
	if lines.is_empty():
		KnowledgeManager.advisor_spoke.emit("No news yet.")
		return
	for line in lines:
		KnowledgeManager.advisor_spoke.emit(line)

func _is_owning_overlord_in_range() -> bool:
	if _player_in_range == null:
		return false
	var advisor := _find_advisor()
	if advisor == null:
		return false
	return _player_in_range.name.to_int() == advisor.owner_peer_id

func _find_advisor() -> MinionActor:
	var parent := get_parent()
	while parent != null:
		if parent is MinionActor:
			return parent
		parent = parent.get_parent()
	return null
