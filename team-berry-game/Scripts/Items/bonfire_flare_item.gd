# res://Scripts/Items/bonfire_flare_item.gd
# Snow-clear chain vmesna stopnja: Flare(C, 3x3) -> bonfire_flare (U, 5x5) ->
# Wildfire Flare(R) -> blizzard_ender(E) -> Aurora Flare(L). Ista
# reveal_area/square_radius_tiles logika kot flare_item.gd, le radius=2 (5x5)
# namesto 1 (3x3), brez wildfire_flare-jeve dodatne pol-stopljene meglice.
extends BaseItem

func _init():
	id = "bonfire_flare"

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	battle_controller.grid_manager.reveal_area(GridManager.square_radius_tiles(grid_pos, 2))
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return GridManager.square_radius_tiles(grid_pos, 2)
