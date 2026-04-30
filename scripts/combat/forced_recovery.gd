class_name ForcedRecovery extends Object

## Authoritative parry consequence for the attacking actor.
##
## Resolution: when `Actor.take_damage` detects a parry (victim is in
## BlockState's parry window AND faces the source), it calls
## ForcedRecovery.apply(attacker). On the host, this transitions the attacker
## into ParryRecoilState directly. The state itself is rollback-synced (it's
## a member of the RewindableStateMachine), so clients reproduce the
## transition deterministically the next time they replay the tick.
##
## Why a state, not a stand-alone action_locked flag:
## - `action_locked` is per-state, not on the actor. To carry forced lock
##   across "whatever state the attacker is in right now", we'd have to push
##   it into Actor properties and then re-establish it after every transition.
## - A dedicated state with `action_locked = true` and an empty
##   `cancel_whitelist` is the clean expression of "you cannot do anything
##   for N ticks." Visually it ties to a `parry_recoil` animation when art
##   lands; without art it falls back to the configured `animation_name`
##   (typically the stagger clip). The state itself self-exits to IdleState
##   after RECOVERY_TICKS_DEFAULT ticks.
##
## Contract: only call from the host (server). The state's `enter()` runs on
## every peer when the state is replicated, so animation/SFX hooks fire
## everywhere; the host-side call is what authoritatively flips the
## attacker's state. There is no separate RPC because the state machine's
## `state` is a `state_property` already.

const RECOVERY_TICKS_DEFAULT: int = 18  # 0.6s at netfox 30Hz

## Force `target_actor` into ParryRecoilState for `ticks` ticks. Host-only.
## Non-actor targets and dead actors are skipped silently. The desired tick
## count is passed via the actor's `parry_recoil_ticks` meta so the state
## can read it on enter; default ticks come from RECOVERY_TICKS_DEFAULT.
##
## If the attacker's state machine doesn't carry a ParryRecoilState (e.g. a
## generic minion that hasn't opted into the parry-able stack), the call is
## a no-op rather than a crash. The parry's other consequences (zero damage
## to victim, posture spike on attacker via gain_posture) still applied.
static func apply(target_actor: Actor, ticks: int = RECOVERY_TICKS_DEFAULT) -> void:
	if target_actor == null or not is_instance_valid(target_actor):
		return
	if target_actor.hp <= 0:
		return
	if target_actor._state_machine == null:
		return
	if target_actor._state_machine.get_node_or_null(^"ParryRecoilState") == null:
		return
	# Stamp the duration on the actor so ParryRecoilState can read it without
	# coupling to ForcedRecovery. The stamp is local — clients use the default
	# duration on resim, which is fine because a parry is a one-shot event and
	# the duration here is purely cosmetic (the state syncs as state_property).
	target_actor.set_meta(&"parry_recoil_ticks", ticks)
	# Bypass action_locked / cancel_whitelist on the attacker's current state —
	# parry is supposed to crack through whatever swing they were committed to.
	target_actor._state_machine.transition(&"ParryRecoilState")
