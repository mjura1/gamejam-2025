# res://Scripts/Curses/stunning_gaze_curse.gd
# Prekletstvo "stunning_gaze": nosilec po vsakem premiku omami najbližjega
# vidnega zaveznika za 1 igralčevo potezo, z lastnim cooldownom (balance
# valve - da ne more chain-stunnati vsako potezo).
extends BaseCurse

# Koliko sovražnikovih potez še ne sme spet omamiti (0 = sme takoj).
var cooldown_left := 0

# IMPOSSIBLE-tier AI positioning weight (curse_synergy, plans/AI_DIFFICULTY_PLAN.md
# §2.6) - placeholder, Miha's to balance.
const AI_POSITIONING_WEIGHT := 3.0

func _init():
	id = "stunning_gaze"

# on_action_taken above always targets whichever visible ally ends up NEAREST by
# raw distance - the AI can't change THAT it picks nearest, but it CAN change WHICH
# piece ends up nearest by choosing where to stand. Steers toward ending up nearest
# the highest-value visible piece instead of just any piece.
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
	return value * AI_POSITIONING_WEIGHT

func on_action_taken(owner, bc) -> void:
	if cooldown_left > 0:
		cooldown_left -= 1
		return

	if not is_instance_valid(owner):
		return

	# find_visible_enemies je poimenovan iz perspektive KLICATELJA - za
	# sovražnika torej vrne vidne ZAVEZNIKE (glej base_character.gd opombo).
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

	target.stunned_turns = CurseData.get_param(id, "duration", 1)
	cooldown_left = CurseData.get_param(id, "cooldown", 2)

	if is_instance_valid(bc):
		bc.notify_stun(target)
