class_name DivineIntervention extends Node

## Lose condition: if total corruption stays below a threshold for too long,
## the gods purge the land and all players lose.
## Host-authoritative. Adds tension — Overlords must keep corruption up.

signal intervention_warning(time_remaining: float)
signal intervention_triggered

const CORRUPTION_THRESHOLD: float = 5.0  # Must maintain at least this much total corruption
const GRACE_PERIOD: float = 60.0  # Seconds below threshold before divine intervention
const WARNING_START: float = 30.0  # Start warning at this many seconds remaining
const CHECK_INTERVAL: float = 2.0  # How often to check corruption level

var _timer: float = 0.0  # Time spent below threshold
var _check_timer: float = 0.0
var _triggered: bool = false
var _active: bool = false  # Only starts after first corruption is placed

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if _triggered:
		return

	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return
	_check_timer = 0.0

	var tm = get_tree().current_scene.get_node_or_null("TerritoryManager")
	if not tm:
		return

	var total = tm.get_total_corruption()

	# Don't start counting until corruption has been established at least once
	if not _active:
		if total > CORRUPTION_THRESHOLD:
			_active = true
		return

	if total < CORRUPTION_THRESHOLD:
		_timer += CHECK_INTERVAL
		var remaining = GRACE_PERIOD - _timer
		if remaining <= WARNING_START:
			_sync_warning.rpc(remaining)
		if _timer >= GRACE_PERIOD:
			_trigger_intervention()
	else:
		if _timer > 0:
			_timer = max(0, _timer - CHECK_INTERVAL * 2.0)  # Recover twice as fast
			if _timer <= GRACE_PERIOD - WARNING_START:
				_sync_warning.rpc(-1)  # Clear warning

func _trigger_intervention() -> void:
	_triggered = true
	_do_intervention.rpc()

@rpc("authority", "call_local", "reliable")
func _do_intervention() -> void:
	_triggered = true
	intervention_triggered.emit()
	# All players lose
	GameState._announce_loss.rpc()
	print("[DivineIntervention] The gods have purged the corruption. All players lose.")

@rpc("authority", "call_local", "reliable")
func _sync_warning(time_remaining: float) -> void:
	intervention_warning.emit(time_remaining)

func get_timer() -> float:
	return _timer

func get_time_remaining() -> float:
	return max(0, GRACE_PERIOD - _timer)

func is_warning() -> bool:
	return _active and _timer > GRACE_PERIOD - WARNING_START
