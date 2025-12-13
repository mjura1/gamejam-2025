extends Node2D

var hovered_tile: Vector2i = Vector2i(-1, -1)
var grid_manager = null
var cell_size: Vector2 = Vector2.ZERO

func _ready():
	grid_manager = get_parent()

func _process(delta):
	if grid_manager == null:
		return
	
	cell_size = grid_manager.cell_size
	var mouse_world = get_global_mouse_position()
	var grid = grid_manager.world_to_grid(mouse_world)

	if grid != hovered_tile:
		hovered_tile = grid
		queue_redraw()

func _draw():
	if hovered_tile.x == -1:
		return

	# Convert grid → world position
	var top_left = Vector2(hovered_tile) * cell_size

	draw_rect(
		Rect2(top_left, cell_size),
		Color(1, 1, 1, 0.5),
		false,
		1.0
	)
