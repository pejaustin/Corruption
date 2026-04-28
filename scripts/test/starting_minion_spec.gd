@tool
class_name StartingMinionSpec extends Marker3D

## Editor-authored placement spec for a single starter minion in a test scene.
## Drop instances of this node under StartingMinions in the test scene tree,
## position the marker where you want the minion to spawn, and pick the
## type/faction/owner from the inspector. The test controller iterates these
## children on _ready and calls MinionManager._spawn_minion_rpc once per spec.

## MinionType.id for the minion to spawn (skeleton, imp, sprite, cultist,
## ghoul, hellhound, neutral_zombie, etc.). Must exist in
## res://data/minion_catalog.tres.
@export var type_id: StringName = &"skeleton"

## Faction the spawned minion belongs to. Determines piece color on the table
## and which overlord considers it friendly.
@export var faction: int = GameConstants.Faction.UNDEATH

## Peer that owns the minion (-1 for neutral / world enemies). The local
## overlord in the test scene is peer 1.
@export var owner_peer_id: int = 1
