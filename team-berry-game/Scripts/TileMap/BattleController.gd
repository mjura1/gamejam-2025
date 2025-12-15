extends Node
class_name BattleController

# ===============================================
# REFERENCE (POPRAVLJENO)
# ===============================================

# POPRAVEK: Spremenjena pot za dostop do bratskega vozlišča GridManager
@onready var grid_manager: GridManager = get_node("../GridManager")
@onready var player_manager = get_node("/root/PlayerManager")

# ENUM za stanja bitke
enum BattleState {
	INITIALIZING,
	PLAYER_TURN,
	ENEMY_TURN,
	TURN_END,
	GAME_OVER
}

var current_state: int = BattleState.INITIALIZING
var turn_count: int = 0
var input_locked: bool = false # Nova spremenljivka, ohranjena

# ----------------- INITIALIZATION -----------------

func _ready():
	# Inicializiramo logiko bitke, vključno z meglo
	if is_instance_valid(grid_manager):
		initialize_battle()
	else:
		push_error("BattleController: GridManager ni najden. Inicializacija bitke ni mogoča.")


func initialize_battle():
	# 1. Pridobimo trenutni napredek igralca
	var current_floor = 0
	if is_instance_valid(player_manager):
		# Uporabimo current_map_floor, ki smo ga dodali v PlayerManager.gd
		current_floor = player_manager.current_map_floor 
		
	# 2. Pokrijemo mapo z dinamično meglo (snežno odejo)
	if is_instance_valid(grid_manager):
		# KRITIČEN POPRAVEK: Podamo trenutno nadstropje, da GridManager izračuna obseg megle
		grid_manager.initialize_all_fog(current_floor) 
		
	# 3. Zaženemo prvo potezo
	start_player_turn()

# ----------------- TURN LOGIC -----------------

func player_can_act() -> bool:
	return (
		current_state == BattleState.PLAYER_TURN
		and not input_locked
	)

func start_player_turn():
	input_locked = false
	turn_count += 1
	current_state = BattleState.PLAYER_TURN
	print(">>> ZAČETEK POTEZE IGRALCA (Turn %d)" % turn_count)
	
	# Razkrijemo figure takoj, ko se poteza začne
	update_fog_after_turn_start()

func end_player_turn():
	print("<<< KONEC POTEZE IGRALCA >>>")

	# Preklopimo na naslednjo fazo (npr. nasprotnikovo potezo)
	start_enemy_turn_delayed()

func start_enemy_turn_delayed() -> void:
	input_locked = true
	# Uporabimo await, da počakamo pol sekunde
	await get_tree().create_timer(0.5).timeout 
	start_enemy_turn()

func start_enemy_turn():
	current_state = BattleState.ENEMY_TURN
	print(">>> ZAČETEK POTEZE SOVRAŽNIKA <<<")

	if not is_instance_valid(grid_manager):
		push_error("GridManager ni veljaven za AI potezo.")
		end_enemy_turn()
		return
	
	for char in grid_manager.get_all_characters():
		if not char.is_enemy:
			continue

		if not char is BaseCharacter:
			continue

		var action = char.calculate_best_move()
		if action.is_empty():
			continue

		# Uporaba try_move za preverjanje zasedenosti in zajetje tarče
		match action.get("move_type", ""):
			"CAPTURE":
				char.try_move(action["target_pos"])
			"MOVE":
				char.try_move(action["target_pos"]) # Uporabimo try_move, ki znotraj sebe kliče execute_move/capture
			_:
				print("Opozorilo: Nepričakovan move_type v AI akciji.")

	end_enemy_turn()


func end_enemy_turn():
	print("<<< KONEC POTEZE SOVRAŽNIKA >>>")
	
	start_player_turn()

# ----------------- FOG OF WAR LOGIC -----------------

# Ta funkcija posodobi meglo na podlagi trenutnih pozicij figur
func update_fog_after_turn_start():
	if not is_instance_valid(grid_manager) or not is_instance_valid(player_manager):
		return
	
	var reveal_positions: Array[Vector2i] = []
	
	# 1. Zberemo pozicije vseh figur zaveznikov
	for char in player_manager.active_party:
		# Ker PlayerManager sedaj shrani BaseCharacter objekte po spawn-u, to preverjanje zagotovi, 
		# da obdelujemo le veljavne figure.
		if is_instance_valid(char) and char is BaseCharacter: 
			var char_pos = char.grid_pos
			
			# 2. Izračunamo vsa polja, ki jih je treba razkriti (3x3 območje)
			for x in range(-1, 2):
				for y in range(-1, 2):
					var new_pos = char_pos + Vector2i(x, y)
					if new_pos not in reveal_positions:
						reveal_positions.append(new_pos)

	# 3. Naročimo GridManagerju, da razkrije (odstrani meglo) na teh poljih
	grid_manager.reveal_area(reveal_positions)
