class_name DamageNumber extends Node3D

## Floating damage number. Tweens upward + fades out, then frees.
## Spawned by the DamageNumbers autoload on Actor.took_damage.
##
## Uses a Label3D billboard so it reads from any camera angle without per-
## peer screen-space math. Local-only — never affects gameplay state.

const FLOAT_DURATION: float = 0.9
const FLOAT_DISTANCE: float = 1.2

@onready var _label: Label3D = $Label3D

func show_amount(amount: int) -> void:
	if not is_inside_tree():
		await ready
	_label.text = str(amount)
	var start_pos: Vector3 = global_position
	var end_pos: Vector3 = start_pos + Vector3(0.0, FLOAT_DISTANCE, 0.0)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "global_position", end_pos, FLOAT_DURATION)
	tween.tween_property(_label, "modulate:a", 0.0, FLOAT_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
