# res://Scripts/BaseCharacter.gd
extends Node2D
class_name BaseCharacter

var grid_pos: Vector2i
# Tracks if the piece has ever seen a player

var has_spotted_player: bool = false
var last_known_player_pos: Vector2i = Vector2i.ZERO


# ----------------- REFERENCE -----------------
# 1. Popravek: Odstranimo @onready za GridManagerja.
# GridManager zdaj ročno dodeli referenco V TEM MESTU.
var grid_manager
 
@onready var tile_map = get_node("../Map/TileMapLayer") 
@onready var player_manager = get_node("/root/PlayerManager")

# ----------------- NASTAVITVE IN VREDNOSTI -----------------
# ... (Ohrani ostale spremenljivke) ...
@export var selected: bool = false
@export var move_range: int = 1
@export var is_enemy: bool = false 
@export var character_scene_path: String = ""

# ----------------- INITIALIZACIJA -----------------

func _ready():
	# KRITIČNO: BaseCharacter._ready NE SME več dostopati do grid_manager.
	# Tu lahko izvajamo samo splošno logiko, ki NI ODVISNA od GridManagerja.
	pass
		
# NOVO: Kliče ga GridManager, ko je pripravljen in je dodeljena referenca.
func on_grid_manager_registered():
	# Tu smo 100% prepričani, da je self.grid_manager že nastavljen.
	
	# 1. Izračunamo mrežno pozicijo iz globalne pozicije
	grid_pos = grid_manager.world_to_grid(global_position)
	
	# 2. Poravnamo globalno pozicijo (centriranje)
	global_position = grid_manager.grid_to_world(grid_pos)
	
	# 3. Registriramo figuro v slovar zasedenosti
	grid_manager.occupy(grid_pos, self)
	
	# Za debug:
	print("%s: Uspešno registriran in inicializiran na mreži %s." % [self.name, str(grid_pos)])
		
		
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
	
func try_move(target: Vector2i) -> bool:
	
	# 1. Ali je tarča veljavna tarča za premik/zajetje?
	if target not in calculate_valid_targets():
		return false
	
	var target_char = grid_manager.get_character_at(target)
	
	# 2. Preverimo zasedenost
	if target_char:
		# Polje je zasedeno. Preverimo frakcijo.
		
		# 2a. Poskus ZAJETJA (Tarča je sovražnik)
		if target_char.is_enemy != is_enemy:
			
			# Izvedemo zajetje tarče! To je manjkajoči del.
			capture(target_char) 
			
			return true # Uspešno zajetje
		
		# 2b. Klik na ZAVEZNIKA (Ni dovoljeno, saj smo v dosegu)
		else:
			return false
	
	# 3. Polje je PRAZNO (Navaden premik)
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
	target.die()
	
	# 2. Premik napadalca na tarčino zdaj prosto polje
	execute_move(target_pos)


# ----------------- AI LOGIKA -----------------

func calculate_best_move() -> Dictionary:
	var valid_targets = calculate_valid_targets()
	var closest_player: BaseCharacter = null
	var min_distance = 999

	# Look for player pieces in view range
	for char in grid_manager.get_all_characters():
		if char.is_enemy == is_enemy:
			continue
		var dist = grid_pos.distance_to(char.grid_pos)
		if dist <= move_range and dist < min_distance:
			min_distance = dist
			closest_player = char

	if closest_player:
		# Player spotted → remember it
		has_spotted_player = true
		last_known_player_pos = closest_player.grid_pos
	elif not has_spotted_player:
		# Never spotted a player → do nothing
		return {}

	# Determine direction toward last known player
	var target_vector = (last_known_player_pos - grid_pos).sign()
	var max_partial_move = min(4, move_range) # Partial move distance

	# Step toward last known position, furthest valid square first
	for step in range(max_partial_move, 0, -1):
		var target_pos = grid_pos + target_vector * step
		if target_pos in valid_targets:
			var target_char = grid_manager.get_character_at(target_pos)
			if target_char and target_char.is_enemy != is_enemy:
				return {"move_type": "CAPTURE", "target_pos": target_pos}
			else:
				return {"move_type": "MOVE", "target_pos": target_pos}

	# Blocked → do nothing
	return {}
