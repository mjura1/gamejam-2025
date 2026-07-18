# res://Scripts/Curses/snowfall_curse.gd
# Prekletstvo "snowfall": nosilec po vsakem premiku znova pokrije 3x3
# območje (radius iz JSON) okoli sebe z meglo (glej GridManager.cover_area).
extends BaseCurse

func _init():
	id = "snowfall"

func on_action_taken(owner, _bc) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(owner.grid_manager):
		return
	var radius: int = CurseData.get_param(id, "radius", 1)
	var tiles: Array[Vector2i] = GridManager.square_radius_tiles(owner.grid_pos, radius)

	# Filtriramo na mejo plošče - grid_manager.cover_area sam ne preverja meje
	# (klicatelj mora).
	var filtered: Array[Vector2i] = []
	if is_instance_valid(owner.tile_map):
		var used_rect: Rect2i = owner.tile_map.get_used_rect()
		for pos in tiles:
			if owner.grid_manager.is_inside_boundary(pos, used_rect):
				filtered.append(pos)
	else:
		filtered = tiles

	owner.grid_manager.cover_area(filtered)
