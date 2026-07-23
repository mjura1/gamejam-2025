# res://Scripts/Items/permafrost_flare_item.gd
# Enkratna uporaba: temporary area-deny - reuses the existing ability-cone
# zone system (GridManager.add_zone("deny_entry", ...), same primitive Rook.
# Reinforce uses) for a 3x3 area sovražniki ne morejo vstopiti. "Temporary"
# (one enemy turn) via BattleController.timed_zone_ids - isti "preživi
# natanko eno sovražnikovo potezo" cleanup kot decoy (glej start_player_turn()).
extends BaseItem

func _init():
	id = "permafrost_flare"

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	var zone_id: int = battle_controller.grid_manager.add_zone("deny_entry", grid_pos, 1, false)
	battle_controller.timed_zone_ids.append(zone_id)
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return GridManager.square_radius_tiles(grid_pos, 1)
