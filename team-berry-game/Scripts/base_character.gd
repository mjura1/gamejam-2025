extends Node2D
class_name BaseCharacter

var grid_pos: Vector2i

@onready var tile_map = get_node("/root/Node/Map/TileMapLayer")

@export var selected: bool = false
@export var move_range: int = 1
@export var grid_manager: Node

func _ready():
	grid_manager = get_node("/root/Node/GridManager")
	grid_pos = grid_manager.world_to_grid(global_position)
	global_position = grid_manager.grid_to_world(grid_pos)
	grid_manager.occupy(grid_pos, self)

# 🔹 VÝCHOZÍ – žádný pohyb
func get_move_directions() -> Array[Vector2i]:
	return []

func get_valid_moves() -> Array[Vector2i]:
	var moves: Array[Vector2i] = []

	for dir in get_move_directions():
		for step in range(1, move_range + 1):
			var target := grid_pos + dir * step

			if not grid_manager.is_inside_boundary(target, tile_map.get_used_rect()):
				break

			if grid_manager.is_occupied(target):
				break

			moves.append(target)

	return moves

func try_move(target: Vector2i) -> bool:
	if target not in get_valid_moves():
		return false

	grid_manager.vacate(grid_pos)
	grid_pos = target
	grid_manager.occupy(grid_pos, self)
	global_position = grid_manager.grid_to_world(grid_pos)
	return true
