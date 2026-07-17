extends RefCounted
class_name BattleBoot

# Shared setup for smoke tests that need a live Battle instance without going
# through the main menu. Replicates what GF._initialize_game() normally does
# (current_map_instance + game_initialized) before spawning battle.tscn.
# Since the placement feature, battles start in a PLACEMENT state waiting for
# the player to drag pieces onto the board - boot() completes that phase
# programmatically (places the whole roster, up to the UI's max, then confirms)
# so tests land in PLAYER_TURN like before. Use boot_placement_only() to get
# a battle still sitting in the PLACEMENT state.
# NOTE: in a -s MainLoop script, add_child() during _initialize() does NOT run
# _ready() synchronously - the scene wakes up on the first frame. Placement
# completion is therefore hooked (deferred) onto the PLACEMENT state signal,
# and tests should poll for PLAYER_TURN in _process() as they already do.
static func boot(tree: SceneTree) -> Node:
	var battle_instance = boot_placement_only(tree)
	var battle_controller = battle_instance.get_node("BattleController")
	battle_controller.state_changed.connect(func(new_state):
		if new_state == battle_controller.BattleState.PLACEMENT:
			Callable(BattleBoot, "complete_placement").call_deferred(battle_instance)
	)
	return battle_instance

static func boot_placement_only(tree: SceneTree) -> Node:
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

# Places pieces from the roster onto the bottom rows via the battle UI's own
# placement API, then presses START. No-op if the battle skipped placement
# (or already left it, e.g. a test force-ended the battle first).
static func complete_placement(battle_instance: Node) -> void:
	if not is_instance_valid(battle_instance) or not battle_instance.is_inside_tree():
		return
	var battle_controller = battle_instance.get_node("BattleController")
	if battle_controller.current_state != battle_controller.BattleState.PLACEMENT:
		return
	var battle_ui = battle_instance.get_node("BattleUI")
	var player_manager = battle_instance.get_tree().root.get_node("PlayerManager")

	var to_place := {}
	for roster_name in player_manager.friendly_party:
		to_place[roster_name] = to_place.get(roster_name, 0) + 1

	var used_rect: Rect2i = battle_instance.get_node("Map/TileMapLayer").get_used_rect()
	for roster_name in to_place:
		for i in range(to_place[roster_name]):
			var placed := false
			for y in range(used_rect.end.y - 1, used_rect.end.y - 4, -1):
				for x in range(used_rect.position.x, used_rect.end.x):
					if battle_ui.place_piece(roster_name, Vector2i(x, y)):
						placed = true
						break
				if placed:
					break

	battle_ui.confirm_placement()
