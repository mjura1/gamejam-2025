extends Resource
class_name MapGenerator # Omogoča tipizacijo (npr. 'var generator: MapGenerator')

# =========================================================
# 1. KONSTANTE ZA MREŽO (GRID) IN GENERACIJO
# =========================================================

# Predpostavimo, da je pot pravilna
const ROOM_RESOURCE = preload("res://Scripts/Map/map_point.gd")

# Logična velikost mreže (kot v Slay the Spire)
const FLOORS: int = 15
const MAP_WIDTH: int = 7
const MAX_PATHS: int = 6
const START_FLOOR: int = 0

# Vizualna postavitev, povecaj za vec nodes
const X_DISTANCE: int = 150
const Y_DISTANCE: int = 100
const PLACEMENT_RANDOMNESS: float = 5.0

# --- Definiranje uteži za naključno dodeljevanje ---
const ROOM_WEIGHTS: Dictionary = {
	Room.RoomType.enemy_bishop: 2,
	Room.RoomType.enemy_king: 0,
	Room.RoomType.enemy_knight: 3,
	Room.RoomType.enemy_rook: 4,
	Room.RoomType.enemy_queen: 1,
	Room.RoomType.enemy_pawn: 5,
	Room.RoomType.friendly_pawn: 5,
	Room.RoomType.friendly_knight: 2,
	Room.RoomType.friendly_rook: 4,
	Room.RoomType.friendly_bishop: 3,
	Room.RoomType.friendly_queen: 1,
	Room.RoomType.friendly_king: 1
}


# Glavni podatkovni objekt: Matrika virov Room
var map_data: Array = [] # Array[Array[Room]]
var total_weight: int = 0 # Skupna utež za uteženo naključno izbiro

# =========================================================
# 2. GLAVNA FUNKCIJA GENERIRANJA
# =========================================================

## Glavna funkcija, ki se pokliče za generiranje celotne mape
func generate_map() -> Array:
	# 1. Izračunamo skupno utež (samo enkrat na začetku)
	if total_weight == 0:
		for weight in ROOM_WEIGHTS.values():
			total_weight += weight
	
	# 2. Inicializacija prazne mreže (matrike)
	_initialize_grid()
	
	# 3. Generiranje poti in povezovanje sob
	_generate_paths()
	
	# 4. FILTRIRANJE: Odstranitev vseh vozlišč, ki niso del poti (ki nimajo naslednikov)
	_cleanup_unconnected_rooms() 
	
	# 5. Dodeljevanje tipov sob (Monster, Shop, Boss...)
	_assign_room_types()
	
	# 6. Vrnemo generirano mapo
	return map_data

# =========================================================
# 3. POMOŽNE FUNKCIJE (KORAKI ALGORITMA)
# =========================================================

## 3.1 Inicializacija mreže in ustvarjanje virov Room
func _initialize_grid():
	map_data.clear()
	
	for i in range(FLOORS):
		var floor_row: Array = []
		for j in range(MAP_WIDTH):
			var room_resource = Room.new()
			room_resource.grid_position = Vector2i(i, j)
			
			# Izračun 2D pozicije na svetu
			var x_pos = float(j) * X_DISTANCE
			var y_pos = float(i) * Y_DISTANCE * -1.0
			
			# Dodamo naključni zamik za 'organski' videz
			x_pos += randf_range(-PLACEMENT_RANDOMNESS, PLACEMENT_RANDOMNESS)
			y_pos += randf_range(-PLACEMENT_RANDOMNESS, PLACEMENT_RANDOMNESS)
			
			room_resource.position = Vector2(x_pos, y_pos)
			
			floor_row.append(room_resource)
		
		map_data.append(floor_row)
	
	print("Mreža je inicializirana z %d nadstropji in %d stolpci." % [FLOORS, MAP_WIDTH])


## 3.2 Generiranje poti (Start in zagon _connect_paths)
func _generate_paths():
	var num_paths = randi_range(3, MAX_PATHS)
	var active_rooms: Array[Room] = []
	
	# Naključno izberemo začetne sobe na dnu (FLOOR 0)
	var available_cols = Array(range(MAP_WIDTH))
	available_cols.shuffle()
	
	for i in range(num_paths):
		var start_col = available_cols.pop_front()
		active_rooms.append(map_data[START_FLOOR][start_col])

	print("Začelo se je generiranje poti iz %d startnih točk." % active_rooms.size())
	
	_connect_paths(active_rooms)


## 3.2.1 Povezovanje sob med nadstropji
func _connect_paths(current_floor_rooms: Array[Room]):
	# Iteriramo od START_FLOOR navzgor do predzadnjega nadstropja
	for current_floor_index in range(START_FLOOR, FLOORS - 1):
		
		var next_floor_index = current_floor_index + 1
		var next_floor_rooms: Array[Room] = []

		for current_room in current_floor_rooms:
			
			var num_connections = randi_range(1, 2)
			
			for i in range(num_connections):
				# Izračunamo možne stolpce za povezavo: trenutni stolpec +/- 1
				var min_col = max(0, current_room.grid_position.y - 1)
				var max_col = min(MAP_WIDTH - 1, current_room.grid_position.y + 1)
				
				var next_col = randi_range(min_col, max_col)
				var next_room = map_data[next_floor_index][next_col]
				
				# Preverjanje, da se izognemo duplikatom povezav
				if not current_room.next_rooms.has(next_room):
					current_room.next_rooms.append(next_room)
					
					# Poskrbimo, da bo naslednja soba obdelana v naslednjem nadstropju
					if not next_floor_rooms.has(next_room):
						next_floor_rooms.append(next_room)

		current_floor_rooms = next_floor_rooms
		
	_connect_to_boss()


## 3.2.2 Končna povezava s sobo Boss
func _connect_to_boss():
	var boss_floor_index = FLOORS - 1
	var boss_room = map_data[boss_floor_index][MAP_WIDTH / 2]

	# Iteriramo skozi predzadnje nadstropje (FLOORS - 2)
	for room in map_data[FLOORS - 2]:
		# Povežemo sobo s šefom le, če je del poti (ima next_rooms)
		if not room.next_rooms.is_empty():
			if not room.next_rooms.has(boss_room):
				room.next_rooms.append(boss_room)


## 3.3 Čiščenje neuporabljenih virov (KLJUČEN korak)
func _cleanup_unconnected_rooms():
	var rooms_to_keep: Array[Room] = []
	
	# 1. Zberemo vse sobe, ki so del poti (imajo vsaj eno povezavo ali so šef)
	for i in range(FLOORS - 1): # Vse razen Boss nadstropja
		for room in map_data[i]:
			if not room.next_rooms.is_empty():
				rooms_to_keep.append(room)
				
	# 2. Dodamo Boss sobo
	rooms_to_keep.append(map_data[FLOORS - 1][MAP_WIDTH / 2])
	
	# 3. Ustvarimo novo, čisto map_data, kjer so vsi prostori, ki niso del poti, NULL
	var new_map_data: Array = []
	for i in range(FLOORS):
		var floor_row: Array = []
		for j in range(MAP_WIDTH):
			var room = map_data[i][j]
			if rooms_to_keep.has(room):
				floor_row.append(room)
			else:
				floor_row.append(null) 
		new_map_data.append(floor_row)
		
	map_data = new_map_data
	print("Očiščenih je %d neuporabljenih vozlišč." % (FLOORS * MAP_WIDTH - rooms_to_keep.size()))


## 3.4 Dodeljevanje tipov sob
func _assign_room_types():
	
	for i in range(FLOORS):
		for j in range(MAP_WIDTH):
			var room = map_data[i][j]
			
			# Tipi so dodeljeni SAMO sobam, ki so na poti
			if room == null:
				continue
			
			match i:
				START_FLOOR:
					room.type = Room.RoomType.enemy_knight
				
				FLOORS - 1:
					room.type = Room.RoomType.enemy_king
				
				# Nadstropje 9: kraljica
				9:
					room.type = Room.RoomType.friendly_queen
				
				# Vsa ostala nadstropja: Utežena naključna izbira
				_:
					room.type = _get_random_room_type()
	
	print("Tip sobe je dodeljen vsem sobam.")


## Pomožna funkcija: Utežena naključna izbira
func _get_random_room_type() -> Room.RoomType:
	var random_value = randi_range(1, total_weight)
	var accumulated_weight = 0
	
	for type_key in ROOM_WEIGHTS:
		accumulated_weight += ROOM_WEIGHTS[type_key]
		if random_value <= accumulated_weight:
			return type_key
			
	# V primeru napake, vrnemo privzeti tip
	return Room.RoomType.friendly_pawn
