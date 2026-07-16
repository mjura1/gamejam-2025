extends Node

@onready var grid_manager = $GridManager
@onready var battle_controller = $BattleController # Dodana referenca za zagon bitke

const obstacle = "res://Scenes/CharacterPiecesNodes/Neutral/House.tscn"

# Enostavna deklaracija brez tipnih namigov, da se izognemo sintaktičnim napakam
var to_spawn_enemy
var to_spawn_ally 

# Friendly pieces dictionary
const friendly_pieces := {
	"friendly_pawn": "res://Scenes/CharacterPiecesNodes/Ally/pawn.tscn",
	"friendly_rook": "res://Scenes/CharacterPiecesNodes/Ally/rook.tscn",
	"friendly_bishop": "res://Scenes/CharacterPiecesNodes/Ally/bishop.tscn",
	"friendly_knight": "res://Scenes/CharacterPiecesNodes/Ally/knight.tscn",
	"friendly_king": "res://Scenes/CharacterPiecesNodes/Ally/king.tscn",
	"friendly_queen": "res://Scenes/CharacterPiecesNodes/Ally/queen.tscn"
}

# Enemy pieces dictionary
const enemy_pieces := {
	"enemy_pawn": "res://Scenes/CharacterPiecesNodes/Enemy/enemy_pawn.tscn",
	"enemy_rook": "res://Scenes/CharacterPiecesNodes/Enemy/enemy_rook.tscn",
	"enemy_bishop": "res://Scenes/CharacterPiecesNodes/Enemy/enemy_bishop.tscn",
	"enemy_knight": "res://Scenes/CharacterPiecesNodes/Enemy/enemy_knight.tscn",
	"enemy_king": "res://Scenes/CharacterPiecesNodes/Enemy/enemy_king.tscn",
	"enemy_queen": "res://Scenes/CharacterPiecesNodes/Enemy/enemy_queen.tscn"
}
	

func _ready() -> void:
	
	# Preverimo, ali obstaja PlayerManager in ga shranimo
	var player_manager = get_node("/root/PlayerManager")
	if not is_instance_valid(player_manager):
		push_error("PlayerManager singleton ni naložen")
		return
	
	# Logika za dodajanje figur ostane v _ready()
	print("test")
	to_spawn_ally = player_manager.active_party.duplicate(true)
	to_spawn_enemy = player_manager.enemy_party.duplicate(true)
	
	var map_width = 12 
	var map_height = 12 
	
	# ========================================================
	# 1. Spawn ALLY pieces (na dnu: vrstici 10 in 11)
	# ========================================================
	
	var ally_spawn_rows = [map_height - 1, map_height - 2] # 11 in 10
	
	while not to_spawn_ally.is_empty():
		for x in range(0, map_width):
			for y in ally_spawn_rows:
				if to_spawn_ally.is_empty():
					break
					
				# Prepreči spawn na že zasedeno mesto ali z nizko verjetnostjo
				if randf() < 0.8 or grid_manager.is_occupied(Vector2i(x, y)):
					continue
					
				var piece_name = to_spawn_ally.pop_at(randi_range(0, to_spawn_ally.size() - 1))
				grid_manager.spawn_character(friendly_pieces[piece_name], grid_manager.grid_to_world(Vector2(x, y)))
				
	# ========================================================
	# 2. Spawn OBSTACLES (V sredini: vrstici 2-9)
	# ========================================================
	
	for x in range(0, map_width):
		for y in range(2, map_height - 2):
			var spawn_chance = randi_range(0, 12)
			if spawn_chance == 1 and not grid_manager.is_occupied(Vector2i(x, y)):
				grid_manager.spawn_character(obstacle, grid_manager.grid_to_world(Vector2(x, y)))
	
	# ========================================================
	# 3. Spawn ENEMY pieces (na vrhu: vrstici 0 in 1)
	# ========================================================
	
	var enemy_spawn_rows = [0, 1]
	
	while not to_spawn_enemy.is_empty():	
		for y in enemy_spawn_rows:
			for x in range(0, map_width):
				if to_spawn_enemy.is_empty():
					break
				
				# Prepreči spawn na že zasedeno mesto ali z nizko verjetnostjo
				if randf() < 0.8 or grid_manager.is_occupied(Vector2i(x, y)):
					continue
					
				var piece_name = to_spawn_enemy.pop_at(randi_range(0, to_spawn_enemy.size() - 1))
				grid_manager.spawn_character(enemy_pieces[piece_name], grid_manager.grid_to_world(Vector2(x, y)))
				
	
	# Zagon BattleControllerja, ki inicializira meglo in začne igro.
	if is_instance_valid(battle_controller):
		battle_controller.initialize_battle()
	
	

