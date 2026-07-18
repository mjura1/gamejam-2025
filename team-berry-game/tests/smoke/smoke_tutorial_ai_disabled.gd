extends SceneTree

# Smoke test for the per-scene AI toggle (BattleController.ai_enabled):
# tutorial_movement.tscn overrides it to false, so ending the player's turn
# must hand the turn straight back (start_enemy_turn() -> end_enemy_turn()
# with no enemy acting) and no enemy piece's grid_pos may change. This is
# the "Moving & Capturing" tutorial stage's core promise - enemies stand
# still while the player practices.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_tutorial_ai_disabled.gd --quit-after 8

var ended_turn := false
var checked := false
var enemy_positions := {} # instance_id -> grid_pos snapshot on turn 1

func _initialize():
	print(">>> SMOKE TEST: tutorial stage with ai_enabled = false <<<")
	var stage: PackedScene = load("res://Scenes/Tutorial/tutorial_movement.tscn")
	var instance = stage.instantiate()
	root.add_child(instance)
	current_scene = instance

func _process(_delta: float) -> bool:
	var bc = current_scene.get_node_or_null("BattleController")
	if bc == null:
		return false

	if not ended_turn:
		if bc.current_state != bc.BattleState.PLAYER_TURN:
			return false # waiting for initialize_battle() to reach turn 1
		if bc.ai_enabled:
			print(">>> SMOKE TEST FAIL: tutorial stage booted with ai_enabled = true <<<")
			return true
		for character in get_nodes_in_group("characters"):
			if character is BaseCharacter and character.is_enemy and not character.is_obstacle:
				enemy_positions[character.get_instance_id()] = character.grid_pos
		if enemy_positions.is_empty():
			print(">>> SMOKE TEST FAIL: no enemy pieces found on the tutorial board <<<")
			return true
		bc.end_player_turn() # coroutine; frames below let it run through ENEMY_TURN
		ended_turn = true
		return false

	if checked:
		return false
	if bc.current_state != bc.BattleState.PLAYER_TURN or bc.turn_count < 2:
		return false # enemy "turn" still in flight
	checked = true

	for character in get_nodes_in_group("characters"):
		if not (character is BaseCharacter) or not character.is_enemy or character.is_obstacle:
			continue
		var before = enemy_positions.get(character.get_instance_id())
		if before != null and before != character.grid_pos:
			print(">>> SMOKE TEST FAIL: enemy %s moved %s -> %s despite ai_enabled = false <<<" % [character.name, before, character.grid_pos])
			return true

	print("SMOKE_TUTORIAL_AI_OK (turn %d reached, %d enemies never moved)" % [bc.turn_count, enemy_positions.size()])
	return false
