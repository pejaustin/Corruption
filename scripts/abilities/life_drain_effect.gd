# PLACEHOLDER: ability not designed by Austin (Austin, 2026-10-14: every ability currently defined is a placeholder): what it does and its numbers.
class_name LifeDrainEffect extends AbilityEffect

## Undeath: Avatar attacks lifesteal for 5 seconds.

const DURATION: float = 5.0

func _on_activate() -> void:
	duration = DURATION

func grants_lifesteal() -> bool:
	return true
