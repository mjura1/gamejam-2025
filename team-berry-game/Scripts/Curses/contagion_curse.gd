# res://Scripts/Curses/contagion_curse.gd
# Prekletstvo "contagion": snowfall-podobna prekletstvena megla ("+" območje
# po vsakem premiku), a vsako njeno polje ima tudi spread_chance verjetnost,
# da se vsak tick_curse_fog_decay() "preseli" tudi na naključno prazno
# sosednje polje (glej grid_manager.cover_area_curse/tick_curse_fog_decay) -
# ignorirana megla sčasoma raste namesto da samo razpada.
extends BaseCurse

func _init():
	id = "contagion"

func on_action_taken(owner, _bc) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(owner.grid_manager):
		return
	var radius: int = CurseData.get_param(id, "radius", 1)
	var tiles: Array[Vector2i] = GridManager.plus_radius_tiles(owner.grid_pos, radius)

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
	var spread_chance: float = CurseData.get_param(id, "spread_chance", 0.15)
	owner.grid_manager.cover_area_curse(filtered, ticks_per_stage, CurseData.get_color(id), spread_chance)
