# res://Scripts/Battle/map_behaviour.gd
extends Node2D

# ===============================================
# REFERENCE
# ===============================================

@onready var tile_selector = get_node("../TileSelector")
@onready var grid_manager = get_node("../GridManager")
@onready var tile_map = get_node("../Map/TileMapLayer") 
@onready var move_highlighter = get_node("../MoveHighlighter")
@onready var battle_controller = get_node("../BattleController") # Dodana @onready referenca

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
	var used_rect = tile_map.get_used_rect() 
	
	# 2. ZAVRNITEV KLIKA ZUNAJ MEJA MAPE
	if not grid_manager.is_inside_boundary(clicked_grid, used_rect):
		# Če je bila figura izbrana, jo deselektujemo in počistimo poudarek
		if selected_character:
			selected_character.selected = false
			selected_character = null
			move_highlighter.clear_moves()
		return

	# Pokaži indikator klika (TileSelector)
	tile_selector.select_tile(clicked_grid)
	
	var clicked_character = grid_manager.get_character_at(clicked_grid)

	# ===================================================
	# LOGIKA 1: KLIK NA FIGURO (ATTEMPT CAPTURE / SWITCH SELECTION)
	# ===================================================
	
	if clicked_character:
		# A) KLIK NA ISTO FIGURO → DESELECT
		if selected_character == clicked_character:
			selected_character.selected = false
			selected_character = null
			move_highlighter.clear_moves()
			return

		# B) KLIK NA ŽE IZBRANO FIGURO (selected_character je nastavljen)
		if selected_character:
			
			# Ali je kliknjena figura SOVRAŽNIK? (Poskus zajetja)
			if clicked_character.is_enemy != selected_character.is_enemy:
				
				# try_move() v BaseCharacter.gd zdaj obravnava logiko capture()
				if selected_character.try_move(clicked_grid): 
					
					# Uspešno zajetje (captured)
					selected_character = null
					move_highlighter.clear_moves()
					
					# Klic BattleControllerja za konec poteze igralca
					if is_instance_valid(battle_controller):
						battle_controller.end_player_turn() 
						
					return # Konec poteze
				else:
					# Neveljavno zajetje (izven dosega). Ohranimo izbiro ali deselektiramo?
					# Odločitev: Pokažemo napako in ohranimo izbiro, če je to igralčeva poteza.
					# Tukaj deselektiramo, če ni bilo uspešno, za preprostejši UX.
					selected_character.selected = false
					selected_character = null
					move_highlighter.clear_moves()
					return


			# C) KLIK NA ZAVEZNIKA (SWITCH SELECTION)
			else:
				# Deselektiraj staro figuro in izberi novo
				selected_character.selected = false
				selected_character = clicked_character
				selected_character.selected = true
				
				var valid_moves = selected_character.calculate_valid_targets()
				move_highlighter.show_moves(valid_moves)
				return
		
		# D) KLIK NA FIGURO, KO NI BILA IZBRANA NOBENA DRUGA
		else:
			# Dovolimo izbiro samo IGRALČEVIH figur
			if not clicked_character.is_enemy:
				selected_character = clicked_character
				selected_character.selected = true
				
				var valid_moves = selected_character.calculate_valid_targets()
				move_highlighter.show_moves(valid_moves)
				return
			else:
				# Klik na sovražnika, ko ni izbrana nobena figura: ne naredimo nič
				return
	
	# ===================================================
	# LOGIKA 2: KLIK NA PRAZNO POLJE (PREMIK)
	# ===================================================
	
	if selected_character:
		# Poskus premika na kliknjeno polje
		if selected_character.try_move(clicked_grid):
			
			# Uspešen premik
			selected_character.selected = false
			selected_character = null
			move_highlighter.clear_moves()
			
			# Klic BattleControllerja za konec poteze igralca
			if is_instance_valid(battle_controller):
				battle_controller.end_player_turn() 
				
			return
		
		# Če premik ni bil uspešen (klikal je na prazno polje, ki ni veljavna tarča):
		selected_character.selected = false
		selected_character = null
		move_highlighter.clear_moves()
