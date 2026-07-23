# res://Scripts/Items/stormcaller_item.gd
# Enkratna uporaba (Epic): razkrije 3x3 okoli grid_pos (kot flare) IN zamrzne
# vsakega SOVRAŽNIKA, ki trenutno stoji v tem območju (vključno s centrom -
# za razliko od frost_nova, ki eksplicitno izključi center). FREEZE_TURNS=2
# (ne 1), glej frozen_lure_item.gd-jevo opombo o effect_frozen_turns
# tick-timing hrošču.
extends BaseItem

const FREEZE_TURNS := 2

func _init():
	id = "stormcaller"

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	var grid_manager = battle_controller.grid_manager
	var area: Array[Vector2i] = GridManager.square_radius_tiles(grid_pos, 1)
	grid_manager.reveal_area(area)
	for pos in area:
		var target = grid_manager.get_character_at(pos)
		if target is BaseCharacter and target.is_enemy and not target.is_obstacle:
			target.effect_frozen_turns = maxi(target.effect_frozen_turns, FREEZE_TURNS)
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return GridManager.square_radius_tiles(grid_pos, 1)
