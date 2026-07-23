# res://Scripts/Items/wildfire_flare_item.gd
# Enkratna uporaba: kot flare (3x3 takojšnje razkritje), a 4 poljem tik izven
# tega kvadrata (+ oblika, glej GridManager.cover_area_half_melt) doda tanko,
# že napol stopljeno prekletstveno meglo, ki izgine sama do naslednje poteze.
extends BaseItem

func _init():
	id = "wildfire_flare"

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	var grid_manager = battle_controller.grid_manager
	grid_manager.reveal_area(GridManager.square_radius_tiles(grid_pos, 1))

	var used_rect: Rect2i = battle_controller.tile_map.get_used_rect()
	var halo: Array[Vector2i] = []
	for dir in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var pos: Vector2i = grid_pos + dir
		if grid_manager.is_inside_boundary(pos, used_rect):
			halo.append(pos)
	grid_manager.cover_area_half_melt(halo)
	return true
