class_name FactionPassiveFey extends FactionPassive

## Fey passive — bleeding vine DOT.
##
## On a successful hit, schedule N bleed ticks against the target via the
## actor's per-tick DOT queue (`Actor._dot_queue`). Each tick applies a small
## damage chunk. This is a TEMPORARY mechanism that lives on Actor — Tier G's
## proper `StatusEffect` system will replace it with a typed status pipeline
## (bleed becomes a `StatusEffect.tres` with its own visual + resistance hook).
## Migration is mechanical: drop `Actor.queue_dot` calls in favor of
## `StatusController.apply(actor, BLEED)` and remove this passive's hook
## body.

const BLEED_DAMAGE_PER_TICK: int = 5
const BLEED_INTERVAL_TICKS: int = 30
const BLEED_STACKS: int = 3

func on_attack_connect(attacker: Actor, target: Actor, final_damage: int) -> void:
	if attacker == null or target == null or final_damage <= 0:
		return
	if not attacker.multiplayer.is_server():
		return
	# Skip when the trigger is itself a delayed-damage application (avoids
	# bleed re-stacking infinitely from its own ticks).
	if attacker.has_meta(&"_passive_inhibit"):
		return
	for stack_idx in range(BLEED_STACKS):
		var delay: int = (stack_idx + 1) * BLEED_INTERVAL_TICKS
		target.queue_delayed_damage(BLEED_DAMAGE_PER_TICK, attacker, delay)
