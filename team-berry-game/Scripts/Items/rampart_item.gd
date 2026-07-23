# res://Scripts/Items/rampart_item.gd
# Wall chain: Barricade(1 wall) -> Bastion(2 walls) -> rampart (3 walls).
# Extends bastion_item.gd's exact pattern (main wall on the chosen tile, extra
# walls on a random empty 8-neighbor of that SAME tile - not chained further)
# one more time instead of inventing a new placement shape.
extends BaseItem

const OBSTACLE_SCENE: PackedScene = preload("res://Scenes/CharacterPiecesNodes/Neutral/House.tscn")
const EXTRA_WALLS := 2

func _init():
	id = "rampart"

func can_use(battle_controller, grid_pos: Vector2i) -> bool:
	if not super.can_use(battle_controller, grid_pos):
		return false
	if not is_instance_valid(battle_controller.grid_manager) or not is_instance_valid(battle_controller.tile_map):
		return false
	if not battle_controller.grid_manager.is_inside_boundary(grid_pos, battle_controller.tile_map.get_used_rect()):
		return false
	return not battle_controller.grid_manager.is_occupied(grid_pos)

func apply(battle_controller, grid_pos: Vector2i) -> bool:
	var grid_manager = battle_controller.grid_manager
	grid_manager.spawn_character(OBSTACLE_SCENE, grid_manager.grid_to_world(grid_pos))

	var used_rect: Rect2i = battle_controller.tile_map.get_used_rect()
	for i in range(EXTRA_WALLS):
		var candidates: Array[Vector2i] = []
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var pos := grid_pos + Vector2i(dx, dy)
				if grid_manager.is_inside_boundary(pos, used_rect) and not grid_manager.is_occupied(pos):
					candidates.append(pos)
		if candidates.is_empty():
			break
		grid_manager.spawn_character(OBSTACLE_SCENE, grid_manager.grid_to_world(candidates.pick_random()))
	return true

func get_aim_cells(grid_pos: Vector2i) -> Array[Vector2i]:
	return [grid_pos]
