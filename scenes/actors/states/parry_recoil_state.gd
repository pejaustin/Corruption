extends ActorState

## Forced recovery for an actor whose swing was just parried. Set up by
## scripts/combat/forced_recovery.gd from inside Actor.take_damage on the
## host the moment a parry resolves; clients reproduce the transition
## because state is in state_properties.
##
## Behaviour: action_locked + empty cancel_whitelist for the duration.
## Stagger-vulnerable so a follow-up swing during recoil punches through
## (the parry is supposed to set up a punish window). Self-exits to
## IdleState after `parry_recoil_ticks` ticks — read from the actor's
## `parry_recoil_ticks` meta when set, else falls back to
## ForcedRecovery.RECOVERY_TICKS_DEFAULT.
##
## Animation: prefer `parry_recoil` from the model's library; fall back to
## the configured `animation_name` (set to a stagger clip in the scene).

const PARRY_RECOIL_CLIP: StringName = &"parry_recoil"

var _enter_tick: int = -1
var _duration_ticks: int = 0

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_enter_tick = NetworkTime.tick
	# Read the stamped duration from the actor; default to 18 if absent.
	# The meta is set on host by ForcedRecovery.apply; clients see the state
	# transition but not the meta — that's fine because the duration is
	# cosmetic (tick comparison is the same).
	var configured: int = ForcedRecovery.RECOVERY_TICKS_DEFAULT
	if actor.has_meta(&"parry_recoil_ticks"):
		configured = actor.get_meta(&"parry_recoil_ticks", configured)
	_duration_ticks = max(1, configured)
	action_locked = true
	stagger_immune = false
	actor.velocity.x = 0
	actor.velocity.z = 0

func display_enter(_previous_state: RewindableState, _tick: int) -> void:
	_play_recoil_clip()

func exit(_next_state: RewindableState, _tick: int) -> void:
	_enter_tick = -1
	action_locked = false

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	if _enter_tick < 0:
		_enter_tick = NetworkTime.tick
		_duration_ticks = ForcedRecovery.RECOVERY_TICKS_DEFAULT
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
	if NetworkTime.tick - _enter_tick >= _duration_ticks:
		state_machine.transition(&"IdleState")

func _play_recoil_clip() -> void:
	var anim: AnimationPlayer = actor._animation_player
	if anim == null:
		return
	var library := _resolve_library_prefix()
	if library == "":
		return
	var full: String = "%s/%s" % [library, PARRY_RECOIL_CLIP]
	if anim.has_animation(full):
		anim.play(full)

func _resolve_library_prefix() -> String:
	var configured: String = animation_name
	var slash: int = configured.find("/")
	if slash <= 0:
		return ""
	return configured.substr(0, slash)
