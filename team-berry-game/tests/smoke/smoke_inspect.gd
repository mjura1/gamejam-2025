extends SceneTree

# Enemy inspection (click an enemy with no ally selected -> red preview +
# status panel, see map_behaviour._inspect_enemy / battle_ui._show_enemy).
# Boots a real battle, force-assigns a curse to one enemy (leaves a second
# enemy uncursed), and drives the REAL inspection path directly
# (map_behaviour._inspect_enemy - the same function the input handler calls)
# for both. Fully synchronous (no BattleController awaits involved), so this
# can run inline like smoke_item_use.gd - no frame-polled state machine
# needed (contrast smoke_curses.gd).
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_inspect.gd --quit-after 4

var battle_instance
var player_manager
var curse_data # CurseData avtoload - ni bare identifikator v --script entry skripti
var reported := false
var fails := 0

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		fails += 1

func _initialize():
	print(">>> SMOKE TEST: enemy inspection (red preview + status panel) <<<")
	player_manager = root.get_node("PlayerManager")
	curse_data = root.get_node("CurseData")
	battle_instance = BattleBoot.boot(self)
	var enemies: Array[String] = ["enemy_pawn", "enemy_rook"]
	player_manager.enemy_party = enemies
	player_manager.active_enemies = enemies.duplicate()

func _process(_delta: float) -> bool:
	if reported or not is_instance_valid(battle_instance):
		return false

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if not battle_controller or battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return false # still waiting for placement to complete

	reported = true

	var grid_manager = battle_instance.get_node("GridManager")
	var move_highlighter = battle_instance.get_node("MoveHighlighter")
	var map_behaviour = battle_instance.get_node("Map")
	var battle_ui = battle_instance.get_node("BattleUI")

	var enemies: Array[BaseCharacter] = []
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and c.is_enemy and not c.is_obstacle:
			enemies.append(c)

	if enemies.size() < 2:
		print("SMOKE TEST FAIL: expected 2 enemies on the board, found %d" % enemies.size())
		return false

	var cursed: BaseCharacter = enemies[0]
	var uncursed: BaseCharacter = enemies[1]
	cursed.apply_curse(curse_data.create_curse("snowfall"))
	_check("uncursed enemy really has no curse", uncursed.curse == null)

	# Ni izbrane nobene zavezniške figure - nič ne poskusi capture flow-a.
	_check("no ally is selected before inspecting", map_behaviour.selected_character == null)

	# --- Uncursed enemy first ---
	map_behaviour._inspect_enemy(uncursed)
	_check("inspecting an enemy does not select it (selected_character stays null)",
		map_behaviour.selected_character == null)
	_check("preview tiles are shown for the uncursed enemy",
		not move_highlighter.enemy_preview.is_empty())
	_check("preview tiles match the enemy's real valid targets",
		move_highlighter.enemy_preview == uncursed.calculate_valid_targets())
	_check("status panel shows plain ENEMY for an uncursed enemy",
		battle_ui.status_value.text == "ENEMY")

	# --- Cursed enemy ---
	map_behaviour._inspect_enemy(cursed)
	_check("preview tiles are shown for the cursed enemy",
		not move_highlighter.enemy_preview.is_empty())
	_check("status panel contains CURSED for a cursed enemy",
		battle_ui.status_value.text.contains("CURSED"))
	_check("status panel names the curse", battle_ui.status_value.text.contains("Snowfall"))

	# Selecting an ally afterward must clear the inspection preview.
	var ally: BaseCharacter = null
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and not c.is_enemy and not c.is_obstacle:
			ally = c
			break
	if is_instance_valid(ally):
		map_behaviour.select_character_via_ui(ally)
		_check("selecting an ally clears the enemy preview",
			move_highlighter.enemy_preview.is_empty())
	else:
		_check("could not find an ally to verify preview-clear-on-select", false)

	if fails == 0:
		print(">>> SMOKE_INSPECT_OK <<<")
	else:
		print("SMOKE TEST FAIL: %d inspection checks failed" % fails)

	return false
