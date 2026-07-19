# res://Scripts/Curses/blizzard_curse.gd
# Prekletstvo "blizzard": kraljeva lastna, MOČNEJŠA različica "snowfall" -
# nosilec po vsakem premiku znova pokrije 3x3 območje (namesto "+") s SVOJO
# meglo, ki razpada POČASNEJE (glej GameParameters/curses.json decay_ticks_per_stage).
# Izločena iz splošnega naključnega nabora (weight: 0 v JSON) - dodeli se
# neposredno kralju, glej battle.gd._apply_curses.
extends BaseCurse

func _init():
	id = "blizzard"

func on_action_taken(owner, _bc) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(owner.grid_manager):
		return
	var radius: int = CurseData.get_param(id, "radius", 1)
	var tiles: Array[Vector2i] = GridManager.square_radius_tiles(owner.grid_pos, radius)

	# Filtriramo na mejo plošče - grid_manager.cover_area_curse sam ne preverja
	# meje (klicatelj mora).
	var filtered: Array[Vector2i] = []
	if is_instance_valid(owner.tile_map):
		var used_rect: Rect2i = owner.tile_map.get_used_rect()
		for pos in tiles:
			if owner.grid_manager.is_inside_boundary(pos, used_rect):
				filtered.append(pos)
	else:
		filtered = tiles

	var ticks_per_stage: int = CurseData.get_param(id, "decay_ticks_per_stage", 1)
	owner.grid_manager.cover_area_curse(filtered, ticks_per_stage, CurseData.get_color(id))
