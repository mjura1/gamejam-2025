# res://Scripts/Curses/changeling_curse.gd
# Prekletstvo "changeling": nosilec po vsakem premiku zamenja mesto s svojim
# NAJBLIŽJIM soborcem (isto is_enemy, glej grid_manager.swap_characters) -
# neodvisno od vidljivosti, po ravni razdalji na celotni mreži. Meša
# sovražnikovo lastno razporeditev, brez učinka na igralca neposredno.
extends BaseCurse

func _init():
	id = "changeling"

func on_action_taken(owner, _bc) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(owner.grid_manager):
		return

	var partner = null
	var best_dist := INF
	for c in owner.grid_manager.get_all_characters():
		if not is_instance_valid(c) or c == owner:
			continue
		if not (c is BaseCharacter) or c.is_obstacle:
			continue
		if c.is_enemy != owner.is_enemy:
			continue
		var d: float = owner.grid_pos.distance_to(c.grid_pos)
		if d < best_dist:
			best_dist = d
			partner = c

	if partner == null:
		return

	owner.grid_manager.swap_characters(owner, partner)
