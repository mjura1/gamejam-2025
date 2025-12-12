extends Node

var grid_manager: Node = null

# Size of one grid cell (match your TileMap)
var cell_size: Vector2 = Vector2(16, 16)

# Stores objects by their grid location
var occupied := {}  # Example: occupied[Vector2i(3,4)] = character reference

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / cell_size.x), floor(world_pos.y / cell_size.y))

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return (Vector2(grid_pos) * cell_size) + cell_size / 2

func is_occupied(grid_pos: Vector2i) -> bool:
	return occupied.has(grid_pos)

func occupy(grid_pos: Vector2i, obj):
	occupied[grid_pos] = obj

func vacate(grid_pos: Vector2i):
	occupied.erase(grid_pos)
