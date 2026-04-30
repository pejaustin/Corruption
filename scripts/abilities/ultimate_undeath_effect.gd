class_name UltimateUndeathEffect extends AbilityEffect

## Tier E — Undeath ultimate placeholder.
## Big self-heal on cast + 5s lifesteal window. The lifesteal is reused from
## the LifeDrainEffect path (grants_lifesteal returns true). When richer
## visuals / mechanics are authored, swap the `effect_scene` on
## `data/abilities/ultimate_undeath.tres` to point at the new scene.

const HEAL_AMOUNT: int = 100
const DURATION: float = 5.0

func _on_activate() -> void:
	duration = DURATION
	var actor := caster as Actor
	if actor == null:
		return
	if not actor.multiplayer.is_server():
		return
	actor.hp = min(actor.hp + HEAL_AMOUNT, actor.get_max_hp())
	actor.hp_changed.emit(actor.hp)

func grants_lifesteal() -> bool:
	return true
