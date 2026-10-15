class_name BossBar
extends CanvasLayer

## The boss's health along the bottom of the screen, Souls style (Austin, 2026-10-14), shown to the
## peer driving the Paladin while this boss is a live foe within SHOW_RANGE. Its own player sees
## BossHUD instead. A passive view; it never writes gameplay state.

## PLACEHOLDER: tuning — metres from the Paladin within which the bar shows.
const SHOW_RANGE: float = 30.0
## PLACEHOLDER: wording — the name over the bar (the boss's player).
const NAME_FORMAT: String = "%s"

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _name_label: Label = %NameLabel

var _boss: BossActor = null

func _ready() -> void:
	_boss = get_parent() as BossActor
	if _boss == null:
		queue_free()
		return
	_name_label.text = NAME_FORMAT % GameState.get_player_name(_boss.owner_peer_id)
	visible = false

func _process(_delta: float) -> void:
	visible = should_show()
	# Read every frame: this bar is ready before its boss sets his HP, and HP set by rollback emits nothing.
	_health_bar.max_value = _boss.get_max_hp()
	_health_bar.value = _boss.hp

func should_show() -> bool:
	if _boss.hp <= 0 or GameState.avatar_peer_id != multiplayer.get_unique_id():
		return false
	var avatar := get_tree().current_scene.get_node_or_null(^"World/Avatar") as AvatarActor
	if avatar == null or not avatar.is_hostile_to(_boss):
		return false
	return avatar.global_position.distance_to(_boss.global_position) <= SHOW_RANGE
