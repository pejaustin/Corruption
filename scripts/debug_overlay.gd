extends PanelContainer

@onready var info_label: RichTextLabel = $MarginContainer/InfoLabel

var _update_timer := 0.0
const UPDATE_INTERVAL := 0.5

func _ready():
	# Toggle with F3
	visible = true

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = !visible

func _process(delta: float):
	if not visible:
		return

	_update_timer += delta
	if _update_timer < UPDATE_INTERVAL:
		return
	_update_timer = 0.0

	var lines: PackedStringArray = []

	lines.append("[b]== DEBUG OVERLAY (F3 to toggle) ==[/b]")
	lines.append("")

	# Network info
	var peer_id = multiplayer.get_unique_id()
	var is_server = multiplayer.is_server()
	lines.append("[b]Network[/b]")
	lines.append("  Peer ID: %d%s" % [peer_id, " (HOST)" if is_server else ""])
	lines.append("  Connected peers: %s" % str(multiplayer.get_peers()))
	lines.append("")

	# Faction enum values
	lines.append("[b]Factions[/b]")
	for faction in GameConstants.Faction.values():
		var name = GameConstants.faction_names[faction]
		var color = GameConstants.faction_colors[faction]
		lines.append("  %d = [color=#%s]%s[/color]" % [faction, color.to_html(false), name])
	lines.append("")

	# Game state
	lines.append("[b]Game State[/b]")
	if GameState.has_avatar():
		var avatar_id = GameState.avatar_peer_id
		var is_me = avatar_id == peer_id
		lines.append("  Avatar Controller: %d%s" % [avatar_id, " (YOU)" if is_me else ""])
	else:
		lines.append("  Avatar: [color=#888888]dormant[/color]")

	# Avatar entity info
	var avatar_node = get_tree().current_scene.get_node_or_null("World/Avatar")
	if avatar_node and avatar_node is Avatar:
		var apos = avatar_node.global_position
		lines.append("  Avatar Pos: (%.1f, %.1f, %.1f)" % [apos.x, apos.y, apos.z])
		lines.append("  Avatar Dormant: %s" % str(avatar_node.is_dormant))
		lines.append("  Watchers: %d" % GameState.watcher_count)
	else:
		lines.append("  Avatar Entity: [color=#ff4444]NOT FOUND[/color]")
	lines.append("")

	# Players in game
	lines.append("[b]Players in Scene[/b]")
	var spawn_point = get_tree().current_scene.get_node_or_null("World/PlayerSpawnPoint")
	if spawn_point:
		for child in spawn_point.get_children():
			var pos = child.global_position if child is Node3D else Vector3.ZERO
			var label = child.name
			if DebugManager.is_dummy(child.name.to_int()):
				label += " (DUMMY)"
			lines.append("  %s — pos: (%.1f, %.1f, %.1f)" % [label, pos.x, pos.y, pos.z])
	else:
		lines.append("  (no spawn point found)")
	lines.append("")

	# Debug info
	lines.append("[b]Controls[/b]")
	lines.append("  E = interact/claim | Q = recall Avatar")
	lines.append("")
	lines.append("[b]Debug (F2 = add dummy)[/b]")
	lines.append("  Dummy players: %d (slots open: %d)" % [DebugManager.get_dummy_count(), DebugManager.get_max_dummy_players()])
	lines.append("")

	# Performance
	lines.append("[b]Performance[/b]")
	lines.append("  FPS: %d" % Engine.get_frames_per_second())

	info_label.text = "\n".join(lines)
