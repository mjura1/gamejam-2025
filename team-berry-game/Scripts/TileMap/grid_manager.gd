# res://Scripts/GridManager.gd
extends Node
class_name GridManager

# ===============================================
# FOG OF WAR (NOVO)
# ===============================================

# Pot do scene, ki predstavlja eno polje megle
const FOG_TILE_SCENE: PackedScene = preload("res://Battle/fog_tile_scene.tscn")

# Slovar za shranjevanje vozlišč megle.
var fog_nodes: Dictionary = {}

# REFERENCE:
@onready var player_manager = get_node("/root/PlayerManager")

# Size of one grid cell (match your TileMap)
var cell_size: Vector2 = Vector2(16, 16)

# Stores objects by their grid location
var occupied := {} 

# KRITIČNO: Deklaracija TileMap vozlišča za Godot 4.
@export var tile_map: Node = null

# ----------------- INITIALIZATION -----------------

func _ready():
	print("DEBUG: GridManager ready. TileMap referenca (v ready): " + str(is_instance_valid(tile_map)))
	
	# register_all_characters_in_scene() se kliče v BattleControllerju ali spawn_character()

func spawn_character(characterScene: String, pos: Vector2):
	var ps: PackedScene = load(characterScene)
	var character = ps.instantiate()

	character.position = pos
	get_parent().add_child(character)
	character.add_to_group("characters")

	# Registracija naj se zgodi takoj po dodajanju v tree
	register_all_characters_in_scene()


# FUNKCIJA ZA REGISTRACIJO FIGUR
func register_all_characters_in_scene():
	
	var character_nodes = get_tree().get_nodes_in_group("characters")
	
	if character_nodes.is_empty():
		push_error("KONČNA NAPAKA: Ni najdena nobena figura v skupini 'characters'.")
		print("GridManager: Registracija figur končana. Velikost ekipe: 0")
		return

	var found_allies = 0
	
	for node in character_nodes:
		# Pazi: BaseCharacter mora biti pravilno definiran kot razred v svoji skripti
		if node is BaseCharacter:
			var char = node as BaseCharacter
			
			# Prepreči ponovno registracijo
			if char.grid_manager == self:
				continue

			# 1. Dodelimo referenco BaseCharacterju
			char.grid_manager = self
			
			# 2. Inicializacija mreže
			char.on_grid_manager_registered()
			
			# 3. Registracija v PlayerManager
			if not char.is_enemy:
				# KRITIČEN POPRAVEK: V PlayerManager shranimo objekt figure (char), NE SAMO IME!
				player_manager.add_to_active_party(char) 
				found_allies += 1
		else:
			print("Opozorilo: Vozlišče v skupini 'characters' ni BaseCharacter: " + node.name)
			
# ----------------- GRID UTILITY FUNCTIONS -----------------

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(floor(world_pos.x / cell_size.x), floor(world_pos.y / cell_size.y))

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return (Vector2(grid_pos) * cell_size) + cell_size / 2

func is_occupied(grid_pos: Vector2i) -> bool:
	return occupied.has(grid_pos)

func occupy(grid_pos: Vector2i, obj):
	if is_occupied(grid_pos):
		pass
	else:
		occupied[grid_pos] = obj

func vacate(grid_pos: Vector2i):
	occupied.erase(grid_pos)

func is_inside_boundary(grid_pos: Vector2i, used_rect: Rect2i) -> bool:
	return (
		grid_pos.x >= used_rect.position.x
		and grid_pos.x < used_rect.position.x + used_rect.size.x
		and grid_pos.y >= used_rect.position.y
		and grid_pos.y < used_rect.position.y + used_rect.size.y
	)

func get_character_at(grid_pos: Vector2i):	
	return occupied.get(grid_pos, null)

func get_all_characters():
	return occupied.values()

# ===============================================
# FOG OF WAR LOGIKA (DINAMIČNA SNEŽNA ODEJA - POPRAVEK)
# ===============================================

## Klicano s strani BattleControllerja, da na novo inicializira meglo
## current_map_floor: 0 (začetek) do 14 (Boss nadstropje)
func initialize_all_fog(current_map_floor: int = 0):
	print("DEBUG FOG: Klic initialize_all_fog().")
	
	# Konstante za skaliranje (ustrezajo MapGenerator.FLOORS = 15)
	const MAX_MAP_FLOOR = 14 # 15 - 1
	const MAX_FOG_ROWS = 10  # Maksimalno število pokritih vrstic (Y=0 do Y=9)
	
	if not is_instance_valid(tile_map):
		push_error("TileMap ni nastavljen v GridManagerju. Inicializacija megle ni mogoča.")
		print("DEBUG FOG: Napaka! tile_map je neveljaven ali null.")
		return
		
	print("DEBUG FOG: tile_map je veljaven. Začenjam generiranje.")
	
	clear_all_fog()
	
	var used_rect = tile_map.get_used_rect()
	
	# 1. Izračunamo število vrstic, ki jih pokrije megla, na podlagi napredka
	var fog_rows_to_cover: int = 0
	
	if MAX_MAP_FLOOR > 0:
		# Skaliranje: Uporabimo razmerje napredka (0/14 do 14/14) na območje megle (0 do 10 vrstic)
		var ratio = float(current_map_floor) / MAX_MAP_FLOOR
		fog_rows_to_cover = ceil(ratio * MAX_FOG_ROWS)
		fog_rows_to_cover = min(fog_rows_to_cover, MAX_FOG_ROWS) # Ne sme preseči 10
		
	# 2. Določimo zgornjo mejo Y koordinat (vrstice Y < fog_limit_y bodo pokrite)
	var fog_limit_y = fog_rows_to_cover 
	
	print("DEBUG FOG: Nadstropje %d. Pokrivanje %d vrstic z meglo (Y=0 do Y=%d)." % [current_map_floor, fog_rows_to_cover, fog_limit_y - 1])

	# 3. Generiranje megle
	for x in range(used_rect.position.x, used_rect.end.x):
		for y in range(used_rect.position.y, used_rect.end.y):
			var tile_pos = Vector2i(x, y)
			
			# POGOJ: Meglo generiraj samo, če je Y koordinata manjša od izračunane meje.
			# (Y=0 je vrh, Y=11 je dno)
			if y < fog_limit_y: 
				if tile_map.get_cell_source_id(tile_pos) != -1:
					_spawn_fog_tile(tile_pos)
	
	print("GridManager: Megla inicializirana na %d poljih." % fog_nodes.size())


# Odstrani vsa vozlišča megle
func clear_all_fog():
	for pos in fog_nodes.keys():
		_remove_fog_tile(pos)
	fog_nodes.clear()
	
# Ustvari vozlišče megle na določeni mreži
func _spawn_fog_tile(grid_pos: Vector2i):
	if fog_nodes.has(grid_pos):
		return # Megla že obstaja
	
	var fog_node = FOG_TILE_SCENE.instantiate()
	
	# Pozicioniranje
	fog_node.position = grid_to_world(grid_pos)
	
	# Uporaba call_deferred() za varno dodajanje vozlišč
	get_parent().call_deferred("add_child", fog_node)
	
	fog_nodes[grid_pos] = fog_node

# Odstrani vozlišče megle na določeni mreži
func _remove_fog_tile(grid_pos: Vector2i):
	if fog_nodes.has(grid_pos):
		var fog_node = fog_nodes.get(grid_pos)
		if is_instance_valid(fog_node):
			fog_node.queue_free()
		fog_nodes.erase(grid_pos)
		return true
	return false

# Klicano s strani BattleControllerja za razkrivanje območja
func reveal_area(positions_to_reveal):
	for pos in positions_to_reveal:
		# Odstrani vozlišče megle, če obstaja
		_remove_fog_tile(pos)
