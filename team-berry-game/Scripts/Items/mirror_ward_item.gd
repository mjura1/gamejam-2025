# res://Scripts/Items/mirror_ward_item.gd
# Enkratna uporaba: cilj (grid_pos) mora biti prijateljska figura - nastavi
# is_capture_warded (glej base_character.gd deklaracijo), ki popolnoma
# prekliče NASLEDNJI poskus zajetja te figure (glej capture() vrh) - enkratno,
# potroši se ob prvem poskusu.
extends BaseItem

func _init():
	id = "mirror_ward"

func can_use(battle_controller, grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, grid_pos):
		return false
	var target = battle_controller.grid_manager.get_character_at(grid_pos)
	return target is BaseCharacter and not target.is_enemy and not target.is_obstacle

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	var target = battle_controller.grid_manager.get_character_at(grid_pos)
	target.is_capture_warded = true
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return [grid_pos]
