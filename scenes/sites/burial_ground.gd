class_name BurialGround extends Node3D

## A burial ground (Austin, 2026-10-12). Not a POI of its own: it belongs to a
## parent site (temples have crypts, runestones ancient battlefields, towns
## graveyards) and whoever holds the parent mines it. Each mined body is one
## remains at the holder's tower, raised there into a troop. Different kinds
## make different troops: `troop_trait`, set per burial ground.
## Burial grounds have no Paladin encounter. Place one as a child of its
## parent CorruptionSite. Host-authoritative.

signal mined(peer_id: int, troop_trait: StringName)

enum Kind { CRYPT, ANCIENT_BATTLEFIELD, GRAVEYARD }

const GROUP: StringName = &"burial_grounds"

@export var kind: Kind = Kind.CRYPT
## What troops raised from here start with. PLACEHOLDER: default, not designed
## (Austin's to set per burial ground).
@export var troop_trait: StringName = &"placeholder_trait"
## PLACEHOLDER: tuning — seconds per body mined while the parent is held.
@export var mine_seconds: float = 30.0
## PLACEHOLDER: tuning — bodies in the ground.
@export var capacity: int = 20

var bodies_left: int = 0

@onready var _mine_timer: Timer = $MineTimer

func _ready() -> void:
	add_to_group(GROUP)
	bodies_left = capacity
	_mine_timer.wait_time = mine_seconds
	_mine_timer.timeout.connect(_on_mine)
	if multiplayer.is_server():
		_mine_timer.start()

func get_parent_site() -> CorruptionSite:
	return get_parent() as CorruptionSite

func get_holder() -> int:
	## Whoever holds the parent site mines this ground (-1 = nobody).
	var site := get_parent_site()
	if site == null or site.unusable:
		return -1
	return site.holder_peer_id

func _on_mine() -> void:
	if not multiplayer.is_server() or bodies_left <= 0:
		return
	var holder := get_holder()
	if holder <= 0:
		return
	var mm := get_tree().current_scene.get_node_or_null(^"MinionManager") as MinionManager
	if mm == null:
		return
	bodies_left -= 1
	mm.add_remains(holder, 1)
	mined.emit(holder, troop_trait)
