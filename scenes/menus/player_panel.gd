class_name PlayerPanel
extends PanelContainer

## A row in the lobby player list. Owns a name input, faction picker, ready
## toggle, and (for CPU seats only, host-only) a remove button. Editability is
## controlled by the lobby — only the local peer's panel is editable, plus
## CPU panels for the host.

signal display_name_changed(peer_id: int, new_name: String)
signal faction_changed(peer_id: int, new_faction: int)
signal ready_changed(peer_id: int, ready: bool)
signal cpu_remove_requested(peer_id: int)

@onready var _name_input: LineEdit = %PlayerNameInput
@onready var _faction_selector: OptionButton = %FactionSelector
@onready var _ready_button: Button = %ReadyButton
@onready var _remove_button: Button = %RemoveButton

var _peer_id: int = -1
var _suppress_signals: bool = false

func _ready() -> void:
	_name_input.text_submitted.connect(_on_name_submitted)
	_name_input.focus_exited.connect(_on_name_focus_exited)
	_faction_selector.item_selected.connect(_on_faction_selected)
	_ready_button.toggled.connect(_on_ready_toggled)
	_remove_button.pressed.connect(_on_remove_pressed)

func update_view(
	peer_id: int,
	display_name: String,
	faction: int,
	ready: bool,
	is_cpu: bool,
	editable: bool,
	is_host: bool,
	available_factions: Array[int]
) -> void:
	_peer_id = peer_id
	_suppress_signals = true

	if not _name_input.has_focus():
		_name_input.text = display_name
	_name_input.editable = editable

	_faction_selector.clear()
	var current_index: int = -1
	for f in available_factions:
		var idx: int = _faction_selector.get_item_count()
		_faction_selector.add_item(GameConstants.faction_names[f], f)
		if f == faction:
			current_index = idx
	if current_index == -1:
		# Current faction wasn't in the available list (race during sync) —
		# add it back so the selector can still display it.
		var idx: int = _faction_selector.get_item_count()
		_faction_selector.add_item(GameConstants.faction_names[faction], faction)
		current_index = idx
	_faction_selector.selected = current_index
	_faction_selector.disabled = not editable

	if is_cpu:
		_ready_button.text = "CPU"
		_ready_button.button_pressed = true
		_ready_button.disabled = true
	else:
		_ready_button.button_pressed = ready
		_ready_button.text = "Ready" if ready else "Not Ready"
		_ready_button.disabled = not editable

	_remove_button.visible = is_cpu and is_host

	var color: Color = GameConstants.faction_colors[faction]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.25)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", style)

	_suppress_signals = false

func _on_name_submitted(text: String) -> void:
	if _suppress_signals:
		return
	display_name_changed.emit(_peer_id, text)
	_name_input.release_focus()

func _on_name_focus_exited() -> void:
	if _suppress_signals:
		return
	display_name_changed.emit(_peer_id, _name_input.text)

func _on_faction_selected(index: int) -> void:
	if _suppress_signals:
		return
	var fid: int = _faction_selector.get_item_id(index)
	faction_changed.emit(_peer_id, fid)

func _on_ready_toggled(pressed: bool) -> void:
	if _suppress_signals:
		return
	ready_changed.emit(_peer_id, pressed)

func _on_remove_pressed() -> void:
	if _suppress_signals:
		return
	cpu_remove_requested.emit(_peer_id)
