extends SceneTree

# AI improvements (Phase 5, base_character.calculate_best_move), decision-making now
# delegated to Scripts/AI/enemy_ai_strategy.gd per SettingsManager.ai_difficulty (see
# plans/AI_DIFFICULTY_PLAN.md):
#   1. Value-aware capture (always on): with a pawn AND a queen both
#      capturable in the same move, the AI takes the queen (higher
#      GameParameters/ai_config.json piece_values).
#   2. Danger avoidance (ai_difficulty-gated, HARD = 100% deterministic, NORMAL =
#      50% probabilistic): among two equal-score chase candidates, the one an
#      ally could capture next turn is avoided in favor of the equally-good safe
#      one - HARD always avoids, NORMAL avoids only sometimes (see TEST 2 below).
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
	# Explicit roster (pawn value 1, queen value 9 in GameParameters/ai_config.json) so
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
	# TEST 2: danger avoidance on HARD (ai_difficulty, decoupled from the curse
	# "difficulty" setting - see plans/AI_DIFFICULTY_PLAN.md §2.1). Enemy PAWN
	# (8-directional - a rook can't move diagonally, so it can't tie here) at
	# (5,5) chasing last_known_player_pos = (6,7): two tiles tie for the best
	# chase score (distance 1) - (5,7) [south, reached FIRST in
	# get_move_directions() order, so it's the AI's undefended pick] and (6,6)
	# [south-east]. Put a lone ally pawn at (5,9) whose own move north covers
	# exactly (5,7) (not (6,6)) - on HARD (danger_avoid_prob = 1.0), the AI must
	# prefer the untied-but-safe (6,6) instead. Move the rook far away first so
	# it doesn't sit on/block any of these tiles.
	# ---------------------------------------------------------------
	settings_manager.ai_difficulty = "hard"

	_teleport(grid_manager, enemy_rook, Vector2i(11, 11))
	_teleport(grid_manager, enemy_pawn, Vector2i(5, 5))
	_teleport(grid_manager, pawn, Vector2i(5, 9)) # the lone "defender" ally
	# Move the queen far away so it doesn't also contribute to the danger set.
	# NOT (0,0): that sits exactly on the (0,0)-(1,1)-...-(5,5)-(6,6) diagonal -
	# post-M3 bugfix, avoid_hanging_pieces now correctly simulates the enemy
	# pawn's own move first, so a queen sitting on that diagonal would see her
	# own line through the pawn's vacated (5,5) newly opened all the way to
	# (6,6) once the pawn moves there - a REAL exposure a live pre-move check
	# structurally cannot see (see enemy_ai_strategy.gd's _hanging_piece_is_safe
	# comment), which would make (6,6) look dangerous too and defeat this test's
	# premise. (11,0) is off that diagonal and off row 5/column 5 entirely.
	_teleport(grid_manager, queen, Vector2i(11, 0))
	enemy_pawn.has_spotted_player = true
	enemy_pawn.last_known_player_pos = Vector2i(6, 7)

	var danger_tiles: Array[Vector2i] = grid_manager.tiles_reachable_by(false)
	_check("(5,7) is in the ally's danger set", Vector2i(5, 7) in danger_tiles)
	_check("(6,6) is NOT in the ally's danger set", not (Vector2i(6, 6) in danger_tiles))

	var hard_action: Dictionary = enemy_pawn.calculate_best_move()
	_check("HARD ai_difficulty steers the tied chase away from the dangerous tile",
		hard_action.get("target_pos", Vector2i(-99, -99)) == Vector2i(6, 6))

	# NORMAL is the new floor (no AI-difficulty EASY rung, see plan §6) and its
	# danger_avoid_prob is 0.5, NOT the old curse-difficulty EASY's 0.0 - the
	# regression-safety anchor (plan §2.1) is "reproduces curse-difficulty NORMAL's
	# 50%", not "reproduces EASY's deterministic 0%". A single call can't assert a
	# fixed outcome at p=0.5, so run many trials from the same tied position and
	# confirm BOTH outcomes appear in a roughly balanced split - proves
	# danger-avoidance is live-but-probabilistic here, distinct from HARD's
	# deterministic 100% above (and distinct from a silently-broken 0%/100%).
	settings_manager.ai_difficulty = "normal"
	const NORMAL_TRIALS := 200
	var normal_dangerous_count := 0
	var normal_safe_count := 0
	for i in range(NORMAL_TRIALS):
		_teleport(grid_manager, enemy_pawn, Vector2i(5, 5))
		enemy_pawn.has_spotted_player = true
		enemy_pawn.last_known_player_pos = Vector2i(6, 7)
		var normal_action: Dictionary = enemy_pawn.calculate_best_move()
		var picked: Vector2i = normal_action.get("target_pos", Vector2i(-99, -99))
		if picked == Vector2i(5, 7):
			normal_dangerous_count += 1
		elif picked == Vector2i(6, 6):
			normal_safe_count += 1
	_check("NORMAL ai_difficulty (danger_avoid_prob=0.5) picks BOTH the dangerous and the safe tile across %d trials (probabilistic, not deterministic)" % NORMAL_TRIALS,
		normal_dangerous_count > 0 and normal_safe_count > 0)
	_check("NORMAL ai_difficulty's two outcomes are roughly balanced (no silent 0%%/100%% regression)",
		normal_dangerous_count >= NORMAL_TRIALS * 0.25 and normal_safe_count >= NORMAL_TRIALS * 0.25)

	if fails == 0:
		print(">>> SMOKE_AI_OK <<<")
	else:
		print("SMOKE TEST FAIL: %d AI checks failed" % fails)

	return false
