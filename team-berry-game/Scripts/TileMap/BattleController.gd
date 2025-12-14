extends Node
class_name BattleController

# ===============================================
# REFERENCE (POPRAVLJENO)
# ===============================================

# POPRAVEK: Spremenjena pot za dostop do bratskega vozlišča GridManager
# Predpostavka: BattleController in GridManager sta na isti ravni (npr. oba otroka vozlišča 'Battle')
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


# ----------------- INITIALIZATION -----------------

func _ready():
	# Inicializiramo logiko bitke, vključno z meglo
	# ZAVAROVALO: Če referenca še vedno ne deluje, to prepreči crash
	if is_instance_valid(grid_manager):
		initialize_battle()
	else:
		push_error("BattleController: GridManager ni najden. Inicializacija bitke ni mogoča.")


func initialize_battle():
	# KRITIČNO: Klic funkcije za inicializacijo megle (Fog of War)
	if is_instance_valid(grid_manager):
		# 1. Pokrijemo celotno mapo z meglo
		grid_manager.initialize_all_fog()
		
		# 2. Razkrijemo območje okoli začetnih figur
		update_fog_after_turn_start()

	start_player_turn()

# ----------------- TURN LOGIC -----------------

func start_player_turn():
	turn_count += 1
	current_state = BattleState.PLAYER_TURN
	print(">>> ZAČETEK POTEZE IGRALCA (Turn %d)" % turn_count)

func end_player_turn():
	print("<<< KONEC POTEZE IGRALCA >>>")
	
	# Po koncu poteze igralca posodobimo meglo
	update_fog_after_turn_start()
	
	# Preklopimo na naslednjo fazo (npr. nasprotnikovo potezo)
	start_enemy_turn()

func start_enemy_turn():
	current_state = BattleState.ENEMY_TURN
	print(">>> ZAČETEK POTEZE SOVRAŽNIKA <<<")
	
	# TU BI SPROŽILI KODO ZA AI
	# ...
	
	# Za testiranje takoj preklopimo nazaj
	end_enemy_turn()

func end_enemy_turn():
	print("<<< KONEC POTEZE SOVRAŽNIKA >>>")
	
	# Posodobimo meglo, preden se začne igralčeva poteza (če je prišlo do premikov)
	update_fog_after_turn_start()
	
	start_player_turn()

# ----------------- FOG OF WAR LOGIC -----------------

# Ta funkcija posodobi meglo na podlagi trenutnih pozicij figur
func update_fog_after_turn_start():
	if not is_instance_valid(grid_manager) or not is_instance_valid(player_manager):
		return
	
	var reveal_positions: Array[Vector2i] = []
	
	# 1. Zberemo pozicije vseh figur zaveznikov
	for char in player_manager.active_party:
		if is_instance_valid(char):
			var char_pos = char.grid_pos
			
			# 2. Izračunamo vsa polja, ki jih je treba razkriti (3x3 območje)
			for x in range(-1, 2):
				for y in range(-1, 2):
					var new_pos = char_pos + Vector2i(x, y)
					if new_pos not in reveal_positions:
						reveal_positions.append(new_pos)

	# 3. Naročimo GridManagerju, da razkrije (odstrani meglo) na teh poljih
	grid_manager.reveal_area(reveal_positions)
