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

const SCENE_PATH: String = "res://scenes/ui/advisor_dialogue.tscn"

static var _instance: AdvisorDialogue

## One button per answer, instanced when a question is asked.
@export var option_button_scene: PackedScene

var _queue: Array[String] = []
var _timer: float = 0.0
var _callbacks: Array[Callable] = []

@onready var _subtitle: Label = %Subtitle
@onready var _panel: PanelContainer = %Panel
@onready var _question: Label = %Question
@onready var _options_box: VBoxContainer = %Options

static func get_instance(tree: SceneTree) -> AdvisorDialogue:
	if _instance == null or not is_instance_valid(_instance):
		# Loaded by path: the scene's own script would make a preload cyclic.
		_instance = (load(SCENE_PATH) as PackedScene).instantiate() as AdvisorDialogue
		_instance.name = "AdvisorDialogue"
		tree.root.add_child(_instance)
	return _instance

func _ready() -> void:
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
		var b := option_button_scene.instantiate() as Button
		b.text = "%d. %s" % [i + 1, options[i]]
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
