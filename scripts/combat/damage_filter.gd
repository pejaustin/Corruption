class_name DamageFilter

## Tier F — central gate for "should this damage be allowed?".
##
## Called from any damage-application site (attack hitboxes on the avatar and
## minion sides; ability AoEs; anywhere `take_damage` is fired with a known
## attacker). Returning `false` blocks the damage; returning `true` allows it.
##
## Default policy is permissive: only blocks the case where friendly fire is
## OFF and the attacker + victim share a controlling peer or share a faction.
## The avatar-combat doc leans "FF on" for the dark-lord 4-way; the global
## toggle lives on `GameState.friendly_fire_enabled` so designers can A/B
## without editing code. See `docs/technical/tier-f-implementation.md` § FF.
##
## All callers SHOULD pipe through this helper. Skipping the gate means the FF
## flag won't be honored on that path. Self-damage (source == victim) and
## unattributed damage (source == null) always pass — those legacy paths exist
## for ability self-effects, environmental hazards, and the `incoming_damage`
## leg that doesn't carry actor refs.
##
## Static-only — no instance state.

## Resolve the controlling peer id of an actor for FF comparison. Avatars
## carry `controlling_peer_id`; minions carry `owner_peer_id`. Returns -1
## when neither resolves (neutral mob, environmental damage source).
static func resolve_owning_peer(actor: Node) -> int:
	if actor == null:
		return -1
	var pid: Variant = actor.get(&"controlling_peer_id")
	if pid is int and int(pid) > 0:
		return int(pid)
	pid = actor.get(&"owner_peer_id")
	if pid is int and int(pid) > 0:
		return int(pid)
	return -1

## Resolve the faction of an actor. Falls back to NEUTRAL when the actor
## has no `faction` field (shouldn't happen for combat actors, but the guard
## is cheap and keeps the gate from crashing on partial subtypes).
static func resolve_faction(actor: Node) -> int:
	if actor == null:
		return GameConstants.Faction.NEUTRAL
	var f: Variant = actor.get(&"faction")
	if f is int:
		return int(f)
	return GameConstants.Faction.NEUTRAL

## Returns true iff damage from `attacker` to `victim` should be applied.
## Default: allow. Blocks only when `GameState.friendly_fire_enabled == false`
## AND attacker/victim share an owning peer OR share a non-neutral faction.
## See module docstring for full rules.
static func allow(attacker: Node, victim: Node) -> bool:
	# Unknown attacker — legacy / environmental / self-effect paths all pass.
	if attacker == null:
		return true
	# Self-damage always passes (ability AoE catching the caster, etc.).
	if attacker == victim:
		return true
	# FF on (default) — every attacker damages every victim.
	if GameState.friendly_fire_enabled:
		return true
	# FF off — block same-peer or same-faction (non-neutral) damage.
	var atk_peer: int = resolve_owning_peer(attacker)
	var vic_peer: int = resolve_owning_peer(victim)
	if atk_peer > 0 and vic_peer > 0 and atk_peer == vic_peer:
		return false
	var atk_faction: int = resolve_faction(attacker)
	var vic_faction: int = resolve_faction(victim)
	if atk_faction == GameConstants.Faction.NEUTRAL or vic_faction == GameConstants.Faction.NEUTRAL:
		return true
	if atk_faction == vic_faction:
		return false
	return true
