class_name Ledger extends Interactable

## The ledger beside the treasure room (GDD §6, ticket #565): a book listing
## the latest report of goods held at each resource location (WorldModel.ledger),
## each with how long ago it was written, plus what the tower holds right now.
## Owner-only. E opens it, E / Q closes; it takes the modal lock and pauses the
## rig's input while open, like the desk.
## PLACEHOLDER: the look (a box and a red slab, authored in ledger.tscn), every string and number below.

const SECONDS_PER_MINUTE: int = 60
# PLACEHOLDER: wording
const PROMPT_OPEN: String = "Press E to read the ledger"
const PROMPT_CLOSE: String = "E / Q to close"
const HELD_FORMAT: String = "In the treasure room: %d"
const ENTRY_FORMAT: String = "%s: %d goods, written %s ago"
const EMPTY_TEXT: String = "No report of goods held elsewhere."

## A line of the page, instanced per line.
@export var line_scene: PackedScene

var _open: bool = false
var _player: OverlordActor = null

@onready var _layer: CanvasLayer = %LedgerLayer
@onready var _lines: VBoxContainer = %Lines

func get_prompt_text() -> String:
	if _open:
		return PROMPT_CLOSE
	if is_active_for_local_peer() and is_overlord_in_range():
		return PROMPT_OPEN
	return ""

func get_prompt_color() -> Color:
	return Color(0.9, 0.8, 0.55)

func is_active_for_local_peer() -> bool:
	var tower := _find_owning_tower()
	if tower == null:
		return true
	return tower.owner_peer_id == multiplayer.get_unique_id()

func is_open() -> bool:
	return _open

func open_ledger(player: OverlordActor) -> void:
	if _open or player == null or not is_active_for_local_peer():
		return
	_player = player
	_open = true
	_claim_modal()
	_set_player_input(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_layer.visible = true
	refresh()
	_refresh_prompt()

func close_ledger() -> void:
	if not _open:
		return
	_open = false
	_layer.visible = false
	_clear_lines()
	_release_modal()
	_set_player_input(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_player = null
	_refresh_prompt()

func get_lines() -> Array[String]:
	## What the page says, newest report first: the tower's holdings, then one
	## line per ledger entry.
	var out: Array[String] = []
	var model := KnowledgeManager.get_model(multiplayer.get_unique_id())
	var mm := _minion_manager()
	if mm:
		out.append(HELD_FORMAT % mm.get_treasury(multiplayer.get_unique_id()))
	if model == null or model.ledger.is_empty():
		out.append(EMPTY_TEXT)
		return out
	var sites: Array = model.ledger.keys()
	sites.sort_custom(func(a: StringName, b: StringName) -> bool:
		return int(model.ledger[a]["tick"]) > int(model.ledger[b]["tick"]))
	for site in sites:
		var e: Dictionary = model.ledger[site]
		out.append(ENTRY_FORMAT % [_site_name(site), int(e["pile"]), format_age(int(e["tick"]))])
	return out

func format_age(tick: int) -> String:
	## How long ago a tick was, as mm:ss.
	var rate: int = maxi(NetworkTime.tickrate, 1)
	var total: int = maxi(0, NetworkTime.tick - tick) / rate
	return "%02d:%02d" % [total / SECONDS_PER_MINUTE, total % SECONDS_PER_MINUTE]

func refresh() -> void:
	if not _open:
		return
	_clear_lines()
	for line in get_lines():
		var l := line_scene.instantiate() as Label
		l.text = line
		_lines.add_child(l)

func _clear_lines() -> void:
	for c in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()

func _site_name(site: StringName) -> String:
	var point := MapPoint.find(get_tree(), site)
	return point.get_label() if point else String(site)

func _on_interact() -> void:
	if _open:
		close_ledger()
	elif is_overlord_in_range():
		open_ledger(_player_in_range)

func _unhandled_input(event: InputEvent) -> void:
	if _open:
		return
	super(event)

func _input(event: InputEvent) -> void:
	if not _open:
		return
	var is_esc: bool = event is InputEventKey and (event as InputEventKey).pressed \
		and (event as InputEventKey).keycode == KEY_ESCAPE
	if is_esc or event.is_action_pressed("interaction") or event.is_action_pressed("cancel"):
		close_ledger()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _open:
		refresh()

func _exit_tree() -> void:
	if _open:
		close_ledger()

func _find_owning_tower() -> Tower:
	var n: Node = get_parent()
	while n:
		if n is Tower:
			return n as Tower
		n = n.get_parent()
	return null

func _minion_manager() -> MinionManager:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("MinionManager") as MinionManager if scene else null

func _set_player_input(enabled: bool) -> void:
	if _player == null:
		return
	for c in _player.get_children():
		if c is PlayerInput:
			(c as PlayerInput).input_enabled = enabled
