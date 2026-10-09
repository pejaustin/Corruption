class_name Desk extends Interactable

## Desk station in each tower (GDD §2 "Desk with books", interview Q8/Q37).
## E at your own desk opens a book: one page per record kind, an "all" page
## (newest first) and a final Notes page bound to WorldModel.notes. The book is
## the only UI; it takes the modal lock, frees the mouse and pauses the rig's
## input while open, and refreshes live when a record arrives.
## PLACEHOLDER: the desk look (a box table and a box book, authored in desk.tscn)
## and every string below.

const PAGE_ALL: StringName = &"all"
const PAGE_NOTES: StringName = &"notes"
const SECONDS_PER_MINUTE: int = 60
# PLACEHOLDER: wording
const PROMPT_OPEN: String = "Press E to open the book"
const PROMPT_CLOSE: String = "E / Q to close"
const TAB_ALL: String = "All"
const TAB_NOTES: String = "Notes"

## Scenes instanced into the book: a tab per page and an entry per record.
@export var tab_button_scene: PackedScene
@export var entry_scene: PackedScene

var _open: bool = false
var _page: StringName = PAGE_ALL
var _player: OverlordActor = null
var _model: WorldModel = null

@onready var _layer: CanvasLayer = %BookLayer
@onready var _tabs: HBoxContainer = %Tabs
@onready var _entries: VBoxContainer = %Entries
@onready var _empty_label: Label = %EmptyLabel
@onready var _notes_edit: TextEdit = %NotesEdit

func _interactable_ready() -> void:
	_notes_edit.text_changed.connect(_save_notes)

func get_prompt_text() -> String:
	if _open:
		return PROMPT_CLOSE
	if is_active_for_local_peer() and is_overlord_in_range():
		return PROMPT_OPEN
	return ""

func get_prompt_color() -> Color:
	return Color(0.9, 0.8, 0.55)

func is_active_for_local_peer() -> bool:
	## True when this desk belongs to the local peer (or has no Tower parent,
	## i.e. a test harness).
	var tower := _find_owning_tower()
	if tower == null:
		return true
	return tower.owner_peer_id == multiplayer.get_unique_id()

func is_open() -> bool:
	return _open

func open_book(player: OverlordActor) -> void:
	if _open or player == null or not is_active_for_local_peer():
		return
	_model = KnowledgeManager.get_model(multiplayer.get_unique_id())
	if _model == null:
		return
	_player = player
	_open = true
	_page = PAGE_ALL
	_claim_modal()
	_set_player_input(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_layer.visible = true
	_model.record_added.connect(_on_record_added)
	_refresh()
	_refresh_prompt()

func close_book() -> void:
	if not _open:
		return
	_save_notes()
	_open = false
	if _model != null and _model.record_added.is_connected(_on_record_added):
		_model.record_added.disconnect(_on_record_added)
	_layer.visible = false
	_clear_page()
	_release_modal()
	_set_player_input(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_player = null
	_refresh_prompt()

func show_page(page: StringName) -> void:
	if not _open:
		return
	_save_notes()
	_page = page
	_refresh()

func get_page() -> StringName:
	return _page

func get_shown_titles() -> Array[String]:
	## Titles of the record entries on the current page, in shown order.
	var out: Array[String] = []
	for c in _entries.get_children():
		if c.has_meta(&"record_title"):
			out.append(str(c.get_meta(&"record_title")))
	return out

func get_notes_edit() -> TextEdit:
	## The notes page's editor, or null while another page is shown.
	return _notes_edit if _notes_edit.visible else null

func format_tick(tick: int) -> String:
	## Match time as mm:ss from a network tick.
	var rate: int = maxi(NetworkTime.tickrate, 1)
	var total: int = tick / rate
	return "%02d:%02d" % [total / SECONDS_PER_MINUTE, total % SECONDS_PER_MINUTE]

func _on_interact() -> void:
	if _open:
		close_book()
	elif is_overlord_in_range():
		open_book(_player_in_range)

func _unhandled_input(event: InputEvent) -> void:
	if _open:
		return
	super(event)

func _input(event: InputEvent) -> void:
	if not _open:
		return
	var typing: bool = _notes_edit.visible and _notes_edit.has_focus()
	var is_esc: bool = event is InputEventKey and (event as InputEventKey).pressed \
		and (event as InputEventKey).keycode == KEY_ESCAPE
	var is_close: bool = event.is_action_pressed("interaction") or event.is_action_pressed("cancel")
	if is_esc or (is_close and not typing):
		close_book()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if _open:
		close_book()

func _find_owning_tower() -> Tower:
	var n: Node = get_parent()
	while n:
		if n is Tower:
			return n as Tower
		n = n.get_parent()
	return null

func _set_player_input(enabled: bool) -> void:
	if _player == null:
		return
	for c in _player.get_children():
		if c is PlayerInput:
			(c as PlayerInput).input_enabled = enabled

func _on_record_added(_entry: Dictionary) -> void:
	_refresh()

func _save_notes() -> void:
	if _notes_edit.visible and _model != null:
		_model.notes = _notes_edit.text

func _kinds() -> Array[StringName]:
	var kinds: Array[StringName] = []
	for r in _model.records:
		var k: StringName = r["kind"]
		if not kinds.has(k):
			kinds.push_back(k)
	return kinds

func _refresh() -> void:
	if not _open:
		return
	_rebuild_tabs()
	_clear_page()
	if _page == PAGE_NOTES:
		_show_notes_page()
	else:
		_show_record_page()

func _clear_page() -> void:
	for c in _entries.get_children():
		_entries.remove_child(c)
		c.queue_free()
	_empty_label.visible = false
	_notes_edit.visible = false

func _rebuild_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_add_tab(TAB_ALL, PAGE_ALL)
	for k in _kinds():
		_add_tab(String(k).capitalize(), k)
	_add_tab(TAB_NOTES, PAGE_NOTES)

func _add_tab(label: String, page: StringName) -> void:
	var b := tab_button_scene.instantiate() as Button
	b.text = label
	b.button_pressed = (page == _page)
	b.pressed.connect(show_page.bind(page))
	_tabs.add_child(b)

func _show_record_page() -> void:
	var shown: Array[Dictionary] = []
	for i in range(_model.records.size() - 1, -1, -1):
		var r: Dictionary = _model.records[i]
		if _page == PAGE_ALL or r["kind"] == _page:
			shown.push_back(r)
	_empty_label.visible = shown.is_empty()
	for r in shown:
		var entry := entry_scene.instantiate() as Control
		entry.set_meta(&"record_title", r["title"])
		(entry.get_node(^"%Title") as Label).text = "%s  %s" % [format_tick(r["tick"]), r["title"]]
		(entry.get_node(^"%Text") as Label).text = r["text"]
		_entries.add_child(entry)

func _show_notes_page() -> void:
	_notes_edit.text = _model.notes
	_notes_edit.visible = true
	_notes_edit.grab_focus()
