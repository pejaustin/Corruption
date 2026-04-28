class_name CooldownPie
extends Control

## Darkening pie-slice overlay that shrinks as a cooldown ticks down.
## Progress 1.0 = full cooldown (covers the whole slot), 0.0 = ready (hidden).
## Sweep is clockwise from 12 o'clock.

const FILL_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)
const SEGMENT_COUNT: int = 48

var _progress: float = 0.0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE

func set_progress(value: float) -> void:
	var clamped: float = clamp(value, 0.0, 1.0)
	if is_equal_approx(clamped, _progress):
		return
	_progress = clamped
	visible = _progress > 0.0
	queue_redraw()

func _draw() -> void:
	if _progress <= 0.0:
		return
	var center: Vector2 = size * 0.5
	var radius: float = min(size.x, size.y) * 0.55
	var sweep: float = TAU * _progress
	var points := PackedVector2Array()
	points.append(center)
	var segments: int = int(max(2.0, SEGMENT_COUNT * _progress))
	for i in range(segments + 1):
		var angle: float = -PI * 0.5 + sweep * (float(i) / float(segments))
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	var colors := PackedColorArray()
	colors.resize(points.size())
	colors.fill(FILL_COLOR)
	draw_polygon(points, colors)
