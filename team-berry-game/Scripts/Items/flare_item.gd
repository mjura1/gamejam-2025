# res://Scripts/Items/flare_item.gd
# Enkratna uporaba: razkrije meglo v 3x3 okoli poljubnega izbranega polja -
# ista GridManager.reveal_area/square_radius_tiles logika kot Rook.Lookout
# (glej Scripts/CharacterPieces/Ally/rook.gd._do_lookout), a s poljem, ki ga
# igralec sam izbere (drop pozicija), namesto samodejno najbližjim sovražnikom.
extends BaseItem

func _init():
	id = "flare"

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	battle_controller.grid_manager.reveal_area(GridManager.square_radius_tiles(grid_pos, 1))
	return true
