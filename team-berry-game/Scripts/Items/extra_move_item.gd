# res://Scripts/Items/extra_move_item.gd
extends BaseItem
# Enkratna uporaba: +1 premik v TEJ potezi. Cilj (grid_pos) je nepomemben.
func _init():
	id = "extra_move"

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	battle_controller.add_bonus_move()
	return true
