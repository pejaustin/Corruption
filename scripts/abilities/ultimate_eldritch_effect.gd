class_name UltimateEldritchEffect extends AbilityEffect

## Tier E — Eldritch ultimate placeholder. Long-range AoE: applies a movement
## slow to every hostile actor in a wide cone in front of the caster. Reuses
## Actor.apply_movement_slow (the same plumbing the Eldritch passive's
## third-strike proc uses). Designers should swap effect_scene for a richer
## boss-tier mind-tear visual when art lands.

const RANGE: float = 18.0
const CONE_ANGLE_DEG: float = 75.0
const SLOW_MULTIPLIER: float = 0.5
const SLOW_DURATION_TICKS: int = 90

func _on_activate() -> void:
	if caster == null:
		return
	if not multiplayer.is_server():
		return
	var caster_actor := caster as Actor
	if caster_actor == null:
		return
	var forward := -caster_actor.global_basis.z
	# Pull every other actor in the scene; cheap enough at scale we ship.
	# Tier G's StatusEffect system will offer a more elegant query path.
	for n in get_tree().get_nodes_in_group(&"actors"):
		var a := n as Actor
		if a == null or a == caster_actor:
			continue
		if not a.is_hostile_to(caster_actor):
			continue
		var to_target := a.global_position - caster_actor.global_position
		if to_target.length() > RANGE:
			continue
		var dir := to_target.normalized()
		var angle := rad_to_deg(forward.angle_to(dir))
		if angle > CONE_ANGLE_DEG:
			continue
		a.apply_movement_slow(SLOW_MULTIPLIER, SLOW_DURATION_TICKS)
