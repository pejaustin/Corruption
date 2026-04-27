extends Node

## Autoload singleton that routes interaction prompts to the currently
## registered HUD label. Interactables call set_prompt/clear_prompt;
## a HUD registers its RichTextLabel in _ready via register_prompt.
##
## Only one prompt is shown at a time (the most recent set_prompt caller).
## When that caller clears, the label hides.

var _current_source: Interactable = null
var _prompt_label: RichTextLabel = null

## Called by a HUD in _ready to become the active prompt surface.
## Most-recent registration wins — on avatar/overlord swap, the new HUD
## replaces the old one.
func register_prompt(label: RichTextLabel) -> void:
	_prompt_label = label

## Called by a HUD in _exit_tree. Only clears if this label is still the
## active one — avoids a stale deregister nuking a newer registration.
func deregister_prompt(label: RichTextLabel) -> void:
	if _prompt_label == label:
		_prompt_label = null
		_current_source = null

func set_prompt(source: Interactable, text: String, color: Color = Color.WHITE) -> void:
	_current_source = source
	if _prompt_label == null or not is_instance_valid(_prompt_label):
		return
	var hex := color.to_html(false)
	_prompt_label.text = "[center][color=#%s]%s[/color][/center]" % [hex, text]
	_prompt_label.visible = true

func clear_prompt(source: Interactable) -> void:
	if _current_source != source:
		return
	_current_source = null
	if _prompt_label and is_instance_valid(_prompt_label):
		_prompt_label.visible = false
		_prompt_label.text = ""

func _process(_delta: float) -> void:
	if _current_source and not is_instance_valid(_current_source):
		_current_source = null
		if _prompt_label and is_instance_valid(_prompt_label):
			_prompt_label.visible = false
