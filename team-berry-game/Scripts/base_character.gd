extends Node2D

var grid_pos: Vector2i

@export var selected: bool = false

@export var move_offsets: Array[Vector2i] = []

@export var grid_manager: Node 

func _ready():
	# Snap to grid on spawn
	grid_manager = get_node("/root/Node/GridManager")

	# Derive grid position from where the node is placed in the editor
	grid_pos = grid_manager.world_to_grid(global_position)

	# Snap visually to grid (optional but recommended)
	global_position = grid_manager.grid_to_world(grid_pos)

	grid_manager.occupy(grid_pos, self)

func try_move(target: Vector2i):
	var offset := target - grid_pos
	if offset not in move_offsets:
		print("Invalid move")
		return false
	
	if grid_manager.is_occupied(target):
		print("Blocked!")
		return false

	grid_manager.vacate(grid_pos)
	grid_pos = target
	grid_manager.occupy(grid_pos, self)
	global_position = grid_manager.grid_to_world(grid_pos)
	
	return true
