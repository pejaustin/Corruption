class_name WorldFog extends Node

## Ties the world's fog to the day/night clock: as night falls the fog gets thicker (the environment's thin
## volumetric haze, and every FogVolume using shaders/drifting_fog.gdshader through the fog_night shader global).
## The fog itself is the FogVolume children of this scene; their shapes and look live in the scene.

## PLACEHOLDER: tuning — how many times thicker the environment's volumetric haze is at full night.
@export var night_boost: float = 2.5
@export var day_night: DayNight
@export var world_environment: WorldEnvironment

## 0 by day, 1 at full night.
var night: float = 0.0
var _day_density: float = -1.0

func _ready() -> void:
	if day_night != null:
		# The clock's own _ready (after this one) copies the environment and emits time_changed, so the first apply
		# lands on that copy, never on the shared resource.
		day_night.time_changed.connect(func(_t: float) -> void: apply(day_night.daylight()))
	else:
		RenderingServer.global_shader_parameter_set("fog_night", 0.0)

func apply(daylight: float) -> void:
	night = 1.0 - clampf(daylight, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("fog_night", night)
	var env := world_environment.environment if world_environment != null else null
	if env == null:
		return
	if _day_density < 0.0:
		_day_density = env.volumetric_fog_density
	env.volumetric_fog_density = _day_density * lerpf(1.0, night_boost, night)
