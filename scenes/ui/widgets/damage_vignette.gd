class_name DamageVignette
extends ColorRect

## Fullscreen red flash triggered when the bound actor's HP drops. Intensity
## scales with the fraction of max HP lost; fades out over ~0.5s.

const FLASH_DURATION: float = 0.5
const MIN_ALPHA: float = 0.2
const MAX_ALPHA: float = 0.65

var _actor: Actor = null
var _prev_hp: int = 0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	color = Color(0.8, 0.05, 0.05, 0.0)

func bind(actor: Actor) -> void:
	_actor = actor
	if actor == null:
		return
	_prev_hp = actor.hp
	actor.hp_changed.connect(_on_hp_changed)

func _on_hp_changed(new_hp: int) -> void:
	var delta := _prev_hp - new_hp
	_prev_hp = new_hp
	if delta <= 0 or _actor == null:
		return
	var max_hp := _actor.get_max_hp()
	var fraction: float = clamp(float(delta) / float(max_hp), 0.0, 1.0)
	var target_alpha: float = lerp(MIN_ALPHA, MAX_ALPHA, fraction)
	var c := color
	c.a = target_alpha
	color = c
	var tween := create_tween()
	tween.tween_property(self, "color:a", 0.0, FLASH_DURATION)
