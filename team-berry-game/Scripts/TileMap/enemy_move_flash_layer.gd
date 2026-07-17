# res://Scripts/TileMap/enemy_move_flash_layer.gd
extends Node2D
class_name EnemyMoveFlashLayer

# Risalna plast samo za MoveHighlighter.enemy_move_flashes/pojemanje - ločena
# od staršu, da queue_redraw() vsako sličico med 5s pojemanjem ne sproži tudi
# ponovnega risanja starševega valid_moves (ki se med pojemanjem ne spreminja).

var highlighter: MoveHighlighter

func _draw_cell(grid_pos: Vector2i, color: Color, filled: bool = true, width: float = -1.0) -> void:
	draw_rect(Rect2(Vector2(grid_pos) * highlighter.cell_size, highlighter.cell_size), color, filled, width)

func _draw():
	if not is_instance_valid(highlighter) or highlighter.enemy_move_flashes.is_empty():
		return

	var alpha_mult = highlighter.current_fade_alpha()

	for flash in highlighter.enemy_move_flashes:
		# Pot / L-figura (siva)
		for path_pos in flash["path"]:
			var path_color: Color = highlighter.PATH_COLOR
			path_color.a *= alpha_mult
			_draw_cell(path_pos, path_color)

		# Ciljno polje (zelena = premik, rdeča = zajetje)
		var dest_color: Color = highlighter.CAPTURE_COLOR if flash["is_capture"] else highlighter.MOVE_COLOR
		dest_color.a *= alpha_mult
		_draw_cell(flash["to"], dest_color)

		# Izvorno polje (bel obris)
		var origin_color := Color(1, 1, 1, 0.9 * alpha_mult)
		_draw_cell(flash["from"], origin_color, false, 2.0)
