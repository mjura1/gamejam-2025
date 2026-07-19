extends SceneTree

# AI difficulty (plans/AI_DIFFICULTY_PLAN.md M3): proves minimax (EXTREME/IMPOSSIBLE)
# and avoid_hanging_pieces (HARD+) are actually doing something, not just present but
# inert - a hand-built "defended pawn" trap where the immediate capture looks great
# (gain a pawn) but is actually a blunder (the square is only reachable by a
# defending rook once the bait pawn is removed - line-of-sight opens up
# post-capture). NORMAL has no protection at all and walks in. HARD/EXTREME/
# IMPOSSIBLE all SIMULATE the capture first (removing the bait pawn), then check the
# post-move position for the now-open defender line - correctly declining the trade.
#
# POST-M3 BUGFIX NOTE: HARD's avoid_hanging_pieces originally checked reachability
# on the LIVE, PRE-move board, which can never see this trap (a same-side-blocking
# gap - see enemy_ai_strategy.gd's _filter_hanging_pieces comment) and made HARD
# walk in identically to NORMAL. Fixed to check POST-move reachability instead, so
# HARD now correctly declines this trap too - it's a real one-ply "is this square
# now defended" check, just not full search. EXTREME/IMPOSSIBLE's minimax remains
# strictly more capable (multi-ply, SEE-ordered, fork-aware) - this specific
# single-ply-detectable trap just no longer happens to be the scenario that
# distinguishes HARD from EXTREME; a deeper/multi-defender scenario would be needed
# for that, left as a possible follow-up rather than in scope for this bugfix.
#
# Enemy rook (5,5) [value 5], bait ally pawn (5,2) [value 1, distance 3 - outside
# panic_distance so panic randomness can't perturb the MOVE result], defender ally
# rook (5,0) directly behind the bait on the same column.
# Run with: godot4 --headless --path . --script res://tests/smoke/smoke_ai_minimax.gd --quit-after 4

var battle_instance
var player_manager
var settings_manager
var reported := false
var fails := 0

const ENEMY_POS := Vector2i(5, 5)
const BAIT_POS := Vector2i(5, 2)
const DEFENDER_POS := Vector2i(5, 0)

func _check(label: String, ok: bool):
	if ok:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		fails += 1

func _initialize():
	print(">>> SMOKE TEST: AI minimax (defended-pawn trap) <<<")
	player_manager = root.get_node("PlayerManager")
	settings_manager = root.get_node("SettingsManager")
	battle_instance = BattleBoot.boot(self)
	var enemies: Array[String] = ["enemy_rook"]
	player_manager.enemy_party = enemies
	player_manager.active_enemies = enemies.duplicate()
	var roster: Array[String] = ["friendly_pawn", "friendly_rook"]
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

	# Clear randomly-spawned obstacles - see smoke_ai.gd for the same precaution.
	for c in grid_manager.get_all_characters():
		if c is BaseCharacter and c.is_obstacle:
			grid_manager.vacate(c.grid_pos)
			c.queue_free()

	var enemy_rook: BaseCharacter = null
	var bait_pawn: BaseCharacter = null
	var defender_rook: BaseCharacter = null
	for c in grid_manager.get_all_characters():
		if not is_instance_valid(c) or not (c is BaseCharacter):
			continue
		if c.is_enemy and c.strName == "rook":
			enemy_rook = c
		elif not c.is_enemy and c.strName == "pawn":
			bait_pawn = c
		elif not c.is_enemy and c.strName == "rook":
			defender_rook = c

	if enemy_rook == null or bait_pawn == null or defender_rook == null:
		print("SMOKE TEST FAIL: need an enemy rook + an ally pawn + an ally rook on the board")
		return false

	_teleport(grid_manager, enemy_rook, ENEMY_POS)
	_teleport(grid_manager, bait_pawn, BAIT_POS)
	_teleport(grid_manager, defender_rook, DEFENDER_POS)

	enemy_rook.has_spotted_player = true
	enemy_rook.last_known_player_pos = bait_pawn.grid_pos

	var valid_targets := enemy_rook.calculate_valid_targets()
	_check("bait pawn is a valid capture target", BAIT_POS in valid_targets)

	var danger_tiles: Array[Vector2i] = grid_manager.tiles_reachable_by(false)
	_check("the defender's line is still blocked pre-move - (5,2) is NOT flagged dangerous yet",
		not (BAIT_POS in danger_tiles))

	for tier in ["normal"]:
		_teleport(grid_manager, enemy_rook, ENEMY_POS)
		_teleport(grid_manager, bait_pawn, BAIT_POS)
		_teleport(grid_manager, defender_rook, DEFENDER_POS)
		enemy_rook.has_spotted_player = true
		enemy_rook.last_known_player_pos = bait_pawn.grid_pos
		settings_manager.ai_difficulty = tier
		var action: Dictionary = enemy_rook.calculate_best_move()
		_check("%s ai_difficulty walks into the defended-pawn trap" % tier.to_upper(),
			action.get("move_type", "") == "CAPTURE" and action.get("target_pos", Vector2i(-99, -99)) == BAIT_POS)

	for tier in ["hard", "extreme", "impossible"]:
		_teleport(grid_manager, enemy_rook, ENEMY_POS)
		_teleport(grid_manager, bait_pawn, BAIT_POS)
		_teleport(grid_manager, defender_rook, DEFENDER_POS)
		enemy_rook.has_spotted_player = true
		enemy_rook.last_known_player_pos = bait_pawn.grid_pos
		settings_manager.ai_difficulty = tier
		var action: Dictionary = enemy_rook.calculate_best_move()
		_check("%s ai_difficulty declines the defended-pawn trap" % tier.to_upper(),
			not (action.get("move_type", "") == "CAPTURE" and action.get("target_pos", Vector2i(-99, -99)) == BAIT_POS))

	# "never paralyze" (§2.4/M3): avoid_hanging_pieces must fall back to the full
	# candidate set if EVERY candidate looks dangerous, not return zero moves. Feed
	# the filter the player's ENTIRE reachable-tile set directly (mostly empty
	# tiles, so gain=0 for all of them - guaranteed less than the rook's own value,
	# so every entry looks "unsafe") and confirm it doesn't collapse to empty.
	_teleport(grid_manager, enemy_rook, ENEMY_POS)
	_teleport(grid_manager, bait_pawn, BAIT_POS)
	_teleport(grid_manager, defender_rook, DEFENDER_POS)
	var strategy := EnemyAIStrategy.new({"avoid_hanging_pieces": true})
	var all_dangerous: Array[Vector2i] = grid_manager.tiles_reachable_by(false)
	_check("setup has at least one dangerous tile to test with", not all_dangerous.is_empty())
	var filtered: Array[Vector2i] = strategy._filter_hanging_pieces(enemy_rook, all_dangerous)
	_check("avoid_hanging_pieces never returns an empty candidate list, even when every candidate looks dangerous",
		not filtered.is_empty())

	if fails == 0:
		print(">>> SMOKE_AI_MINIMAX_OK <<<")
	else:
		print("SMOKE TEST FAIL: %d AI minimax checks failed" % fails)

	return false
