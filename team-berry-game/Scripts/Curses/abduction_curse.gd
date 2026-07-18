# res://Scripts/Curses/abduction_curse.gd
# Prekletstvo "abduction": nosilec po vsakem premiku zamenja mesto z
# NAJBLIŽJIM VIDNIM nasprotnikom (za nosilca = igralčevo figuro, glej
# find_visible_enemies opombo v base_character.gd) - potegne jo globlje med
# sovražnike (ali jo, redkeje, potegne STRAN iz nevarnosti - tveganje je
# obojestransko). Ista LOS/domet geometrija kot stunning_gaze.
extends BaseCurse

func _init():
	id = "abduction"

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
