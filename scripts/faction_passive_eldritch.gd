class_name FactionPassiveEldritch extends FactionPassive

## Eldritch passive — every Nth strike applies a movement slow.
##
## Counter is per-attacker, stored as actor meta `_eldritch_strike_counter`.
## (We can't put it on the passive itself — passives are shared across all
## actors of the same faction.) Counter resets to 0 on kill so each victim
## gets their own ramp-up.
##
## The slow is applied via the target's `_eldritch_slow_until_tick` field on
## Actor (Tier E). Movement states multiply their walk/run velocity by
## `Actor.get_movement_speed_mult()` which checks the slow timer.

const STRIKES_PER_PROC: int = 3
const SLOW_DURATION_TICKS: int = 60
const SLOW_MULTIPLIER: float = 0.75

func on_attack_connect(attacker: Actor, target: Actor, final_damage: int) -> void:
	if attacker == null or target == null or final_damage <= 0:
		return
	if not attacker.multiplayer.is_server():
		return
	# Skip counter advancement on delayed-damage re-entry.
	if attacker.has_meta(&"_passive_inhibit"):
		return
	var counter: int = int(attacker.get_meta(&"_eldritch_strike_counter", 0))
	counter += 1
	if counter < STRIKES_PER_PROC:
		attacker.set_meta(&"_eldritch_strike_counter", counter)
		return
	# Proc!
	attacker.set_meta(&"_eldritch_strike_counter", 0)
	target.apply_movement_slow(SLOW_MULTIPLIER, SLOW_DURATION_TICKS)

func on_kill(attacker: Actor, _target: Actor) -> void:
	if attacker == null:
		return
	# Reset the strike counter so each fresh engagement ramps to a new proc.
	attacker.set_meta(&"_eldritch_strike_counter", 0)
