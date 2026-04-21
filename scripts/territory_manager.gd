class_name TerritoryManager extends Node

## Grid-based corruption territory system.
## Corruption spreads from minion presence, decays without them.
## Host-authoritative: server ticks corruption, broadcasts snapshots to clients.

signal corruption_changed(cell: Vector2i, faction: int, level: float)
signal total_corruption_changed(total: float)

const CELL_SIZE: float = 10.0  # World units per grid cell
const GRID_HALF: int = 15    # Grid extends -15 to +15 cells (300x300 world units)
const SPREAD_RATE: float = 0.05  # Corruption gained per second per nearby minion
const DECAY_RATE: float = 0.02   # Corruption lost per second with no minions
const MAX_CORRUPTION: float = 1.0
const SYNC_INTERVAL: float = 1.0  # Seconds between full sync broadcasts

# cell (Vector2i) -> { "faction": int, "level": float }
var _cells: Dictionary = {}
var _sync_timer: float = 0.0
var _minion_manager: Node

func _ready() -> void:
	_minion_manager = get_tree().current_scene.get_node_or_null("MinionManager")

func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / CELL_SIZE)),
		int(floor(pos.z / CELL_SIZE))
	)

func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(
		cell.x * CELL_SIZE + CELL_SIZE * 0.5,
		0,
		cell.y * CELL_SIZE + CELL_SIZE * 0.5
	)

func get_corruption(cell: Vector2i) -> Dictionary:
	## Returns { "faction": int, "level": float } or empty dict.
	return _cells.get(cell, {})

func get_corruption_level(cell: Vector2i) -> float:
	var data = _cells.get(cell, {})
	return data.get("level", 0.0)

func get_cell_faction(cell: Vector2i) -> int:
	var data = _cells.get(cell, {})
	return data.get("faction", -1)

func get_total_corruption() -> float:
	## Sum of all corruption levels across all cells.
	var total := 0.0
	for cell in _cells:
		total += _cells[cell].get("level", 0.0)
	return total

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	_tick_corruption(delta)

	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		_broadcast_corruption()

func _tick_corruption(delta: float) -> void:
	# Gather minion positions by faction
	var minion_cells: Dictionary = {}  # Vector2i -> faction
	if _minion_manager:
		for minion in _minion_manager.get_all_minions():
			var cell = world_to_cell(minion.global_position)
			minion_cells[cell] = minion.faction

	# Spread corruption near minions
	for cell in minion_cells:
		var faction = minion_cells[cell]
		_add_corruption(cell, faction, SPREAD_RATE * delta)
		# Spread to adjacent cells at half rate
		for offset in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var adj = cell + offset
			_add_corruption(adj, faction, SPREAD_RATE * 0.5 * delta)

	# Decay cells with no nearby minions
	var cells_to_remove: Array[Vector2i] = []
	for cell in _cells:
		if cell not in minion_cells:
			_cells[cell]["level"] -= DECAY_RATE * delta
			if _cells[cell]["level"] <= 0:
				cells_to_remove.append(cell)
			else:
				corruption_changed.emit(cell, _cells[cell]["faction"], _cells[cell]["level"])

	for cell in cells_to_remove:
		_cells.erase(cell)
		corruption_changed.emit(cell, -1, 0.0)

	total_corruption_changed.emit(get_total_corruption())

func _add_corruption(cell: Vector2i, faction: int, amount: float) -> void:
	if cell.x < -GRID_HALF or cell.x > GRID_HALF or cell.y < -GRID_HALF or cell.y > GRID_HALF:
		return
	if cell not in _cells:
		_cells[cell] = { "faction": faction, "level": 0.0 }
	var data = _cells[cell]
	if data["faction"] != faction and data["level"] > 0:
		# Contested — reduce existing before adding new
		data["level"] -= amount
		if data["level"] <= 0:
			data["faction"] = faction
			data["level"] = 0.0
	else:
		data["faction"] = faction
		data["level"] = minf(data["level"] + amount, MAX_CORRUPTION)
	corruption_changed.emit(cell, data["faction"], data["level"])

func _broadcast_corruption() -> void:
	## Serialize and send the full corruption grid to all clients.
	var packed: Dictionary = {}
	for cell in _cells:
		# Pack cell as "x,y" string key for RPC compatibility
		var key = "%d,%d" % [cell.x, cell.y]
		packed[key] = [_cells[cell]["faction"], _cells[cell]["level"]]
	_sync_corruption.rpc(packed)

@rpc("authority", "call_local", "reliable")
func _sync_corruption(packed: Dictionary) -> void:
	_cells.clear()
	for key in packed:
		var parts = key.split(",")
		var cell = Vector2i(parts[0].to_int(), parts[1].to_int())
		_cells[cell] = { "faction": packed[key][0], "level": packed[key][1] }
