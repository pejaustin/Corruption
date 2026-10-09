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

	# Game state
	lines.append("[b]Game State[/b]")
	var owner_txt = str(GameState.avatar_owner_peer_id) if GameState.has_avatar_owner() else "[color=#888888]neutral[/color]"
	var ctrl_txt = str(GameState.avatar_peer_id) if GameState.has_avatar() else "[color=#888888]released[/color]"
	if GameState.is_avatar(peer_id):
		ctrl_txt += " (YOU)"
	lines.append("  Avatar Owner: %s | Controller: %s" % [owner_txt, ctrl_txt])

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

	# Good-faction units (humans, soldiers)
	var mm_dbg = get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	var enemy_count := 0
	if mm_dbg:
		for m in mm_dbg.get_all_minions():
			if m.owner_peer_id == -1:
				enemy_count += 1
	lines.append("  Good-faction units: %d" % enemy_count)
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

	# Corruption sites (each grants a capability; there is no score)
	var sites := GameState.get_all_sites()
	if sites.size() > 0:
		lines.append("[b]Corruption Sites[/b]")
		for node in sites:
			var site := node as CorruptionSite
			if site == null:
				continue
			var holder := "neutral" if site.holder_peer_id == -1 else GameState.get_player_name(site.holder_peer_id)
			var extra := ""
			if site.unusable:
				extra = " [UNUSABLE]"
			elif site.permanent and site.sacked:
				extra = " [SACKED]"
			elif not site.is_held() and site.progress > 0.0:
				extra = " (%d%% → %s)" % [int(site.progress * 100), GameState.get_player_name(site.progress_peer_id)]
			lines.append("  %s: %s%s" % [site.get_display_name(), holder, extra])
		lines.append("")

	# Units
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm:
		lines.append("[b]Units[/b]")
		lines.append("  Total: %d | Mine: %d | Remains at my tower: %d" % [
			mm.get_all_minions().size(), mm.get_minion_count(peer_id), mm.get_remains(peer_id)])
		lines.append("")

	# Good faction growth (the draw clock)
	var gf := get_tree().current_scene.get_node_or_null("GoodFaction") as GoodFaction
	if gf:
		lines.append("[b]Good Faction[/b]")
		lines.append("  Growth step %d / %d | next in %.0fs | thresholds x%.2f" % [
			GoodFaction.step, GoodFaction.DRAW_AT_STEP, gf.get_time_to_next_step(), GoodFaction.threshold_scale()])
		lines.append("")

	# The boss gauntlet
	if HolySite.state == HolySite.State.GAUNTLET:
		lines.append("[b]Gauntlet[/b]")
		lines.append("  Boss %d / %d: %s" % [HolySite.boss_index, HolySite.boss_total, GameState.get_player_name(HolySite.boss_peer)])
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
