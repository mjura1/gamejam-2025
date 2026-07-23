# res://Scripts/Items/warm_cloak_item.gd
# Enkratna uporaba: cilj (grid_pos) mora biti prijateljska figura - nastavi
# is_freeze_immune (glej base_character.gd deklaracijo in
# BattleController._update_snow_freeze_states), ki za PRESTANEK BITKE
# prepreči, da bi se snow_frozen kdaj nastavil na to figuro.
extends BaseItem

func _init():
	id = "warm_cloak"

func can_use(battle_controller, grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, grid_pos):
		return false
	var target = battle_controller.grid_manager.get_character_at(grid_pos)
	return target is BaseCharacter and not target.is_enemy and not target.is_obstacle

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	var target = battle_controller.grid_manager.get_character_at(grid_pos)
	target.is_freeze_immune = true
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return [grid_pos]
