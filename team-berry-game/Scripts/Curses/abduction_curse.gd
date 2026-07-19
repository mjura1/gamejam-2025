# res://Scripts/Curses/abduction_curse.gd
# Prekletstvo "abduction": nosilec po vsakem premiku zamenja mesto z
# NAJBLIŽJIM VIDNIM nasprotnikom (za nosilca = igralčevo figuro, glej
# find_visible_enemies opombo v base_character.gd) - potegne jo globlje med
# sovražnike (ali jo, redkeje, potegne STRAN iz nevarnosti - tveganje je
# obojestransko). Ista LOS/domet geometrija kot stunning_gaze.
extends BaseCurse

# IMPOSSIBLE-tier AI positioning weight (curse_synergy, plans/AI_DIFFICULTY_PLAN.md
# §2.6) - deliberately heavier than stunning_gaze/entangle's (3.0): abduction's
# effect (yanking a player piece into the enemy cluster) is far more punishing than
# a stun/root. Placeholder, Miha's to balance - needs to be large relative to
# _evaluate()'s board-control/mobility terms (see smoke_ai_curse_synergy.gd) since
# it's a small per-candidate nudge competing against those across the WHOLE
# candidate set, not just against one specific alternative.
const AI_POSITIONING_WEIGHT := 5.0

func _init():
	id = "abduction"

# Same "nearest visible" targeting as stunning_gaze/entangle, but the swap means the
# abducted piece lands EXACTLY at candidate_pos (owner's own post-move square,
# vacated when owner swaps into the target's old spot) - so the bonus also scales
# with how exposed that landing tile is (snapshot_reachable_count: more of the
# owner's own side able to reach it next turn = a worse spot to be abducted into).
func ai_positioning_bonus(owner, candidate_pos: Vector2i, snapshot: Dictionary) -> float:
	var seen: Array[Vector2i] = EnemyAIStrategy.snapshot_visible_positions(
		snapshot, candidate_pos, owner.get_move_directions(), owner.move_range, owner.is_enemy)
	if seen.is_empty():
		return 0.0
	var nearest_pos: Vector2i = seen[0]
	var best_dist := INF
	for pos in seen:
		var dist: float = Vector2(candidate_pos).distance_to(Vector2(pos))
		if dist < best_dist:
			best_dist = dist
			nearest_pos = pos
	var value: int = snapshot.get(nearest_pos, {}).get("value", 1)
	var exposure: int = EnemyAIStrategy.snapshot_reachable_count(snapshot, owner.is_enemy, candidate_pos)
	return value * maxi(1, exposure) * AI_POSITIONING_WEIGHT

func on_action_taken(owner, _bc) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(owner.grid_manager):
		return

	var seen: Array = owner.find_visible_enemies(owner.move_range)
	if seen.is_empty():
		return

	var target = null
	var best_dist := INF
	for candidate in seen:
		var dist: float = owner.grid_pos.distance_to(candidate.grid_pos)
		if dist < best_dist:
			best_dist = dist
			target = candidate

	if target == null:
		return

	var target_was_enemy: bool = target.is_enemy
	owner.grid_manager.swap_characters(owner, target)

	# Zaveznik (igralčeva figura) je pravkar pristal na novem polju - osvežimo
	# meglo okoli njega enako, kot bi ob navadnem premiku (glej
	# base_character.execute_move) - drugače bi njegova stara pozicija ostala
	# "razkrita", nova pa ne.
	if not target_was_enemy and is_instance_valid(target):
		var positions_to_reveal: Array[Vector2i] = []
		for x in range(-1, 2):
			for y in range(-1, 2):
				positions_to_reveal.append(target.grid_pos + Vector2i(x, y))
		owner.grid_manager.reveal_area(positions_to_reveal)
