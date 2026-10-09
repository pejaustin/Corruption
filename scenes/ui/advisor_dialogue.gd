class_name AdvisorDialogue extends CanvasLayer

## The advisor's voice (GDD §2: "Hears couriers' reports, takes your orders,
## other dialogue. The main interface."). Two parts, both minimal:
##   - subtitles: what the advisor says (reports, answers), queued at the
##     bottom of the screen;
##   - a choice: a question with numbered answers, picked with 1–9 or the mouse,
##     Esc to walk away.
## One per local player, created on demand under the scene root.
## PLACEHOLDER: wording and look — the advisor's character is Austin's (#585).

const SUBTITLE_SECONDS: float = 4.0
const MAX_QUEUED: int = 6

static var _instance: AdvisorDialogue

var _subtitle: Label
var _queue: Array[String] = []
var _timer: float = 0.0
var _panel: PanelContainer
var _question: Label
var _options_box: VBoxContainer
var _callbacks: Array[Callable] = []

static func get_instance(tree: SceneTree) -> AdvisorDialogue:
	if _instance == null or not is_instance_valid(_instance):
		_instance = AdvisorDialogue.new()
		_instance.name = "AdvisorDialogue"
		tree.root.add_child(_instance)
	return _instance

func _ready() -> void:
	layer = 20
	_subtitle = Label.new()
	_subtitle.anchor_left = 0.15
	_subtitle.anchor_right = 0.85
	_subtitle.anchor_top = 0.82
	_subtitle.anchor_bottom = 0.95
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_color_override(&"font_color", Color(0.95, 0.9, 0.75))
	_subtitle.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_subtitle.add_theme_constant_override(&"outline_size", 6)
	_subtitle.add_theme_font_size_override(&"font_size", 20)
	add_child(_subtitle)
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.3
	_panel.anchor_right = 0.7
	_panel.anchor_top = 0.45
	_panel.anchor_bottom = 0.8
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_question = Label.new()
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_question)
	_options_box = VBoxContainer.new()
	box.add_child(_options_box)
	KnowledgeManager.advisor_spoke.connect(say)

func _process(delta: float) -> void:
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0:
			_next_line()

func say(line: String) -> void:
	_queue.append(line)
	while _queue.size() > MAX_QUEUED:
		_queue.pop_front()
	if _timer <= 0.0:
		_next_line()

func _next_line() -> void:
	if _queue.is_empty():
		_subtitle.text = ""
		return
	_subtitle.text = _queue.pop_front()
	_timer = SUBTITLE_SECONDS

func is_open() -> bool:
	return _panel.visible

func ask(question: String, options: Array[String], callbacks: Array[Callable]) -> void:
	## Show a question; picking option i calls callbacks[i]. Picking or Esc
	## closes it.
	for c in _options_box.get_children():
		c.queue_free()
	_question.text = question
	_callbacks = callbacks.duplicate()
	for i in options.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, options[i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(choose.bind(i))
		_options_box.add_child(b)
	_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func choose(index: int) -> void:
	if not _panel.visible:
		return
	close()
	if index >= 0 and index < _callbacks.size():
		_callbacks[index].call()

func close() -> void:
	_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_9:
			choose(k - KEY_1)
			get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
