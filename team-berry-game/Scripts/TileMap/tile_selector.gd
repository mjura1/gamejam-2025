extends Node2D

var cell_size: Vector2
var selected_tile: Vector2i = Vector2i(-1, -1)

func _ready():
	var grid_manager = get_node("../GridManager")
	cell_size = grid_manager.cell_size


func select_tile(tile: Vector2i):
	selected_tile = tile
	queue_redraw()


func _draw():
	if selected_tile.x == -1:
		return

	var top_left = Vector2(selected_tile) * cell_size

	draw_rect(
		Rect2(top_left, cell_size),
		Color(1, 1, 1, 1),
		false,
		2.0
	)
