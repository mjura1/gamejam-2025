# res://Scripts/Curses/entangle_curse.gd
# Prekletstvo "entangle": nosilec po vsakem premiku ukorenini najbližjega
# vidnega zaveznika za 1 igralčevo potezo (glej base_character.rooted_turns/
# calculate_valid_targets) - za razliko od stunning_gaze omamljena figura NE
# more premakniti na prazno polje, a SME zajeti nasprotnika, če je v dosegu.
# Ista cooldown-varovalka kot stunning_gaze (da ne more chain-root-ati vsako
# potezo).
extends BaseCurse

# Koliko sovražnikovih potez še ne sme spet ukoreniniti (0 = sme takoj).
var cooldown_left := 0

# IMPOSSIBLE-tier AI positioning weight (curse_synergy, plans/AI_DIFFICULTY_PLAN.md
# §2.6) - placeholder, Miha's to balance.
const AI_POSITIONING_WEIGHT := 3.0

func _init():
	id = "entangle"

# Same targeting shape as stunning_gaze_curse.gd (nearest visible ally by raw
# distance) - identical positioning override, see that file's comment.
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

	target.rooted_turns = CurseData.get_param(id, "duration", 1)
	cooldown_left = CurseData.get_param(id, "cooldown", 2)

	if is_instance_valid(bc):
		bc.notify_root(target)
