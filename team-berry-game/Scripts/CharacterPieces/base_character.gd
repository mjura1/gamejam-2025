# res://Scripts/BaseCharacter.gd
extends Node2D
class_name BaseCharacter

var grid_pos: Vector2i
# Tracks if the piece has ever seen a player

var has_spotted_player: bool = false
var last_known_player_pos: Vector2i = Vector2i.ZERO
var last_known_direction: Vector2i = Vector2i.ZERO
var is_panicking: bool = false


# ----------------- REFERENCE -----------------
# GridManager zdaj ročno dodeli referenco
var grid_manager
@onready var battle_controller = get_node("/root/Battle/BattleController")
@onready var tile_map = get_node("../Map/TileMapLayer")
@onready var player_manager = get_node("/root/PlayerManager")

# ----------------- NASTAVITVE IN VREDNOSTI -----------------
@export var selected: bool = false
@export var move_range: int = 1
@export var is_enemy: bool = false
@export var is_obstacle: bool = false
@export var character_scene_path: String = ""
@export var panic_distance: int = 2
@export var panic_randomness: float = 0.5 # 0 = calm, 1 = total chaos
@export var strName: String

# ----------------- audio -----------------------
@onready var move_sound = $MoveSound
@onready var take_sound = $TakeSound

# ----------------- INITIALIZACIJA (KLJUČNA ZA IZBIRO) -----------------

func _ready():
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
				if target_char and target_char.is_enemy != is_enemy and target_char.is_obstacle != true:
					targets.append(target_pos)
				
				# Gibanje se vedno ustavi ob prvi zasedeni celici
				break

			# 3. Polje je prazno
			targets.append(target_pos)

	return targets

# Premesti figuro na novo lokacijo
func execute_move(target: Vector2i):
	# 1. Posodobitev mreže in pozicije
	grid_manager.vacate(grid_pos)
	grid_pos = target
	grid_manager.occupy(grid_pos, self)
	global_position = grid_manager.grid_to_world(grid_pos)
	move_sound.play()
	
	# ===============================================
	# FOG OF WAR (NOVO)
	# ===============================================
	
	# Posodobitev megle okoli nove pozicije, samo za zaveznike!
	if not is_enemy and is_instance_valid(grid_manager):
		
		var positions_to_reveal: Array[Vector2i] = []
		
		# Vidni doseg: 3x3 območje okoli figure (x in y od -1 do 1)
		for x in range(-1, 2):
			for y in range(-1, 2):
				positions_to_reveal.append(grid_pos + Vector2i(x, y))
				
		# Naročimo GridManagerju, da odstrani meglo na teh poljih
		grid_manager.reveal_area(positions_to_reveal)
	
	
func try_move(target: Vector2i) -> bool:
	# Omogoči AI-ju premik brez preverjanja stanja battle_controllerja
	if not is_enemy and not battle_controller.player_can_act():
		return false
	
	# 1. Ali je tarča veljavna tarča za premik/zajetje?
	if target not in calculate_valid_targets():
		return false
	
	var target_char = grid_manager.get_character_at(target)
	
	# 2. Preverimo zasedenost
	if target_char:
		# Polje je zasedeno. Preverimo frakcijo.
		
		# 2a. Poskus ZAJETJA (Tarča je sovražnik)
		if target_char.is_enemy != is_enemy:
			
			# Izvedemo zajetje tarče!
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
	
	if is_enemy == true:
		player_manager.register_dead_character("enemy_" + strName)
	else:
		player_manager.register_dead_character("friendly_" + strName)
	
	if player_manager.enemyGone():
		GF.return_to_map()
		
	if player_manager.activeGone():
		PlayerManager.reset_floor_number()
		GF.game_over()
	
	queue_free() # Uniči vozlišče

# Logika zajetja tarče in premika napadalca na tarčino polje
func capture(target: BaseCharacter):
	print("Izvajam zajetje tarče...")
	
	# KRITIČNO: Shranimo pozicijo tarče, preden jo uničimo
	var target_pos = target.grid_pos
	
	# 1. Zajem/Smrt tarče
	target.die()
	take_sound.play()
	
	# 2. Premik napadalca na tarčino zdaj prosto polje
	# Klic execute_move zdaj poskrbi tudi za posodobitev FOG OF WAR
	execute_move(target_pos)


# ----------------- AI LOGIKA (POPRAVLJENA) -----------------
func can_see_player(max_view_range: int) -> BaseCharacter:
	for dir in get_move_directions():
		for step in range(1, max_view_range + 1):
			var check_pos = grid_pos + dir * step

			if not grid_manager.is_inside_boundary(check_pos, tile_map.get_used_rect()):
				break

			if grid_manager.is_occupied(check_pos):
				var char = grid_manager.get_character_at(check_pos)

				# Sees player
				if char and char.is_enemy != is_enemy and not char.is_obstacle:
					return char

				# Vision blocked by any piece (or obstacle)
				break

	return null

func calculate_best_move() -> Dictionary:
	# Logika samo za sovražnike
	if not is_enemy:
		return {}
		
	# -------------------------------
	# 1. LINE-OF-SIGHT SPOTTING
	# -------------------------------
	# Uporabimo move_range kot domet vida, da se ne premakne v prvem krogu, ko ga zagleda
	var seen_player = can_see_player(move_range) 

	if seen_player and not has_spotted_player:
		has_spotted_player = true
		last_known_player_pos = seen_player.grid_pos
		last_known_direction = (seen_player.grid_pos - grid_pos).sign()
		# Wake-up turn, no movement (to se bo izvajalo samo, ko prvič zagleda)
		return {} 

	if seen_player:
		last_known_player_pos = seen_player.grid_pos
		last_known_direction = (seen_player.grid_pos - grid_pos).sign()

	# ---------------------------------
	# 2. MOVEMENT OPTIONS
	# ---------------------------------
	var valid_targets = calculate_valid_targets()
	if valid_targets.is_empty():
		return {}
	
	# ---------------------------------
	# 3. SLEPO ISKANJE (BLIND SEEK) - NOV DODATEK
	# ---------------------------------
	if not has_spotted_player:
		var target_y = 7 # Ciljna vrstica (približna sredina bojišča, če je 12 vrstic)
		var best_move: Vector2i = grid_pos
		var min_distance_sq = INF
		
		# Izberemo potezo, ki sovražnika najbolj približa centru bojišča (navzdol)
		for move_pos in valid_targets:
			var distance_to_center = abs(move_pos.y - target_y)
			
			if distance_to_center < min_distance_sq:
				min_distance_sq = distance_to_center
				best_move = move_pos
				
		# Če se sploh lahko premakne
		if best_move != grid_pos:
			return {"move_type": "MOVE", "target_pos": best_move}
		else:
			return {} # Ne more se premakniti bližje, ostane na mestu
			
	# NASLEDNJI KORAKI (4-7) SE ZGODIJO SAMO, ČE JE 'has_spotted_player' TRUE!
	
	# ---------------------------------
	# 4. CHECK FOR CURRENTLY VISIBLE PLAYER
	# ---------------------------------
	var closest_player: BaseCharacter = null
	var min_distance := INF

	for char in grid_manager.get_all_characters():
		if char.is_enemy == is_enemy:
			continue
		
		if not char is BaseCharacter:
			continue

		var dist = grid_pos.distance_to(char.grid_pos)
		if dist <= move_range and dist < min_distance:
			min_distance = dist
			closest_player = char

	# Update tracking if visible this turn
	if closest_player:
		last_known_player_pos = closest_player.grid_pos
		last_known_direction = (closest_player.grid_pos - grid_pos).sign()

	# ---------------------------------
	# 5. PANIC CHECK
	# ---------------------------------
	is_panicking = false
	if closest_player and min_distance <= panic_distance:
		is_panicking = true

	# ---------------------------------
	# 6. CAPTURE HAS ABSOLUTE PRIORITY
	# ---------------------------------
	for pos in valid_targets:
		var target_char = grid_manager.get_character_at(pos)
		# 1. Prioriteta: ZAJETJE nasprotnika
		if target_char and target_char.is_obstacle:
			continue # skip any obstacle entirely

		if target_char and target_char.is_enemy != is_enemy:
			return {
				"move_type": "CAPTURE",
				"target_pos": pos
			}


	# ---------------------------------
	# 7. NORMAL CHASE (TOWARD LAST SEEN)
	# ---------------------------------
	var best_move: Vector2i = valid_targets[0]
	var best_score := INF

	for pos in valid_targets:
		var score = pos.distance_to(last_known_player_pos)
		if score < best_score:
			best_score = score
			best_move = pos

	# ---------------------------------
	# 8. PANIC RANDOMNESS
	# ---------------------------------
	if is_panicking and randf() < panic_randomness:
		best_move = valid_targets[randi() % valid_targets.size()]

	return {
		"move_type": "MOVE",
		"target_pos": best_move
	}
