extends SceneTree

# Item "spyglass": selecting a piece marks which of its valid moves an enemy
# could capture next turn (map_behaviour.gd._compute_risk_tiles, wired into
# _apply_selection). Boots a real battle, teleports an ally pawn and a lone
# enemy pawn onto a shared axis 2 tiles apart (both pawns have move_range 2
# and slide along all 8 directions - see pawn.gd) so a contested empty tile
# sits exactly between them, then asserts _compute_risk_tiles flags it and
# the real MoveHighlighter.risk_tiles picks it up via a real selection.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_spyglass.gd --quit-after 4

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
	print(">>> SMOKE TEST: spyglass risk tiles <<<")
	player_manager = root.get_node("PlayerManager")
	battle_instance = BattleBoot.boot(self)
	var enemies: Array[String] = ["enemy_pawn"]
	player_manager.enemy_party = enemies
	player_manager.active_enemies = enemies.duplicate()

func _process(_delta: float) -> bool:
	if reported or not is_instance_valid(battle_instance):
		return false

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if not battle_controller or battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return false # still waiting for placement to complete

	reported = true
	player_manager.add_item("spyglass", 1)

	var grid_manager = battle_instance.get_node("GridManager")
	var ally: BaseCharacter = null
	var enemy: BaseCharacter = null
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and not c.is_obstacle:
			if c.is_enemy:
				enemy = c
			elif ally == null:
				ally = c

	if ally == null or enemy == null:
		print("SMOKE TEST FAIL: could not find both an ally and an enemy pawn on the board")
		return false

	# Hiše (ovire) so naključno generirane vsak zagon - poišči prvi prosti
	# stolpec, kjer so vse 3 pozicije (ally/contested/enemy) proste.
	var used_rect: Rect2i = battle_instance.get_node("Map/TileMapLayer").get_used_rect()
	var ally_pos := Vector2i(-1, -1)
	var enemy_pos := Vector2i(-1, -1)
	var contested := Vector2i(-1, -1)
	for x in range(used_rect.position.x, used_rect.end.x):
		var candidate_ally := Vector2i(x, 5)
		var candidate_contested := Vector2i(x, 3)
		var candidate_enemy := Vector2i(x, 1)
		if grid_manager.is_inside_boundary(candidate_ally, used_rect) \
				and grid_manager.is_inside_boundary(candidate_contested, used_rect) \
				and grid_manager.is_inside_boundary(candidate_enemy, used_rect) \
				and (not grid_manager.is_occupied(candidate_ally) or grid_manager.get_character_at(candidate_ally) == ally) \
				and not grid_manager.is_occupied(candidate_contested) \
				and (not grid_manager.is_occupied(candidate_enemy) or grid_manager.get_character_at(candidate_enemy) == enemy):
			ally_pos = candidate_ally
			contested = candidate_contested
			enemy_pos = candidate_enemy
			break

	if ally_pos == Vector2i(-1, -1):
		print("SMOKE TEST FAIL: could not find a free 3-tile column for the spyglass setup")
		return false

	grid_manager.vacate(ally.grid_pos)
	ally.grid_pos = ally_pos
	grid_manager.occupy(ally_pos, ally)
	ally.global_position = grid_manager.grid_to_world(ally_pos)

	grid_manager.vacate(enemy.grid_pos)
	enemy.grid_pos = enemy_pos
	grid_manager.occupy(enemy_pos, enemy)
	enemy.global_position = grid_manager.grid_to_world(enemy_pos)

	var map_behaviour = battle_instance.get_node("Map")
	var valid_moves := ally.calculate_valid_targets()
	_check("contested tile is a valid ally move", contested in valid_moves)

	var risk_tiles: Array[Vector2i] = map_behaviour._compute_risk_tiles(valid_moves)
	_check("_compute_risk_tiles flags the contested tile", contested in risk_tiles)

	map_behaviour.select_character_via_ui(ally)
	var move_highlighter = battle_instance.get_node("MoveHighlighter")
	_check("real selection populates MoveHighlighter.risk_tiles with the contested tile",
		contested in move_highlighter.risk_tiles)

	map_behaviour._clear_selection()
	_check("clearing the selection clears risk_tiles too", move_highlighter.risk_tiles.is_empty())

	if fails == 0:
		print(">>> SMOKE TEST: spyglass risk tiles work <<<")
	else:
		print("SMOKE TEST FAIL: %d spyglass checks failed" % fails)

	return false
