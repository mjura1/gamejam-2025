# Manual visual preview - NOT part of run_all.sh. Opens a window straight
# into CampfirePartyPanel with a fake roster, so you can click around without
# playing through Start -> map -> campfire room every time.
# Run: godot4 --path . --script res://tests/dev/preview_party_panel.gd
extends SceneTree


func _initialize():
	var player_manager = root.get_node("PlayerManager")

	var friendly: Array[String] = [
		"friendly_pawn", "friendly_pawn", "friendly_rook", "friendly_knight",
	]
	var reserve: Array[String] = [
		"friendly_bishop", "friendly_bishop", "friendly_queen", "friendly_pawn", "friendly_king",
	]
	player_manager.friendly_party = friendly
	player_manager.reserve_party = reserve

	var panel = load("res://Scenes/Menu/CampfirePartyPanel.tscn").instantiate()
	root.add_child(panel)
	current_scene = panel
