# res://Scripts/Items/blink_step_item.gd
# Consumable verzija drillmaster-jevega swapa (glej drillmaster_item.gd) -
# porabi se iz inventarja normalno (ni "1x na bitko brez porabe"). Ista
# "target A = trenutno izbrana figura, target B = drop pozicija" logika, iz
# istega razloga v celoti v battle_ui.gd.use_item() (BaseItem.apply() nima
# dostopa do map_behaviour.selected_character). Ta razred obstaja samo za
# ITEM_SCRIPTS registracijo in get_aim_cells predogled.
extends BaseItem

func _init():
	id = "blink_step"

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return [grid_pos]
