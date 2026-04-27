class_name GuardianBoss extends MinionActor

## The guardian boss at the Capitol. Must be defeated to win.
## Debuffed by total corruption: higher corruption = weaker boss.
## Base stats come from guardian_boss.tres (MinionType). This class layers on
## corruption-driven HP/damage scaling, threshold-only stagger, and win signalling.

const CORRUPTION_DEBUFF_MAX: float = 0.6  # At max corruption, boss stats reduced by 60%
const HP_FLOOR: int = 100

@export var boss_name: String = "Capitol Guardian"

signal boss_defeated
signal boss_hp_changed(current: int, maximum: int)

var _base_hp: int = 500
var _base_damage: int = 30
var max_hp_effective: int = 500
var _debuff_update_timer: float = 0.0
var _territory_manager: Node

func _ready() -> void:
	super()
	_base_hp = max_hp_value
	_base_damage = attack_damage
	max_hp_effective = _base_hp
	_territory_manager = get_tree().current_scene.get_node_or_null("TerritoryManager")

func get_max_hp() -> int:
	return max_hp_effective

func get_attack_damage() -> int:
	var debuff = _get_corruption_debuff()
	return int(_base_damage * (1.0 - debuff))

func get_stagger_duration() -> float:
	return 0.3

func _physics_process(delta: float) -> void:
	super(delta)
	if not multiplayer.is_server():
		return
	_debuff_update_timer += delta
	if _debuff_update_timer >= 2.0:
		_debuff_update_timer = 0.0
		_update_corruption_debuff()

func _update_corruption_debuff() -> void:
	var debuff = _get_corruption_debuff()
	var new_max = int(_base_hp * (1.0 - debuff))
	if new_max != max_hp_effective:
		max_hp_effective = max(HP_FLOOR, new_max)
		if hp > max_hp_effective:
			hp = max_hp_effective
		boss_hp_changed.emit(hp, max_hp_effective)

func _get_corruption_debuff() -> float:
	if not _territory_manager:
		return 0.0
	var total = _territory_manager.get_total_corruption()
	return clampf(total / 60.0, 0.0, CORRUPTION_DEBUFF_MAX)

func _die() -> void:
	boss_defeated.emit()
	super()
	if multiplayer.is_server():
		_announce_boss_defeated.rpc()

@rpc("authority", "call_local", "reliable")
func _announce_boss_defeated() -> void:
	var bm = get_tree().current_scene.get_node_or_null("BossManager")
	if bm:
		return
	if GameState.has_avatar():
		GameState._announce_win.rpc(GameState.avatar_peer_id)

func take_damage(amount: int) -> void:
	if not can_take_damage():
		return
	hp = max(0, hp - amount)
	boss_hp_changed.emit(hp, max_hp_effective)
	hp_changed.emit(hp)
	if hp <= 0:
		_die()
	else:
		# Boss doesn't stagger from normal hits — only at HP thresholds.
		if hp < max_hp_effective * 0.5 and hp + amount >= max_hp_effective * 0.5:
			try_stagger()
		elif hp < max_hp_effective * 0.25 and hp + amount >= max_hp_effective * 0.25:
			try_stagger()
