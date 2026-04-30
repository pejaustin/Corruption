extends PlayerState

## Held-button defensive guard. While in this state and facing the attacker,
## incoming damage is reduced by BLOCK_DAMAGE_REDUCTION (host-side, in
## Actor.take_damage). If a hit lands within PARRY_WINDOW_TICKS of entry,
## the host promotes the block into a parry — see Actor.take_damage and
## scripts/combat/forced_recovery.gd.
##
## Action-gating: action_locked = true while held, cancel_whitelist allows
## RollState (which becomes a backstep when entered from BlockState — see
## RollState._roll_dir computation) so the player can disengage on demand.
##
## Networking: BlockState's enter is run on every peer that resimulates the
## tick (see netfox-reference §2). On enter we latch
## actor.block_press_tick = NetworkTime.tick, which IS in the avatar's
## state_properties, so the host's hit-application logic on tick T+N can
## query the same value clients carried. That's what makes parry causality
## host-authoritative + rollback-deterministic.

## Block clip suffixes; resolved against the library prefix from
## `animation_name`. Falls back silently when missing — the state runs
## correctly even with no `block_*` clips authored, you just won't see the
## guard pose.
const BLOCK_ENTER_CLIP: StringName = &"block_enter"
const BLOCK_LOOP_CLIP: StringName = &"block_loop"
## Local-only "I'm in this state" marker — survives non-authority's skipped
## enter() since clients also re-latch on first tick.
var _enter_tick: int = -1

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_enter_tick = NetworkTime.tick
	# Stamp the press tick into the actor as a state_property so the host's
	# hit-application logic on a later tick can check the parry window. This
	# is the heart of Tier C's parry causality — see the doc's risk callout
	# and netfox-reference.md §5.
	actor.block_press_tick = NetworkTime.tick
	action_locked = true
	# Allow Roll / Backstep to break out of guard. Cancel_whitelist is per-
	# state and runs through Actor.try_transition, so the held-block grammar
	# stays clean: block-and-roll = backstep, block-and-release-then-roll =
	# normal roll. Both consume the press buffer in try_roll/try_block.
	cancel_whitelist = [&"RollState", &"BackstepState"]
	actor.velocity.x = 0
	actor.velocity.z = 0

func display_enter(_previous_state: RewindableState, _tick: int) -> void:
	_play_block_clip(true)

func exit(_next_state: RewindableState, _tick: int) -> void:
	# Don't clear block_press_tick on exit — late hits resolved a few ticks
	# after release should still be considered for the parry check on the
	# host. block_press_tick naturally ages out when the window expires
	# (NetworkTime.tick - block_press_tick > PARRY_WINDOW_TICKS).
	_enter_tick = -1
	action_locked = false

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	# Non-authority peers bypass enter(); re-latch on first tick.
	if _enter_tick < 0:
		_enter_tick = NetworkTime.tick
	# Block doesn't glide — zero horizontal velocity each tick. Allow gravity
	# to land us if we entered mid-air; physics_move handles the rest.
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
	# Posture-broken transition is host-driven inside gain_posture; we just
	# yield naturally next tick once the state machine flips.
	# Released?
	if not _is_block_held():
		# Roll buffered during block becomes a backstep — handled by RollState.
		if try_roll():
			return
		state_machine.transition(&"IdleState")
		return
	# Roll-cancel mid-block (typed Souls verb). RollState will pick a
	# backstep when input is empty and/or block was held.
	if try_roll():
		return

func _is_block_held() -> bool:
	return player.avatar_input.block_input

## Pick the right block clip — block_enter on first tick, block_loop after
## the enter clip's natural length elapses. Falls back silently to the
## configured animation_name (typically the stagger clip) if either is
## missing. Local-only; not gated against rollback because we early-return
## when AnimationPlayer is missing.
func _play_block_clip(initial: bool) -> void:
	var anim: AnimationPlayer = actor._animation_player
	if anim == null:
		return
	var library := _resolve_library_prefix()
	if library == "":
		return
	var clip_suffix: StringName = BLOCK_ENTER_CLIP if initial else BLOCK_LOOP_CLIP
	var full: String = "%s/%s" % [library, clip_suffix]
	if anim.has_animation(full):
		anim.play(full)

func _resolve_library_prefix() -> String:
	var configured: String = animation_name
	var slash: int = configured.find("/")
	if slash <= 0:
		return ""
	return configured.substr(0, slash)
