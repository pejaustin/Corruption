class_name RitualData extends Resource

## An Eldritch ritual. Authored as .tres files under res://data/rituals/.
## The RitualSite scene takes one via @export and applies its effect on
## completion. State lives on GameState / MinionManager / TerritoryManager
## as typed fields (not metadata).

enum Effect {
	DOMINATION_MASTERY, ## Halves domination cost for the completing peer for the match.
	CORRUPTION_SURGE,   ## Doubles corruption spread for the completing peer for `duration` seconds.
	ELDRITCH_VISION,    ## Reveals enemy minions to the completing peer for `duration` seconds.
}

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var effect: Effect = Effect.DOMINATION_MASTERY
@export var channel_time: float = 5.0

@export_group("Tuning")
## Discount multiplier applied to domination cost (0.5 = 50% off). Used by DOMINATION_MASTERY.
@export var domination_discount: float = 0.5
## How long timed effects last, in seconds. Ignored by permanent effects.
@export var duration: float = 60.0
