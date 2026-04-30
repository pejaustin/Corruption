extends ActorState

## Long uninterruptible stagger entered when posture reaches max_posture.
## Marks the actor as ripostable for Tier D's heavy-attack-vs-broken-target
## logic. Self-exits after POSTURE_BROKEN_DURATION_TICKS unless a riposte
## interrupts (Tier D will transition out early when a riposte connects).
##
## Why a separate state from StaggerState:
## - StaggerState exits on `get_stagger_duration()` (~0.5s default) and is
##   cancellable by stagger_immune flags from animations. Posture-broken is
##   a longer, harder commitment — designers tune the duration via the
##   Actor.POSTURE_BROKEN_DURATION_TICKS constant, not per-actor stagger time.
## - StaggerState picks light/heavy hit-react clips from
##   `_last_damage_amount`. Posture break has its own animation (`posture_broken`)
##   that should always play regardless of incoming damage. Splitting the state
##   keeps the clip-pick logic simple in StaggerState and gives the broken
##   pose its own behavioural envelope.
##
## Networking: `state` is in state_properties on PlayerActor; clients see
## the broken state when host's gain_posture flips it. is_ripostable is a
## local flag — the host attacker reads its own copy of the victim's flag
## when running riposte gating. Setting it in enter()/exit() runs on every
## peer that sees the state change (because non-authority enters bypass
## enter() — wait, that's the non-rewindable transition; here transitions
## ARE rewindable so enter does fire on resim). Either way, when the host
## evaluates the riposte trigger, it does so via its own actor reference,
## which has the flag set deterministically.

const POSTURE_BROKEN_CLIP: StringName = &"posture_broken"
var _enter_tick: int = -1

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_enter_tick = NetworkTime.tick
	actor.is_ripostable = true
	action_locked = true
	stagger_immune = false  # i-frames don't apply — that's the punishment
	actor.velocity.x = 0
	actor.velocity.z = 0

func display_enter(_previous_state: RewindableState, _tick: int) -> void:
	_play_broken_clip()

func exit(_next_state: RewindableState, _tick: int) -> void:
	_enter_tick = -1
	actor.is_ripostable = false
	action_locked = false

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	# Non-authority peers skip enter(); re-latch on first tick. is_ripostable
	# is also re-asserted so the flag exists on every peer, not just host.
	if _enter_tick < 0:
		_enter_tick = NetworkTime.tick
		actor.is_ripostable = true
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
	var elapsed: int = NetworkTime.tick - _enter_tick
	if elapsed >= Actor.POSTURE_BROKEN_DURATION_TICKS:
		state_machine.transition(&"IdleState")

## Try the dedicated `posture_broken` clip; fall back to the configured
## animation_name (typically the stagger or death pose) when missing. The
## state never crashes if the clip isn't authored.
func _play_broken_clip() -> void:
	var anim: AnimationPlayer = actor._animation_player
	if anim == null:
		return
	var library := _resolve_library_prefix()
	if library == "":
		return
	var full: String = "%s/%s" % [library, POSTURE_BROKEN_CLIP]
	if anim.has_animation(full):
		anim.play(full)

func _resolve_library_prefix() -> String:
	var configured: String = animation_name
	var slash: int = configured.find("/")
	if slash <= 0:
		return ""
	return configured.substr(0, slash)
