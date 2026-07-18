extends SceneTree

# AI improvements (Phase 5, base_character.calculate_best_move):
#   1. Value-aware capture (always on): with a pawn AND a queen both
#      capturable in the same move, the AI takes the queen (higher
#      Data/ai_config.json piece_values).
#   2. Danger avoidance (difficulty-gated, HARD = 100%): among two
#      equal-score chase candidates, the one an ally could capture next
#      turn is avoided in favor of the equally-good safe one.
#
# Fully synchronous (calls calculate_best_move()/BaseCharacter fields
# directly - no BattleController coroutine involved), so this is a plain
# linear script like smoke_item_use.gd, not a frame-polled state machine
# (contrast smoke_curses.gd).
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_ai.gd --quit-after 4

var battle_instance
var player_manager
var settings_manager # avtoload - ni bare identifikator v --script entry skripti
var reported := false
var fails := 0

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		fails += 1

func _initialize():
	print(">>> SMOKE TEST: AI improvements (value-aware capture + danger avoidance) <<<")
	player_manager = root.get_node("PlayerManager")
	settings_manager = root.get_node("SettingsManager")
	battle_instance = BattleBoot.boot(self)
	# enemy_rook for TEST 1 (needs 2 simultaneous straight-line captures);
	# enemy_pawn for TEST 2 (needs 8-directional movement for the diagonal
	# tie - a rook can't move diagonally at all).
	var enemies: Array[String] = ["enemy_rook", "enemy_pawn"]
	player_manager.enemy_party = enemies
	player_manager.active_enemies = enemies.duplicate()
	# Explicit roster (pawn value 1, queen value 9 in Data/ai_config.json) so
	# the value-aware capture check has a real, known value gap to assert on -
	# BattleBoot.boot()'s default roster composition is otherwise not part of
	# this test's contract.
	var roster: Array[String] = ["friendly_pawn", "friendly_queen"]
	player_manager.friendly_party = roster

func _teleport(grid_manager, character: BaseCharacter, pos: Vector2i):
	grid_manager.vacate(character.grid_pos)
	character.grid_pos = pos
	grid_manager.occupy(pos, character)
	character.global_position = grid_manager.grid_to_world(pos)

func _process(_delta: float) -> bool:
	if reported or not is_instance_valid(battle_instance):
		return false

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if not battle_controller or battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return false # still waiting for placement to complete

	reported = true

	var grid_manager = battle_instance.get_node("GridManager")

	# Clear randomly-spawned obstacles - they'd otherwise occasionally sit on
	# one of the hand-picked coordinates below and break a teleport.
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and c.is_obstacle:
			grid_manager.vacate(c.grid_pos)
			c.queue_free()

	var enemy_rook: BaseCharacter = null
	var enemy_pawn: BaseCharacter = null
	var pawn: BaseCharacter = null
	var queen: BaseCharacter = null
	for c in grid_manager.get_all_characters():
		if not is_instance_valid(c) or not (c is BaseCharacter):
			continue
		if c.is_enemy:
			if c.strName == "rook" and enemy_rook == null:
				enemy_rook = c
			elif c.strName == "pawn" and enemy_pawn == null:
				enemy_pawn = c
		elif c.strName == "pawn" and pawn == null:
			pawn = c
		elif c.strName == "queen" and queen == null:
			queen = c

	if enemy_rook == null or enemy_pawn == null or pawn == null or queen == null:
		print("SMOKE TEST FAIL: need an enemy rook + an enemy pawn + a pawn ally + a queen ally on the board")
		return false

	# ---------------------------------------------------------------
	# TEST 1: value-aware capture. Enemy rook at (5,5); pawn 2 tiles north
	# (5,3), queen 2 tiles east (7,5) - both simultaneously capturable along
	# the rook's straight lines. AI must take the higher-value queen.
	# ---------------------------------------------------------------
	_teleport(grid_manager, enemy_rook, Vector2i(5, 5))
	_teleport(grid_manager, pawn, Vector2i(5, 3))
	_teleport(grid_manager, queen, Vector2i(7, 5))
	# Park the enemy pawn (used by TEST 2) somewhere it can't interfere here.
	_teleport(grid_manager, enemy_pawn, Vector2i(0, 0))

	enemy_rook.has_spotted_player = true
	enemy_rook.last_known_player_pos = pawn.grid_pos # irrelevant to the capture step itself

	var targets := enemy_rook.calculate_valid_targets()
	_check("both the pawn and the queen are simultaneously capturable",
		pawn.grid_pos in targets and queen.grid_pos in targets)

	var action: Dictionary = enemy_rook.calculate_best_move()
	_check("AI captures instead of just moving", action.get("move_type", "") == "CAPTURE")
	_check("AI takes the higher-value queen over the pawn",
		action.get("target_pos", Vector2i(-99, -99)) == queen.grid_pos)

	# ---------------------------------------------------------------
	# TEST 2: danger avoidance on HARD. Enemy PAWN (8-directional - a rook
	# can't move diagonally, so it can't tie here) at (5,5) chasing
	# last_known_player_pos = (6,7): two tiles tie for the best chase score
	# (distance 1) - (5,7) [south, reached FIRST in get_move_directions()
	# order, so it's the AI's undefended pick] and (6,6) [south-east]. Put a
	# lone ally pawn at (5,9) whose own move north covers exactly (5,7) (not
	# (6,6)) - on HARD (danger_avoid_prob = 1.0), the AI must prefer the
	# untied-but-safe (6,6) instead. Move the rook far away first so it
	# doesn't sit on/block any of these tiles.
	# ---------------------------------------------------------------
	settings_manager.difficulty = "hard"

	_teleport(grid_manager, enemy_rook, Vector2i(11, 11))
	_teleport(grid_manager, enemy_pawn, Vector2i(5, 5))
	_teleport(grid_manager, pawn, Vector2i(5, 9)) # the lone "defender" ally
	# Move the queen far away so it doesn't also contribute to the danger set.
	_teleport(grid_manager, queen, Vector2i(0, 0))
	enemy_pawn.has_spotted_player = true
	enemy_pawn.last_known_player_pos = Vector2i(6, 7)

	var danger_tiles: Array[Vector2i] = grid_manager.tiles_reachable_by(false)
	_check("(5,7) is in the ally's danger set", Vector2i(5, 7) in danger_tiles)
	_check("(6,6) is NOT in the ally's danger set", not (Vector2i(6, 6) in danger_tiles))

	var hard_action: Dictionary = enemy_pawn.calculate_best_move()
	_check("HARD difficulty steers the tied chase away from the dangerous tile",
		hard_action.get("target_pos", Vector2i(-99, -99)) == Vector2i(6, 6))

	# EASY (danger_avoid_prob = 0.0) must behave exactly like before -
	# undefended pick, no avoidance.
	settings_manager.difficulty = "easy"
	_teleport(grid_manager, enemy_pawn, Vector2i(5, 5))
	enemy_pawn.has_spotted_player = true
	enemy_pawn.last_known_player_pos = Vector2i(6, 7)
	var easy_action: Dictionary = enemy_pawn.calculate_best_move()
	_check("EASY difficulty keeps the undefended (dangerous) pick",
		easy_action.get("target_pos", Vector2i(-99, -99)) == Vector2i(5, 7))

	if fails == 0:
		print(">>> SMOKE_AI_OK <<<")
	else:
		print("SMOKE TEST FAIL: %d AI checks failed" % fails)

	return false
