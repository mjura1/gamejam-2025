# res://Scripts/map_behaviour.gd
extends Node2D

# Sproži se ob vsaki spremembi izbire (character ali null), da battle UI
# lahko posodobi prikaz izbrane figure.
signal selection_changed(character)

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
# POMOŽNE FUNKCIJE ZA IZBIRO
# ===============================================

# Izbere figuro in pokaže njene veljavne poteze.
func _apply_selection(character: BaseCharacter):
	if selected_character:
		selected_character.selected = false
	selected_character = character
	selected_character.selected = true

	var valid_moves = selected_character.calculate_valid_targets()
	move_highlighter.show_moves(valid_moves)
	selection_changed.emit(selected_character)

# Odstrani izbiro in počisti poudarke.
func _clear_selection():
	if selected_character:
		selected_character.selected = false
		selected_character = null
	move_highlighter.clear_moves()
	tile_selector.clear_selection()
	selection_changed.emit(null)

# Izbira figure preko UI (klik na ikono v battle UI panelu).
func select_character_via_ui(character):
	if not is_instance_valid(character) or not (character is BaseCharacter):
		return
	if character.is_enemy or character.is_obstacle:
		return
	if is_instance_valid(battle_controller) and not battle_controller.player_can_act():
		return

	_apply_selection(character)
	tile_selector.select_tile(character.grid_pos)

# ===============================================
# VNOS (INPUT)
# ===============================================

func _unhandled_input(event):
	# 1. Preverimo, ali gre za levi klik miške.
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	# Med placement fazo klike na ploščo obravnava battle UI (drag & drop),
	# ne izbirna logika bitke.
	if is_instance_valid(battle_controller) and battle_controller.current_state == battle_controller.BattleState.PLACEMENT:
		return

	var mouse_world_pos = get_global_mouse_position()
	var clicked_grid = grid_manager.world_to_grid(mouse_world_pos)
	var used_rect = tile_map.get_used_rect() 
	
	# 2. ZAVRNITEV KLIKA ZUNAJ MEJA MAPE
	if not grid_manager.is_inside_boundary(clicked_grid, used_rect):
		# Če je bila figura izbrana, jo deselektujemo in počistimo poudarek
		if selected_character:
			_clear_selection()
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
			_clear_selection()
			return

		# B) KLIK NA ŽE IZBRANO FIGURO (selected_character je nastavljen)
		if selected_character:

			# Ali je kliknjena figura SOVRAŽNIK? (Poskus zajetja)
			if clicked_character.is_enemy != selected_character.is_enemy:

				# try_move() v BaseCharacter.gd zdaj obravnava logiko capture()
				if selected_character.try_move(clicked_grid):

					# Uspešno zajetje (captured)
					_clear_selection()

					# Klic BattleControllerja za konec poteze igralca
					if is_instance_valid(battle_controller):
						battle_controller.end_player_turn()

					return # Konec poteze
				else:
					# Neveljavno zajetje (izven dosega). Ohranimo izbiro ali deselektiramo?
					# Odločitev: Pokažemo napako in ohranimo izbiro, če je to igralčeva poteza.
					# Tukaj deselektiramo, če ni bilo uspešno, za preprostejši UX.
					_clear_selection()
					return


			# C) KLIK NA ZAVEZNIKA (SWITCH SELECTION)
			else:
				# Deselektiraj staro figuro in izberi novo
				_apply_selection(clicked_character)
				return

		# D) KLIK NA FIGURO, KO NI BILA IZBRANA NOBENA DRUGA
		else:
			# Dovolimo izbiro samo IGRALČEVIH figur
			if not clicked_character.is_enemy:
				_apply_selection(clicked_character)
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
			_clear_selection()

			# Klic BattleControllerja za konec poteze igralca
			if is_instance_valid(battle_controller):
				battle_controller.end_player_turn()

			return

		# Če premik ni bil uspešen (klikal je na prazno polje, ki ni veljavna tarča):
		_clear_selection()
