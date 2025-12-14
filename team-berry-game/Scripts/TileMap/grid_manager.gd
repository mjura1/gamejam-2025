# res://Scripts/GridManager.gd
extends Node
class_name GridManager

# ===============================================
# FOG OF WAR (NOVO)
# ===============================================

# Pot do scene, ki predstavlja eno polje megle
# Prilagodite pot, če je vaša scena shranjena drugje!
const FOG_TILE_SCENE: PackedScene = preload("res://Battle/fog_tile_scene.tscn")

# Slovar za shranjevanje vozlišč megle. Key: Vector2i, Value: FogTile node
var fog_nodes: Dictionary = {}

# REFERENCE:
@onready var player_manager = get_node("/root/PlayerManager")

# Size of one grid cell (match your TileMap)
var cell_size: Vector2 = Vector2(16, 16)

# Stores objects by their grid location
var occupied := {} # Primer: occupied[Vector2i(3,4)] = character reference

# KRITIČNO: Deklaracija TileMap vozlišča za Godot 4. Uporabimo Node za lažje povezovanje.
@export var tile_map: Node = null

# ----------------- INITIALIZATION -----------------

func _ready():
	# NOVO DEBUG SPOROČILO ZA PREVERJANJE STANJA REFERENCE
	print("DEBUG: GridManager ready. TileMap referenca (v ready): " + str(is_instance_valid(tile_map)))
	
	# Opomba: Prepričajte se, da je tile_map nastavljen v Inšpektorju ali kodi pred tem klicem.

func spawn_character(characterScene: String, pos: Vector2):
	var ps: PackedScene = load(characterScene)
	var character = ps.instantiate()

	character.position = pos
	get_parent().add_child(character)
	character.add_to_group("characters")

	# ✅ počakamo 1 frame, da je node RES v tree-ju
	call_deferred("register_all_characters_in_scene")


# FUNKCIJA ZA REGISTRACIJO FIGUR
func register_all_characters_in_scene():
	
	var character_nodes = get_tree().get_nodes_in_group("characters")
	
	if character_nodes.is_empty():
		push_error("KONČNA NAPAKA: Ni najdena nobena figura v skupini 'characters'.")
		print("GridManager: Registracija figur končana. Velikost ekipe: 0")
		return

	var found_allies = 0
	
	for node in character_nodes:
		print("Najdeno vozlišče v skupini 'characters': " + node.name)
		
		# Predpostavlja, da obstaja skripta BaseCharacter
		if node is BaseCharacter:
			var char = node as BaseCharacter
			
			# 1. Dodelimo referenco BaseCharacterju
			if char.grid_manager == self:
				continue

			# ✅ prva registracija
			char.grid_manager = self
			
			# 2. KRITIČNO NOVO: Inicializacija mreže se ZDAJ zgodi v figuri
			char.on_grid_manager_registered()
			
			# 3. Registracija v PlayerManager
			if not char.is_enemy:
				player_manager.add_to_active_party(char.strName) # assuming char.character_type is a string
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

func get_character_at(grid_pos: Vector2i) -> Node:
	return occupied.get(grid_pos, null)

func get_all_characters() -> Array:
	return occupied.values()

# ===============================================
# FOG OF WAR LOGIKA (NOVO)
# ===============================================

# Klicano s strani BattleControllerja, da na novo inicializira meglo
func initialize_all_fog():
	print("DEBUG FOG: Klic initialize_all_fog().")
	
	if not is_instance_valid(tile_map):
		push_error("TileMap ni nastavljen v GridManagerju. Inicializacija megle ni mogoča.")
		print("DEBUG FOG: Napaka! tile_map je neveljaven ali null.")
		return
		
	print("DEBUG FOG: tile_map je veljaven. Začenjam generiranje.")
	
	# Odstranimo vso staro meglo, če obstaja
	clear_all_fog()
	
	# Predpostavljamo, da tile_map.get_used_rect() deluje
	var used_rect = tile_map.get_used_rect()
	var fog_layer_id = 0 # Ta ID ni več uporabljen v klicu get_cell_source_id
	
	for x in range(used_rect.position.x, used_rect.end.x):
		for y in range(used_rect.position.y, used_rect.end.y):
			var tile_pos = Vector2i(x, y)
			
			# POPRAVLJENA VRSTICA 140: Odstranili smo fog_layer_id iz klica
			if tile_map.get_cell_source_id(tile_pos) != -1:
				_spawn_fog_tile(tile_pos)
	
	print("GridManager: Megla inicializirana na %d poljih." % fog_nodes.size())


# Odstrani vsa vozlišča megle
func clear_all_fog():
	# Uporabimo keys() za varno iteracijo, medtem ko brišemo elemente
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
	
	# POPRAVEK ZA NAPAKO "Parent node is busy": Uporaba call_deferred()
	# To zagotavlja, da se vozlišče megle doda šele, ko starševsko vozlišče (Battle scena) konča s svojo inicializacijo.
	get_parent().call_deferred("add_child", fog_node)
	
	fog_nodes[grid_pos] = fog_node

# Odstrani vozlišče megle na določeni mreži
func _remove_fog_tile(grid_pos: Vector2i):
	if fog_nodes.has(grid_pos):
		var fog_node = fog_nodes.get(grid_pos)
		if is_instance_valid(fog_node):
			# Znebimo se vozlišča, da ga ne riše več
			fog_node.queue_free()
		fog_nodes.erase(grid_pos)
		return true
	return false

# Klicano s strani BattleControllerja za razkrivanje območja
func reveal_area(positions_to_reveal: Array[Vector2i]):
	for pos in positions_to_reveal:
		# Odstrani vozlišče megle, če obstaja
		_remove_fog_tile(pos)
