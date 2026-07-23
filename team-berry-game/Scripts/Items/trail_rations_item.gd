# res://Scripts/Items/trail_rations_item.gd
# Enkratna uporaba: povrne nazaj v inventar ZADNJI consumable, ki je bil v TEJ
# bitki porabljen do 0 (glej PlayerManager.used_up_this_battle). Poenostavljeno
# na "zadnji porabljen" namesto igralčeve izbire med več kandidati - ta UI
# nima nobenega "izberi izmed svojih itemov" vzorca (samo ciljanje polj na
# plošči, glej BaseItem.get_aim_cells), zato bi nov izbirni panel bil
# nesorazmeren obseg za en item (isti razlog kot howling_gale row-only
# odločitev, glej NEW_ITEMS_WAVE2_PLAN.md §1a).
extends BaseItem

func _init():
	id = "trail_rations"

func can_use(battle_controller, _grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, _grid_pos):
		return false
	return not battle_controller.player_manager.used_up_this_battle.is_empty()

func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	var used: Array[String] = battle_controller.player_manager.used_up_this_battle
	if used.is_empty():
		return false
	var restored: String = used.back()
	used.pop_back()
	battle_controller.player_manager.add_item(restored, 1)
	return true
