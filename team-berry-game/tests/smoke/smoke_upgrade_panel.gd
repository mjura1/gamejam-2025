extends SceneTree

# Drives the campfire upgrade panel (CampfireUpgradePanel.tscn) headlessly:
# grants upgrade items, presses the real LEVEL UP / UNLOCK buttons and checks
# that PlayerManager.piece_upgrades and the item count change accordingly.
# The panel rebuilds its rows on every items_changed signal, so each button
# press happens in its own frame (old rows are queue_free()d and only
# actually gone on the next frame).
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_upgrade_panel.gd --quit-after 8

var player_manager
var ability_data
var panel
var step := 0
var fails := 0
var expected_items := 0

func _initialize():
	print(">>> SMOKE TEST: campfire upgrade panel spend flow <<<")

	player_manager = root.get_node("PlayerManager")
	ability_data = root.get_node("AbilityData")
	player_manager.setStarting() # roster: 3x friendly_pawn -> ena vrstica (pawn)
	player_manager.add_upgrade_items(5)
	expected_items = 5

	var panel_scene: PackedScene = load("res://Scenes/Menu/CampfireUpgradePanel.tscn")
	panel = panel_scene.instantiate()
	panel.name = "UpgradeScreenNode"
	root.add_child(panel)

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		fails += 1

# Vrstica za pawn: [TextureRect ikona, VBox slot 1, VBox slot 2];
# gumb je drugi otrok slot-boxa (za name_label).
func _slot_button(slot: int) -> Button:
	var rows: Array = panel.type_list.get_children()
	if rows.is_empty():
		return null
	var row = rows[0]
	if row.get_child_count() < slot + 1:
		return null
	return row.get_child(slot).get_child(1)

func _process(_delta: float) -> bool:
	if not is_instance_valid(panel):
		return false

	match step:
		0:
			_check("panel shows one row for the all-pawn roster", panel.type_list.get_child_count() == 1)
			_check("items label shows granted item count", panel.items_label.text.contains("x5"))

			var b1 := _slot_button(1)
			var cost: int = ability_data.get_level_up_cost("rally")
			_check("slot 1 button offers LEVEL UP with rally's cost", b1 != null and b1.text == "LEVEL UP (%d)" % cost and not b1.disabled)
			expected_items -= cost
			b1.pressed.emit()
		1:
			_check("rally leveled 1 -> 2", player_manager.get_piece_upgrades("pawn")["levels"][1] == 2)
			_check("level up spent the cost", player_manager.upgrade_items == expected_items)

			var b2 := _slot_button(2)
			var cost: int = ability_data.get_unlock_cost("lantern_signal")
			_check("slot 2 button offers UNLOCK with lantern_signal's cost", b2 != null and b2.text == "UNLOCK (%d)" % cost and not b2.disabled)
			expected_items -= cost
			b2.pressed.emit()
		2:
			_check("slot 2 unlocked", player_manager.get_piece_upgrades("pawn")["slot2_unlocked"])
			_check("unlock spent the cost", player_manager.upgrade_items == expected_items)

			var b2 := _slot_button(2)
			var cost: int = ability_data.get_level_up_cost("lantern_signal")
			_check("unlocked slot 2 button now offers LEVEL UP", b2 != null and b2.text == "LEVEL UP (%d)" % cost)
			expected_items -= cost
			b2.pressed.emit()
		3:
			_check("lantern_signal leveled 1 -> 2", player_manager.get_piece_upgrades("pawn")["levels"][2] == 2)
			_check("all items spent", player_manager.upgrade_items == 0 and expected_items == 0)

			var b1 := _slot_button(1)
			_check("buttons disabled once items run out", b1 != null and b1.disabled)

			panel.close_menu()
			if fails == 0:
				print(">>> SMOKE TEST: upgrade panel spend flow completed cleanly <<<")
			else:
				print("SMOKE TEST FAIL: %d upgrade panel checks failed" % fails)

	step += 1
	return false
