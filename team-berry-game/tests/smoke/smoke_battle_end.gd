extends SceneTree

# Drives a battle to a WIN (all enemies dead) headlessly - the exact path
# T5.1 fixed: die() no longer directly calls GF.return_to_map()/game_over()
# mid-capture; BattleController.check_battle_end() does it instead, deferred,
# after the action that ended the battle has fully resolved.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_battle_end.gd --quit-after 6

var killed_enemies := false

func _initialize():
	print(">>> SMOKE TEST: battle-end WIN path (C7/T5.1) <<<")
	var player_manager = root.get_node("PlayerManager")
	player_manager.setStarting()
	player_manager.resetActives()

	# return_to_map() needs GF.current_map_instance set (normally done by
	# GF._initialize_game() on Start) - replicate that here so the deferred
	# scene-transition path we're testing has somewhere valid to return to.
	var gf = root.get_node("GF")
	var map_scene: PackedScene = load("res://Scenes/Map/map.tscn")
	gf.current_map_instance = map_scene.instantiate()
	gf.current_map_instance.name = "MapInstance"
	gf.game_initialized = true

	var battle_scene: PackedScene = load("res://Scenes/Map/battle.tscn")
	var battle_instance = battle_scene.instantiate()
	root.add_child(battle_instance)

func _process(_delta: float) -> bool:
	var battle_instance = root.get_node_or_null("Battle")
	if battle_instance == null:
		print(">>> SMOKE TEST: Battle scene left the tree - transition happened cleanly <<<")
		return false

	if killed_enemies:
		return true # give the deferred call a frame to fire

	var grid_manager = battle_instance.get_node_or_null("GridManager")
	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if grid_manager == null or battle_controller == null:
		return true # still spawning

	var enemies: Array = []
	for character in grid_manager.get_all_characters():
		if character is BaseCharacter and character.is_enemy:
			enemies.append(character)

	if enemies.is_empty():
		return true # pieces haven't spawned yet

	print(">>> SMOKE TEST: killing %d enemies to force a WIN <<<" % enemies.size())
	for enemy in enemies:
		enemy.die()
	killed_enemies = true

	# Same check the real turn loop runs right after an action resolves.
	battle_controller.check_battle_end()
	return true
