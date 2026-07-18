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

	var spawned_enemies: Array = []

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
				spawned_enemies.append(enemy)

	_apply_curses(spawned_enemies)


	# Zagon BattleControllerja, ki inicializira meglo in začne igro.
	if is_instance_valid(battle_controller):
		battle_controller.initialize_battle()


# Prekletstva (Scripts/Curses/): od nadstropja CurseData.get_min_floor() naprej
# vsaka bitka ZAGOTOVI vsaj CurseData.get_min_curse_count(current_floor)
# prekletih sovražnikov (naključno izbranih izmed spawnanih, glej
# CurseData.roll_curse_for - excluded_pieces). Vsak PREOSTALI, še ne prekleti
# sovražnik ima poleg tega še vedno CurseData.get_curse_chance() možnost
# dodatnega naključnega prekletstva - verjetnost je odvisna od izbrane
# težavnosti (SettingsManager.difficulty, glej Data/curses.json
# config.difficulty_chance_mult).
#
# Enemy king: "blizzard" (razpadajoča 3x3 megla, glej blizzard_curse.gd) je
# kraljev lastni, zajamčeni prekletstveni mehanizem - močnejša, počasneje
# razpadajoča različica navadne "snowfall" ("+"), ki je izločena iz
# splošnega naključnega nabora (Data/curses.json weight=0) in je NI mogoče
# naključno dobiti. Kralj dobi "blizzard" TUKAJ neposredno (šteje kot 1 od
# get_min_curse_count() zajamčenih mest); preostali sovražniki se še vedno
# potegujejo za snowfall/frenzy/stunning_gaze kot prej.
func _apply_curses(enemies: Array) -> void:
	var valid_enemies: Array = enemies.filter(func(e): return is_instance_valid(e))
	if valid_enemies.is_empty():
		return

	var current_floor: int = 0
	if is_instance_valid(player_manager):
		current_floor = player_manager.current_map_floor
	var difficulty := "normal"
	if is_instance_valid(settings_manager):
		difficulty = settings_manager.difficulty

	var min_count: int = min(CurseData.get_min_curse_count(current_floor), valid_enemies.size())

	var roll_pool: Array = valid_enemies.duplicate()
	var king_matches: Array = roll_pool.filter(func(e): return e.strName == "king")
	if not king_matches.is_empty():
		var king_enemy = king_matches[0]
		roll_pool.erase(king_enemy)
		king_enemy.apply_curse(CurseData.create_curse("blizzard"))
		min_count = maxi(0, min_count - 1)

	roll_pool.shuffle()
	for i in range(roll_pool.size()):
		var enemy = roll_pool[i]
		if i < min_count:
			_curse_enemy(enemy) # zajamčeno mesto - prekletstvo ne glede na met
		elif CurseData.should_curse(current_floor, randf(), difficulty):
			_curse_enemy(enemy) # bonus met nad zajamčenim minimumom

func _curse_enemy(enemy) -> bool:
	var curse_id := CurseData.roll_curse_for(enemy.strName)
	if curse_id == "":
		return false
	enemy.apply_curse(CurseData.create_curse(curse_id))
	return true
