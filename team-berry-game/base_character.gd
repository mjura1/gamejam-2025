extends Node2D

var grid_pos: Vector2i
var grid_manager: Node # reference to GridManager

func _ready():
	# Snap to grid on spawn
	grid_pos = grid_manager.world_to_grid(global_position)
	grid_manager.occupy(grid_pos, self)
	global_position = grid_manager.grid_to_world(grid_pos)

func try_move(direction: Vector2i):
	var target = grid_pos + direction
	if grid_manager.is_occupied(target):
		print("Blocked!")
		return

	grid_manager.vacate(grid_pos)
	grid_pos = target
	grid_manager.occupy(grid_pos, self)
	global_position = grid_manager.grid_to_world(grid_pos)
