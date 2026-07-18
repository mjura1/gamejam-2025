extends SceneTree

# Items "barricade" (drop an is_obstacle wall on an empty tile, same logic
# as the level-generated House obstacle, see Scripts/Neutral/house.gd) and
# "flare" (reveal a 3x3 fog area around a chosen tile, same
# GridManager.reveal_area/square_radius_tiles helpers as Rook.Lookout, see
# Scripts/CharacterPieces/Ally/rook.gd._do_lookout). Boots a real battle,
# drives both items through the real battle_ui.use_item() path and checks
# the resulting grid/fog state.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_barricade_flare.gd --quit-after 4

var battle_instance
var player_manager
var reported := false
var fails := 0

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		fails += 1

func _initialize():
	print(">>> SMOKE TEST: barricade + flare items <<<")
	battle_instance = BattleBoot.boot(self)
	player_manager = root.get_node("PlayerManager")

func _process(_delta: float) -> bool:
	if reported or not is_instance_valid(battle_instance):
		return false

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if not battle_controller or battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return false # still waiting for placement to complete

	reported = true

	var grid_manager = battle_instance.get_node("GridManager")
	var battle_ui = battle_instance.get_node("BattleUI")
	var used_rect: Rect2i = battle_instance.get_node("Map/TileMapLayer").get_used_rect()

	# Hiše (ovire) so naključno generirane vsak zagon - poišči prosto polje.
	var empty_pos := Vector2i(-1, -1)
	for x in range(used_rect.position.x, used_rect.end.x):
		var candidate := Vector2i(x, 6)
		if not grid_manager.is_occupied(candidate):
			empty_pos = candidate
			break
	if empty_pos == Vector2i(-1, -1):
		print("SMOKE TEST FAIL: could not find a free tile to test barricade/flare")
		return false

	# --- barricade ---
	player_manager.add_item("barricade", 1)
	var ok_barricade: bool = battle_ui.use_item("barricade", empty_pos)
	_check("use_item(barricade) returns true on an empty tile", ok_barricade)
	_check("tile is occupied after barricade", grid_manager.is_occupied(empty_pos))
	var placed = grid_manager.get_character_at(empty_pos)
	_check("placed piece is an obstacle", is_instance_valid(placed) and placed.is_obstacle)
	_check("barricade consumed from inventory", player_manager.get_item_count("barricade") == 0)

	var ok_barricade_occupied: bool = battle_ui.use_item("barricade", empty_pos)
	_check("use_item(barricade) refuses without inventory/on an occupied tile", not ok_barricade_occupied)

	# --- flare ---
	var flare_pos := Vector2i(clampi(empty_pos.x, used_rect.position.x + 1, used_rect.end.x - 2), used_rect.position.y)
	grid_manager._spawn_fog_tile(flare_pos)
	_check("(setup) flare target is fogged before use", grid_manager.fog_nodes.has(flare_pos))

	player_manager.add_item("flare", 1)
	var ok_flare: bool = battle_ui.use_item("flare", flare_pos)
	_check("use_item(flare) returns true", ok_flare)
	_check("flare target tile is no longer fogged", not grid_manager.fog_nodes.has(flare_pos))
	_check("flare consumed from inventory", player_manager.get_item_count("flare") == 0)

	if fails == 0:
		print(">>> SMOKE TEST: barricade + flare items work <<<")
	else:
		print("SMOKE TEST FAIL: %d barricade/flare checks failed" % fails)

	return false
