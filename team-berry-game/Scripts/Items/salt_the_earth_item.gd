# res://Scripts/Items/salt_the_earth_item.gd
# Enkratna uporaba: zaščiti EN sam izbran tile pred kakršnokoli prekletstveno
# meglo (cover_area_curse) za preostanek bitke (glej GridManager.salt_tile) -
# reveal_area sam pobriše morebitno obstoječo meglo na njem takoj.
extends BaseItem

func _init():
	id = "salt_the_earth"

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	battle_controller.grid_manager.salt_tile(grid_pos)
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return [grid_pos]
