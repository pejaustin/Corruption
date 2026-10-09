class_name Desk extends Interactable

## Desk station in each tower (GDD §2 "Desk with books", interview Q8/Q37).
## E at your own desk opens a book: one page per record kind, an "all" page
## (newest first) and a final Notes page bound to WorldModel.notes. The book is
## the only UI; it takes the modal lock, frees the mouse and pauses the rig's
## input while open, and refreshes live when a record arrives.
## PLACEHOLDER: the desk look (a box table and a box book) and every string below.

const PAGE_ALL: StringName = &"all"
const PAGE_NOTES: StringName = &"notes"
const BOOK_SIZE: Vector2 = Vector2(760.0, 520.0)
const PAGE_MARGIN: int = 18
const SECONDS_PER_MINUTE: int = 60
const PAPER_COLOR: Color = Color(0.93, 0.87, 0.72)
const TAB_COLOR: Color = Color(0.78, 0.68, 0.5)
const INK_COLOR: Color = Color(0.16, 0.1, 0.06)
const DIM_COLOR: Color = Color(0.4, 0.3, 0.2)
const TITLE_SIZE: int = 20
const BODY_SIZE: int = 16
const NOTES_SIZE: int = 18
# PLACEHOLDER: wording
const PROMPT_OPEN: String = "Press E to open the book"
const PROMPT_CLOSE: String = "E / Q to close"
const TAB_ALL: String = "All"
const TAB_NOTES: String = "Notes"
const EMPTY_TEXT: String = "Nothing written here yet."
const NOTES_HINT: String = "Write your own notes here."

var _open: bool = false
var _page: StringName = PAGE_ALL
var _player: OverlordActor = null
var _model: WorldModel = null
var _layer: CanvasLayer = null
var _tabs: HBoxContainer = null
var _body: VBoxContainer = null
var _scroll: ScrollContainer = null
var _notes_edit: TextEdit = null

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
	_build_ui()
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
	if _layer != null:
		_layer.queue_free()
		_layer = null
	_notes_edit = null
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
	if _body == null:
		return out
	for c in _body.get_children():
		if c.has_meta(&"record_title"):
			out.append(str(c.get_meta(&"record_title")))
	return out

func get_notes_edit() -> TextEdit:
	return _notes_edit

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
	var typing: bool = _notes_edit != null and _notes_edit.has_focus()
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
	if _notes_edit != null and _model != null:
		_model.notes = _notes_edit.text

func _kinds() -> Array[StringName]:
	var kinds: Array[StringName] = []
	for r in _model.records:
		var k: StringName = r["kind"]
		if not kinds.has(k):
			kinds.push_back(k)
	return kinds

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "BookLayer"
	add_child(_layer)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER_COLOR
	style.border_color = INK_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(PAGE_MARGIN)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.custom_minimum_size = BOOK_SIZE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	panel.add_child(col)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override(&"separation", 6)
	col.add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"separation", 12)
	_scroll.add_child(_body)

func _refresh() -> void:
	if not _open or _body == null:
		return
	_rebuild_tabs()
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_notes_edit = null
	if _page == PAGE_NOTES:
		_build_notes_page()
	else:
		_build_record_page()

func _rebuild_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_add_tab(TAB_ALL, PAGE_ALL)
	for k in _kinds():
		_add_tab(String(k).capitalize(), k)
	_add_tab(TAB_NOTES, PAGE_NOTES)

func _add_tab(label: String, page: StringName) -> void:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.button_pressed = (page == _page)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override(&"font_color", INK_COLOR)
	b.add_theme_color_override(&"font_pressed_color", INK_COLOR)
	b.add_theme_color_override(&"font_hover_color", INK_COLOR)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER_COLOR if page == _page else TAB_COLOR
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	for state in [&"normal", &"pressed", &"hover"]:
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(show_page.bind(page))
	_tabs.add_child(b)

func _build_record_page() -> void:
	var shown: Array[Dictionary] = []
	for i in range(_model.records.size() - 1, -1, -1):
		var r: Dictionary = _model.records[i]
		if _page == PAGE_ALL or r["kind"] == _page:
			shown.push_back(r)
	if shown.is_empty():
		_body.add_child(_make_label(EMPTY_TEXT, BODY_SIZE, DIM_COLOR))
		return
	for r in shown:
		var entry := VBoxContainer.new()
		entry.set_meta(&"record_title", r["title"])
		var head := "%s  %s" % [format_tick(r["tick"]), r["title"]]
		entry.add_child(_make_label(head, TITLE_SIZE, INK_COLOR))
		var text := _make_label(r["text"], BODY_SIZE, INK_COLOR)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(text)
		_body.add_child(entry)

func _build_notes_page() -> void:
	_notes_edit = TextEdit.new()
	_notes_edit.text = _model.notes
	_notes_edit.placeholder_text = NOTES_HINT
	_notes_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_notes_edit.custom_minimum_size = Vector2(BOOK_SIZE.x - 2.0 * PAGE_MARGIN - 8.0, BOOK_SIZE.y - 90.0)
	_notes_edit.add_theme_color_override(&"font_color", INK_COLOR)
	_notes_edit.add_theme_color_override(&"font_placeholder_color", DIM_COLOR)
	_notes_edit.add_theme_font_size_override(&"font_size", NOTES_SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER_COLOR
	_notes_edit.add_theme_stylebox_override(&"normal", sb)
	_notes_edit.add_theme_stylebox_override(&"focus", sb)
	_notes_edit.text_changed.connect(_save_notes)
	_body.add_child(_notes_edit)
	_notes_edit.grab_focus()

func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	return l
