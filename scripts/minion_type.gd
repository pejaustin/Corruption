class_name MinionType extends Resource

## Data describing a single minion variant (skeleton, imp, wisp, etc).
## Authored as .tres files under res://data/minions/.
## Shared across all instances by default. Call duplicate_for_match()
## when spawning a minion so per-instance buffs (upgrades, domination)
## cannot bleed back to the on-disk resource.

@export var id: StringName
@export var display_name: String
@export var faction: GameConstants.Faction = GameConstants.Faction.NEUTRAL

@export_group("Stats")
@export var hp: int = 40
@export var damage: int = 10
@export var speed: float = 3.5
@export var cost: int = 8

@export_group("Combat Tuning")
@export var aggro_radius: float = 8.0
@export var attack_range: float = 1.8
@export var attack_cooldown: float = 1.5

@export_group("Presentation")
@export var color: Color = Color.WHITE
@export var icon: Texture2D
## Visual-only model for the war-table ghost popup (and any future "show me a
## little version of this minion" affordance). Lightweight by design — no
## physics, no nav agent, no state machine. Leave null to fall back to the
## chess-piece cylinder.
@export var model_scene: PackedScene

@export_group("Behavior")
## Trait-tag consumed by minion AI and MinionManager (raise_dead, stealth, dominate, ...).
@export var trait_tag: StringName
## How many distinct sub-orders a courier of this type can carry per outing.
## Read by KnowledgeManager._dispatch_entries to batch readied entries into the
## fewest couriers. A "sub-order" is one (source cluster, target_pos, minion
## set) tuple — N minions in the same stack getting the same target counts as
## one sub-order; the same minions getting different targets is N sub-orders.
## Couriers with max_orders = 1 behave like the pre-batching version (one
## courier per entry); higher values allow advanced couriers to deliver
## multiple distinct orders, potentially across multiple source clusters, in a
## single outing. Ignored on non-courier minion types.
@export var max_orders: int = 1
## How far (world meters) a courier of this type can "see" on arrival to
## confirm the targeted minions are at the believed location. If none of the
## targets are within this radius, the courier loiters for courier_wait_seconds
## hoping they wander back, then heads home with a "missing" report so the
## overlord knows their belief was stale.
@export var courier_visual_range: float = 6.0
## Seconds a courier loiters at a leg's source when the targeted minions
## aren't visible on arrival. The courier keeps re-checking each tick during
## the wait, so a minion that walks into range mid-wait still gets the order.
@export var courier_wait_seconds: float = 4.0

@export_group("Retreat")
## When true, this minion's combat states yield to RetreatState once HP drops
## below retreat_hp_threshold. Opt-in — most fighters fight to the death; only
## minions whose role includes "carry intel home" (some scouts, info-couriers,
## retreat-trained warband units) flip this on. Couriers / advisors / bosses
## leave it false because their state machines own their own retreat semantics
## or aren't retreat-shaped at all.
@export var can_retreat: bool = false
## Fraction of max HP at or below which a retreat-capable minion breaks off
## and heads home. 0.3 = retreat at 30% HP. Ignored when can_retreat is false.
@export var retreat_hp_threshold: float = 0.3

func duplicate_for_match() -> MinionType:
	## Return a match-local copy safe to mutate (upgrades, buffs, domination).
	return duplicate(true) as MinionType
