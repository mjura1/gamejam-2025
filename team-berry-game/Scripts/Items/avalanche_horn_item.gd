# res://Scripts/Items/avalanche_horn_item.gd
# Enkratna uporaba: potisne vsakega sovražnika v 3x3 okoli grid_pos eno polje
# RADIALNO STRAN OD centra (smer = sign(sovražnikov_pozicija - center), ista
# .sign() poteza kot base_character.gd uporablja za last_known_direction) -
# uporablja GridManager.push_character (4.0 knockback helper). Sovražnik
# TOČNO na centru (redek rob primer) se ne potisne - smer bi bila (0,0).
extends BaseItem

func _init():
	id = "avalanche_horn"

func _area_tiles(grid_pos: Vector2i) -> Array[Vector2i]:
	return GridManager.square_radius_tiles(grid_pos, 1)

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	var grid_manager = battle_controller.grid_manager
	for pos in _area_tiles(grid_pos):
		var target = grid_manager.get_character_at(pos)
		if target is BaseCharacter and target.is_enemy and not target.is_obstacle:
			var direction: Vector2i = (target.grid_pos - grid_pos).sign()
			if direction != Vector2i.ZERO:
				grid_manager.push_character(target, direction, 1)
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return _area_tiles(grid_pos)
