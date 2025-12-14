# map_behaviour.gd
extends Node2D

@onready var tile_selector = get_node("../TileSelector")
@onready var grid_manager = get_node("../GridManager")
@onready var tile_map = get_node("../Map/TileMapLayer") # Referenca je že prisotna

var selected_character: Node = null 

func _unhandled_input(event):
	# 1. Preverimo, ali gre za levi klik miške.
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var mouse_world_pos = get_global_mouse_position()
	var clicked_grid = grid_manager.world_to_grid(mouse_world_pos)
	var used_rect = tile_map.get_used_rect()
	
	# =================================================================
	# NOVO: ZAVRNITEV KLIKA ZUNAJ MEJA MAPE
	# =================================================================
	# Preverimo, ali je klik (clicked_grid) znotraj meja (used_rect),
	# preden nadaljujemo z logiko.
	if not grid_manager.is_inside_boundary(clicked_grid, used_rect):
		# Klik je zunaj mape (npr. na GUI območju). Ignoriramo ga.
		return

	# Če je klik znotraj mape, nadaljujemo z logiko igre:

	tile_selector.select_tile(clicked_grid)
	
	var clicked_character = grid_manager.get_character_at(clicked_grid)

	# CLICK ON CHARACTER
	if clicked_character:
		# Clicking the same character → deselect
		if selected_character == clicked_character:
			selected_character.selected = false
			selected_character = null
			return

		# Switching characters
		if selected_character:
			selected_character.selected = false

		selected_character = clicked_character
		selected_character.selected = true
		return


	# CLICK ON EMPTY TILE → MOVE
	if selected_character:
		# is_inside_boundary preverjanje je sedaj redundantno,
		# a ga ohranjamo za vsak slučaj, če bi se meje mape spremenile
		# med klikom in premikom.
		if selected_character.try_move(clicked_grid):
			selected_character.selected = false
			selected_character = null
