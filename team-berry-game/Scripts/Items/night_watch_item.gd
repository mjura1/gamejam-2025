# res://Scripts/Items/night_watch_item.gd
# Enkratna uporaba: cilj (grid_pos) mora biti sovražna figura - doda jo v
# battle_controller.night_watch_targets (glej tam), ki jo
# update_fog_after_turn_start() od zdaj naprej vsako potezo znova razkrije,
# ne glede na to, kam se figura premakne.
extends BaseItem

func _init():
	id = "night_watch"

func can_use(battle_controller, grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, grid_pos):
		return false
	var target = battle_controller.grid_manager.get_character_at(grid_pos)
	return target is BaseCharacter and target.is_enemy and not target.is_obstacle

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	var target = battle_controller.grid_manager.get_character_at(grid_pos)
	if target in battle_controller.night_watch_targets:
		return false
	battle_controller.night_watch_targets.append(target)
	battle_controller.grid_manager.reveal_area([grid_pos])
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return [grid_pos]
