class_name FactionPassiveUndeath extends FactionPassive

## Undeath passive — sustain through attrition.
##
## - `on_attack_connect`: the attacker recovers `LIFESTEAL_RATIO` × final_damage
##   as HP. Stacks additively with the LifeDrainEffect ability (lifesteal
##   ability ratio is separate; both fire on the same hit if both are active).
## - `on_kill`: full-kill bonus heal of `KILL_HEAL_AMOUNT`. Caps at max_hp.
##
## All effects mutate `attacker.hp` host-side; the rollback synchronizer
## carries `hp` into clients on the next tick. No resimulation hazard — the
## damage hook itself runs inside the host's `take_damage`, which is the
## authoritative point of HP application.

const LIFESTEAL_RATIO: float = 0.05
const KILL_HEAL_AMOUNT: int = 30

func on_attack_connect(attacker: Actor, _target: Actor, final_damage: int) -> void:
	if attacker == null or final_damage <= 0:
		return
	# Skip lifesteal on delayed-damage re-entry — the original hit already
	# healed; re-applying on each follow-up tick would feel feels weird (small
	## numbers but stacking) and isn't intentional.
	if attacker.has_meta(&"_passive_inhibit"):
		return
	var heal: int = int(round(final_damage * LIFESTEAL_RATIO))
	if heal <= 0:
		return
	attacker.hp = min(attacker.hp + heal, attacker.get_max_hp())
	attacker.hp_changed.emit(attacker.hp)

func on_kill(attacker: Actor, _target: Actor) -> void:
	if attacker == null:
		return
	attacker.hp = min(attacker.hp + KILL_HEAL_AMOUNT, attacker.get_max_hp())
	attacker.hp_changed.emit(attacker.hp)
