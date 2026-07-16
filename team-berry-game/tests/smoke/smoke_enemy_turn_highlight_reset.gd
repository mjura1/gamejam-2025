extends SceneTree

# Regression test: MoveHighlighter's enemy_move_flashes used to accumulate
# forever - if the player acted again before the 5s fade-out finished, old
# (partially faded) flashes and new ones got mixed, and the NEXT
# start_fade_out() call reset ALL of them (old and new) back to full
# opacity together, making stale highlights jump back to full brightness
# instead of continuing to fade. start_enemy_turn() now clears leftover
# flashes at the very start, before any new ones are added.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_enemy_turn_highlight_reset.gd --quit-after 15

var checked := false

func _initialize():
	print(">>> SMOKE TEST: leftover highlight reset at start of enemy turn <<<")
	var player_manager = root.get_node("PlayerManager")
	player_manager.setStarting()
	player_manager.resetActives()

	var gf = root.get_node("GF")
	var map_scene: PackedScene = load("res://Scenes/Map/map.tscn")
	gf.current_map_instance = map_scene.instantiate()
	gf.current_map_instance.name = "MapInstance"
	gf.game_initialized = true

	var battle_scene: PackedScene = load("res://Scenes/Map/battle.tscn")
	var battle_instance = battle_scene.instantiate()
	root.add_child(battle_instance)
	current_scene = battle_instance

func _process(_delta: float) -> bool:
	if checked:
		return false

	var battle_instance = root.get_node_or_null("Battle")
	if battle_instance == null:
		return false

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	var move_highlighter = battle_instance.get_node_or_null("MoveHighlighter")
	if battle_controller == null or move_highlighter == null:
		return false

	if battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return false # wait for initial setup to settle

	checked = true

	# Simulate a leftover, still-fading flash from a previous enemy turn -
	# as if the player had acted again before its 5s fade-out finished.
	var empty_path: Array[Vector2i] = []
	move_highlighter.flash_enemy_move(Vector2i(0, 0), Vector2i(1, 0), empty_path, false)
	move_highlighter.start_fade_out(5.0)

	battle_controller.start_enemy_turn()

	# clear_enemy_moves() runs synchronously at the top of start_enemy_turn(),
	# before its first await, so this is already reflected on the same frame.
	var still_has_dummy = false
	for flash in move_highlighter.enemy_move_flashes:
		if flash["from"] == Vector2i(0, 0) and flash["to"] == Vector2i(1, 0):
			still_has_dummy = true

	if still_has_dummy:
		print(">>> SMOKE TEST FAIL: leftover dummy flash was NOT cleared <<<")
	else:
		print(">>> SMOKE TEST: leftover flash correctly cleared when new enemy turn started <<<")
	return false
