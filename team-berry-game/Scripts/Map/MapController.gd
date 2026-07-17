# res://Scripts/Map/MapController.gd
extends Node2D
class_name MapController

# Sklici na generator in vizualno predlogo
const MapGenerator = preload("res://Scripts/Map/MapGenerator.gd")
const RoomIconScene = preload("res://Scenes/Map/map_node_icon.tscn")

@onready var map_camera: Camera2D = $MapCamera

var map_data: Array = []
var room_node_map: Dictionary = {}
var current_room: Room = null
var is_initialized: bool = false
var generator: MapGenerator = null

# NOVO: Nivo (0-2), ki naj se generira ob naslednji _ready(). GameFlow ga
# nastavi takoj po instantiate(), PREDEN je vozlišče v drevesu - zato ne sme
# biti @onready in initialize_map() se ne sme klicati neposredno pred tem
# (map_camera in drugi @onready sklici tedaj še niso na voljo).
var pending_tier: int = 0

var pan_start_position: Vector2 = Vector2.ZERO
var is_panning: bool = false

# NEW: Meje celotne mape za omejitev kamere
var map_boundary_min: Vector2 = Vector2.ZERO
var map_boundary_max: Vector2 = Vector2.ZERO

func _ready():
	if not is_initialized:
		initialize_map(pending_tier)
	else:
		queue_redraw()

func _on_button_pressed():
	UiAudio.play_click()
	print("predvajam zvok")

# =========================================================
# METODE ZA ZAGON, VIZUALIZACIJO IN STANJE 
# =========================================================

func initialize_map(tier: int = 0):
	if is_initialized: return

	generator = MapGenerator.new()
	map_data = generator.generate_map(tier)

	_visualize_rooms()
	_set_initial_state()
	
	_calculate_map_boundaries() # NEW: Izračun meje celotne mape
	_center_and_zoom_camera() 
	
	is_initialized = true
	queue_redraw()
	
func _set_initial_state():
	for room in map_data[MapGenerator.START_FLOOR]:
		if room != null:
			_set_room_unlocked(room, true)

# NEW: Izračun meje CELOTNE mape za kamero
func _calculate_map_boundaries():
	if map_data.is_empty():
		return

	var min_x = 1e9
	var max_x = -1e9
	var min_y = 1e9
	var max_y = -1e9
	
	# Iteriramo skozi VSA nadstropja in VSE sobe, da najdemo absolutne meje
	for i in range(map_data.size()):
		for room in map_data[i]:
			if room != null:
				var pos = room.position
				min_x = min(min_x, pos.x)
				max_x = max(max_x, pos.x)
				min_y = min(min_y, pos.y)
				max_y = max(max_y, pos.y)
	
	# Dodamo rob (margin), da imamo malo prostora okoli robov mape
	var margin = 200.0 
	
	map_boundary_min = Vector2(min_x - margin, min_y - margin)
	map_boundary_max = Vector2(max_x + margin, max_y + margin)


func _input(event):
	# ================= 1. Premikanje (Pan) =================
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: 
			if event.pressed:
				is_panning = true
				pan_start_position = event.position
			else:
				is_panning = false

	if is_panning and event is InputEventMouseMotion:
		var delta = event.relative

		# Izračunamo novo pozicijo kamere brez omejitev
		var new_camera_position = map_camera.position - delta / map_camera.zoom.x

		map_camera.position = _clamp_camera_position(new_camera_position, map_camera.zoom)

	# ================= 2. Povečava (Zoom) =================
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			map_camera.zoom /= 1.1
			map_camera.zoom = map_camera.zoom.max(_min_zoom_to_fit_map())

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			map_camera.zoom *= 1.1
			map_camera.zoom = map_camera.zoom.min(Vector2(2.0, 2.0))

		# Če je zoom spremenjen, ponovno preveri omejitve
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Ko spremenimo zoom, moramo ponovno izračunati in omejiti pozicijo kamere,
			# saj so se clamp meje spremenile (zaradi half_viewport)
			map_camera.position = _clamp_camera_position(map_camera.position, map_camera.zoom)

## Najmanjši dovoljeni zoom (največji dovoljeni zoom-out): raven, pri kateri
## se cela mapa ravno prilega vidnemu polju. Prej je bila spodnja meja fiksna
## (0.5) ne glede na velikost mape - pri majhnih mapah (tier 0 ima samo 5
## nadstropij) je to dopuščalo zoom precej čez rob mape (glej _clamp_camera_position).
func _min_zoom_to_fit_map() -> Vector2:
	var map_size = map_boundary_max - map_boundary_min
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		return Vector2(0.5, 0.5)

	var viewport_size = get_viewport_rect().size
	var fit_zoom = minf(viewport_size.x / map_size.x, viewport_size.y / map_size.y)
	return Vector2(fit_zoom, fit_zoom)

## Omeji pozicijo kamere znotraj meja mape (map_boundary_min/max) za dani zoom.
## Če je vidno polje (v world enotah) na kaki osi VEČJE od same mape - npr.
## pri majhnih mapah (tier 0 ima samo 5 nadstropij) ob največjem zoom-out
## (0.5) - navaden clampf poda min > max. Prejšnja "varnostna" vrstica je
## to reševala z min(clamp_min, clamp_max), kar je kamero potisnilo na rob
## namesto na sredino mape - zato je mapa pri zoom-outu izgledala majhna in
## odrinjena v kot namesto centrirana. Tu na taki osi namesto tega kamero
## postavimo na sredino mape.
func _clamp_camera_position(position: Vector2, zoom: Vector2) -> Vector2:
	var half_viewport = (get_viewport_rect().size / zoom) / 2.0
	var clamp_min = map_boundary_min + half_viewport
	var clamp_max = map_boundary_max - half_viewport
	var map_center = (map_boundary_min + map_boundary_max) / 2.0

	var result = position
	if clamp_min.x <= clamp_max.x:
		result.x = clampf(position.x, clamp_min.x, clamp_max.x)
	else:
		result.x = map_center.x
	if clamp_min.y <= clamp_max.y:
		result.y = clampf(position.y, clamp_min.y, clamp_max.y)
	else:
		result.y = map_center.y
	return result

func _visualize_rooms():
	for i in range(map_data.size()):
		for j in range(map_data[i].size()):
			var room_resource = map_data[i][j]
			
			if room_resource == null:
				continue
			
			var room_node = RoomIconScene.instantiate()
			add_child(room_node)
			
			room_node.initialize(room_resource)
			room_node.room_clicked.connect(_on_room_selected)
			
			room_node.position = room_resource.position
			room_node_map[room_resource] = room_node


func _set_room_unlocked(room: Room, unlocked: bool):
	if room != null and not room.selected:
		room.is_unlocked = unlocked
		
		if room_node_map.has(room):
			var room_node = room_node_map[room]
			room_node.update_look(unlocked, room.selected)


func _refresh_all_icons():
	for room in room_node_map.keys():
		var room_node = room_node_map[room]
		room_node.update_look(room.is_unlocked, room.selected)


func _update_reachable_rooms(new_room: Room):
	
	new_room.selected = true
	current_room = new_room
	
	var reachable_rooms: Array[Room] = new_room.next_rooms.duplicate()
	
	for i in range(map_data.size()):
		for j in range(map_data[i].size()):
			var room = map_data[i][j]
			
			if room == null:
				continue
			
			if room.selected:
				room.is_unlocked = false
			elif reachable_rooms.has(room):
				_set_room_unlocked(room, true)
			else:
				_set_room_unlocked(room, false)
	
	_refresh_all_icons()


# =========================================================
# METODA ZA RISANJE IN KLIK
# =========================================================

func _draw():
	if map_data.is_empty():
		return

	var color_line = Color(0.5, 0.5, 0.5, 0.7)
	var line_width = 4.0

	for current_room_resource in room_node_map.keys():
		var start_node = room_node_map[current_room_resource]
		var start_pos = start_node.position
		
		for next_room_resource in current_room_resource.next_rooms:
			if room_node_map.has(next_room_resource):
				var end_node = room_node_map[next_room_resource]
				var end_pos = end_node.position
				
				draw_line(start_pos, end_pos, color_line, line_width)

func _center_and_zoom_camera():
	# Ta funkcija ostane enaka, kot je bila določena v prejšnji seji, 
	# saj že osredotoča kamero na prva dve nadstropja.
	if map_data.is_empty():
		return

	const START_FLOOR_INDEX = 0
	const END_FLOOR_INDEX = 1 
	
	var min_x = 1e9 
	var max_x = -1e9
	var min_y = 1e9
	var max_y = -1e9
	var found_nodes = false

	for i in range(START_FLOOR_INDEX, min(map_data.size(), END_FLOOR_INDEX + 1)):
		for room in map_data[i]:
			if room != null:
				var pos = room.position
				min_x = min(min_x, pos.x)
				max_x = max(max_x, pos.x)
				min_y = min(min_y, pos.y)
				max_y = max(max_y, pos.y)
				found_nodes = true
	
	if not found_nodes:
		return

	var margin = 150.0 
	min_x -= margin
	max_x += margin
	min_y -= margin
	max_y += margin
	
	var center_x = (min_x + max_x) / 2.0
	var center_y = (min_y + max_y) / 2.0
	
	map_camera.position = Vector2(center_x, center_y)
	
	var map_width = max_x - min_x
	var map_height = max_y - min_y
	
	var viewport_size = get_viewport_rect().size
	var viewport_width = viewport_size.x
	var viewport_height = viewport_size.y
	
	var zoom_x = map_width / viewport_width
	var zoom_y = map_height / viewport_height
	
	var required_zoom = max(zoom_x, zoom_y)
	var final_zoom = required_zoom * 1.05 
	
	var new_zoom = Vector2(1.0, 1.0) / final_zoom 
	
	new_zoom.x = clamp(new_zoom.x, 0.5, 2.0) 
	new_zoom.y = clamp(new_zoom.y, 0.5, 2.0)
	
	map_camera.zoom = new_zoom


func _on_room_selected(room_data: Room):
	print("Igralec izbral sobo: %s pri %s" % [Room.RoomType.keys()[room_data.type], room_data.grid_position])
	
	# grid_position = Vector2i(nadstropje, stolpec) - glej MapGenerator._initialize_grid()
	var new_floor = room_data.grid_position.x
	
	# Posodobitev globalnega stanja v PlayerManagerju
	# PlayerManager naj bo globalno dostopen (npr. /root/PlayerManager)
	if PlayerManager: 
		PlayerManager.set_current_floor(new_floor)
	
	_on_button_pressed()
	_handle_event(room_data)
	_update_reachable_rooms(room_data)
	
	queue_redraw()

func _handle_event(room_data: Room):
	var room_name = Room.RoomTypeNames.get(room_data.type, "unknown_event")
	print("Zagon %s..." % room_name)

	PlayerManager.is_boss_floor = room_data.grid_position.x == generator.FLOORS - 1

	if room_name.begins_with("enemy_"):
		PlayerManager.add_to_enemy_party(room_name)
	elif room_name.begins_with("friendly_"):
		PlayerManager.add_to_friendly_party(room_name)
	# campfire: ne dodaja v enemy_party/friendly_party, samo GF.start_event()
	# preklopi na campfire sceno (glej GameFlow.start_event()).

	PlayerManager.addSnow()
	
	GF.start_event(room_data.type)
