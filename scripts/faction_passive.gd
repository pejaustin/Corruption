class_name FactionPassive extends Resource

## Tier E — base class for per-faction combat passives. Subclasses implement
## one or more of the hooks below; data-only fields go on `.tres` instances
## under `data/factions/passives/`.
##
## Hook contract:
## - `on_attack_connect` — called on the ATTACKER's faction passive, on the
##   host that authoritatively resolved the hit, AFTER block/parry resolution
##   and AFTER `final_damage` is computed but BEFORE animations resolve. Skip
##   if `final_damage <= 0` (parried/zeroed hits).
## - `on_take_damage` — called on the VICTIM's faction passive, host-side,
##   AFTER final_damage is computed and BEFORE HP is mutated. (Currently
##   unused by shipped passives but reserved for "thorns" / damage-on-hurt
##   designs.)
## - `on_kill` — called on the KILLER's faction passive when the victim's HP
##   drops to 0 from a hit they dealt. Host-side, before any
##   ownership/respawn fallout.
## - `on_tick` — called every rollback tick on the actor's own passive.
##   Reserved for ramping buffs / charge accrual that shouldn't live on a
##   state. Default no-op; keep allocations out.
##
## Resource is a SHARED instance per faction (loaded once via `FactionData`).
## Per-instance mutable counters (e.g. Eldritch's third-strike counter) MUST
## live on the actor, not on the passive — otherwise multiple actors of the
## same faction stomp each other. Subclasses store transient state in actor
## meta or actor fields and document which ones.

@export var id: StringName = &""
@export var display_name: String = ""

## Called after an attacker's hit has landed (final_damage > 0). Default no-op.
func on_attack_connect(_attacker: Actor, _target: Actor, _final_damage: int) -> void:
	pass

## Called when the actor takes damage, after block/parry resolution. Default no-op.
func on_take_damage(_actor: Actor, _amount: int, _source: Node) -> void:
	pass

## Called when this actor's hit reduced a target to 0 HP. Default no-op.
func on_kill(_actor: Actor, _target: Actor) -> void:
	pass

## Called every rollback tick on the owning actor. Default no-op. Don't
## allocate; this runs at netfox tick rate.
func on_tick(_actor: Actor, _delta: float) -> void:
	pass
