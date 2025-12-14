# res://Scripts/GridManager.gd
extends Node
class_name GridManager

# REFERENCE:
@onready var player_manager = get_node("/root/PlayerManager")
# OPOMBA: Če figure nimajo BaseCharacter skripte, boste morali GridManager dodati BaseCharacter referenco tukaj.

# Size of one grid cell (match your TileMap)
var cell_size: Vector2 = Vector2(16, 16)

# Stores objects by their grid location
var occupied := {} # Primer: occupied[Vector2i(3,4)] = character reference

# ----------------- INITIALIZATION -----------------

func _ready():
	# Pokličemo funkcijo za registracijo figur, ko je scena naložena.
	register_all_characters_in_scene()
	print("GridManager: Pripravljen.")


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
		
		if node is BaseCharacter:
			var char = node as BaseCharacter
			
			# 1. Dodelimo referenco BaseCharacterju
			char.grid_manager = self
			
			# 2. KRITIČNO NOVO: Inicializacija mreže se ZDAJ zgodi v figuri
			char.on_grid_manager_registered() 
			
			# (Opomba: grid_pos in occupy() se zdaj izvajata znotraj char.on_grid_manager_registered())
			
			# 3. Registracija v PlayerManager
			if not char.is_enemy:
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
		# Pustimo opozorilo, vendar ne prekinemo, če je figura že tam.
		# To se lahko zgodi, če BaseCharacter._ready in GridManager._ready kličeta hkrati.
		# push_error("Trying to occupy already occupied tile " + str(grid_pos))
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

# Funkcija za AI/BattleController
func get_all_characters() -> Array:
	return occupied.values()
