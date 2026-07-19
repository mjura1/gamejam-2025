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

# Item "fortress": polja med prijateljsko trdnjavo in hišo v njeni ravni
# liniji so za sovražnike neprehodna. Vključno s poljem hiše ni treba -
# hiša je že ovira; blokiramo stroga vmesna polja. Računa se na klic (12x12
# plošča, poceni) - ni potrebe po predpomnjenju.
func fortress_blocked_tiles() -> Array[Vector2i]:
	var blocked: Array[Vector2i] = []
	if not is_instance_valid(player_manager) or not player_manager.has_passive("fortress"):
		return blocked
	if not is_instance_valid(tile_map):
		return blocked

	var used_rect: Rect2i = tile_map.get_used_rect()
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	for character in get_all_characters():
		if not is_instance_valid(character) or not (character is BaseCharacter):
			continue
		if character.is_enemy or character.is_obstacle or character.strName != "rook":
			continue

		for dir in directions:
			var between: Array[Vector2i] = []
			var step: Vector2i = character.grid_pos + dir
			while is_inside_boundary(step, used_rect):
				if is_occupied(step):
					var c = get_character_at(step)
					if c and c.is_obstacle:
						blocked.append_array(between)
					break
				between.append(step)
				step += dir

	return blocked

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

	# Vrnemo instanco, da lahko klicatelj takoj deluje na njej (npr. curse
	# assignment v battle.gd._apply_curses) - preverjeno, noben obstoječi
	# klicatelj (vključno s King.Heal) tega ni uporabljal.
	return character


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

# Unija VSEH polj (praznih ALI zasedljivih), ki bi jih katerakoli živa,
# ne-ovira figura dane frakcije lahko dosegla naslednjo potezo (zajetje v tej
# igri poteka natanko vzdolž premika - glej calculate_valid_targets). Skupna
# osnova za:
#   - item "spyglass" (map_behaviour._compute_risk_tiles presekano z
#     izbrane figure valid_moves)
#   - AI "danger avoidance" (base_character.calculate_best_move - raw unija,
#     brez preseka, glej Phase 5 v ENEMY_CURSES_PLAN.md)
# is_enemy_side: true = unija sovražnikovih dosegov, false = zaveznikovih.
func tiles_reachable_by(is_enemy_side: bool) -> Array[Vector2i]:
	var reachable: Array[Vector2i] = []
	for character in get_all_characters():
		if not is_instance_valid(character) or not (character is BaseCharacter):
			continue
		# GOTCHA (glej ENEMY_CURSES_PLAN.md POST-SHOP-V2 opombo): character je
		# tu Variant tudi po "is BaseCharacter" preverjanju - eksplicitno
		# tipiziran loop var za target, NE ":=", da se AI/spyglass koda ne
		# zaleti na znano GDScript type-inference napako.
		if character.is_enemy != is_enemy_side or character.is_obstacle:
			continue
		for target in character.calculate_valid_targets():
			var t: Vector2i = target
			if t not in reachable:
				reachable.append(t)
	return reachable

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

# Klicano s strani BattleControllerja za razkrivanje območja - odstrani OBA
# sistema megle (ambientno in prekletstveno), da so vsa "clear snow" mesta
# (figure, predmeti, pasivke) resnično dosledna z opisi, ki jih obljubljajo.
func reveal_area(positions_to_reveal):
	for pos in positions_to_reveal:
		# Odstrani vozlišče megle, če obstaja
		_remove_fog_tile(pos)
		_remove_curse_fog_tile(pos)

# Prekletstvo "snowfall": zrcalno reveal_area - PONOVNO pokrije polja z
# meglo. Klicatelj (snowfall_curse.gd) polja že filtrira na mejo plošče, zato
# tu tega ne preverjamo znova (_spawn_fog_tile je no-op, če megla na tem
# polju že obstaja). Zavezniki, ki se znajdejo pod novo meglo, se spet
# razkrijejo na začetku naslednje igralčeve poteze (update_fog_after_turn_start) -
# namerno, brez posebne izjeme.
func cover_area(positions_to_cover) -> void:
	for pos in positions_to_cover:
		_spawn_fog_tile(pos)

# Prekletstvi "changeling"/"abduction": neposredno zamenja mrežni poziciji
# dveh figur (BREZ execute_move-a - ni to "premik" v smislu enega koraka po
# get_move_directions(), zato tudi ne sproži zajetja/immunity/fortress
# preverjanj, ki veljajo samo za navadne premike/zajetja). Klicatelj (curse
# skripta) je odgovoren za izbiro veljavnega partnerja.
func swap_characters(a, b) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b) or a == b:
		return
	var pos_a: Vector2i = a.grid_pos
	var pos_b: Vector2i = b.grid_pos
	vacate(pos_a)
	vacate(pos_b)
	a.grid_pos = pos_b
	b.grid_pos = pos_a
	occupy(pos_b, a)
	occupy(pos_a, b)
	a.slide_to(grid_to_world(pos_b))
	b.slide_to(grid_to_world(pos_a))

# Kvadratna oblika s "+" (križ) rokami dolžine radius - center + polja
# neposredno gor/dol/levo/desno vsak korak do radiusa (BREZ diagonal), za
# razliko od square_radius_tiles zgoraj. radius=1 => klasičen 5-poljski križ.
static func plus_radius_tiles(center: Vector2i, radius: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = [center]
	for r in range(1, radius + 1):
		tiles.append(center + Vector2i(r, 0))
		tiles.append(center + Vector2i(-r, 0))
		tiles.append(center + Vector2i(0, r))
		tiles.append(center + Vector2i(0, -r))
	return tiles

# ===============================================
# PREKLETSTVENA MEGLA ("snowfall" curse) - LOČEN sistem od ambientne megle
# zgoraj (ki je zdaj rezervirana za kralja, glej BattleController.initialize_battle).
# Ta megla RAZPADA sama (glej tick_curse_fog_decay) namesto da bi jo
# razkrivala bližina zaveznikov - polja, ki že imajo prekletstveno meglo, se
# ob ponovnem pokritju NE osvežijo (glej cover_area_curse), da premikanje po
# istih poljih ne drži megle v neskončnost.
# ===============================================

const CURSE_FOG_ALPHAS: Array[float] = [0.95, 0.75, 0.5, 0.25]
const CURSE_FOG_COLOR := Color(0.55, 0.75, 1.0) # rahlo modrikasta - vizualno ločena od sive ambientne megle

# grid_pos -> Node2D (fog_tile_scene instanca)
var curse_fog_nodes: Dictionary = {}
# grid_pos -> int (indeks v CURSE_FOG_ALPHAS - trenutna faza razpada)
var curse_fog_stage: Dictionary = {}
# grid_pos -> int (koliko tick_curse_fog_decay() klicev preteče med fazami -
# npr. kraljev "blizzard" razpada počasneje kot navadni "snowfall", glej
# GameParameters/curses.json decay_ticks_per_stage)
var curse_fog_ticks_per_stage: Dictionary = {}
# grid_pos -> int (koliko tickov je minilo od zadnje spremembe faze na tem polju)
var curse_fog_tick_progress: Dictionary = {}
# grid_pos -> {"chance": float, "color": Color} - SAMO za polja, ki jih je
# pokrila "spreading" prekletstvena megla (contagion), glej cover_area_curse
# spread_chance parameter in tick_curse_fog_decay spodaj.
var curse_fog_spread: Dictionary = {}

# Prekletstvo "snowfall"/"blizzard"/"contagion": pokrije polja s SVOJO
# (razpadajočo) meglo. Polje, ki že ima prekletstveno meglo, PRESKOČIMO - ne
# resetiramo faze razpada. ticks_per_stage: koliko rund traja ena faza
# (1 = privzeto tempo, več = počasnejši razpad). color: naj se vizualno loči
# med viri (npr. kraljev "blizzard" od navadnega "snowfall").
# spread_chance > 0: prekletstvo "contagion" - vsako polje, ki ga to
# pokrivanje NA NOVO ustvari, ima to verjetnost, da se ob vsakem tick-u
# razpadanja "preseli" tudi na naključno prazno sosednje polje (glej spodaj).
func cover_area_curse(positions_to_cover, ticks_per_stage: int = 1, color: Color = CURSE_FOG_COLOR, spread_chance: float = 0.0) -> void:
	for pos in positions_to_cover:
		if curse_fog_nodes.has(pos):
			continue
		var fog_node = FOG_TILE_SCENE.instantiate()
		fog_node.position = grid_to_world(pos)
		var color_rect = fog_node.get_node_or_null("ColorRect")
		if is_instance_valid(color_rect):
			color_rect.color = color
		fog_node.modulate.a = CURSE_FOG_ALPHAS[0]
		get_parent().call_deferred("add_child", fog_node)
		curse_fog_nodes[pos] = fog_node
		curse_fog_stage[pos] = 0
		curse_fog_ticks_per_stage[pos] = maxi(1, ticks_per_stage)
		curse_fog_tick_progress[pos] = 0
		if spread_chance > 0.0:
			curse_fog_spread[pos] = {"chance": spread_chance, "color": color}

# Pokliče se enkrat na rundo (glej BattleController.update_fog_after_turn_start) -
# vsako prekletstveno polje napreduje 1 tick proti svoji naslednji fazi
# (CURSE_FOG_ALPHAS); ko doseže svoj curse_fog_ticks_per_stage prag, se stopi
# za 1 fazo, ob zadnji fazi pa se namesto tega odstrani.
func tick_curse_fog_decay() -> void:
	for pos in curse_fog_nodes.keys():
		var progress: int = curse_fog_tick_progress.get(pos, 0) + 1
		var needed: int = curse_fog_ticks_per_stage.get(pos, 1)
		if progress < needed:
			curse_fog_tick_progress[pos] = progress
			continue
		curse_fog_tick_progress[pos] = 0

		var stage: int = curse_fog_stage.get(pos, 0)
		if stage >= CURSE_FOG_ALPHAS.size() - 1:
			_remove_curse_fog_tile(pos)
			continue
		stage += 1
		curse_fog_stage[pos] = stage
		var fog_node = curse_fog_nodes.get(pos)
		if is_instance_valid(fog_node):
			fog_node.modulate.a = CURSE_FOG_ALPHAS[stage]

	# Prekletstvo "contagion": vsako še živeče "spreading" polje ima svojo
	# verjetnost, da ta tick "preskoči" na eno naključno prazno sosednje
	# polje (samo ravne smeri, ne diagonale) - iteriramo SNAPSHOT ključev
	# (.keys() vrne nov Array), ker spodnji cover_area_curse med iteracijo
	# doda NOVE vnose v ta isti slovar (verižna rast).
	var used_rect: Rect2i = tile_map.get_used_rect() if is_instance_valid(tile_map) else Rect2i()
	for pos in curse_fog_spread.keys():
		if not curse_fog_nodes.has(pos):
			curse_fog_spread.erase(pos)
			continue
		var info: Dictionary = curse_fog_spread[pos]
		if randf() >= info["chance"]:
			continue
		var neighbors: Array[Vector2i] = [
			pos + Vector2i(1, 0), pos + Vector2i(-1, 0),
			pos + Vector2i(0, 1), pos + Vector2i(0, -1),
		]
		neighbors.shuffle()
		for n in neighbors:
			if curse_fog_nodes.has(n) or is_occupied(n):
				continue
			if is_instance_valid(tile_map) and not is_inside_boundary(n, used_rect):
				continue
			cover_area_curse([n], curse_fog_ticks_per_stage.get(pos, 1), info["color"], info["chance"])
			break

func _remove_curse_fog_tile(pos: Vector2i) -> void:
	var fog_node = curse_fog_nodes.get(pos)
	if is_instance_valid(fog_node):
		fog_node.queue_free()
	curse_fog_nodes.erase(pos)
	curse_fog_stage.erase(pos)
	curse_fog_ticks_per_stage.erase(pos)
	curse_fog_tick_progress.erase(pos)
	curse_fog_spread.erase(pos)

func clear_all_curse_fog() -> void:
	for pos in curse_fog_nodes.keys():
		_remove_curse_fog_tile(pos)
	curse_fog_nodes.clear()
	curse_fog_stage.clear()
