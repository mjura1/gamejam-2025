extends Node
class_name BattleController

# ===============================================
# REFERENCE
# ===============================================

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
	# Bitko inicializira battle.gd (Scenes/Map/battle.gd) PO spawnu figur,
	# zato tukaj samo preverimo reference.
	if not is_instance_valid(grid_manager):
		push_error("BattleController: GridManager ni najden. Inicializacija bitke ni mogoča.")


func initialize_battle():
	# 1. Pridobimo trenutni napredek igralca
	var current_floor = 0
	if is_instance_valid(player_manager):
		# Uporabimo current_map_floor, ki smo ga dodali v PlayerManager.gd
		current_floor = player_manager.current_map_floor 
		
	# 2. Pokrijemo mapo z dinamično meglo (snežno odejo)
	if is_instance_valid(grid_manager):
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

	if check_battle_end():
		return

	# Preklopimo na naslednjo fazo (nasprotnikovo potezo)
	start_enemy_turn_delayed()

func start_enemy_turn_delayed() -> void:
	input_locked = true
	start_enemy_turn()

func start_enemy_turn():
	current_state = BattleState.ENEMY_TURN
	print(">>> ZAČETEK POTEZE SOVRAŽNIKA <<<")

	if not is_instance_valid(grid_manager):
		push_error("GridManager ni veljaven za AI potezo.")
		end_enemy_turn()
		return

	for character in grid_manager.get_all_characters():
		if not (character is BaseCharacter):
			continue
		if not character.is_enemy:
			continue

		var action = character.calculate_best_move()
		if action.is_empty():
			continue

		# try_move sam ponovno preveri veljavnost tarče in izvede premik ALI zajetje
		character.try_move(action["target_pos"])

		# Če je ta akcija končala bitko, takoj prekinemo potezo
		if check_battle_end():
			return

	end_enemy_turn()


func end_enemy_turn():
	print("<<< KONEC POTEZE SOVRAŽNIKA >>>")

	start_player_turn()

# Preveri, ali je bitke konec, in po potrebi sproži prehod scene.
# Prehod je call_deferred, da se trenutna akcija (capture/premik) varno dokonča,
# preden GameFlow odstrani sceno iz drevesa.
func check_battle_end() -> bool:
	if not is_instance_valid(player_manager):
		return false

	if player_manager.enemyGone():
		current_state = BattleState.GAME_OVER
		GF.call_deferred("return_to_map")
		return true

	if player_manager.activeGone():
		current_state = BattleState.GAME_OVER
		player_manager.reset_floor_number()
		GF.call_deferred("game_over")
		return true

	return false

# ----------------- FOG OF WAR LOGIC -----------------

# Ta funkcija posodobi meglo na podlagi trenutnih pozicij figur
func update_fog_after_turn_start():
	if not is_instance_valid(grid_manager):
		return

	var reveal_positions: Array[Vector2i] = []

	# Zberemo pozicije vseh ŽIVIH zavezniških figur na mreži
	for character in grid_manager.get_all_characters():
		if not (character is BaseCharacter):
			continue
		if character.is_enemy or character.is_obstacle:
			continue

		var char_pos: Vector2i = character.grid_pos

		# Razkrijemo 3x3 območje okoli figure
		for x in range(-1, 2):
			for y in range(-1, 2):
				var new_pos = char_pos + Vector2i(x, y)
				if new_pos not in reveal_positions:
					reveal_positions.append(new_pos)

	grid_manager.reveal_area(reveal_positions)
