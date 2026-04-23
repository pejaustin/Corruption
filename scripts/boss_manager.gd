class_name BossManager extends Node

## Manages the two-boss endgame sequence.
## Phase 1: Capitol Guardian (stats from guardian_boss.tres)
## Phase 2: Corrupted Seraph (stats from corrupted_seraph.tres)
## Defeating both wins the game.
##
## Wire the first boss and the seraph scene via the inspector; no string paths.

signal phase_changed(phase: int)
signal boss_spawned(boss: GuardianBoss)

enum Phase { WAITING, BOSS_1, INTERMISSION, BOSS_2, COMPLETE }

const INTERMISSION_TIME: float = 3.0

## Pre-placed Capitol Guardian in the world. Set in the inspector.
@export var initial_boss: GuardianBoss
## Scene for phase-2 boss. Defaults to CorruptedSeraph; override for custom.
@export var seraph_scene: PackedScene = preload("res://scenes/actors/enemy/seraph/corrupted_seraph.tscn")
## Where the seraph spawns. If unset, uses the initial boss's position.
@export var seraph_spawn_point: Node3D

var current_phase: Phase = Phase.WAITING
var current_boss: GuardianBoss = null
var _intermission_timer: float = 0.0

func _ready() -> void:
	if initial_boss:
		current_boss = initial_boss
		current_phase = Phase.BOSS_1
		initial_boss.boss_defeated.connect(_on_boss_1_defeated)
	else:
		push_warning("[BossManager] initial_boss is not set — phase 1 will not start.")

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
	_spawn_seraph.rpc()

@rpc("authority", "call_local", "reliable")
func _spawn_seraph() -> void:
	if seraph_scene == null:
		push_warning("[BossManager] seraph_scene is not set")
		return
	var boss := seraph_scene.instantiate() as GuardianBoss
	if boss == null:
		push_warning("[BossManager] seraph_scene root is not a GuardianBoss")
		return
	var world := get_tree().current_scene.get_node_or_null("World")
	if world == null:
		return
	world.add_child(boss)
	var spawn_pos := _get_seraph_spawn_position()
	boss.global_position = spawn_pos
	current_boss = boss
	boss.boss_defeated.connect(_on_boss_2_defeated)
	boss_spawned.emit(boss)
	print("[BossManager] %s spawned at %s" % [boss.boss_name, spawn_pos])

func _get_seraph_spawn_position() -> Vector3:
	if seraph_spawn_point:
		return seraph_spawn_point.global_position
	if initial_boss:
		return initial_boss.global_position
	return Vector3.ZERO

func _on_boss_2_defeated() -> void:
	if not multiplayer.is_server():
		return
	current_phase = Phase.COMPLETE
	_set_phase.rpc(Phase.COMPLETE)
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
