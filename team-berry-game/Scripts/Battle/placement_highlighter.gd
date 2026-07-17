# res://Scripts/Battle/placement_highlighter.gd
# Med placement fazo obarva ploščo: spodnje vrstice (placement cona) zeleno,
# vse ostalo rdeče - ista logika barvanja kot MoveHighlighter za poteze.
class_name PlacementHighlighter
extends Node2D

const PLACEMENT_ROWS := 3 # spodnje 3 vrstice = placement cona (nikoli pod snegom)

const VALID_COLOR := Color(0.1, 0.9, 0.1, 0.35) # zelena - prosto polje v coni
const INVALID_COLOR := Color(0.9, 0.1, 0.1, 0.18) # rdeča - izven cone / zasedeno

@onready var grid_manager = get_node("../GridManager")
@onready var tile_map = get_node("../Map/TileMapLayer")

var active: bool = false


func show_zone():
	active = true
	queue_redraw()


func clear_zone():
	active = false
	queue_redraw()


# Kliče battle_ui po vsaki postavitvi/premiku/odstranitvi figure, da se
# zasedena polja v coni prebarvajo.
func refresh():
	if active:
		queue_redraw()


func is_placement_cell(grid_pos: Vector2i) -> bool:
	var used_rect: Rect2i = tile_map.get_used_rect()
	if not grid_manager.is_inside_boundary(grid_pos, used_rect):
		return false
	return grid_pos.y >= used_rect.end.y - PLACEMENT_ROWS


func _draw():
	if not active:
		return
	if not is_instance_valid(grid_manager) or not is_instance_valid(tile_map):
		return

	var used_rect: Rect2i = tile_map.get_used_rect()
	var cell_size: Vector2 = grid_manager.cell_size

	for x in range(used_rect.position.x, used_rect.end.x):
		for y in range(used_rect.position.y, used_rect.end.y):
			var grid_pos := Vector2i(x, y)
			var color := INVALID_COLOR
			if is_placement_cell(grid_pos) and not grid_manager.is_occupied(grid_pos):
				color = VALID_COLOR
			draw_rect(Rect2(Vector2(grid_pos) * cell_size, cell_size), color)
