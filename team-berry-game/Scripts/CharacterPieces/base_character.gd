# res://Scripts/BaseCharacter.gd
extends Node2D
class_name BaseCharacter

var grid_pos: Vector2i

# ----------------- REFERENCE -----------------
# Uporabljamo @onready, saj so to Singletoni in vozlišča v sceni
@onready var tile_map = get_node("/root/Node/Map/TileMapLayer") 
@onready var player_manager = get_node("/root/PlayerManager")

# To je ključno vozlišče
@onready var grid_manager = get_node("/root/Node/GridManager") 

# ----------------- NASTAVITVE IN VREDNOSTI -----------------
@export var selected: bool = false
@export var move_range: int = 1
@export var is_enemy: bool = false 
@export var character_scene_path: String = "" # POT DO SCENE (Npr.: "res://Scenes/Characters/Bishop.tscn")

# ----------------- audio -----------------------
@onready var move_sound = $MoveSound
@onready var take_sound = $TakeSound

# ----------------- INITIALIZACIJA (KLJUČNA ZA IZBIRO) -----------------

func _ready():
	# To zagotavlja, da je vsaka figura takoj registrirana in poravnana
	if is_instance_valid(grid_manager):
		# 1. Izračunamo mrežno pozicijo iz globalne pozicije
		grid_pos = grid_manager.world_to_grid(global_position)
		
		# 2. Poravnamo globalno pozicijo (centriranje)
		global_position = grid_manager.grid_to_world(grid_pos)
		
		# 3. Registriramo figuro v slovar zasedenosti
		grid_manager.occupy(grid_pos, self) 
	else:
		print("POZOR: GridManager še ni pripravljen za %s" % self.name)
		pass 
		
# ----------------- GIBANJE IN CILJANJE -----------------

func get_move_directions() -> Array[Vector2i]:
	# Podrazredi (Bishop, Rook) implementirajo to
	return [] 

func calculate_valid_targets() -> Array[Vector2i]:
	var targets: Array[Vector2i] = []

	for dir in get_move_directions():
		for step in range(1, move_range + 1):
			var target_pos := grid_pos + dir * step

			# 1. Preverjanje mej
			if not grid_manager.is_inside_boundary(target_pos, tile_map.get_used_rect()):
				break

			# 2. Preverjanje zasedenosti
			if grid_manager.is_occupied(target_pos):
				var target_char = grid_manager.get_character_at(target_pos)
				
				# PREVERJANJE: Ali je tarča sovražnik?
				if target_char and target_char.is_enemy != is_enemy:
					targets.append(target_pos)
				
				# Gibanje se vedno ustavi ob prvi zasedeni celici
				break 

			# 3. Polje je prazno
			targets.append(target_pos)

	return targets

# Premesti figuro na novo lokacijo
func execute_move(target: Vector2i):
	grid_manager.vacate(grid_pos)
	grid_pos = target
	grid_manager.occupy(grid_pos, self)
	global_position = grid_manager.grid_to_world(grid_pos)
	move_sound.play()
	
	
func try_move(target: Vector2i) -> bool:
	if target not in calculate_valid_targets():
		return false
	
	if grid_manager.is_occupied(target):
		return false

	execute_move(target)
	return true

# ----------------- SMRT IN ZAJETJE (KLJUČNO ZA REVIVE) -----------------

# Odstranitev figure iz igre (umre)
func die():
	print("Figura %s je bila uničena in odstranjena." % name)
	
	# Osvobodi polje na mreži
	if is_instance_valid(grid_manager):
		grid_manager.vacate(grid_pos)
	
	if not is_enemy and is_instance_valid(player_manager):
		
		# 1. Če umre zaveznik, ga odstranimo iz seznama aktivnih figur igralca
		if player_manager.active_party.has(self):
			player_manager.active_party.erase(self)
			
			print("Zaveznik umrl. Preostali aktivni party size: %d" % player_manager.active_party.size())
			
			# 2. REGISTRIRAMO PODATKE O PADLI FIGURI (ZA REVIVE)
			player_manager.register_dead_character(name, 1, character_scene_path)
			
			# TODO: Preverjanje pogojev za konec igre (Game Over)
			if player_manager.active_party.is_empty():
				print("GAME OVER - Igralec poražen!")
		
	queue_free() # Uniči vozlišče

# Logika zajetja tarče in premika napadalca na tarčino polje
func capture(target: BaseCharacter):
	print("Izvajam zajetje tarče...")
	
	# KRITIČNO: Shranimo pozicijo tarče, preden jo uničimo
	var target_pos = target.grid_pos 
	
	# 1. Zajem/Smrt tarče
	take_sound.play()
	target.die()
	
	# 2. Premik napadalca na tarčino zdaj prosto polje
	execute_move(target_pos)


# ----------------- AI LOGIKA -----------------

func calculate_best_move() -> Dictionary:
	
	var valid_targets = calculate_valid_targets()
	var possible_moves: Array = [] 
	
	for pos in valid_targets:
		var target_char = grid_manager.get_character_at(pos)
		
		# 1. Prioriteta: ZAJETJE nasprotnika
		if target_char and target_char.is_enemy != is_enemy:
			return {
				"move_type": "CAPTURE",
				"target_pos": pos
			}
			
		# 2. Shranimo prazna polja za premik
		elif not target_char:
			possible_moves.append(pos)
			
	# 3. Naključni premik
	if not possible_moves.is_empty():
		var random_pos = possible_moves[randi() % possible_moves.size()]
		return {
			"move_type": "MOVE",
			"target_pos": random_pos
		}
	
	return {}
