class_name UltimateDemonicEffect extends AbilityEffect

## Tier E — Demonic ultimate placeholder. 5-second damage buff (×2.5).
## Designers should swap the `effect_scene` on
## `data/abilities/ultimate_demonic.tres` for one that adds an AoE shockwave
## on cast + visuals when art lands.

const DAMAGE_MULT: float = 2.5
const DURATION: float = 5.0

func _on_activate() -> void:
	duration = DURATION

func get_damage_multiplier() -> float:
	return DAMAGE_MULT
