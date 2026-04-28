class_name Crosshair
extends Control

## Simple free-aim crosshair drawn with _draw. Center dot + four short
## arm ticks offset from center.

const COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)
const DOT_RADIUS: float = 1.5
const ARM_INNER: float = 5.0
const ARM_OUTER: float = 10.0
const ARM_WIDTH: float = 2.0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, DOT_RADIUS, COLOR)
	draw_line(c + Vector2(ARM_INNER, 0), c + Vector2(ARM_OUTER, 0), COLOR, ARM_WIDTH)
	draw_line(c + Vector2(-ARM_INNER, 0), c + Vector2(-ARM_OUTER, 0), COLOR, ARM_WIDTH)
	draw_line(c + Vector2(0, ARM_INNER), c + Vector2(0, ARM_OUTER), COLOR, ARM_WIDTH)
	draw_line(c + Vector2(0, -ARM_INNER), c + Vector2(0, -ARM_OUTER), COLOR, ARM_WIDTH)
