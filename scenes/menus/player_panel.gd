extends PanelContainer

func set_player(player_name: String, player_number: int) -> void:
	%PlayerName.text = player_name

func set_faction(faction: GameConstants.Faction) -> void:
	var color = GameConstants.faction_colors[faction]
	var faction_name = GameConstants.faction_names[faction]
	%PlayerName.text += " - " + faction_name
	var style = StyleBoxFlat.new()
	style.bg_color = Color(color, 0.3)
	add_theme_stylebox_override("panel", style)
