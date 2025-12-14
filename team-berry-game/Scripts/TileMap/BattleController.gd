
# res://Scripts/BattleController.gd
extends Node

# Stanja igre: Kdo je na vrsti.
enum TurnState {
	PLAYER_TURN,
	ENEMY_TURN
}

var current_state = TurnState.PLAYER_TURN

# REFERENCE:
@onready var player_manager = get_node("/root/PlayerManager")
@onready var grid_manager = get_node("../GridManager")


func _ready():
	print("Igra se je začela! Na vrsti je igralec.")
	start_player_turn()

# ----------------- IGRALČEVE POTEZE -----------------

func start_player_turn():
	current_state = TurnState.PLAYER_TURN
	print(">> Na vrsti je Igralec!")

func end_player_turn():
	# 1. Preverjanje Game Over
	if player_manager.active_party.is_empty():
		print("GAME OVER - Igralec poražen.")
		return

	# 2. Preverjanje Pogojev Zmage (če na mreži ni sovražnikov)
	# Če klic get_all_characters() ne vrne sovražnikov, bo to obravnavano v execute_enemy_move().
	
	# 3. Preklop na AI
	start_enemy_turn()

# ----------------- SOVRAŽNIKOVE POTEZE -----------------

func start_enemy_turn():
	current_state = TurnState.ENEMY_TURN
	print(">> Na vrsti je Sovražnik!")
	
	# Čakamo 0.5 sekunde za vizualno pavzo
	var timer = Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.start(0.5)
	await timer.timeout
	timer.queue_free()
	
	# Izvršimo logiko AI-ja
	execute_enemy_move()

func end_enemy_turn():
	# Preverjanje Game Over po sovražnikovi potezi
	if player_manager.active_party.is_empty():
		print("GAME OVER - Igralec poražen.")
		return
	
	# Preklop nazaj na igralca
	start_player_turn()

# DECENTRALIZIRANA AI LOGIKA
func execute_enemy_move():
	
	if not is_instance_valid(grid_manager):
		push_error("AI ne more dostopati do GridManagerja.")
		end_enemy_turn()
		return

	var all_characters = grid_manager.get_all_characters()
	var enemy_pieces: Array = []
	
	# 1. Zberemo vse aktivne sovražne figure
	for char in all_characters:
		if char is BaseCharacter and char.is_enemy:
			enemy_pieces.append(char)
	
	if enemy_pieces.is_empty():
		print("Zmaga! Vsi sovražniki uničeni. (Game Win)")
		return
		
	# 2. Iščemo najboljšo potezo med vsemi sovražniki
	var best_move: Dictionary = {}
	var piece_to_act: BaseCharacter = null # Katera figura bo izvedla potezo

	for enemy in enemy_pieces:
		var move_suggestion = enemy.calculate_best_move() # KLJUČNI DECENTRALIZIRANI KLIC
		
		if move_suggestion.is_empty():
			continue
			
		# Prioriteta: Vedno izberemo prvo najdeno ZAJETJE
		if move_suggestion.has("move_type") and move_suggestion.move_type == "CAPTURE":
			best_move = move_suggestion
			piece_to_act = enemy
			break # Ustavimo iskanje, saj zajetje ne bo prekašano
			
		# Če ni zajetja, si shranimo vsaj en premik (prvi najdeni)
		elif piece_to_act == null:
			best_move = move_suggestion
			piece_to_act = enemy
			
	# 3. IZVEDBA POTEZE
	if piece_to_act:
		var target_pos = best_move.target_pos
		
		if best_move.move_type == "CAPTURE":
			var target_char = grid_manager.get_character_at(target_pos)
			piece_to_act.capture(target_char)
			print("AI: Zajetje z %s na %s" % [piece_to_act.name, target_pos])
			
		elif best_move.move_type == "MOVE":
			piece_to_act.try_move(target_pos)
			print("AI: Premik z %s na %s" % [piece_to_act.name, target_pos])
			
		end_enemy_turn() # Poteza je končana po uspešni akciji
		return
		
	# Če ni bilo najdeno nič
	print("AI: Ni možnih potez. Preskok poteze.")
	end_enemy_turn()
