extends SceneTree

# Item "mounted_hunters": the player's queen and bishops can also move/
# capture like a knight (true jumps, ignoring blockers). Boots a real
# battle with a lone queen on an empty board, checks an L-tile is NOT a
# valid target before owning the item, IS a valid target once granted, and
# is removed again once un-granted - plus that an enemy queen (same
# script, is_enemy = true) never gets the jump regardless of ownership.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_mounted_hunters.gd --quit-after 4

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
	print(">>> SMOKE TEST: mounted_hunters queen/bishop knight-jump <<<")
	player_manager = root.get_node("PlayerManager")
	battle_instance = BattleBoot.boot(self)
	var friendly: Array[String] = ["friendly_queen"]
	var enemies: Array[String] = ["enemy_queen"]
	player_manager.friendly_party = friendly
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
	var queen: BaseCharacter = null
	var enemy_queen: BaseCharacter = null
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and not c.is_obstacle:
			if c.is_enemy:
				enemy_queen = c
			else:
				queen = c

	if queen == null or enemy_queen == null:
		print("SMOKE TEST FAIL: could not find both a friendly and an enemy queen")
		return false

	var used_rect: Rect2i = battle_instance.get_node("Map/TileMapLayer").get_used_rect()
	var l_tile: Vector2i = Vector2i(-1, -1)
	for offset in queen.KNIGHT_OFFSETS:
		var candidate := queen.grid_pos + offset
		if grid_manager.is_inside_boundary(candidate, used_rect) and not grid_manager.is_occupied(candidate):
			l_tile = candidate
			break
	if l_tile == Vector2i(-1, -1):
		print("SMOKE TEST FAIL: no in-bounds L-tile found for the queen")
		return false

	_check("L-tile is NOT a valid queen move before owning mounted_hunters",
		not (l_tile in queen.calculate_valid_targets()))

	player_manager.add_item("mounted_hunters", 1)
	_check("L-tile IS a valid queen move once mounted_hunters is owned",
		l_tile in queen.calculate_valid_targets())

	var enemy_l_tile: Vector2i = Vector2i(-1, -1)
	for offset in enemy_queen.KNIGHT_OFFSETS:
		var candidate := enemy_queen.grid_pos + offset
		if grid_manager.is_inside_boundary(candidate, used_rect) and not grid_manager.is_occupied(candidate):
			enemy_l_tile = candidate
			break
	if enemy_l_tile != Vector2i(-1, -1):
		_check("enemy queen never gets the knight-jump regardless of ownership",
			not (enemy_l_tile in enemy_queen.calculate_valid_targets()))

	player_manager.remove_item("mounted_hunters")
	_check("L-tile is removed again once mounted_hunters is un-granted",
		not (l_tile in queen.calculate_valid_targets()))

	if fails == 0:
		print(">>> SMOKE TEST: mounted_hunters works <<<")
	else:
		print("SMOKE TEST FAIL: %d mounted_hunters checks failed" % fails)

	return false
