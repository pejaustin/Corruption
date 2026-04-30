class_name PostureBar extends Control

## Sekiro-style posture meter readout. Rolls up the actor's `posture /
## max_posture` ratio into a `ProgressBar` value each frame. Local-only —
## this script does not write any gameplay state.
##
## Tier C ships the bar with no fixed placement in the live HUD: it lives
## in `scenes/ui/posture_bar.tscn` and exists in scene/test contexts as a
## standalone node. Wiring it into AvatarHUD is left to the user (drop the
## .tscn under `AvatarHUD` and it auto-binds to its parent's parent's actor
## via `_resolve_actor`). See docs/technical/tier-c-implementation.md.

## Color when the meter is in the "almost broken" warning band — ramps to
## this from the resting tone.
const PULSE_NEAR_BREAK_COLOR: Color = Color(1.0, 0.4, 0.2, 1.0)
const RESTING_COLOR: Color = Color(0.95, 0.55, 0.15, 1.0)
## Posture distance from max_posture below which the bar pulses.
const PULSE_THRESHOLD: int = 5
## Pulse speed in Hz (cycles per second).
const PULSE_HZ: float = 4.0

## Optional explicit binding. Leave empty to auto-resolve via _resolve_actor.
@export var target_actor: Actor

@onready var _bar: ProgressBar = %ProgressBar

var _pulse_time: float = 0.0

func _ready() -> void:
	if target_actor == null:
		target_actor = _resolve_actor()
	if _bar:
		_bar.min_value = 0
		_bar.max_value = 100  # Replaced from target_actor.max_posture in _process.
		_bar.show_percentage = false

func _process(delta: float) -> void:
	if target_actor == null or not is_instance_valid(target_actor):
		visible = false
		return
	if _bar == null:
		return
	visible = true
	if _bar.max_value != target_actor.max_posture:
		_bar.max_value = target_actor.max_posture
	_bar.value = target_actor.posture
	# Pulse near break — local cosmetic, never enters rollback state. The
	# pulse runs on real time; under heavy lag the visual mismatches the
	# rollback-driven posture by a frame or two, but the bar itself lerps to
	# whatever the synced posture says, so the pulse just rides on top.
	var distance_from_max: int = target_actor.max_posture - target_actor.posture
	var modulate_color: Color = RESTING_COLOR
	if distance_from_max <= PULSE_THRESHOLD and target_actor.posture > 0:
		_pulse_time += delta * PULSE_HZ * TAU
		var t: float = (sin(_pulse_time) + 1.0) * 0.5
		modulate_color = RESTING_COLOR.lerp(PULSE_NEAR_BREAK_COLOR, t)
	else:
		_pulse_time = 0.0
	_bar.modulate = modulate_color

## Auto-resolve: walk up the parent chain looking for the nearest Actor.
## When the bar is dropped under AvatarHUD (which is under AvatarActor), this
## finds the avatar without explicit wiring. Falls back to null if no actor
## ancestor exists, which makes the bar invisible.
func _resolve_actor() -> Actor:
	var n: Node = get_parent()
	while n:
		if n is Actor:
			return n as Actor
		n = n.get_parent()
	return null
