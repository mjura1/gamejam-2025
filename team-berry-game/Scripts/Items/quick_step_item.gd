# res://Scripts/Items/quick_step_item.gd
# Enkratna uporaba: cilj (grid_pos) mora biti trenutno zamrznjena prijateljska
# figura (sneg ALI effect_frozen_turns - glej base_character.gd) - takoj
# odmrzne, tako da lahko to isto potezo normalno premakne (calculate_valid_targets
# takoj neha vračati prazen seznam, ko sta oba pogoja počiščena).
extends BaseItem

func _init():
	id = "quick_step"

func can_use(battle_controller, grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, grid_pos):
		return false
	var target = battle_controller.grid_manager.get_character_at(grid_pos)
	if not (target is BaseCharacter and not target.is_enemy and not target.is_obstacle):
		return false
	return target.is_snow_frozen_now() or target.effect_frozen_turns > 0

func apply(_battle_controller, grid_pos: Vector2i) -> bool:
	var target = _battle_controller.grid_manager.get_character_at(grid_pos)
	target.snow_frozen = false
	target.snow_trapped_turns = 0
	target.effect_frozen_turns = 0
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return [grid_pos]
