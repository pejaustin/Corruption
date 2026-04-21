extends Control

func _on_main_menu_pressed() -> void:
	NetworkManager.disconnect_from_game()
