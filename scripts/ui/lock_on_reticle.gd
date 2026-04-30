class_name LockOnReticle extends Node3D

## Billboarded reticle that follows a locked target's chest. Local-only
## presentation — never gates damage, never enters rollback. Targeting
## instances/destroys this scene; the only state it owns is `target`.

## Vertical bias on the target's origin where the reticle floats. Roughly
## chest height for the existing avatar/minion rigs.
@export var target_offset: Vector3 = Vector3(0.0, 1.4, 0.0)
## Pulse amplitude/period for the idle "live lock" visual heartbeat.
const PULSE_AMPLITUDE: float = 0.05
const PULSE_PERIOD_SEC: float = 0.6

var target: Actor = null

@onready var _sprite: Sprite3D = $Sprite3D

var _time: float = 0.0
var _base_scale: Vector3 = Vector3.ONE

func _ready() -> void:
	if _sprite:
		_base_scale = _sprite.scale

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		visible = false
		return
	visible = true
	global_position = target.global_position + target_offset
	_time += delta
	if _sprite:
		var pulse: float = 1.0 + PULSE_AMPLITUDE * sin(_time * TAU / PULSE_PERIOD_SEC)
		_sprite.scale = _base_scale * pulse
