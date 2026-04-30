class_name FactionPassiveDemonic extends FactionPassive

## Demonic passive — extra hit bursts.
##
## On each successful attack-connect, with `EXTRA_HIT_CHANCE` probability the
## target receives a delayed half-damage follow-up `DELAY_TICKS` later. The
## delayed hit is enqueued onto the *target* via `Actor._passive_queued_hits`
## and applied during their `_rollback_tick`. The queue lives on the actor so
## the same passive resource serves every Demonic actor without per-instance
## state.
##
## RNG note: `randf()` is intentionally non-deterministic across rollback
## resimulation. The queued hit lands on the host's authoritative pass; if a
## client resims a roll-back tick, they'll re-roll a different number — but
## the actual damage application is host-driven (queue + take_damage), so the
## visual divergence at most affects "did the visual sparkle fire on this
## tick" cosmetics, not the canonical damage. If this becomes an issue we can
## switch to a deterministic xorshift seeded by tick + attacker id.

const EXTRA_HIT_CHANCE: float = 0.25
const EXTRA_HIT_DAMAGE_RATIO: float = 0.5
const DELAY_TICKS: int = 4

func on_attack_connect(attacker: Actor, target: Actor, final_damage: int) -> void:
	if attacker == null or target == null or final_damage <= 0:
		return
	if not attacker.multiplayer.is_server():
		return
	# Guard against the "hit-spawned-by-our-own-passive triggers another
	# pass" cascade. The drain path tags re-applied damage with a transient
	# meta on the attacker; we skip the proc check when set.
	if attacker.has_meta(&"_passive_inhibit"):
		return
	if randf() > EXTRA_HIT_CHANCE:
		return
	var bonus: int = int(round(final_damage * EXTRA_HIT_DAMAGE_RATIO))
	if bonus <= 0:
		return
	target.queue_delayed_damage(bonus, attacker, DELAY_TICKS)
