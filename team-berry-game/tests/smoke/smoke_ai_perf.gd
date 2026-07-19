extends SceneTree

# AI difficulty performance guardrail (plans/AI_DIFFICULTY_PLAN.md M5): times
# calculate_best_move() at IMPOSSIBLE (depth-2 alpha-beta minimax, every tier flag
# on) across a realistic worst-case enemy count.
#
# Worst case, derived from the actual codebase (not guessed): battle.gd caps enemy
# spawns at `map_width * enemy_spawn_rows.size()` = 12 * 2 = 24 - PlayerManager's
# enemy_party GROWS across every battle within a map tier (add_to_enemy_party,
# reset only on a new tier) and infinite mode keeps that growth going forever past
# Tier 2, so 24 is the actual hard ceiling this codebase will ever ask the AI to
# handle in one turn, not an arbitrary guess. Mix proportioned to Tier 2's
# TIER_CONFIGS enemy_pool weights (pawn 5 : knight 3 : rook 4 : bishop 2 : queen 1)
# for a realistic worst case rather than an artificial all-queens extreme.
#
# DEVIATION from the plan's literal "time one full start_enemy_turn() pass": that
# coroutine awaits BattleController.ENEMY_MOVE_DELAY (0.3s) per action for the move
# flash/pause - purely a UI pacing cost, unrelated to AI decision cost, and it would
# swamp the number this milestone actually cares about (24 * 0.3s = 7.2s of pure
# sleep, dwarfing any real search-time signal or regression). Times the sum of
# calculate_best_move() calls directly instead - the actual expensive part - on a
# STATIC board (moves computed but not applied), which is if anything a slightly
# PESSIMISTIC/conservative estimate versus a real turn (a real turn thins out via
# captures as it goes, making later pieces' searches cheaper; this keeps the board
# fully loaded for every single evaluation).
#
# No hard frame budget exists elsewhere in this codebase to match against (per the
# plan) - prints the measured time so Miha can judge by feel, and only hard-fails on
# a generous sanity ceiling (a catastrophic regression - seconds becoming tens of
# seconds - not a tuned budget).
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_ai_perf.gd --quit-after 8

const ENEMY_SPAWN_SLOTS := 24 # map_width(12) * enemy_spawn_rows.size()(2), see battle.gd
const SANITY_CEILING_MS := 5000 # generous - a real regression should blow way past this

var battle_instance
var player_manager
var settings_manager
var reported := false
var fails := 0

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		fails += 1

func _build_worst_case_enemy_roster() -> Array[String]:
	# Tier 2 enemy_pool weights (MapGenerator.TIER_CONFIGS[2]): pawn 5, knight 3,
	# rook 4, bishop 2, queen 1 (total 15) - repeat the weighted cycle to fill
	# ENEMY_SPAWN_SLOTS for a realistic mix, not an artificial all-queens worst case.
	var weighted_cycle: Array[String] = []
	for i in range(5):
		weighted_cycle.append("enemy_pawn")
	for i in range(3):
		weighted_cycle.append("enemy_knight")
	for i in range(4):
		weighted_cycle.append("enemy_rook")
	for i in range(2):
		weighted_cycle.append("enemy_bishop")
	weighted_cycle.append("enemy_queen")

	var roster: Array[String] = []
	while roster.size() < ENEMY_SPAWN_SLOTS:
		for piece in weighted_cycle:
			if roster.size() >= ENEMY_SPAWN_SLOTS:
				break
			roster.append(piece)
	return roster

func _initialize():
	print(">>> SMOKE TEST: AI difficulty performance guardrail (IMPOSSIBLE, %d enemies) <<<" % ENEMY_SPAWN_SLOTS)
	player_manager = root.get_node("PlayerManager")
	settings_manager = root.get_node("SettingsManager")
	battle_instance = BattleBoot.boot(self)
	var enemies: Array[String] = _build_worst_case_enemy_roster()
	player_manager.enemy_party = enemies
	player_manager.active_enemies = enemies.duplicate()
	var roster: Array[String] = ["friendly_king", "friendly_queen"]
	player_manager.friendly_party = roster

func _process(_delta: float) -> bool:
	if reported or not is_instance_valid(battle_instance):
		return false

	var battle_controller = battle_instance.get_node_or_null("BattleController")
	if not battle_controller or battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
		return false # still waiting for placement to complete

	reported = true

	var grid_manager = battle_instance.get_node("GridManager")
	settings_manager.ai_difficulty = "impossible"

	var enemies: Array = []
	for c in grid_manager.get_all_characters():
		if not is_instance_valid(c) or not (c is BaseCharacter):
			continue
		if c.is_enemy and not c.is_obstacle:
			enemies.append(c)
			c.has_spotted_player = true

	var friendly_pos := Vector2i(-1, -1)
	for c in grid_manager.get_all_characters():
		if is_instance_valid(c) and c is BaseCharacter and not c.is_enemy and not c.is_obstacle:
			friendly_pos = c.grid_pos
			break
	for e in enemies:
		e.last_known_player_pos = friendly_pos

	_check("spawned the full %d-enemy worst-case roster" % ENEMY_SPAWN_SLOTS, enemies.size() == ENEMY_SPAWN_SLOTS)

	var start_ms := Time.get_ticks_msec()
	for e in enemies:
		e.calculate_best_move()
	var elapsed_ms := Time.get_ticks_msec() - start_ms

	print(">>> AI_PERF: %d enemies @ IMPOSSIBLE, calculate_best_move() total = %d ms (avg %.1f ms/enemy) <<<" \
		% [enemies.size(), elapsed_ms, float(elapsed_ms) / maxf(1.0, float(enemies.size()))])
	_check("total decision time stays under the sanity ceiling (%d ms) - see file header for why this isn't a tuned budget" % SANITY_CEILING_MS,
		elapsed_ms < SANITY_CEILING_MS)

	if fails == 0:
		print(">>> SMOKE_AI_PERF_OK <<<")
	else:
		print("SMOKE TEST FAIL: %d AI perf checks failed" % fails)

	return false
