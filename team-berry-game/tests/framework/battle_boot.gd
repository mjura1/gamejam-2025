extends RefCounted
class_name BattleBoot

# Shared setup for smoke tests that need a live Battle instance without going
# through the main menu. Replicates what GF._initialize_game() normally does
# (current_map_instance + game_initialized) before spawning battle.tscn.
static func boot(tree: SceneTree) -> Node:
	var player_manager = tree.root.get_node("PlayerManager")
	player_manager.setStarting()
	player_manager.resetActives()

	var gf = tree.root.get_node("GF")
	var map_scene: PackedScene = load("res://Scenes/Map/map.tscn")
	gf.current_map_instance = map_scene.instantiate()
	gf.current_map_instance.name = "MapInstance"
	gf.game_initialized = true

	var battle_scene: PackedScene = load("res://Scenes/Map/battle.tscn")
	var battle_instance = battle_scene.instantiate()
	tree.root.add_child(battle_instance)
	tree.current_scene = battle_instance
	return battle_instance
