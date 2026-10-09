class_name DayNight extends Node

## The day/night cycle (GDD §2 balcony: "keeping track of the day/night cycle").
## Host-driven time of day, synced to clients, rotating the world's sun and
## tinting its colour and energy plus the sky and ambient light. Night is
## visibly darker but stays playable.
## FLAVOUR ONLY: whether day and night change play is an open question (ticket
## #574); nothing but light and sky reads `time_of_day`.
## PLACEHOLDER: the length of a day and every light/sky number and colour below.

signal time_changed(time_of_day: float)

## PLACEHOLDER: tuning — real seconds in one full day.
const DAY_SECONDS: float = 600.0
## PLACEHOLDER: tuning — the host re-sends the clock this often (seconds).
const SYNC_SECONDS: float = 10.0
## PLACEHOLDER: tuning — time of day at match start (0 = midnight, 0.25 = sunrise,
## 0.5 = noon, 0.75 = sunset).
const START_TIME: float = 0.4
## PLACEHOLDER: tuning — sun/moon light.
const DAY_LIGHT_COLOR: Color = Color(0.980392, 0.717647, 0.0470588, 1)
const NIGHT_LIGHT_COLOR: Color = Color(0.45, 0.55, 0.9, 1)
const DAY_LIGHT_ENERGY: float = 1.0
const NIGHT_LIGHT_ENERGY: float = 0.25
const MIN_LIGHT_PITCH: float = deg_to_rad(12.0)
const SUN_YAW: float = deg_to_rad(20.0)
## PLACEHOLDER: tuning — sky and ambient at night (day values come from the scene).
const NIGHT_SKY_TOP: Color = Color(0.03, 0.05, 0.14, 1)
const NIGHT_SKY_HORIZON: Color = Color(0.1, 0.12, 0.25, 1)
const NIGHT_AMBIENT_COLOR: Color = Color(0.25, 0.3, 0.55, 1)
const NIGHT_AMBIENT_ENERGY: float = 0.9

var time_of_day: float = START_TIME

var _light: DirectionalLight3D = null
var _environment: Environment = null
var _sky: ProceduralSkyMaterial = null
var _day_sky_top: Color = Color.WHITE
var _day_sky_horizon: Color = Color.WHITE
var _day_ambient_color: Color = Color.WHITE
var _day_ambient_energy: float = 1.0
var _since_sync: float = 0.0
var _day_light_color: Color = DAY_LIGHT_COLOR

func _ready() -> void:
	var root: Node = get_parent()
	_light = root.get_node_or_null("World/Atmosphere/DirectionalLight3D") as DirectionalLight3D
	var env_node := root.get_node_or_null("World/Atmosphere/WorldEnvironment") as WorldEnvironment
	if env_node != null and env_node.environment != null:
		# Copies, so a second load of the world never starts from a night tint.
		_environment = env_node.environment.duplicate() as Environment
		env_node.environment = _environment
		_day_ambient_color = _environment.ambient_light_color
		_day_ambient_energy = _environment.ambient_light_energy
		if _environment.sky != null:
			_environment.sky = _environment.sky.duplicate() as Sky
			if _environment.sky.sky_material != null:
				_environment.sky.sky_material = _environment.sky.sky_material.duplicate()
			_sky = _environment.sky.sky_material as ProceduralSkyMaterial
	if _sky != null:
		_day_sky_top = _sky.sky_top_color
		_day_sky_horizon = _sky.sky_horizon_color
	if _light != null:
		_day_light_color = _light.light_color
	_apply()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		multiplayer.peer_connected.connect(func(id: int) -> void: _sync_time.rpc_id(id, time_of_day))

func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / DAY_SECONDS, 1.0)
	_apply()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_since_sync += delta
		if _since_sync >= SYNC_SECONDS:
			_since_sync = 0.0
			_sync_time.rpc(time_of_day)

func set_time(value: float) -> void:
	## Host/test: jump the clock and push it to clients.
	time_of_day = fposmod(value, 1.0)
	_apply()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_time.rpc(time_of_day)

func sun_elevation() -> float:
	## -1 (midnight) .. 1 (noon); 0 at sunrise and sunset.
	return sin(TAU * (time_of_day - 0.25))

func daylight() -> float:
	## 0 (full night) .. 1 (full day), easing through dawn and dusk.
	return smoothstep(-0.15, 0.3, sun_elevation())

func is_night() -> bool:
	return daylight() < 0.5

@rpc("authority", "call_remote", "reliable")
func _sync_time(value: float) -> void:
	time_of_day = value
	_apply()

func _apply() -> void:
	var day: float = daylight()
	if _light != null:
		var e: float = sun_elevation()
		# By night the light becomes a moon on the far side of the sky, so it
		# always shines downward.
		var pitch: float = maxf(asin(clampf(absf(e), 0.0, 1.0)), MIN_LIGHT_PITCH)
		var yaw: float = SUN_YAW if e >= 0.0 else SUN_YAW + PI
		_light.rotation = Vector3(-pitch, yaw, 0.0)
		_light.light_color = NIGHT_LIGHT_COLOR.lerp(_day_light_color, day)
		_light.light_energy = lerpf(NIGHT_LIGHT_ENERGY, DAY_LIGHT_ENERGY, day)
	if _sky != null:
		_sky.sky_top_color = NIGHT_SKY_TOP.lerp(_day_sky_top, day)
		_sky.sky_horizon_color = NIGHT_SKY_HORIZON.lerp(_day_sky_horizon, day)
	if _environment != null:
		_environment.ambient_light_color = NIGHT_AMBIENT_COLOR.lerp(_day_ambient_color, day)
		_environment.ambient_light_energy = lerpf(NIGHT_AMBIENT_ENERGY, _day_ambient_energy, day)
	time_changed.emit(time_of_day)
