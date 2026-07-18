extends SceneTree

# Item "vicious_knights": a friendly knight capture grants +1 move, limited
# to once per player turn (map_behaviour.gd's capture-success branch calls
# battle_controller.add_bonus_move(), guarded by vicious_knight_used - see
# SHOP_V2_PLAN.md Phase 4a). Boots a real battle with a lone knight vs a
# lone enemy pawn, teleports the pawn into the knight's L-reach (same
# vacate/occupy/grid_pos pattern as smoke_enemy_turn_stale_reference.gd),
# then drives the actual capture via knight.try_move() and runs the same
# guard condition map_behaviour's click handler runs. Doesn't simulate the
# mouse click itself - _unhandled_input reads the real viewport mouse
# position rather than the dispatched event's, so headless click simulation
# isn't practical here (same reasoning other direct-call smoke tests use).
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_vicious_knights.gd --quit-after 4

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
	print(">>> SMOKE TEST: vicious_knights bonus move <<<")
	player_manager = root.get_node("PlayerManager")
	battle_instance = BattleBoot.boot(self)
	var friendly: Array[String] = ["friendly_knight"]
	var enemies: Array[String] = ["enemy_pawn"]
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
	player_manager.add_item("vicious_knights", 1)

	var grid_manager = battle_instance.get_node("GridManager")
	var used_rect: Rect2i = battle_instance.get_node("Map/TileMapLayer").get_used_rect()

	var knight: BaseCharacter = null
	var enemy: BaseCharacter = null
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and not c.is_obstacle:
			if c.is_enemy:
				enemy = c
			else:
				knight = c

	if knight == null or enemy == null:
		print("SMOKE TEST FAIL: could not find both a knight and an enemy pawn on the board")
		return false

	# Poišči prvi L-offset znotraj meja plošče in tja teleportiraj sovražnika,
	# da bo natanko na dosegu skakača.
	var target_pos: Vector2i = Vector2i(-1, -1)
	for offset in knight.get_move_directions():
		var candidate := knight.grid_pos + offset
		if grid_manager.is_inside_boundary(candidate, used_rect):
			target_pos = candidate
			break
	if target_pos == Vector2i(-1, -1):
		print("SMOKE TEST FAIL: no in-bounds L-tile found for the knight")
		return false

	grid_manager.vacate(enemy.grid_pos)
	enemy.grid_pos = target_pos
	grid_manager.occupy(target_pos, enemy)
	enemy.global_position = grid_manager.grid_to_world(target_pos)

	_check("latch starts unused at turn start", not battle_controller.vicious_knight_used)

	var moves_before: int = battle_controller.moves_remaining
	var mover := knight
	var captured: bool = mover.try_move(target_pos)
	_check("knight capture succeeds against the teleported enemy", captured)

	# Isti pogoj kot map_behaviour.gd capture-success veja.
	if mover.strName == "knight" and player_manager.has_passive("vicious_knights") \
			and not battle_controller.vicious_knight_used:
		battle_controller.vicious_knight_used = true
		battle_controller.add_bonus_move()
	_check("knight capture grants a bonus move", battle_controller.moves_remaining == moves_before + 1)
	_check("latch is now used", battle_controller.vicious_knight_used)

	# Drugo zajetje v isti potezi ne sme podeliti drugega bonusa (once per turn).
	var moves_before_second: int = battle_controller.moves_remaining
	if mover.strName == "knight" and player_manager.has_passive("vicious_knights") \
			and not battle_controller.vicious_knight_used:
		battle_controller.vicious_knight_used = true
		battle_controller.add_bonus_move()
	_check("second capture same turn grants no extra bonus", battle_controller.moves_remaining == moves_before_second)

	battle_controller.start_player_turn()
	_check("latch resets on the next start_player_turn", not battle_controller.vicious_knight_used)

	if fails == 0:
		print(">>> SMOKE TEST: vicious_knights bonus move works, once-per-turn latch holds <<<")
	else:
		print("SMOKE TEST FAIL: %d vicious_knights checks failed" % fails)

	return false
