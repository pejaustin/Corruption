class_name GuardianBoss extends EnemyActor

## The guardian boss at the Capitol. Must be defeated to win.
## Debuffed by total corruption: higher corruption = weaker boss.
## Replaces the simple gem win condition from earlier tiers.

const BASE_HP: int = 500
const BASE_DAMAGE: int = 30
const CORRUPTION_DEBUFF_MAX: float = 0.6  # At max corruption, boss stats reduced by 60%

@export var boss_name: String = "Capitol Guardian"

signal boss_defeated
signal boss_hp_changed(current: int, maximum: int)

var max_hp_effective: int = BASE_HP
var _debuff_update_timer: float = 0.0
var _territory_manager: Node

func _ready() -> void:
	super()
	hp = BASE_HP
	max_hp_effective = BASE_HP
	# Override enemy defaults
	collision_layer = 4
	_territory_manager = get_tree().current_scene.get_node_or_null("TerritoryManager")

func get_max_hp() -> int:
	return max_hp_effective

func get_attack_damage() -> int:
	var debuff = _get_corruption_debuff()
	return int(BASE_DAMAGE * (1.0 - debuff))

func get_stagger_duration() -> float:
	return 0.3  # Bosses recover faster

func _physics_process(delta: float) -> void:
	super(delta)
	if not multiplayer.is_server():
		return

	# Periodically recalculate debuff
	_debuff_update_timer += delta
	if _debuff_update_timer >= 2.0:
		_debuff_update_timer = 0.0
		_update_corruption_debuff()

func _update_corruption_debuff() -> void:
	var debuff = _get_corruption_debuff()
	var new_max = int(BASE_HP * (1.0 - debuff))
	if new_max != max_hp_effective:
		max_hp_effective = max(100, new_max)  # Floor at 100 HP
		# If current HP exceeds new max, cap it
		if hp > max_hp_effective:
			hp = max_hp_effective
		boss_hp_changed.emit(hp, max_hp_effective)

func _get_corruption_debuff() -> float:
	## Returns 0.0 to CORRUPTION_DEBUFF_MAX based on total corruption in the world.
	if not _territory_manager:
		return 0.0
	var total = _territory_manager.get_total_corruption()
	# Scale: every 10 corruption points = 10% debuff, capped
	var debuff = clampf(total / 60.0, 0.0, CORRUPTION_DEBUFF_MAX)
	return debuff

func _die() -> void:
	boss_defeated.emit()
	super()
	# Notify all clients that the boss is dead — this triggers the win
	if multiplayer.is_server():
		_announce_boss_defeated.rpc()

@rpc("authority", "call_local", "reliable")
func _announce_boss_defeated() -> void:
	# If BossManager exists, it handles win logic (two-boss sequence)
	var bm = get_tree().current_scene.get_node_or_null("BossManager")
	if bm:
		return
	# Fallback: single-boss win (Tier 3 behavior)
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
		# Boss doesn't stagger from normal hits — only at HP thresholds
		if hp < max_hp_effective * 0.5 and hp + amount >= max_hp_effective * 0.5:
			_state_machine.transition(&"StaggerState")
		elif hp < max_hp_effective * 0.25 and hp + amount >= max_hp_effective * 0.25:
			_state_machine.transition(&"StaggerState")
