@tool
class_name WorldCurve
extends Node

## The curved-world bend for this world (shaders/curved_world.gdshaderinc): sets the project-wide shader globals
## curve_horizon_m and curve_eye_height_m from this node, so each world size carries its own values and the editor shows
## them. The project settings (Project Settings > Globals > Shader Globals) stay the fallback for scenes without one.

## Distance at which ground at eye level has dropped by eye_height_m. 0 = no bend.
## PLACEHOLDER: tuning (2 km world 1500 m; the size builder scales it with the world's width: 400 m 300, 6 km 4500)
@export var horizon_m: float = 1500.0:
	set(value):
		horizon_m = value
		_apply()
## PLACEHOLDER: tuning (40 m on the 2 km world; the size builder scales it with the world's height)
@export var eye_height_m: float = 40.0:
	set(value):
		eye_height_m = value
		_apply()

func _ready() -> void:
	_apply()

func _apply() -> void:
	if not is_inside_tree():
		return
	RenderingServer.global_shader_parameter_set("curve_horizon_m", horizon_m)
	RenderingServer.global_shader_parameter_set("curve_eye_height_m", eye_height_m)
