# res://Scripts/Battle/MoveHighlighter.gd
extends Node2D

# Referenci na GridManager in velikost celice
@onready var grid_manager = get_node("../GridManager")
var cell_size: Vector2 = Vector2.ZERO

# Array veljavnih mrežnih pozicij (Vector2i), ki jih moramo narisati
var valid_moves: Array[Vector2i] = []

const MOVE_COLOR = Color(0.1, 0.9, 0.1, 0.6) # Svetla Zelena
const CAPTURE_COLOR = Color(0.9, 0.1, 0.1, 0.6) # Svetla Rdeča

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
		
		# 1. Privzeta barva: Zelena (premik)
		var draw_color = MOVE_COLOR
		
		# 2. Preverjanje za ZAJETJE
		var target_char = grid_manager.get_character_at(grid_pos)
		
		# Če je na polju figura:
		if target_char:
			draw_color = CAPTURE_COLOR # Rdeča
		
		# Risanje polnila (fill)
		draw_rect(
			Rect2(top_left, cell_size),
			draw_color,
			true 
		)
