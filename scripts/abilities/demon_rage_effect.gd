class_name DemonRageEffect extends AbilityEffect

## Demonic: double Avatar damage for 8 seconds.

const DAMAGE_MULT: float = 2.0
const DURATION: float = 8.0

func _on_activate() -> void:
	duration = DURATION

func get_damage_multiplier() -> float:
	return DAMAGE_MULT
