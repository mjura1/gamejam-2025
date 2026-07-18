# res://Scripts/Curses/stunning_gaze_curse.gd
# Prekletstvo "stunning_gaze": nosilec po vsakem premiku omami najbližjega
# vidnega zaveznika za 1 igralčevo potezo, z lastnim cooldownom (balance
# valve - da ne more chain-stunnati vsako potezo).
extends BaseCurse

# Koliko sovražnikovih potez še ne sme spet omamiti (0 = sme takoj).
var cooldown_left := 0

func _init():
	id = "stunning_gaze"

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
