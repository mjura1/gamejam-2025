extends Node2D

@onready var tile_selector = get_node("/root/Node/TileSelector")
@onready var grid_manager = get_node("/root/Node/GridManager")
@onready var tile_map = get_node("/root/Node/Map/TileMapLayer")
@onready var move_highlighter = get_node("/root/Node/MoveHighlighter")

var selected_character: Node = null  # trenutno izbrana figura

func _unhandled_input(event):
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var clicked_grid = grid_manager.world_to_grid(get_global_mouse_position())
	var used_rect = tile_map.get_used_rect()

	tile_selector.select_tile(clicked_grid)
	
	var clicked_character = grid_manager.get_character_at(clicked_grid)

	# 1. LOGIKA IZBIRE/ODIZBIRE
	if clicked_character:
		# Clicking the same character → deselect
		if selected_character == clicked_character:
			selected_character.selected = false
			selected_character = null
			move_highlighter.clear_moves() # Počisti poudarek
			return

		# Switching characters
		if selected_character:
			selected_character.selected = false

		selected_character = clicked_character
		selected_character.selected = true
		
		# Prikaz veljavnih potez
		var valid_moves = selected_character.calculate_valid_targets()
		move_highlighter.show_moves(valid_moves)
		return


	# 2. LOGIKA AKCIJE (PREMIK ALI ZAJETJE)
	# Izvede se, če je figura izbrana in je klik znotraj mej mreže.
	if selected_character and grid_manager.is_inside_boundary(clicked_grid, used_rect):
		
		var valid_targets = selected_character.calculate_valid_targets()
		
		# Preverimo, ali je ciljno polje sploh veljavno
		if valid_targets.has(clicked_grid):
			
			var target_on_tile = grid_manager.get_character_at(clicked_grid)
			
			if target_on_tile:
				# --- AKCIJA ZAJETJA (CAPTURE) ---
				# Če je polje zasedeno, je to zajetje (preverjanje sovražnika je nujno)
				if target_on_tile.is_enemy != selected_character.is_enemy:
					
					selected_character.capture(target_on_tile) # <--- ZAJETJE
					
					# PO AKCIJI: Zaključimo potezo in odizberemo figuro
					selected_character.selected = false
					selected_character = null
					move_highlighter.clear_moves()

			else:
				# --- AKCIJA PREMIKA (MOVE) ---
				# Polje je prazno -> Premik
				if selected_character.try_move(clicked_grid):
					print("Premik na: {}".format([clicked_grid]))
					
					# PO AKCIJI: Zaključimo potezo in odizberemo figuro
					selected_character.selected = false
					selected_character = null
					move_highlighter.clear_moves()
