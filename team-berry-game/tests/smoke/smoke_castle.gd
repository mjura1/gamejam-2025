extends SceneTree

# Item "castle": the king cannot be captured while a friendly rook has line
# of sight to him (calculate_valid_targets()'s capture-immune break, see
# base_character.gd.is_castle_protected()). Boots a real battle with a king
# + rook vs an enemy rook lined up on a shared free column, checks the
# enemy's valid targets exclude the king's tile while the friendly rook is
# in LOS, then moves the friendly rook away and checks the king becomes a
# valid target again.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_castle.gd --quit-after 4

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
	print(">>> SMOKE TEST: castle item protects the king in rook LOS <<<")
	player_manager = root.get_node("PlayerManager")
	battle_instance = BattleBoot.boot(self)
	var friendly: Array[String] = ["friendly_king", "friendly_rook"]
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
	player_manager.add_item("castle", 1)

	var grid_manager = battle_instance.get_node("GridManager")
	var king: BaseCharacter = null
	var rook: BaseCharacter = null
	var enemy: BaseCharacter = null
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and not c.is_obstacle:
			if c.is_enemy:
				enemy = c
			elif c.strName == "king":
				king = c
			elif c.strName == "rook":
				rook = c

	if king == null or rook == null or enemy == null:
		print("SMOKE TEST FAIL: could not find king, friendly rook and enemy rook on the board")
		return false

	# Hiše so naključno generirane vsak zagon - poišči prvi prosti stolpec za
	# king(y=5)/rook(y=3)/enemy(y=1) KJER JE CELOTNA VRSTICA (y=1..5) prosta,
	# da hiša med njimi ne blokira trdnjavinega drsenja (false negative).
	var used_rect: Rect2i = battle_instance.get_node("Map/TileMapLayer").get_used_rect()
	var king_pos := Vector2i(-1, -1)
	var rook_pos := Vector2i(-1, -1)
	var enemy_pos := Vector2i(-1, -1)
	for x in range(used_rect.position.x, used_rect.end.x):
		var column_clear := true
		for y in range(1, 6):
			var pos := Vector2i(x, y)
			if not grid_manager.is_inside_boundary(pos, used_rect):
				column_clear = false
				break
			if grid_manager.is_occupied(pos) and grid_manager.get_character_at(pos) not in [king, rook, enemy]:
				column_clear = false
				break
		if column_clear:
			king_pos = Vector2i(x, 5)
			rook_pos = Vector2i(x, 3)
			enemy_pos = Vector2i(x, 1)
			break

	if king_pos == Vector2i(-1, -1):
		print("SMOKE TEST FAIL: could not find a free 3-tile column for the castle setup")
		return false

	for pair in [[king, king_pos], [rook, rook_pos], [enemy, enemy_pos]]:
		var piece: BaseCharacter = pair[0]
		var pos: Vector2i = pair[1]
		grid_manager.vacate(piece.grid_pos)
		piece.grid_pos = pos
		grid_manager.occupy(pos, piece)
		piece.global_position = grid_manager.grid_to_world(pos)

	_check("king is castle-protected with the friendly rook in LOS", king.is_castle_protected())
	_check("enemy's valid targets do NOT include the protected king",
		not (king_pos in enemy.calculate_valid_targets()))

	# Premakni prijateljsko trdnjavo STRAN OD kraljeve vrstice IN stolpca
	# (is_castle_protected preverja vse 4 ravne smeri), da LOS zares prekinemo.
	var away_pos := Vector2i(-1, -1)
	for corner in [Vector2i(used_rect.position.x, used_rect.position.y),
			Vector2i(used_rect.end.x - 1, used_rect.position.y),
			Vector2i(used_rect.position.x, used_rect.end.y - 1),
			Vector2i(used_rect.end.x - 1, used_rect.end.y - 1)]:
		if corner.x != king_pos.x and corner.y != king_pos.y \
				and (not grid_manager.is_occupied(corner) or grid_manager.get_character_at(corner) == rook):
			away_pos = corner
			break
	if away_pos == Vector2i(-1, -1):
		print("SMOKE TEST FAIL: could not find a free tile off the king's row/column")
		return false

	grid_manager.vacate(rook.grid_pos)
	rook.grid_pos = away_pos
	grid_manager.occupy(away_pos, rook)
	rook.global_position = grid_manager.grid_to_world(away_pos)

	_check("king is no longer castle-protected once the rook leaves LOS", not king.is_castle_protected())
	_check("enemy's valid targets now include the unprotected king",
		king_pos in enemy.calculate_valid_targets())

	if fails == 0:
		print(">>> SMOKE TEST: castle item works <<<")
	else:
		print("SMOKE TEST FAIL: %d castle checks failed" % fails)

	return false
