extends Node2D

@onready var tile_selector = get_node("/root/Node/TileSelector")
@onready var grid_manager = get_node("/root/Node/GridManager")
@onready var tile_map = get_node("/root/Node/Map/TileMapLayer")
@onready var move_highlighter = get_node("/root/Node/MoveHighlighter")
@onready var battle_controller = get_parent().get_node("BattleController")

var selected_character: Node = null # trenutno izbrana figura

func _input(event):
	# Preverjanje dogodka klika miške (pravilno)
	if battle_controller.current_state != battle_controller.TurnState.PLAYER_TURN:
		return
	
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	# VSA NASLEDNJA KODA MORA BITI VREČANA V FUNKCIJO _input(event):
	
	var clicked_grid = grid_manager.world_to_grid(get_global_mouse_position())
	var used_rect = tile_map.get_used_rect()

	tile_selector.select_tile(clicked_grid)
	
	# KLJUČNI POPRAVEK: Ta vrstica je sedaj ZNOTRAJ _input()
	var clicked_character = grid_manager.get_character_at(clicked_grid) 

	# 1. GLAVNA LOGIKA KLIKA NA FIGURO (IZBIRA ALI ZAJETJE)
	if clicked_character:
		# A. ČE JE ŽE KAJ IZBRANO (IMAMO selected_character)
		if selected_character:
			
			# 1. Ali je klik na SOVRAŽNIKA? (Akcija Zajetja)
			# Preverimo, ali je tarča sovražnik IN ali je ta tarča veljavna poteza za že izbrano figuro.
			if clicked_character.is_enemy != selected_character.is_enemy and \
				selected_character.calculate_valid_targets().has(clicked_grid):

				# --- AKCIJA ZAJETJA (CAPTURE) ---
				selected_character.capture(clicked_character)
				
				# Po akciji počistimo
				selected_character.selected = false
				selected_character = null
				move_highlighter.clear_moves()
				battle_controller.end_player_turn()
				get_viewport().set_input_as_handled() 
				return # KONEC: Zajetje je končano

			# 2. Ali je klik na ISTO figuro? (Odizbira)
			if selected_character == clicked_character:
				selected_character.selected = false
				selected_character = null
				move_highlighter.clear_moves()
				get_viewport().set_input_as_handled() 
				return

			# 3. Ali je klik na PRIJATELJA? (Preklop na novo izbiro)
			if clicked_character.is_enemy == selected_character.is_enemy:
				selected_character.selected = false # Odizberemo starega
				# Nadaljujemo s kodo spodaj, da izberemo novega
				
				
		# B. NOVA IZBIRA (Ne glede na to, ali je bil prejšnji preklop ali prazno)
		
		# Nastavimo novo figuro za selected_character
		selected_character = clicked_character
		selected_character.selected = true
		
		# Prikaz veljavnih potez (za novo izbrano figuro)
		var valid_moves = selected_character.calculate_valid_targets()
		move_highlighter.show_moves(valid_moves)
		get_viewport().set_input_as_handled() 
		return


	# 2. LOGIKA AKCIJE (PREMIK)
	# Če je selected_character izbran in kliknemo na prazno polje:
	if selected_character and grid_manager.is_inside_boundary(clicked_grid, used_rect):
		
		var valid_targets = selected_character.calculate_valid_targets()
		
		if valid_targets.has(clicked_grid):
			
			var target_on_tile = grid_manager.get_character_at(clicked_grid)
			
			if not target_on_tile: # Samo če je polje prazno
				# --- AKCIJA PREMIKA (MOVE) ---
				if selected_character.try_move(clicked_grid):
					print("Premik na: {}".format([clicked_grid]))
					
					selected_character.selected = false
					selected_character = null
					move_highlighter.clear_moves()
					battle_controller.end_player_turn()
					get_viewport().set_input_as_handled()
					return

	# Konec funkcije _input(event)
