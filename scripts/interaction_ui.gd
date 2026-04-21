extends Node

## Autoload singleton that manages the interaction prompt HUD label.
## Interactables call set_prompt/clear_prompt; this drives a Label
## on the CanvasLayer in the game scene.
##
## Only one prompt is shown at a time (the most recent set_prompt caller).
## When that caller clears, the label hides.

var _current_source: Interactable = null
var _prompt_label: RichTextLabel = null

func _ready() -> void:
	# Label is created when the game scene loads; we find it each time.
	pass

func _get_label() -> RichTextLabel:
	if _prompt_label and is_instance_valid(_prompt_label):
		return _prompt_label
	# Look for it in the scene tree under CanvasLayer
	var scene = get_tree().current_scene
	if not scene:
		return null
	_prompt_label = scene.get_node_or_null("CanvasLayer/InteractionPrompt")
	return _prompt_label

func set_prompt(source: Interactable, text: String, color: Color = Color.WHITE) -> void:
	_current_source = source
	var label = _get_label()
	if not label:
		return
	# Use BBCode for color
	var hex = color.to_html(false)
	label.text = "[center][color=#%s]%s[/color][/center]" % [hex, text]
	label.visible = true

func clear_prompt(source: Interactable) -> void:
	if _current_source != source:
		return  # A different interactable took focus; don't clear it
	_current_source = null
	var label = _get_label()
	if label:
		label.visible = false
		label.text = ""

func _process(_delta: float) -> void:
	# If our source was freed, clear
	if _current_source and not is_instance_valid(_current_source):
		_current_source = null
		var label = _get_label()
		if label:
			label.visible = false
