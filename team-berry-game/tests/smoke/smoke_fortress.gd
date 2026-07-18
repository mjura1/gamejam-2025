extends SceneTree

# Item "fortress": enemies cannot enter or cross the straight line between a
# friendly rook and a house in its line of sight. Boots a real battle with a
# rook + a house lined up on a shared free column and a lone enemy on the
# far side of the house, checks the enemy has no valid target on/through
# the line while the item is owned, then un-grants it and checks the path
# opens back up.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_fortress.gd --quit-after 4

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
	print(">>> SMOKE TEST: fortress item blocks the rook-house line <<<")
	player_manager = root.get_node("PlayerManager")
	battle_instance = BattleBoot.boot(self)
	var friendly: Array[String] = ["friendly_rook"]
	var enemies: Array[String] = ["enemy_rook"]
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
	player_manager.add_item("fortress", 1)

	var grid_manager = battle_instance.get_node("GridManager")
	var rook: BaseCharacter = null
	var enemy: BaseCharacter = null
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and not c.is_obstacle:
			if c.is_enemy:
				enemy = c
			else:
				rook = c

	if rook == null or enemy == null:
		print("SMOKE TEST FAIL: could not find both a friendly rook and an enemy rook")
		return false

	# Hiše so naključno generirane - poišči prosto obmocje: stolpec x z
	# rookom (y=7)/hišo (y=5, med rookom in med-poljem)/med-poljem (y=6), IN
	# tri prosta polja v isti vrstici y=6 zahodno, od koder sovražnik pride
	# VODORAVNO do med-polja, ne da bi kdaj prečkal hišo (ki je v drugi
	# vrstici) - s tem izognemo geometrijski dvoumnosti "hiša itak blokira".
	var used_rect: Rect2i = battle_instance.get_node("Map/TileMapLayer").get_used_rect()
	var rook_pos := Vector2i(-1, -1)
	var house_pos := Vector2i(-1, -1)
	var between_pos := Vector2i(-1, -1)
	var enemy_pos := Vector2i(-1, -1)
	for x in range(used_rect.position.x + 3, used_rect.end.x):
		var area_clear := true
		for y in range(1, 8):
			var pos := Vector2i(x, y)
			if not grid_manager.is_inside_boundary(pos, used_rect) \
					or (grid_manager.is_occupied(pos) and grid_manager.get_character_at(pos) not in [rook, enemy]):
				area_clear = false
				break
		if not area_clear:
			continue
		for dx in range(1, 4):
			var pos := Vector2i(x - dx, 6)
			if not grid_manager.is_inside_boundary(pos, used_rect) \
					or (grid_manager.is_occupied(pos) and grid_manager.get_character_at(pos) not in [rook, enemy]):
				area_clear = false
				break
		if area_clear:
			rook_pos = Vector2i(x, 7)
			between_pos = Vector2i(x, 6)
			house_pos = Vector2i(x, 5)
			enemy_pos = Vector2i(x - 3, 6)
			break

	if rook_pos == Vector2i(-1, -1):
		print("SMOKE TEST FAIL: could not find a free column for the fortress setup")
		return false

	grid_manager.vacate(rook.grid_pos)
	rook.grid_pos = rook_pos
	grid_manager.occupy(rook_pos, rook)
	rook.global_position = grid_manager.grid_to_world(rook_pos)

	grid_manager.vacate(enemy.grid_pos)
	enemy.grid_pos = enemy_pos
	grid_manager.occupy(enemy_pos, enemy)
	enemy.global_position = grid_manager.grid_to_world(enemy_pos)

	# Priklical hišo (obstacle) med rooka in tarčo.
	var house_scene: PackedScene = load("res://Scenes/CharacterPiecesNodes/Neutral/House.tscn")
	grid_manager.spawn_character(house_scene, grid_manager.grid_to_world(house_pos))
	var house: BaseCharacter = grid_manager.get_character_at(house_pos)
	_check("a house obstacle was spawned in the rook's LOS", is_instance_valid(house) and house.is_obstacle)

	var blocked: Array[Vector2i] = grid_manager.fortress_blocked_tiles()
	_check("fortress_blocked_tiles includes the strict between-tile", between_pos in blocked)
	_check("fortress_blocked_tiles does NOT include the house tile itself (already an obstacle)",
		not (house_pos in blocked))

	_check("enemy has no valid target on the blocked between-tile",
		not (between_pos in enemy.calculate_valid_targets()))

	player_manager.remove_item("fortress")
	_check("removing fortress opens the path (between-tile reachable again)",
		between_pos in enemy.calculate_valid_targets())

	if fails == 0:
		print(">>> SMOKE TEST: fortress item works <<<")
	else:
		print("SMOKE TEST FAIL: %d fortress checks failed" % fails)

	return false
