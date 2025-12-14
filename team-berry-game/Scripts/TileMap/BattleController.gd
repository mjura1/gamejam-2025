# res://Scripts/BattleController.gd
extends Node

# Stanja igre: Kdo je na vrsti.
enum TurnState { 
	PLAYER_TURN, 
	ENEMY_TURN 
}

var current_state = TurnState.PLAYER_TURN

# REFERENCE:
# Dobi referenco na Singleton, da preveri Game Over pogoje.
@onready var player_manager = get_node("/root/PlayerManager") 
# TODO: Dobi referenco na GridManager, da kasneje najde sovražnike.
# @onready var grid_manager = get_node("/root/Node/GridManager") 


func _ready():
	print("Igra se je začela! Na vrsti je igralec.")
	start_player_turn()

# ----------------- IGRALČEVE POTEZE -----------------

func start_player_turn():
	current_state = TurnState.PLAYER_TURN
	print(">> Na vrsti je Igralec!")
	# V prihodnosti: Kličemo signal, da se prikažejo UI elementi (gumb za konec poteze, itd.)

# Funkcija, ki jo kliče input controller po uspešnem premiku ali zajetju
func end_player_turn():
	# 1. Preverjanje Game Over (če je igralec ravnokar izgubil zadnjo figuro)
	if player_manager.active_party.is_empty():
		# To je že obravnavano v BaseCharacter.die(), a vseeno dobro za centralizirano preverjanje.
		print("GAME OVER - Igralec poražen.")
		return 

	# 2. Preverjanje Pogojev Zmage
	# TODO: Preveri, ali so na plošči ostali še kakšni sovražniki. Če ne, kličemo Game Win.
	
	# 3. Preklop na AI
	start_enemy_turn()

# ----------------- SOVRAŽNIKOVE POTEZE -----------------

func start_enemy_turn(): 
	current_state = TurnState.ENEMY_TURN
	print(">> Na vrsti je Sovražnik!")
	
	# To je del, ki ga bomo v naslednji fazi zamenjali z AI logiko.
	# Za zdaj le simuliramo potezo s čakanjem:
	
	var timer = Timer.new()
	timer.one_shot = true # Nastavimo ga kot one-shot, če želimo enostavno
	add_child(timer)
	
	timer.start(1.0)
	
	# KLJUČNI POPRAVEK: Zamenjamo 'yield(timer, "timeout")' z 'await timer.timeout'
	await timer.timeout 
	
	timer.queue_free()
	
	end_enemy_turn()

func end_enemy_turn():
	# Preverjanje Game Over po sovražnikovi potezi
	if player_manager.active_party.is_empty():
		print("GAME OVER - Igralec poražen.")
		return

	# Preklop nazaj na igralca
	start_player_turn()
