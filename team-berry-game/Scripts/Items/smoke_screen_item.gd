# res://Scripts/Items/smoke_screen_item.gd
# Enkratna uporaba: cilj (grid_pos) mora biti prijateljska (ne-sovražna,
# ne-ovira) figura - nastavi is_hidden (glej base_character.gd deklaracijo),
# ki jo AI izključi iz gonje/zajetja (base_character.calculate_best_move),
# dokler se figura ne premakne ali zajame (execute_move to počisti).
extends BaseItem

func _init():
	id = "smoke_screen"

func can_use(battle_controller, grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, grid_pos):
		return false
	var target = battle_controller.grid_manager.get_character_at(grid_pos)
	return target is BaseCharacter and not target.is_enemy and not target.is_obstacle

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	var target = battle_controller.grid_manager.get_character_at(grid_pos)
	target.is_hidden = true
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return [grid_pos]
