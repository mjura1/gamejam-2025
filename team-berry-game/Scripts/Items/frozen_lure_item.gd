# res://Scripts/Items/frozen_lure_item.gd
# Enkratna uporaba: postavi enkratno past (glej GridManager.place_trap/
# trigger_trap) na prazno polje - prvi SOVRAŽNIK, ki nanj stopi (premik ALI
# zajetje), se zamrzne za natanko 1 svojo naslednjo potezo.
#
# freeze_turns=2, NE 1: effect_frozen_turns tika ENKRAT na konec VSAKE
# igralčeve poteze (BattleController.end_player_turn), tudi za tisto, ki
# sledi TAKOJ po sprožitvi pasti med sovražnikovo potezo - torej bi vrednost
# 1 potekla PREDEN sovražnik sploh poskusi svojo naslednjo potezo (glej
# NEW_ITEMS_WAVE2_PLAN.md gotcha). 2 preživi ta prvi tik in dejansko blokira
# natanko eno sovražnikovo potezo, kot obljublja opis.
extends BaseItem

const TRAP_FREEZE_TURNS := 2

func _init():
	id = "frozen_lure"

func can_use(battle_controller, grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, grid_pos):
		return false
	if not is_instance_valid(battle_controller.grid_manager) or not is_instance_valid(battle_controller.tile_map):
		return false
	if not battle_controller.grid_manager.is_inside_boundary(grid_pos, battle_controller.tile_map.get_used_rect()):
		return false
	return not battle_controller.grid_manager.is_occupied(grid_pos)

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	battle_controller.grid_manager.place_trap(grid_pos, false, TRAP_FREEZE_TURNS, false)
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return [grid_pos]
