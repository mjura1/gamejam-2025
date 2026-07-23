# res://Scripts/Items/hunters_snare_item.gd
# Enkratna uporaba: kot frozen_lure_item.gd (isti GridManager.place_trap/
# trigger_trap enkratni trap-tile sistem, zgrajen za frozen_lure v Phase 2 -
# ničesar novega potrebnega), a tudi razkrije ("revealed for the rest of the
# battle" - reveal=true na place_trap) sprožilca. Ista TRAP_FREEZE_TURNS=2
# tick-timing korekcija kot frozen_lure (glej tam za polno razlago).
extends BaseItem

const TRAP_FREEZE_TURNS := 2

func _init():
	id = "hunters_snare"

func can_use(battle_controller, grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, grid_pos):
		return false
	if not is_instance_valid(battle_controller.grid_manager) or not is_instance_valid(battle_controller.tile_map):
		return false
	if not battle_controller.grid_manager.is_inside_boundary(grid_pos, battle_controller.tile_map.get_used_rect()):
		return false
	return not battle_controller.grid_manager.is_occupied(grid_pos)

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	battle_controller.grid_manager.place_trap(grid_pos, false, TRAP_FREEZE_TURNS, true)
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return [grid_pos]
