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

# Placeholder weights (Miha's to balance by playtest, see plan §6 - "not something to
# hard-code a fairness cap for"). Kept as named constants per §2.5.1's suggestion.
const BOARD_CONTROL_WEIGHT := 0.05
const MOBILITY_WEIGHT := 0.1
const THREAT_CREATION_BONUS := 1.5
const SEE_ORDERING_WEIGHT := 0.5
const FOLLOWUP_CAPTURE_BONUS := 1.0
# Per-piece radius contribution cap (M5 perf guardrail, plans/AI_DIFFICULTY_PLAN.md).
# §2.5's literal "move_range + opponent's own move_range" bound barely bounds
# anything on this board: sliding pieces (queen/rook/bishop) have move_range 8 on a
# ~12-wide board, so two of them sum to 16 - wider than the board itself, meaning
# EVERY piece on the board "qualifies" as a plausible reply at every ply and the
# radius bound does no pruning at all. Capping each side's contribution keeps the
# *spirit* (nearby pieces only) while actually bounding branching factor - measured
# via smoke_ai_perf.gd, see that file + the M5 plan notes for before/after numbers.
const RADIUS_CAP := 3

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

# =====================================================================
# NORMAL/HARD: heuristic ladder (§2.3) - value-aware capture priority (always on -
# "captures stay aggressive", never gated by any tier flag), then
# chase-with-danger-avoidance. Mirrors calculate_best_move()'s old steps 6-7
# verbatim for the case where every flag below is off (NORMAL - regression-safety
# anchor, see M2). `avoid_hanging_pieces` (HARD+) is the one addition on top.
# =====================================================================
func _choose_heuristic(character: BaseCharacter, context: Dictionary) -> Dictionary:
	var valid_targets: Array[Vector2i] = context.get("valid_targets", [])
	var capture_candidates: Array[Vector2i] = context.get("capture_candidates", [])
	var last_known_player_pos: Vector2i = context.get("last_known_player_pos", Vector2i.ZERO)
	var avoid_hanging: bool = _params.get("avoid_hanging_pieces", false)

	if not capture_candidates.is_empty():
		var safe_captures: Array[Vector2i] = capture_candidates
		if avoid_hanging:
			safe_captures = _filter_hanging_pieces(character, capture_candidates)
		var best_capture: Vector2i = safe_captures[0]
		var best_value := -1
		for pos in safe_captures:
			var target_char = character.grid_manager.get_character_at(pos)
			var value: int = character.curse_data.get_piece_value(target_char.strName)
			if value > best_value:
				best_value = value
				best_capture = pos
		return {"move_type": "CAPTURE", "target_pos": best_capture}

	var chase_candidates: Array[Vector2i] = valid_targets
	if avoid_hanging:
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

# `avoid_hanging_pieces` (HARD+, §2.4): generalizes danger-avoidance from the chase
# step to EVERY candidate, captures included (pre-refactor code explicitly never
# filtered captures - "captures stay aggressive"; this tier flag is what changes
# that). For each candidate in the ally-reachable ("danger") set, keeps it only if
# what we'd gain (captured piece's value, 0 for a plain move) isn't clearly less than
# what we'd risk (this piece's own value) - i.e. drops candidates that are a bad
# trade. Never leaves zero candidates - falls back to the unfiltered set if every
# candidate looks dangerous (same "never paralyze" rule as the pre-refactor code).
func _filter_hanging_pieces(character: BaseCharacter, candidates: Array[Vector2i]) -> Array[Vector2i]:
	var danger_tiles: Array[Vector2i] = character.grid_manager.tiles_reachable_by(false)
	var own_value: int = character.curse_data.get_piece_value(character.strName)
	var safe: Array[Vector2i] = []
	for pos in candidates:
		if pos not in danger_tiles:
			safe.append(pos)
			continue
		var target_char = character.grid_manager.get_character_at(pos)
		var gain: int = character.curse_data.get_piece_value(target_char.strName) if target_char else 0
		if gain > own_value:
			safe.append(pos)
	if safe.is_empty():
		return candidates
	return safe

# =====================================================================
# EXTREME/IMPOSSIBLE: minimax over a board snapshot (§2.5). NOTE: `min_max` tiers
# do NOT also run `_filter_hanging_pieces` - that heuristic-path filter is a cheap
# stand-in for what real search-based safety (minimax's own recursive evaluation)
# does more accurately here. avoid_hanging_pieces stays "true" for these tiers in
# ai_difficulty.json for the ladder's additive/superset property (§2.4), but this
# path intentionally doesn't read it - minimax subsumes it.
# =====================================================================
func _choose_minimax(character: BaseCharacter, context: Dictionary) -> Dictionary:
	var valid_targets: Array[Vector2i] = context.get("valid_targets", [])
	var bounds: Rect2i = character.tile_map.get_used_rect()
	var snapshot: Dictionary = _build_snapshot(character)
	var depth: int = _params.get("minimax_depth", 0)
	var use_see: bool = _params.get("static_exchange_evaluation", false)
	var use_threats: bool = _params.get("threat_creation", false)
	var use_curse_synergy: bool = _params.get("curse_synergy", false)

	var candidates: Array[Vector2i] = valid_targets.duplicate()
	if use_see:
		# Move ordering (§2.5: "alpha-beta pruning required") - a cheap static
		# (non-recursive) estimate searched first prunes more of the tree once the
		# real minimax search below finds a strong alpha early.
		candidates.sort_custom(func(a, b):
			return _static_exchange_score(character, snapshot, a, bounds) \
				> _static_exchange_score(character, snapshot, b, bounds))

	var best_pos: Vector2i = candidates[0]
	var best_value := -INF
	var alpha := -INF
	var beta := INF
	for pos in candidates:
		var child: Dictionary = _simulate_move(snapshot, character.grid_pos, pos)
		var value: float = _minimax(child, depth, false, alpha, beta, character.is_enemy, pos, bounds)
		if use_see:
			value += SEE_ORDERING_WEIGHT * _static_exchange_score(character, snapshot, pos, bounds)
		if use_threats:
			value += _threat_bonus(character, snapshot, pos, bounds)
		if use_curse_synergy and character.curse:
			value += character.curse.ai_positioning_bonus(character, pos, child)
			value += _followup_capture_bonus(character, snapshot, child, pos, bounds)
		if value > best_value:
			best_value = value
			best_pos = pos
		alpha = maxf(alpha, value)

	var move_type := "CAPTURE" if snapshot.has(best_pos) else "MOVE"
	return {"move_type": move_type, "target_pos": best_pos}

# Lightweight, pure board snapshot (§2.5) - Vector2i -> piece data, cloned once from
# live state. Never mutated in place (see _simulate_move) and never holds live
# BaseCharacter references, so search below can never touch grid_manager/scene-tree
# state (fog, visuals, curse hooks) no matter how deep it recurses. move_directions +
# move_range are captured per-piece here so the pure move-generator below can reuse
# each piece's real movement geometry without needing a live BaseCharacter reference
# (get_move_directions() is a pure per-subclass override, see knight.gd/bishop.gd/...).
func _build_snapshot(character: BaseCharacter) -> Dictionary:
	var snapshot: Dictionary = {}
	for c in character.grid_manager.get_all_characters():
		if not is_instance_valid(c) or not (c is BaseCharacter):
			continue
		snapshot[c.grid_pos] = {
			"is_enemy": c.is_enemy,
			"is_obstacle": c.is_obstacle,
			"value": character.curse_data.get_piece_value(c.strName),
			"move_directions": c.get_move_directions(),
			"move_range": c.move_range,
		}
	return snapshot

# Returns a NEW snapshot with the piece at from_pos relocated to to_pos (capturing
# whatever was there, if anything) - never mutates the input.
func _simulate_move(snapshot: Dictionary, from_pos: Vector2i, to_pos: Vector2i) -> Dictionary:
	var next_snapshot: Dictionary = snapshot.duplicate(true)
	var mover: Dictionary = next_snapshot.get(from_pos, {})
	next_snapshot.erase(from_pos)
	next_snapshot[to_pos] = mover
	return next_snapshot

func _in_bounds(pos: Vector2i, bounds: Rect2i) -> bool:
	return pos.x >= bounds.position.x and pos.x < bounds.position.x + bounds.size.x \
		and pos.y >= bounds.position.y and pos.y < bounds.position.y + bounds.size.y

# Pure move generator against the snapshot (§2.5) - same sliding-until-blocked loop
# shape as base_character.calculate_valid_targets(), minus LOS/fog/entry-denial
# concerns (irrelevant to a hypothetical 1-2 ply lookahead).
func _snapshot_valid_targets(snapshot: Dictionary, from_pos: Vector2i, bounds: Rect2i) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	if not snapshot.has(from_pos):
		return targets
	var entry: Dictionary = snapshot[from_pos]
	var directions: Array = entry.get("move_directions", [])
	var move_range: int = entry.get("move_range", 1)
	var is_enemy: bool = entry.get("is_enemy", false)
	for dir in directions:
		var d: Vector2i = dir
		for step in range(1, move_range + 1):
			var target_pos: Vector2i = from_pos + d * step
			if not _in_bounds(target_pos, bounds):
				break
			if snapshot.has(target_pos):
				var occupant: Dictionary = snapshot[target_pos]
				if occupant.get("is_enemy", false) != is_enemy and not occupant.get("is_obstacle", false):
					targets.append(target_pos)
				break
			targets.append(target_pos)
	return targets

# Radius-bounded opponent move generation (§2.5): only pieces of `side_is_enemy`
# within (their own move_range + the contested piece's move_range, each capped at
# RADIUS_CAP - see that constant's comment) tiles of `contested_pos` are considered
# - pieces far away can't plausibly punish/exploit this move, and scanning them
# wastes time. Replies are ordered captures-first (cheap, no extra snapshot walk -
# reuses the occupancy check already done while building the list) so alpha-beta
# above finds a strong bound early and prunes more.
func _generate_radius_bounded_moves(snapshot: Dictionary, side_is_enemy: bool, contested_pos: Vector2i, bounds: Rect2i) -> Array:
	var captures: Array = []
	var quiet_moves: Array = []
	var contested_range: int = mini(snapshot.get(contested_pos, {}).get("move_range", 1), RADIUS_CAP)
	for from_pos in snapshot.keys():
		var entry: Dictionary = snapshot[from_pos]
		if entry.get("is_enemy", false) != side_is_enemy or entry.get("is_obstacle", false):
			continue
		var piece_range: int = mini(entry.get("move_range", 1), RADIUS_CAP)
		if Vector2(from_pos).distance_to(Vector2(contested_pos)) > piece_range + contested_range:
			continue
		for to_pos in _snapshot_valid_targets(snapshot, from_pos, bounds):
			if snapshot.has(to_pos):
				captures.append({"from": from_pos, "to": to_pos})
			else:
				quiet_moves.append({"from": from_pos, "to": to_pos})
	captures.append_array(quiet_moves)
	return captures

# Minimax with alpha-beta pruning (required per §2.5, not optional - without it,
# depth 2 with even a handful of nearby pieces gets slow). `maximizing` = is it the
# ORIGINAL mover's side choosing at this node (maximize) or the opponent's
# (minimize) - `mover_is_enemy` stays fixed across the whole recursion, only
# `maximizing` alternates. depth counts ADVERSARIAL REPLIES (§2.5), not full game
# turns - our own candidate move is already applied by the caller before the first
# call, so the first ply here is always the opponent's reply (maximizing=false).
func _minimax(snapshot: Dictionary, depth: int, maximizing: bool, alpha: float, beta: float, mover_is_enemy: bool, contested_pos: Vector2i, bounds: Rect2i) -> float:
	if depth <= 0:
		return _evaluate(snapshot, mover_is_enemy, contested_pos, bounds)

	var side_is_enemy: bool = mover_is_enemy if maximizing else not mover_is_enemy
	var replies: Array = _generate_radius_bounded_moves(snapshot, side_is_enemy, contested_pos, bounds)
	if replies.is_empty():
		return _evaluate(snapshot, mover_is_enemy, contested_pos, bounds)

	if maximizing:
		var value := -INF
		for reply in replies:
			var child: Dictionary = _simulate_move(snapshot, reply["from"], reply["to"])
			value = maxf(value, _minimax(child, depth - 1, false, alpha, beta, mover_is_enemy, reply["to"], bounds))
			alpha = maxf(alpha, value)
			if alpha >= beta:
				break
		return value
	else:
		var value := INF
		for reply in replies:
			var child: Dictionary = _simulate_move(snapshot, reply["from"], reply["to"])
			value = minf(value, _minimax(child, depth - 1, true, alpha, beta, mover_is_enemy, reply["to"], bounds))
			beta = minf(beta, value)
			if alpha >= beta:
				break
		return value

# §2.5.1 evaluation function - higher = better for mover_is_enemy's side. Material +
# lightweight board-control (piece-square-table analogue) + mobility of whichever
# piece currently sits on contested_pos (the search's focal point at this leaf - may
# be empty if that piece got captured along the way, in which case mobility is 0).
#
# DEVIATION from §2.5.1's literal 4-component list: threat_creation (M3) and
# curse_synergy (M4) are NOT folded in here - both are computed ONCE per ROOT
# candidate in _choose_minimax instead of at every leaf this function is called
# from. Reasoning: (1) performance - a depth-2 search can call _evaluate at many
# leaf nodes per root candidate, and neither term's underlying question ("does MY
# OWN move create a fork" / "does MY OWN move help MY curse's on-move effect")
# changes meaning or needs re-checking at deeper hypothetical future board states,
# so recomputing them per-leaf would be pure waste (relevant given M5's perf
# guardrail); (2) semantics - both are about the ORIGINAL mover's own move this
# turn, evaluated once, not a recursively-meaningful property of the search tree.
func _evaluate(snapshot: Dictionary, mover_is_enemy: bool, contested_pos: Vector2i, bounds: Rect2i) -> float:
	var center := Vector2(bounds.position) + Vector2(bounds.size) / 2.0
	var max_dist: float = Vector2(bounds.size).length() / 2.0

	var material := 0.0
	var control := 0.0
	for pos in snapshot.keys():
		var entry: Dictionary = snapshot[pos]
		if entry.get("is_obstacle", false):
			continue
		var sign := 1.0 if entry.get("is_enemy", false) == mover_is_enemy else -1.0
		material += sign * entry.get("value", 1)
		var dist_to_center: float = Vector2(pos).distance_to(center)
		control += sign * BOARD_CONTROL_WEIGHT * (max_dist - dist_to_center)

	var mobility := 0.0
	if snapshot.has(contested_pos):
		var focal: Dictionary = snapshot[contested_pos]
		if not focal.get("is_obstacle", false):
			var sign := 1.0 if focal.get("is_enemy", false) == mover_is_enemy else -1.0
			mobility = sign * MOBILITY_WEIGHT * _snapshot_valid_targets(snapshot, contested_pos, bounds).size()

	return material + control + mobility

# `static_exchange_evaluation` (SEE, §2.4) - a STATIC (non-recursive) net-material
# estimate for landing at `pos`: material gained by this move (if it's a capture)
# minus this piece's own value if ANY opposing piece could reach `pos` afterward
# (worst case - assumes they would recapture). "Static" because it doesn't search
# further plies itself (that's minimax's job, §2.5) - used above for candidate
# ORDERING (real chess-engine technique: order captures first so alpha-beta prunes
# more) and as a small additive nudge on the final score, reinforcing what deep
# search already tends to find (declining a rook-defended pawn) even at shallow
# depth/narrow radius bounds.
func _static_exchange_score(character: BaseCharacter, snapshot: Dictionary, pos: Vector2i, bounds: Rect2i) -> int:
	var gain: int = snapshot[pos].get("value", 1) if snapshot.has(pos) else 0
	var own_value: int = character.curse_data.get_piece_value(character.strName)
	for from_pos in snapshot.keys():
		var entry: Dictionary = snapshot[from_pos]
		if entry.get("is_enemy", false) == character.is_enemy or entry.get("is_obstacle", false):
			continue
		if pos in _snapshot_valid_targets(snapshot, from_pos, bounds):
			return gain - own_value
	return gain

# `threat_creation` (fork bonus, §2.4) - small bonus if landing at `pos` would put
# 2+ opposing pieces within this piece's OWN next-turn capture range simultaneously.
# Evaluated from a hypothetical snapshot (this piece placed at pos, any capture at
# pos already resolved) - not a live move, per §2.4.
func _threat_bonus(character: BaseCharacter, snapshot: Dictionary, pos: Vector2i, bounds: Rect2i) -> float:
	var hypothetical: Dictionary = _simulate_move(snapshot, character.grid_pos, pos)
	var reachable: Array[Vector2i] = _snapshot_valid_targets(hypothetical, pos, bounds)
	var threatened := 0
	for target in reachable:
		if hypothetical.has(target) and hypothetical[target].get("is_enemy", false) != character.is_enemy:
			threatened += 1
	return THREAT_CREATION_BONUS if threatened >= 2 else 0.0

# `frenzy`/`bloodlust` extra-action awareness (§2.6, IMPOSSIBLE/curse_synergy only -
# NOT a BaseCurse hook, this is about the piece's own extra-action mechanic, not a
# per-curse "who do I target" question). frenzy always grants another action this
# turn (extra_actions() > 0); bloodlust only does when THIS specific candidate is
# itself a capture (grants_bonus_action_on_capture(), checked against the PRE-move
# snapshot). Cheap approximation per §2.6: does the post-move position's own
# valid_targets include a follow-up capture?
func _followup_capture_bonus(character: BaseCharacter, snapshot: Dictionary, child_snapshot: Dictionary, pos: Vector2i, bounds: Rect2i) -> float:
	if not character.curse:
		return 0.0
	var is_capture: bool = snapshot.has(pos)
	var gets_extra_action: bool = character.curse.extra_actions() > 0 \
		or (character.curse.grants_bonus_action_on_capture() and is_capture)
	if not gets_extra_action:
		return 0.0
	for target in _snapshot_valid_targets(child_snapshot, pos, bounds):
		if child_snapshot.has(target) and child_snapshot[target].get("is_enemy", false) != character.is_enemy:
			return FOLLOWUP_CAPTURE_BONUS
	return 0.0

# =====================================================================
# Snapshot-equivalent visibility/reachability utilities (§2.6) - STATIC and public
# (unlike the rest of this file's search internals) so BaseCurse.ai_positioning_bonus
# overrides (stunning_gaze_curse.gd etc.) can reuse them without needing an
# EnemyAIStrategy instance. Deliberately bounds-free (unlike _snapshot_valid_targets
# above): both only ever check a SPECIFIC known in-bounds position (a visible
# occupant found along a ray, or a named candidate_pos), never enumerate "all empty
# tiles" the way move generation does - board-edge bookkeeping only matters for the
# latter, so it's safe to skip here.
# =====================================================================

# Snapshot-equivalent of BaseCharacter.find_visible_enemies() - same "first occupant
# per direction blocks LOS" geometry, walked against a search/curse-hook snapshot
# instead of live grid_manager state. viewer_is_enemy: the viewer's OWN side -
# returns opposing-side positions only (mirrors find_visible_enemies' is_enemy !=
# check).
static func snapshot_visible_positions(snapshot: Dictionary, from_pos: Vector2i, directions: Array, max_view_range: int, viewer_is_enemy: bool) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for dir in directions:
		var d: Vector2i = dir
		for step in range(1, max_view_range + 1):
			var check_pos: Vector2i = from_pos + d * step
			if snapshot.has(check_pos):
				var occupant: Dictionary = snapshot[check_pos]
				if occupant.get("is_enemy", false) != viewer_is_enemy and not occupant.get("is_obstacle", false):
					found.append(check_pos)
				break
	return found

# Can the piece at from_pos (per the snapshot's stored move_directions/move_range)
# reach target_pos in one move - sliding geometry, blocked by the first occupant
# along the way (captures the blocker only if target_pos IS that occupant and it's
# an opposing piece).
static func snapshot_can_reach(snapshot: Dictionary, from_pos: Vector2i, target_pos: Vector2i) -> bool:
	if not snapshot.has(from_pos):
		return false
	var entry: Dictionary = snapshot[from_pos]
	var move_range: int = entry.get("move_range", 1)
	var is_enemy: bool = entry.get("is_enemy", false)
	for dir in entry.get("move_directions", []):
		var d: Vector2i = dir
		for step in range(1, move_range + 1):
			var pos: Vector2i = from_pos + d * step
			if snapshot.has(pos):
				if pos == target_pos:
					var occupant: Dictionary = snapshot[pos]
					return occupant.get("is_enemy", false) != is_enemy and not occupant.get("is_obstacle", false)
				break
			if pos == target_pos:
				return true
	return false

# How many pieces of side_is_enemy could reach target_pos in one move - used by
# abduction_curse.gd's ai_positioning_bonus override ("how exposed would the
# abducted piece's landing tile be").
static func snapshot_reachable_count(snapshot: Dictionary, side_is_enemy: bool, target_pos: Vector2i) -> int:
	var count := 0
	for from_pos in snapshot.keys():
		var entry: Dictionary = snapshot[from_pos]
		if entry.get("is_enemy", false) != side_is_enemy or entry.get("is_obstacle", false):
			continue
		if snapshot_can_reach(snapshot, from_pos, target_pos):
			count += 1
	return count
