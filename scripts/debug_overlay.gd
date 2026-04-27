extends PanelContainer

@onready var info_label: RichTextLabel = $MarginContainer/InfoLabel

var _update_timer := 0.0
const UPDATE_INTERVAL: float = 0.5

func _ready() -> void:
	# Toggle with F3. Host sees it by default; clients must opt in.
	visible = multiplayer.is_server()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = !visible

func _process(delta: float) -> void:
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
	if avatar_node and avatar_node is AvatarActor:
		var apos = avatar_node.global_position
		lines.append("  Avatar Pos: (%.1f, %.1f, %.1f)" % [apos.x, apos.y, apos.z])
		lines.append("  Avatar Dormant: %s" % str(avatar_node.is_dormant))
		var hp_color = "00ff00" if avatar_node.hp > 50 else ("ffaa00" if avatar_node.hp > 25 else "ff4444")
		lines.append("  HP: [color=#%s]%d / %d[/color]%s" % [hp_color, avatar_node.hp, avatar_node.get_max_hp(), " [GOD]" if avatar_node.god_mode else ""])
		lines.append("  State: %s" % str(avatar_node._state_machine.state))
		lines.append("  Watchers: %d" % GameState.watcher_count)
	else:
		lines.append("  Avatar Entity: [color=#ff4444]NOT FOUND[/color]")

	# Neutral minion count (formerly "enemies")
	var mm_dbg = get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	var enemy_count := 0
	if mm_dbg:
		for m in mm_dbg.get_all_minions():
			if m.owner_peer_id == -1:
				enemy_count += 1
	lines.append("  Enemies alive: %d" % enemy_count)
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

	# Influence scores
	lines.append("[b]Influence[/b]")
	if GameState.influence.size() > 0:
		for pid in GameState.influence:
			var score = GameState.influence[pid]
			var marker = " (YOU)" if pid == peer_id else ""
			lines.append("  Peer %d: %.1f%s" % [pid, score, marker])
	else:
		lines.append("  (no scores yet)")
	lines.append("")

	# Minions
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if mm:
		lines.append("[b]Minions[/b]")
		var all_minions = mm.get_all_minions()
		lines.append("  Total: %d" % all_minions.size())
		var my_minions = mm.get_minion_count(peer_id)
		var my_res = mm.get_resources(peer_id)
		lines.append("  Mine: %d/%d | Resources: %.0f" % [my_minions, MinionManager.MAX_MINIONS_PER_PLAYER, my_res])
		lines.append("")

	# Territory
	var tm = get_tree().current_scene.get_node_or_null("TerritoryManager")
	if tm:
		lines.append("[b]Territory[/b]")
		lines.append("  Corrupted cells: %d | Total corruption: %.1f" % [tm._cells.size(), tm.get_total_corruption()])
		lines.append("")

	# Guardian Boss
	var boss = get_tree().current_scene.get_node_or_null("World/GuardianBoss")
	if boss and boss is GuardianBoss:
		var debuff = int(boss._get_corruption_debuff() * 100)
		var boss_hp_color = "00ff00" if boss.hp > boss.max_hp_effective * 0.5 else ("ffaa00" if boss.hp > boss.max_hp_effective * 0.25 else "ff4444")
		lines.append("[b]Guardian Boss[/b]")
		lines.append("  HP: [color=#%s]%d / %d[/color] (Debuff: %d%%)" % [boss_hp_color, boss.hp, boss.max_hp_effective, debuff])
		lines.append("  Damage: %d" % boss.get_attack_damage())
		lines.append("")

	# Boss Manager
	var bm = get_tree().current_scene.get_node_or_null("BossManager")
	if bm:
		lines.append("[b]Boss Phase[/b]")
		lines.append("  Phase: %s" % bm.get_phase_name())
		lines.append("")

	# Divine Intervention
	var di = get_tree().current_scene.get_node_or_null("DivineIntervention")
	if di:
		lines.append("[b]Divine Intervention[/b]")
		if di._triggered:
			lines.append("  [color=#ff4444]TRIGGERED — GAME OVER[/color]")
		elif di.is_warning():
			lines.append("  [color=#ffaa00]WARNING: %.0fs remaining![/color]" % di.get_time_remaining())
		elif di._active:
			lines.append("  Active (timer: %.0f / %.0f)" % [di._timer, DivineIntervention.GRACE_PERIOD])
		else:
			lines.append("  Inactive (waiting for first corruption)")
		lines.append("")

	# Faction
	if mm:
		var my_faction = mm._get_player_faction(peer_id)
		var fname = GameConstants.faction_names.get(my_faction, "Unknown")
		var fcolor = GameConstants.faction_colors.get(my_faction, Color.WHITE)
		lines.append("[b]My Faction[/b]")
		lines.append("  [color=#%s]%s[/color] (F9 to swap)" % [fcolor.to_html(false), fname])
		lines.append("")

	# Debug info
	lines.append("[b]Controls[/b]")
	lines.append("  E = interact/claim | Q = recall | LMB = attack")
	lines.append("")
	lines.append("[b]Debug[/b]")
	lines.append("  F3 = toggle this overlay | Esc = open pause menu (debug buttons)")
	lines.append("  Dummy players: %d (slots open: %d)" % [DebugManager.get_dummy_count(), DebugManager.get_max_dummy_players()])
	lines.append("")

	# Performance
	lines.append("[b]Performance[/b]")
	lines.append("  FPS: %d" % Engine.get_frames_per_second())

	info_label.text = "\n".join(lines)
