extends SceneTree

# AI difficulty curse synergy (plans/AI_DIFFICULTY_PLAN.md M4, §2.6): IMPOSSIBLE-only
# `curse_synergy` steers a stunning_gaze-cursed enemy queen toward ending its move
# nearest the HIGHER-value of two visible player pieces, instead of whichever one
# happens to be nearest by raw distance from wherever it started. stunning_gaze's
# on_action_taken always targets the nearest VISIBLE ally after the move completes -
# the AI can't change that it targets nearest, but it CAN change WHICH piece ends up
# nearest by choosing where to stand.
#
# Enemy queen (5,5), no direct captures available (neither ally piece lies on one of
# the queen's 8 principal directions from its start - see per-piece comments below).
# Candidate A=(5,4): only the low-value pawn (2,4) is visible from there (same row).
# Candidate B=(5,6): only the high-value KNIGHT (2,6) is visible from there (same
# row). The "high value" piece is deliberately a knight, not another queen/rook -
# its jump-only geometry means it CANNOT reach back to threaten our queen at B (the
# offset (3,0) isn't a knight jump), even though OUR queen's sliding LOS can still
# see it along the row. An earlier version of this test used a second queen there
# and failed for the RIGHT reason: minimax correctly declined to stand next to a
# piece that could immediately recapture, since that queen's own move_range (8)
# covered the same line right back. Visibility and threat-range are decoupled here
# on purpose so this test isolates curse_synergy's positioning bonus specifically,
# without also tripping the (working-as-intended) danger-avoidance search.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_ai_curse_synergy.gd --quit-after 8

var battle_instance
var player_manager
var settings_manager
var curse_data
var reported := false
var fails := 0

const ENEMY_POS := Vector2i(5, 5)
const CANDIDATE_A := Vector2i(5, 4) # near the low-value pawn
const CANDIDATE_B := Vector2i(5, 6) # near the high-value knight
const LOW_VALUE_POS := Vector2i(2, 4)
const HIGH_VALUE_POS := Vector2i(2, 6)

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		fails += 1

func _initialize():
	print(">>> SMOKE TEST: AI curse synergy (stunning_gaze positioning) <<<")
	player_manager = root.get_node("PlayerManager")
	settings_manager = root.get_node("SettingsManager")
	curse_data = root.get_node("CurseData")
	battle_instance = BattleBoot.boot(self)
	var enemies: Array[String] = ["enemy_queen"]
	player_manager.enemy_party = enemies
	player_manager.active_enemies = enemies.duplicate()
	var roster: Array[String] = ["friendly_pawn", "friendly_knight"]
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

	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and c.is_obstacle:
			grid_manager.vacate(c.grid_pos)
			c.queue_free()

	var enemy_queen: BaseCharacter = null
	var low_value_pawn: BaseCharacter = null
	var high_value_knight: BaseCharacter = null
	for c in grid_manager.get_all_characters():
		if not is_instance_valid(c) or not (c is BaseCharacter):
			continue
		if c.is_enemy and c.strName == "queen":
			enemy_queen = c
		elif not c.is_enemy and c.strName == "pawn":
			low_value_pawn = c
		elif not c.is_enemy and c.strName == "knight":
			high_value_knight = c

	if enemy_queen == null or low_value_pawn == null or high_value_knight == null:
		print("SMOKE TEST FAIL: need an enemy queen + an ally pawn + an ally knight on the board")
		return false

	_teleport(grid_manager, enemy_queen, ENEMY_POS)
	_teleport(grid_manager, low_value_pawn, LOW_VALUE_POS)
	_teleport(grid_manager, high_value_knight, HIGH_VALUE_POS)
	enemy_queen.apply_curse(curse_data.create_curse("stunning_gaze"))
	enemy_queen.has_spotted_player = true
	enemy_queen.last_known_player_pos = low_value_pawn.grid_pos

	var valid_targets := enemy_queen.calculate_valid_targets()
	_check("neither ally is directly capturable from the enemy queen's start (off-axis)",
		not (LOW_VALUE_POS in valid_targets) and not (HIGH_VALUE_POS in valid_targets))
	_check("candidate A (near the pawn) is a valid move", CANDIDATE_A in valid_targets)
	_check("candidate B (near the high-value knight) is a valid move", CANDIDATE_B in valid_targets)

	var danger_tiles: Array[Vector2i] = grid_manager.tiles_reachable_by(false)
	_check("candidate B is not itself dangerous (the knight's jump geometry can't reach back)",
		not (CANDIDATE_B in danger_tiles))

	# Direct hook-level check (deterministic, independent of full-tier scoring/board
	# geometry noise): the curse's own ai_positioning_bonus must score ending up
	# near the HIGH-value knight higher than ending up near the low-value pawn.
	var strategy := EnemyAIStrategy.new({})
	var snapshot: Dictionary = strategy._build_snapshot(enemy_queen)
	var snapshot_a: Dictionary = strategy._simulate_move(snapshot, ENEMY_POS, CANDIDATE_A)
	var snapshot_b: Dictionary = strategy._simulate_move(snapshot, ENEMY_POS, CANDIDATE_B)
	var bonus_a: float = enemy_queen.curse.ai_positioning_bonus(enemy_queen, CANDIDATE_A, snapshot_a)
	var bonus_b: float = enemy_queen.curse.ai_positioning_bonus(enemy_queen, CANDIDATE_B, snapshot_b)
	_check("ai_positioning_bonus favors ending up nearest the HIGHER-value piece",
		bonus_b > bonus_a)
	_check("ai_positioning_bonus is 0 with no visible ally (empty snapshot)",
		enemy_queen.curse.ai_positioning_bonus(enemy_queen, CANDIDATE_A, {}) == 0.0)

	# Default hook sanity: a curse WITHOUT an override (frenzy) always returns 0.0.
	# NAMENOMA netipizirano (ne "var frenzy: BaseCurse") - --script entry skripta,
	# glej opombo pri "var curse" v base_character.gd/curse_data.gd v tej datoteki.
	var frenzy = curse_data.create_curse("frenzy")
	_check("BaseCurse default ai_positioning_bonus is 0.0 for curses without an override",
		frenzy.ai_positioning_bonus(enemy_queen, CANDIDATE_B, snapshot_b) == 0.0)

	# Full end-to-end tier check: IMPOSSIBLE (curse_synergy on) should end up
	# somewhere that results in the curse targeting the HIGH-value knight, not
	# necessarily candidate B exactly - the row (5,6)/(6,6)/(7,6)/... all see the
	# knight along the same line and score identically on the curse bonus, so
	# secondary terms (mobility/board-control) may reasonably pick any of them.
	# What matters is WHICH piece ends up nearest, not the exact tile.
	settings_manager.ai_difficulty = "impossible"
	var impossible_action: Dictionary = enemy_queen.calculate_best_move()
	var final_pos: Vector2i = impossible_action.get("target_pos", Vector2i(-99, -99))
	var final_snapshot: Dictionary = strategy._simulate_move(snapshot, ENEMY_POS, final_pos)
	var final_seen: Array[Vector2i] = EnemyAIStrategy.snapshot_visible_positions(
		final_snapshot, final_pos, enemy_queen.get_move_directions(), enemy_queen.move_range, enemy_queen.is_enemy)
	var final_nearest_value := 0
	var final_nearest_dist := INF
	for pos in final_seen:
		var dist: float = Vector2(final_pos).distance_to(Vector2(pos))
		if dist < final_nearest_dist:
			final_nearest_dist = dist
			final_nearest_value = final_snapshot.get(pos, {}).get("value", 1)
	_check("IMPOSSIBLE ends up somewhere the curse would target the HIGH-value knight (value 3), not the low-value pawn (value 1)",
		final_nearest_value == 3)

	# EXTREME (curse_synergy off) sanity - still returns a legal move, doesn't crash
	# just because character.curse is set (the flag being off must be a true no-op).
	_teleport(grid_manager, enemy_queen, ENEMY_POS)
	settings_manager.ai_difficulty = "extreme"
	var extreme_action: Dictionary = enemy_queen.calculate_best_move()
	_check("EXTREME (no curse_synergy) still returns a legal move with a curse present",
		extreme_action.get("target_pos", Vector2i(-99, -99)) in valid_targets)

	if fails == 0:
		print(">>> SMOKE_AI_CURSE_SYNERGY_OK <<<")
	else:
		print("SMOKE TEST FAIL: %d AI curse synergy checks failed" % fails)

	return false
