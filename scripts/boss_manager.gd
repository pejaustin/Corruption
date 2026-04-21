class_name BossManager extends Node

## Manages the two-boss endgame sequence.
## Phase 1: Capitol Guardian (500 HP base, corruption-debuffed)
## Phase 2: Corrupted Seraph (750 HP base, corruption-debuffed, stronger attacks)
## Defeating both in sequence wins the game.

signal phase_changed(phase: int)
signal boss_spawned(boss: GuardianBoss)

enum Phase { WAITING, BOSS_1, INTERMISSION, BOSS_2, COMPLETE }

const INTERMISSION_TIME: float = 3.0  # Seconds between bosses
const BOSS_2_HP: int = 750
const BOSS_2_DAMAGE: int = 45
const BOSS_SPAWN_POS: Vector3 = Vector3(0, 0, 0)  # Capitol center

var current_phase: Phase = Phase.WAITING
var current_boss: GuardianBoss = null
var _intermission_timer: float = 0.0

func _ready() -> void:
	# Listen for the first boss being defeated
	_find_and_connect_boss()

func _find_and_connect_boss() -> void:
	# Look for an existing GuardianBoss in the scene
	var boss = get_tree().current_scene.get_node_or_null("World/GuardianBoss")
	if boss and boss is GuardianBoss:
		current_boss = boss
		current_phase = Phase.BOSS_1
		boss.boss_defeated.connect(_on_boss_1_defeated)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if current_phase == Phase.INTERMISSION:
		_intermission_timer += delta
		if _intermission_timer >= INTERMISSION_TIME:
			_spawn_boss_2()

func _on_boss_1_defeated() -> void:
	if not multiplayer.is_server():
		return
	current_phase = Phase.INTERMISSION
	_intermission_timer = 0.0
	_set_phase.rpc(Phase.INTERMISSION)
	print("[BossManager] Phase 1 complete, intermission started")

func _spawn_boss_2() -> void:
	current_phase = Phase.BOSS_2
	_set_phase.rpc(Phase.BOSS_2)
	# Spawn second boss via RPC
	_spawn_seraph.rpc()

@rpc("authority", "call_local", "reliable")
func _spawn_seraph() -> void:
	var boss_scene = preload("res://scenes/actors/enemy/zombie/zombie_actor.tscn")
	var boss = boss_scene.instantiate()
	# Re-class as GuardianBoss by adding the script
	boss.set_script(preload("res://scripts/guardian_boss.gd"))
	boss.name = "CorruptedSeraph"
	boss.boss_name = "Corrupted Seraph"
	var world = get_tree().current_scene.get_node_or_null("World")
	if world:
		world.add_child(boss)
		boss.global_position = BOSS_SPAWN_POS
		# Override stats for phase 2
		boss.hp = BOSS_2_HP
		boss.max_hp_effective = BOSS_2_HP
		boss.boss_hp_changed.emit(boss.hp, boss.max_hp_effective)
		current_boss = boss
		boss.boss_defeated.connect(_on_boss_2_defeated)
		boss_spawned.emit(boss)
		print("[BossManager] Corrupted Seraph spawned")

func _on_boss_2_defeated() -> void:
	if not multiplayer.is_server():
		return
	current_phase = Phase.COMPLETE
	_set_phase.rpc(Phase.COMPLETE)
	# NOW the game is actually won
	if GameState.has_avatar():
		GameState._announce_win.rpc(GameState.avatar_peer_id)
	print("[BossManager] Both bosses defeated — game won!")

@rpc("authority", "call_local", "reliable")
func _set_phase(new_phase: int) -> void:
	current_phase = new_phase as Phase
	phase_changed.emit(current_phase)

func get_phase_name() -> String:
	match current_phase:
		Phase.WAITING:
			return "Waiting"
		Phase.BOSS_1:
			return "Guardian"
		Phase.INTERMISSION:
			return "Intermission"
		Phase.BOSS_2:
			return "Seraph"
		Phase.COMPLETE:
			return "Complete"
	return "Unknown"
