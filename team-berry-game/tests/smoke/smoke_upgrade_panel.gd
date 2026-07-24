extends SceneTree

# Drives the real campfire upgrade panel (CampfireUpgradePanel.tscn) headlessly:
# grants upgrade items, presses the real skill-tree node buttons and checks
# that PlayerManager's derived getters + the item count change accordingly.
# The panel rebuilds its rows on every items_changed signal, so each button
# press happens in its own frame (old rows are queue_free()d and only
# actually gone on the next frame).
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_upgrade_panel.gd --quit-after 8

var player_manager
var skill_tree_data
var panel
var step := 0
var fails := 0
var expected_items := 0

func _initialize():
	print(">>> SMOKE TEST: campfire upgrade panel spend flow <<<")

	player_manager = root.get_node("PlayerManager")
	skill_tree_data = root.get_node("SkillTreeData")
	player_manager.setStarting() # roster: 3x friendly_pawn -> ena vrstica (pawn)
	# Exactly enough to buy a1_lv2 + a2_unlock + a2_lv2 below and nothing more,
	# so the final "all items spent" check lands on 0 - keep in sync with
	# GameParameters/skill_trees.json pawn costs if those change.
	var starting_items := 39
	player_manager.add_upgrade_items(starting_items)
	expected_items = starting_items

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

# Vrstica za pawn: [TextureRect ikona, VBox stolpec1 (ABILITY 1), stolpec2
# (ABILITY 2), stolpec3 (ABILITY 3), stolpec4 (PERKS)]. V vsakem stolpcu je
# prvi otrok naslovni Label, gumbi sledijo v vrstnem redu iz node_ids.
func _node_button(column: int, index_in_column: int) -> Button:
	var rows: Array = panel.type_list.get_children()
	if rows.is_empty():
		return null
	var row = rows[0]
	if row.get_child_count() <= column:
		return null
	var col = row.get_child(column)
	if col.get_child_count() <= index_in_column + 1:
		return null
	return col.get_child(index_in_column + 1)

func _cost(piece_type: String, node_id: String) -> int:
	return int(skill_tree_data.get_node_def(piece_type, node_id).get("cost", 0))

func _process(_delta: float) -> bool:
	if not is_instance_valid(panel):
		return false

	match step:
		0:
			_check("panel shows one row for the all-pawn roster", panel.type_list.get_child_count() == 1)
			_check("items label shows granted item count", panel.items_label.text.contains("x%d" % expected_items))

			# column 1 = ABILITY 1 (a1_lv2, a1_lv3), index 0 = a1_lv2
			var b1 := _node_button(1, 0)
			var cost := _cost("pawn", "a1_lv2")
			_check("a1_lv2 button offers purchase with its cost", b1 != null and b1.text == "Rally II (%d)" % cost and not b1.disabled)
			expected_items -= cost
			b1.pressed.emit()
		1:
			_check("a1_lv2 bought", player_manager.has_tree_node("pawn", "a1_lv2"))
			_check("ability level derived from purchase", player_manager.get_ability_level("pawn", 1) == 2)
			_check("buy spent the cost", player_manager.upgrade_items == expected_items)

			var b1 := _node_button(1, 0)
			_check("bought node flips to owned and disables", b1 != null and b1.text == "✔ Rally II" and b1.disabled)

			# column 2 = ABILITY 2 (a2_unlock, a2_lv2, a2_lv3), index 0 = a2_unlock
			var b2 := _node_button(2, 0)
			var cost := _cost("pawn", "a2_unlock")
			_check("a2_unlock button offers purchase with its cost", b2 != null and b2.text == "Lantern Signal (%d)" % cost and not b2.disabled)
			expected_items -= cost
			b2.pressed.emit()
		2:
			_check("slot 2 unlocked", player_manager.is_slot_unlocked("pawn", 2))
			_check("unlock spent the cost", player_manager.upgrade_items == expected_items)

			var b2 := _node_button(2, 0)
			_check("unlocked node flips to owned", b2 != null and b2.text == "✔ Lantern Signal" and b2.disabled)

			# now-unlocked a2_lv2 (column 2, index 1)
			var b2lv2 := _node_button(2, 1)
			var cost := _cost("pawn", "a2_lv2")
			_check("a2_lv2 offers purchase now that a2_unlock is owned", b2lv2 != null and b2lv2.text == "Lantern Signal II (%d)" % cost and not b2lv2.disabled)
			expected_items -= cost
			b2lv2.pressed.emit()
		3:
			_check("a2_lv2 bought", player_manager.has_tree_node("pawn", "a2_lv2"))
			_check("ability level derived from purchase", player_manager.get_ability_level("pawn", 2) == 2)
			_check("all items spent", player_manager.upgrade_items == 0 and expected_items == 0)

			var b1 := _node_button(1, 1) # a1_lv3
			_check("buttons disabled once items run out", b1 != null and b1.disabled)

			var bp := _node_button(4, 0) # p1, never bought
			_check("p1 still shows a purchasable price format even though items ran out", bp != null and bp.text.begins_with("Long March (") and bp.disabled)

			panel.close_menu()
			if fails == 0:
				print(">>> SMOKE TEST: upgrade panel spend flow completed cleanly <<<")
			else:
				print("SMOKE TEST FAIL: %d upgrade panel checks failed" % fails)

	step += 1
	return false
