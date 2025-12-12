extends Node2D

var grid_pos: Vector2i
@export var grid_manager: Node 

func _ready():
	# Snap to grid on spawn
	grid_manager = get_node("/root/Node/GridManager")
	global_position = grid_manager.grid_to_world(grid_pos)
	grid_pos = grid_manager.world_to_grid(global_position)
	grid_manager.occupy(grid_pos, self)

func try_move(direction: Vector2i):
	var target = grid_pos + direction
	if grid_manager.is_occupied(target):
		print("Blocked!")
		return

	grid_manager.vacate(grid_pos)
	grid_pos = target
	grid_manager.occupy(grid_pos, self)
	global_position = grid_manager.grid_to_world(grid_pos)
