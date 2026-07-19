# res://Scripts/AI/enemy_ai_strategy.gd
# Data-driven enemy DECISION strategy (SettingsManager.ai_difficulty), one class for
# all four tiers - parametrized by the bool/param Dictionary AiStrategyData loads per
# tier from GameParameters/ai_difficulty.json. Replaces steps 6-8 of
# base_character.calculate_best_move() (perception - LOS spotting/blind seek/panic
# detection - stays in base_character.gd, untouched, shared by all tiers). See
# plans/AI_DIFFICULTY_PLAN.md §2.2-2.5.
#
# class_name + extends RefCounted mirrors base_curse.gd's BaseCurse - same
# "instantiated on demand, never an autoload" shape. Safe to type parameters as
# BaseCharacter here (unlike inside base_character.gd itself - see the "NAMENOMA
# get_node()" gotcha comment on curse_data there): this file is only ever compiled
# at runtime, after autoloads are registered, since nothing eagerly-scanned
# (class_name) statically types a var/param/local to EnemyAIStrategy.
class_name EnemyAIStrategy
extends RefCounted

var _params: Dictionary

func _init(params: Dictionary):
	_params = params

# character: BaseCharacter (the enemy piece deciding its move). context keys:
#   "valid_targets": Array[Vector2i] - already curse-filtered (Fey Step), see caller.
#   "capture_candidates": Array[Vector2i] - subset of valid_targets, obstacles excluded.
#   "last_known_player_pos": Vector2i
# Returns {"move_type": "MOVE"|"CAPTURE", "target_pos": Vector2i}, or {} if no move
# is possible - same shape base_character.calculate_best_move() returned pre-refactor.
func choose_action(character: BaseCharacter, context: Dictionary) -> Dictionary:
	var valid_targets: Array[Vector2i] = context.get("valid_targets", [])
	if valid_targets.is_empty():
		return {}

	if _params.get("min_max", false):
		return _choose_minimax(character, context)

	return _choose_heuristic(character, context)

# NORMAL/HARD path: value-aware capture priority (always on - "captures stay
# aggressive", never gated by any tier flag), then chase-with-danger-avoidance.
# Mirrors calculate_best_move()'s old steps 6-7 verbatim for the case where every
# flag below is off (regression-safety anchor for NORMAL, see M2 in the plan).
func _choose_heuristic(character: BaseCharacter, context: Dictionary) -> Dictionary:
	var valid_targets: Array[Vector2i] = context.get("valid_targets", [])
	var capture_candidates: Array[Vector2i] = context.get("capture_candidates", [])
	var last_known_player_pos: Vector2i = context.get("last_known_player_pos", Vector2i.ZERO)

	if not capture_candidates.is_empty():
		var best_capture: Vector2i = capture_candidates[0]
		var best_value := -1
		for pos in capture_candidates:
			var target_char = character.grid_manager.get_character_at(pos)
			var value: int = character.curse_data.get_piece_value(target_char.strName)
			if value > best_value:
				best_value = value
				best_capture = pos
		return {"move_type": "CAPTURE", "target_pos": best_capture}

	var chase_candidates: Array[Vector2i] = valid_targets
	if _params.get("avoid_hanging_pieces", false):
		chase_candidates = _filter_hanging_pieces(character, chase_candidates)

	var best_move: Vector2i = chase_candidates[0]
	var best_score := INF
	for pos in chase_candidates:
		var score = pos.distance_to(last_known_player_pos)
		if score < best_score:
			best_score = score
			best_move = pos

	var avoid_prob: float = _params.get("danger_avoid_prob", 0.0)
	if avoid_prob > 0.0 and randf() < avoid_prob:
		var danger_tiles: Array[Vector2i] = character.grid_manager.tiles_reachable_by(false)
		var safe_move: Vector2i = best_move
		var safe_score := INF
		var found_safe := false
		for pos in chase_candidates:
			if pos in danger_tiles:
				continue
			var score = pos.distance_to(last_known_player_pos)
			if score < safe_score:
				safe_score = score
				safe_move = pos
				found_safe = true
		if found_safe:
			best_move = safe_move

	return {"move_type": "MOVE", "target_pos": best_move}

# `avoid_hanging_pieces` (HARD+): wired in M3 (§2.4 of the plan) - value-aware danger
# filter applied to every candidate, captures included. No-op passthrough for now so
# selecting HARD/EXTREME/IMPOSSIBLE mid-plan doesn't change chase behavior yet.
func _filter_hanging_pieces(_character: BaseCharacter, candidates: Array[Vector2i]) -> Array[Vector2i]:
	return candidates

# EXTREME/IMPOSSIBLE path (`min_max`): wired in M3 (§2.5 of the plan) - minimax with
# alpha-beta over a board snapshot. Falls back to the heuristic path for now so
# selecting EXTREME/IMPOSSIBLE mid-plan still produces a legal move instead of a
# missing-method error.
func _choose_minimax(character: BaseCharacter, context: Dictionary) -> Dictionary:
	return _choose_heuristic(character, context)
