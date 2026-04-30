extends ActorState

## Tier D — riposte (execution) victim side. Forced into this state by
## RiposteAttackerState's host-authoritative transition, mirroring the
## ForcedRecovery pattern from Tier C. Plays a paired animation, holds the
## victim still, and exits naturally when the animation finishes (the
## attacker's hitbox-on-active-frame deals the actual damage via the normal
## take_damage path).
##
## The victim's body locks for the duration — `action_locked = true`,
## empty `cancel_whitelist`. Stagger-vulnerable (the riposte hit lands here),
## but the attacker's swing is the only thing in the air during the snap-in,
## so vulnerability is purely cosmetic.
##
## Animation: prefer `<library>/riposte_victim`; fall back to configured
## `animation_name` (typically `posture_broken` or `Stagger`).
##
## This state lives in `scenes/actors/states/` (not the player-only path)
## because riposte targets can include MinionActors with the right state
## machine wired in. Generic ActorState extension keeps it reusable.

const RIPOSTE_VICTIM_CLIP: StringName = &"riposte_victim"
## Default duration if no animation player is present (host-authoritative
## fallback). Matches a typical riposte clip length at 30Hz.
const VICTIM_DURATION_TICKS: int = 30

var _enter_tick: int = -1

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_enter_tick = NetworkTime.tick
	action_locked = true
	stagger_immune = false  # the riposte's damage hits here
	actor.velocity.x = 0
	actor.velocity.z = 0
	# Posture state is reset; the riposte consumes the broken-window.
	actor.is_ripostable = false

func display_enter(_previous_state: RewindableState, _tick: int) -> void:
	_play_victim_clip()

func exit(_next_state: RewindableState, _tick: int) -> void:
	_enter_tick = -1
	action_locked = false

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	if _enter_tick < 0:
		_enter_tick = NetworkTime.tick
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
	# Time out either by animation progress or by tick budget — whichever
	# comes first. The animation timing wins when art is authored; the tick
	# budget is the safety net when fallback clips finish too quickly.
	var anim_done: bool = false
	if actor._animation_player:
		var len: float = actor._animation_player.current_animation_length
		if len > 0.0:
			anim_done = actor._animation_player.current_animation_position >= len
	var elapsed: int = NetworkTime.tick - _enter_tick
	if anim_done or elapsed >= VICTIM_DURATION_TICKS:
		state_machine.transition(&"IdleState")

func _play_victim_clip() -> void:
	var anim: AnimationPlayer = actor._animation_player
	if anim == null:
		return
	var library := _resolve_library_prefix()
	if library != "":
		var full: String = "%s/%s" % [library, RIPOSTE_VICTIM_CLIP]
		if anim.has_animation(full):
			anim.play(full)
			return
	# Fallback to configured animation_name.
	if animation_name != "" and anim.has_animation(animation_name):
		anim.play(animation_name)

func _resolve_library_prefix() -> String:
	var configured: String = animation_name
	var slash: int = configured.find("/")
	if slash <= 0:
		return ""
	return configured.substr(0, slash)
