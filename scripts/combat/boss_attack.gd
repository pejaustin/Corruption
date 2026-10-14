class_name BossAttack extends Resource

## One heavy, telegraphed attack of a boss form (GDD §8 "Combat" C9): a windup
## the other players can read, a short hit window, then a long recovery. Pure
## data; BossActor and BossAttackState play it.
## PLACEHOLDER: every attack, name and number in data/bosses/placeholder/ is
## a stand-in, not designed.

enum Phase { WINDUP, ACTIVE, RECOVERY, DONE }

## Shown over the boss during the windup.
@export var display_name: String = ""
## The input action that throws it.
@export var input_action: StringName = &""
@export var windup_seconds: float = 1.0
@export var active_seconds: float = 0.25
@export var recovery_seconds: float = 1.0
## Multiplies the boss's own attack damage.
@export var damage_multiplier: float = 3.0
## How far in front of the boss the blow reaches, and how wide it is (metres).
@export var reach: float = 4.0
@export var width: float = 3.0

func total_seconds() -> float:
	return windup_seconds + active_seconds + recovery_seconds

func phase_at(elapsed: float) -> Phase:
	if elapsed < windup_seconds:
		return Phase.WINDUP
	if elapsed < windup_seconds + active_seconds:
		return Phase.ACTIVE
	if elapsed < total_seconds():
		return Phase.RECOVERY
	return Phase.DONE
