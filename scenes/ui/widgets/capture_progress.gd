class_name CaptureProgress
extends Control

## Bar shown while the bound Avatar is mid-channel. Polls
## active_channel.get_progress() each frame — the channel itself is the
## source of truth, this widget is a passive view.

@onready var _bar: ProgressBar = %Bar
@onready var _label: Label = %Label

var _actor: AvatarActor = null

func _ready() -> void:
	visible = false
	if _bar:
		_bar.min_value = 0.0
		_bar.max_value = 1.0
		_bar.value = 0.0

func bind(actor: AvatarActor) -> void:
	_actor = actor

func _process(_delta: float) -> void:
	if _actor == null:
		visible = false
		return
	var channel := _actor.active_channel
	if channel != null and channel.is_active():
		_bar.value = channel.get_progress()
		visible = true
	else:
		visible = false
