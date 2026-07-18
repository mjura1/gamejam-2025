extends Node

@onready var grid_manager = $GridManager
@onready var battle_controller = $BattleController # Dodana referenca za zagon bitke
@onready var player_manager = get_node("/root/PlayerManager")
@onready var settings_manager = get_node("/root/SettingsManager")

const obstacle: PackedScene = preload("res://Scenes/CharacterPiecesNodes/Neutral/House.tscn")

# Enostavna deklaracija brez tipnih namigov, da se izognemo sintaktičnim napakam
var to_spawn_enemy

# Friendly pieces dictionary
const friendly_pieces := {
	"friendly_pawn": preload("res://Scenes/CharacterPiecesNodes/Ally/pawn.tscn"),
	"friendly_rook": preload("res://Scenes/CharacterPiecesNodes/Ally/rook.tscn"),
	"friendly_bishop": preload("res://Scenes/CharacterPiecesNodes/Ally/bishop.tscn"),
	"friendly_knight": preload("res://Scenes/CharacterPiecesNodes/Ally/knight.tscn"),
	"friendly_king": preload("res://Scenes/CharacterPiecesNodes/Ally/king.tscn"),
	"friendly_queen": preload("res://Scenes/CharacterPiecesNodes/Ally/queen.tscn"),
	"friendly_wolf": preload("res://Scenes/CharacterPiecesNodes/Ally/wolf.tscn")
}

# Enemy pieces dictionary
const enemy_pieces := {
	"enemy_pawn": preload("res://Scenes/CharacterPiecesNodes/Enemy/enemy_pawn.tscn"),
	"enemy_rook": preload("res://Scenes/CharacterPiecesNodes/Enemy/enemy_rook.tscn"),
	"enemy_bishop": preload("res://Scenes/CharacterPiecesNodes/Enemy/enemy_bishop.tscn"),
	"enemy_knight": preload("res://Scenes/CharacterPiecesNodes/Enemy/enemy_knight.tscn"),
	"enemy_king": preload("res://Scenes/CharacterPiecesNodes/Enemy/enemy_king.tscn"),
	"enemy_queen": preload("res://Scenes/CharacterPiecesNodes/Enemy/enemy_queen.tscn")
}
	

func _ready() -> void:

	# Preverimo, ali obstaja PlayerManager
	if not is_instance_valid(player_manager):
		push_error("PlayerManager singleton ni naložen")
		return
	
	# Logika za dodajanje figur ostane v _ready()
	to_spawn_enemy = player_manager.active_enemies.duplicate(true)

	var map_width = 12
	var map_height = 12

	# ========================================================
	# 1. ALLY pieces se NE spawnajo več samodejno - igralec jih v placement
	# fazi sam postavi v spodnje 3 vrstice (glej battle_ui.gd + PLACEMENT
	# stanje v BattleControllerju).
	# ========================================================

	# ========================================================
	# 2. Spawn OBSTACLES (V sredini: vrstici 2-9)
	# ========================================================
	
	# map_height - 3: spodnje 3 vrstice so placement cona - tam ovire ne smejo
	# zasedati polj za postavljanje figur.
	for x in range(0, map_width):
		for y in range(2, map_height - 3):
			var spawn_chance = randi_range(0, 12)
			if spawn_chance == 1 and not grid_manager.is_occupied(Vector2i(x, y)):
				grid_manager.spawn_character(obstacle, grid_manager.grid_to_world(Vector2(x, y)))
	
	# ========================================================
	# 3. Spawn ENEMY pieces (na vrhu: vrstici 0 in 1)
	# ========================================================
	
	var enemy_spawn_rows = [0, 1]
	var max_enemy_slots = map_width * enemy_spawn_rows.size()
	if to_spawn_enemy.size() > max_enemy_slots:
		push_warning("battle.gd: preveč sovražnikov za spawn (%d > %d) - odvečni so izpuščeni." % [to_spawn_enemy.size(), max_enemy_slots])
		to_spawn_enemy.resize(max_enemy_slots)

	while not to_spawn_enemy.is_empty():
		for y in enemy_spawn_rows:
			for x in range(0, map_width):
				if to_spawn_enemy.is_empty():
					break
				
				# Prepreči spawn na že zasedeno mesto ali z nizko verjetnostjo
				if randf() < 0.8 or grid_manager.is_occupied(Vector2i(x, y)):
					continue
					
				var piece_name = to_spawn_enemy.pop_at(randi_range(0, to_spawn_enemy.size() - 1))
				var enemy = grid_manager.spawn_character(enemy_pieces[piece_name], grid_manager.grid_to_world(Vector2(x, y)))
				_maybe_curse(enemy)


	# Zagon BattleControllerja, ki inicializira meglo in začne igro.
	if is_instance_valid(battle_controller):
		battle_controller.initialize_battle()


# Prekletstva (Scripts/Curses/): od nadstropja 2 naprej ima vsak spawnan
# sovražnik CurseData.get_curse_chance() možnost, da dobi naključno
# prekletstvo (uteženo, glej CurseData.roll_curse_for - excluded_pieces).
# Verjetnost je odvisna od izbrane težavnosti (SettingsManager.difficulty -
# easy/normal/hard, glej Data/curses.json config.difficulty_chance_mult).
func _maybe_curse(enemy) -> void:
	if not is_instance_valid(enemy):
		return
	var current_floor: int = 0
	if is_instance_valid(player_manager):
		current_floor = player_manager.current_map_floor
	var difficulty := "normal"
	if is_instance_valid(settings_manager):
		difficulty = settings_manager.difficulty
	if not CurseData.should_curse(current_floor, randf(), difficulty):
		return
	var curse_id := CurseData.roll_curse_for(enemy.strName)
	if curse_id != "":
		enemy.apply_curse(CurseData.create_curse(curse_id))
