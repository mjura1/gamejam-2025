extends Node2D

@onready var tile_selector = get_node("/root/Node/TileSelector")
@onready var grid_manager = get_node("/root/Node/GridManager")
@onready var tile_map = get_node("/root/Node/Map/TileMapLayer")
# NEW: Dodana referenca na MoveHighlighter
@onready var move_highlighter = get_node("/root/Node/MoveHighlighter") 

var selected_character: Node = null  # currently selected character

func _unhandled_input(event):
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var clicked_grid = grid_manager.world_to_grid(get_global_mouse_position())
	var used_rect = tile_map.get_used_rect()

	tile_selector.select_tile(clicked_grid)
	
	var clicked_character = grid_manager.get_character_at(clicked_grid)

	# CLICK ON CHARACTER
	if clicked_character:
		# Clicking the same character → deselect
		if selected_character == clicked_character:
			selected_character.selected = false
			selected_character = null
			move_highlighter.clear_moves() # NEW: Počisti poudarek
			return

		# Switching characters
		if selected_character:
			selected_character.selected = false

		selected_character = clicked_character
		selected_character.selected = true
		
		# NEW: Prikaz veljavnih potez
		# Predpostavlja, da je funkcija calculate_valid_targets() implementirana na BaseCharacter/Rook
		var valid_moves = selected_character.calculate_valid_targets() 
		move_highlighter.show_moves(valid_moves)
		
		return


	# CLICK ON EMPTY TILE → MOVE
	if selected_character and grid_manager.is_inside_boundary(clicked_grid, used_rect):
		
		# NEW: Preveri, ali je cilj znotraj veljavnega obsega, ki ga figura lahko doseže
		var valid_targets = selected_character.calculate_valid_targets()
		
		# Preverimo, ali je cilj veljaven IN ali je polje PRAZNO (za premik)
		if valid_targets.has(clicked_grid) and not grid_manager.is_occupied(clicked_grid):
			
			if selected_character.try_move(clicked_grid):
				selected_character.selected = false
				selected_character = null
				move_highlighter.clear_moves() # NEW: Počisti poudarek po premiku
