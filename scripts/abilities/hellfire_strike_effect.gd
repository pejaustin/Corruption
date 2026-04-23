class_name HellfireStrikeEffect extends AbilityEffect

## Demonic: next Avatar attack deals 3x damage. Consumed on attack.
## Duration is a safety window so a missed strike doesn't buff forever.

const DAMAGE_MULT: float = 3.0
const WINDOW: float = 10.0

func _on_activate() -> void:
	duration = WINDOW

func get_damage_multiplier() -> float:
	return DAMAGE_MULT

func consume_on_damage_query() -> bool:
	return true
