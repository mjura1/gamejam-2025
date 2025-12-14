# res://Scripts/Battle/map_behaviour.gd
extends Node2D

# ===============================================
# REFERENCE
# Opomba: Vsa vozlišča so brata (siblings) pod vozliščem 'Battle' (..)
# ===============================================

@onready var tile_selector = get_node("../TileSelector")
@onready var grid_manager = get_node("../GridManager")
@onready var tile_map = get_node("../Map/TileMapLayer") 
@onready var move_highlighter = get_node("../MoveHighlighter")

var selected_character: BaseCharacter = null 

# ===============================================
# VNOS (INPUT)
# ===============================================

func _unhandled_input(event):
	# 1. Preverimo, ali gre za levi klik miške.
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var mouse_world_pos = get_global_mouse_position()
	var clicked_grid = grid_manager.world_to_grid(mouse_world_pos)
	
	# Za pridobitev mej mape (TileMapLayer)
	var used_rect = tile_map.get_used_rect() 
	
	# 2. ZAVRNITEV KLIKA ZUNAJ MEJA MAPE
	if not grid_manager.is_inside_boundary(clicked_grid, used_rect):
		# Klik je zunaj mape. Če je bila figura izbrana, jo deselektujemo
		# in počistimo poudarek, da UI ostane čist.
		if selected_character:
			selected_character.selected = false
			selected_character = null
			move_highlighter.clear_moves()
		return

	# Pokaži indikator klika (TileSelector)
	tile_selector.select_tile(clicked_grid)
	
	var clicked_character = grid_manager.get_character_at(clicked_grid)

	# ===================================================
	# LOGIKA 1: KLIK NA FIGURO (SELECT/DESELECT)
	# ===================================================
	
	if clicked_character:
		# Klik na isto figuro → deselect
		if selected_character == clicked_character:
			selected_character.selected = false
			selected_character = null
			move_highlighter.clear_moves() # Počisti poudarke
			return

		# Preklapljanje figur
		if selected_character:
			selected_character.selected = false

		# Izbira nove figure (ali prve figure)
		selected_character = clicked_character
		selected_character.selected = true
		
		# Pokaži možne poteze za novo izbrano figuro
		var valid_moves = selected_character.calculate_valid_targets()
		move_highlighter.show_moves(valid_moves) # Pokaži poudarke
		return


	# ===================================================
	# LOGIKA 2: KLIK NA PRAZNO POLJE (PREMIK)
	# ===================================================
	
	if selected_character:
		# Poskus premika na kliknjeno polje
		if selected_character.try_move(clicked_grid): # try_move poskrbi za veljavnost poteze
			
			# Uspešen premik
			selected_character.selected = false
			selected_character = null
			move_highlighter.clear_moves() # Počisti poudarke po premiku
			
			# Klic BattleControllerja za konec poteze igralca
			# (Predpostavljamo, da je BattleController brat)
			var battle_controller = get_node("../BattleController")
			if is_instance_valid(battle_controller):
				battle_controller.end_player_turn() 
				
			return
		
		# Če premik ni bil uspešen (klikal je na prazno polje, ki ni veljavna tarča):
		# Deselektira figuro in počisti poudarek
		selected_character.selected = false
		selected_character = null
		move_highlighter.clear_moves()
