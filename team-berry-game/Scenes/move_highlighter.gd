# res://Scripts/Battle/MoveHighlighter.gd
extends Node2D

# Referenci na GridManager in velikost celice
@onready var grid_manager = get_node("/root/Node/GridManager")
var cell_size: Vector2 = Vector2.ZERO

# Array veljavnih mrežnih pozicij (Vector2i), ki jih moramo narisati
var valid_moves: Array[Vector2i] = []

func _ready():
	# Preverite, ali je referenca pravilna, in pridobite velikost celice
	if is_instance_valid(grid_manager):
		# Grid Manager je v drugem delu vaše skripte (dummy.txt) določil velikost: Vector2(16, 16)
		cell_size = grid_manager.cell_size
	else:
		push_error("MoveHighlighter: GridManager ni najden na poti /root/Node/GridManager.")

func show_moves(moves: Array[Vector2i]):
 #"""Sprejme seznam veljavnih pozicij in sproži ponovno risanje."""
	valid_moves = moves
	queue_redraw()

func clear_moves():
	#"""Počisti seznam in skrije poudarek."""
	valid_moves.clear()
	queue_redraw()

func _draw():
	if valid_moves.is_empty() or not is_instance_valid(grid_manager):
		return

	for grid_pos in valid_moves:
		var top_left = Vector2(grid_pos) * cell_size
		
		# Barva za premikanje (prazno polje)
		var draw_color = Color(0, 0.8, 0.2, 0.3) 
		
		# OPOZORILO: Zaenkrat ne preverjamo, ali gre za napad ali premik, 
		# ker logika napada še ni popolnoma implementirana.
		# Risanje polnila (fill)
		draw_rect(
			Rect2(top_left, cell_size),
			draw_color,
			true 
		)
