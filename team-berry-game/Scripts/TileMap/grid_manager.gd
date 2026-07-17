# res://Scripts/TileMap/grid_manager.gd
extends Node
class_name GridManager

# ===============================================
# FOG OF WAR 
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

# ===============================================
# ABILITY CONE (Bishop.Traps / Rook.Reinforce)
# ===============================================
# id -> {"type": "freeze"/"deny_entry", "center": Vector2i, "radius": int, "owner_is_enemy": bool, "shape_offsets": Array[Vector2i]}
var zones: Dictionary = {}
var _next_zone_id := 0

# shape_offsets (relativno na center, glej plus_extended_offsets spodaj):
# če ni prazen, NADOMESTI navadni radius-kvadrat test v _in_zone (glej spodaj) -
# omogoča ne-kvadratne cone (npr. "plus" oblika) brez spreminjanja klicateljev.
func add_zone(type: String, center: Vector2i, radius: int, owner_is_enemy: bool, shape_offsets: Array[Vector2i] = []) -> int:
	var id := _next_zone_id
	_next_zone_id += 1
	zones[id] = {
		"type": type,
		"center": center,
		"radius": radius,
		"owner_is_enemy": owner_is_enemy,
		"shape_offsets": shape_offsets,
	}
	return id

func remove_zone(id: int):
	zones.erase(id)

# Ali je pos znotraj sovražnikove "freeze" cone glede na mover_is_enemy?
func is_frozen(pos: Vector2i, mover_is_enemy: bool) -> bool:
	for zone in zones.values():
		if zone.type == "freeze" and zone.owner_is_enemy != mover_is_enemy and _in_zone(pos, zone):
			return true
	return false

# Ali je pos znotraj sovražnikove "deny_entry" cone glede na mover_is_enemy?
func is_entry_denied(pos: Vector2i, mover_is_enemy: bool) -> bool:
	for zone in zones.values():
		if zone.type == "deny_entry" and zone.owner_is_enemy != mover_is_enemy and _in_zone(pos, zone):
			return true
	return false

func _in_zone(pos: Vector2i, zone: Dictionary) -> bool:
	var d: Vector2i = pos - zone.center
	var shape_offsets: Array = zone.get("shape_offsets", [])
	if not shape_offsets.is_empty():
		return d in shape_offsets
	return absi(d.x) <= zone.radius and absi(d.y) <= zone.radius

# Kvadratno območje radiusa "radius" okoli center (vključno s center samim).
static func square_radius_tiles(center: Vector2i, radius: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			tiles.append(center + Vector2i(x, y))
	return tiles

# Vmesna oblika med radius=1 (3x3) in radius=2 (5x5) kvadratom: osnovni 3x3
# plus 4 "roke" na razdalji 2 v vsako od 4 glavnih smeri ("+" oblika). Odmiki
# so relativni na (0,0) - klicatelj jih premakne na svoj center sam.
static func plus_extended_offsets() -> Array[Vector2i]:
	var offsets: Array[Vector2i] = square_radius_tiles(Vector2i.ZERO, 1)
	for dir in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		offsets.append(dir)
	return offsets

# ----------------- INITIALIZATION -----------------

func _ready():
	# tile_map (@export zgoraj) MORA biti ročno povezan v urejevalniku/scene datoteki
	# preden se bitka zažene - initialize_all_fog() brez njega samo izpiše push_error
	# in megla se nikoli ne generira (glej Scenes/test_sandbox.tscn za primer popravka).
	if not is_instance_valid(tile_map):
		push_warning("GridManager: tile_map ni povezan - fog of war ne bo deloval.")

func spawn_character(characterScene: PackedScene, pos: Vector2):
	var character = characterScene.instantiate()

	character.position = pos
	character.name = "%s_%d" % [characterScene.resource_path.get_file().get_basename(), occupied.size()]
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
		push_error("GridManager.occupy: polje %s je že zasedeno (poskus: %s)." % [grid_pos, obj])
		return
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

## Klicano s strani BattleControllerja, da na novo inicializira meglo.
## current_map_floor: 0 (začetek) do 14 (Boss); prikaz je omejen na MAX_FOG_ROWS_CAP vrstic.
func initialize_all_fog(current_map_floor: int = 0):
	const MAX_FOG_ROWS_CAP = 10 # megla nikoli ne pokrije več kot 10 vrstic
	const CLEAN_ROWS = 3 # spodnje 3 vrstice (placement cona) morajo ostati čiste

	if not is_instance_valid(tile_map):
		push_error("TileMap ni nastavljen v GridManagerju. Inicializacija megle ni mogoča.")
		return

	clear_all_fog()

	var used_rect = tile_map.get_used_rect()
	var total_map_rows = used_rect.size.y

	if total_map_rows <= CLEAN_ROWS:
		print("OPOZORILO: Mapa je premajhna za čiste vrstice.")
		return

	# LOGIKA ZAKRIVANJA: na N. nadstropju zakrijemo N vrstic od vrha navzdol.
	var max_fog_rows = total_map_rows - CLEAN_ROWS
	var fog_rows_to_cover: int = mini(mini(current_map_floor, MAX_FOG_ROWS_CAP), max_fog_rows)
	var fog_limit_y = fog_rows_to_cover

	print("DEBUG FOG: Nadstropje %d. Pokrivanje %d vrstic z meglo. Skupno vrstic: %d." % [current_map_floor, fog_rows_to_cover, total_map_rows])

	for x in range(used_rect.position.x, used_rect.end.x):
		for y in range(used_rect.position.y, used_rect.end.y):
			var tile_pos = Vector2i(x, y)
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
